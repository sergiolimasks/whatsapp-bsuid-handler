-- WhatsApp BSUID Handler — migração schema
--
-- Adapta uma tabela existente que usa `telefone` como PK pra suportar leads
-- BSUID-only (sem phone). Estratégia: coluna GENERATED `identifier` que é
-- COALESCE(telefone, bsuid), e usa ela como PK ao invés de telefone direto.
--
-- Substitua `rastreio_whats.contatos` pelo seu schema.tabela.

-- ============================================================================
-- 1. Adiciona coluna bsuid nullable
-- ============================================================================
ALTER TABLE rastreio_whats.contatos
  ADD COLUMN IF NOT EXISTS bsuid VARCHAR(150);

COMMENT ON COLUMN rastreio_whats.contatos.bsuid IS
  'Business-Scoped User ID do WhatsApp. Formato: {ISO2}.{digitos}, ex CO.13491208655302741918';


-- ============================================================================
-- 2. Drop PK antiga ANTES de mexer em telefone NOT NULL
--    (Postgres não permite DROP NOT NULL enquanto coluna é PK)
-- ============================================================================
ALTER TABLE rastreio_whats.contatos
  DROP CONSTRAINT IF EXISTS contatos_pkey;


-- ============================================================================
-- 3. Relaxa telefone pra NULLABLE (leads BSUID-only vêm sem phone)
-- ============================================================================
ALTER TABLE rastreio_whats.contatos
  ALTER COLUMN telefone DROP NOT NULL;


-- ============================================================================
-- 4. Coluna gerada identifier = telefone OU bsuid
--    STORED (não VIRTUAL) porque queremos indexar como PK
-- ============================================================================
ALTER TABLE rastreio_whats.contatos
  ADD COLUMN IF NOT EXISTS identifier VARCHAR(150)
  GENERATED ALWAYS AS (COALESCE(telefone, bsuid)) STORED;

COMMENT ON COLUMN rastreio_whats.contatos.identifier IS
  'Chave lógica: telefone se existe, senão bsuid. STORED pra permitir PK/indexes. Recalcula automaticamente ao atualizar telefone';


-- ============================================================================
-- 5. Check constraint: identifier nunca deve ser NULL
--    (defesa contra bug: lead sem telefone E sem bsuid não deveria existir)
-- ============================================================================
ALTER TABLE rastreio_whats.contatos
  DROP CONSTRAINT IF EXISTS contatos_identifier_notnull;
ALTER TABLE rastreio_whats.contatos
  ADD CONSTRAINT contatos_identifier_notnull CHECK (identifier IS NOT NULL);


-- ============================================================================
-- 6. Nova PK: (identifier, webinar_slug)
--    Se sua tabela não tem webinar_slug, ajuste pra sua segmentação
-- ============================================================================
ALTER TABLE rastreio_whats.contatos
  ADD CONSTRAINT contatos_pkey PRIMARY KEY (identifier, webinar_slug);


-- ============================================================================
-- 7. Índices parciais pra lookup rápido por bsuid ou telefone diretos
--    (as queries do funil de produção usam telefone; queries do handler usam bsuid)
-- ============================================================================
CREATE INDEX IF NOT EXISTS contatos_bsuid_idx
  ON rastreio_whats.contatos (bsuid) WHERE bsuid IS NOT NULL;

CREATE INDEX IF NOT EXISTS contatos_telefone_idx
  ON rastreio_whats.contatos (telefone) WHERE telefone IS NOT NULL;


-- ============================================================================
-- 8. Colunas de métrica pra acompanhar conversão do handler
-- ============================================================================
ALTER TABLE rastreio_whats.contatos
  ADD COLUMN IF NOT EXISTS phone_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS phone_shared_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS phone_shared_via VARCHAR(20);

COMMENT ON COLUMN rastreio_whats.contatos.phone_requested_at IS
  'Timestamp em que o Meta request_contact_info foi enviado pro cliente. Preservado em retries (ON CONFLICT COALESCE)';

COMMENT ON COLUMN rastreio_whats.contatos.phone_shared_at IS
  'Timestamp em que o cliente respondeu com o telefone. NULL se ainda não respondeu ou virou lost_bsuid';

COMMENT ON COLUMN rastreio_whats.contatos.phone_shared_via IS
  'Como o cliente respondeu: "native_button" (clicou no botão nativo) ou "text_input" (digitou o número livre)';


-- ============================================================================
-- 9. Sanity checks
-- ============================================================================

-- Verifica que colunas existem
SELECT column_name, data_type, is_nullable, generation_expression
FROM information_schema.columns
WHERE table_schema = 'rastreio_whats' AND table_name = 'contatos'
  AND column_name IN ('telefone', 'bsuid', 'identifier',
                      'phone_requested_at', 'phone_shared_at', 'phone_shared_via');

-- Verifica constraints
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'rastreio_whats' AND tablename = 'contatos'
ORDER BY indexname;

-- Verifica que rows existentes não têm identifier NULL (esperado 0)
SELECT COUNT(*) AS deve_ser_zero
FROM rastreio_whats.contatos WHERE identifier IS NULL;


-- ============================================================================
-- ROLLBACK — se precisar reverter
-- ============================================================================
/*
ALTER TABLE rastreio_whats.contatos DROP CONSTRAINT IF EXISTS contatos_pkey;
ALTER TABLE rastreio_whats.contatos DROP CONSTRAINT IF EXISTS contatos_identifier_notnull;
ALTER TABLE rastreio_whats.contatos DROP COLUMN IF EXISTS identifier;
ALTER TABLE rastreio_whats.contatos DROP COLUMN IF EXISTS phone_shared_via;
ALTER TABLE rastreio_whats.contatos DROP COLUMN IF EXISTS phone_shared_at;
ALTER TABLE rastreio_whats.contatos DROP COLUMN IF EXISTS phone_requested_at;
ALTER TABLE rastreio_whats.contatos DROP COLUMN IF EXISTS bsuid;

-- ATENÇÃO: DROP NOT NULL requer que todas as linhas tenham telefone
-- Antes de rodar essa parte, popule qualquer linha com telefone NULL manualmente
ALTER TABLE rastreio_whats.contatos ALTER COLUMN telefone SET NOT NULL;
ALTER TABLE rastreio_whats.contatos ADD CONSTRAINT contatos_pkey PRIMARY KEY (telefone, webinar_slug);
*/
