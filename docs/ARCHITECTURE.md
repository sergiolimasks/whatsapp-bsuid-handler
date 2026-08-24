# Arquitetura

## Visão end-to-end

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        FLUXO DE UM LEAD BSUID-ONLY                           │
└──────────────────────────────────────────────────────────────────────────────┘

  1. Cliente clica ad CTWA no Meta Ads
                    │
                    ▼
  2. WhatsApp abre no celular do cliente
                    │
                    ▼
  3. Cliente manda 1ª mensagem (keyword da campanha)
                    │
                    ▼
  4. Meta Cloud API envia webhook pro BSP (DataCrazy)
     ┌─────────────────────────────────────────┐
     │ { "type": "text",                       │
     │   "from_user_id": "CO.13491208655...",  │  ← BSUID no lugar do wa_id
     │   "profile": { "name": "Juan" }          │
     │ }                                        │
     └─────────────────────────────────────────┘
                    │
                    ▼
  5. DataCrazy cria lead com phone="" e contactId="CO.xxx"
                    │
                    ▼
  6. Flow "BSUID Handler" — Trigger 1 dispara:
     ┌──────────────────────────────────────────────────┐
     │ H1: HTTP POST → n8n /bsuid-request         │
     └──────────────────────────────────────────────────┘
                    │
                    ▼
  7. n8n workflow "Pedir Contato":
     • IF gate: leadPhone vazio E bsuid preenchido?
     • INSERT rastreio_whats.contatos (bsuid, ctwaclid, phone_requested_at=NOW)
     • POST Meta Graph API /messages type=interactive request_contact_info
                    │
                    ▼
  8. Cliente recebe no WA botão nativo "📇 Compartilhar contato"

  ┌─────────────────────────────────────────────────────────────┐
  │  ➊ Se cliente clica NA HORA:                                │
  │                                                              │
  │  9a. Meta envia webhook type=contacts pro DataCrazy         │
  │      ┌─────────────────────────────────────────────┐         │
  │      │ { "type": "contacts",                       │         │
  │      │   "from_user_id": "CO.13491208655...",      │         │
  │      │   "contacts": [{                            │         │
  │      │     "phones": [{"phone": "+57 300 1234"}],  │         │
  │      │     "name": {"formatted_name": "Juan"}      │         │
  │      │   }]                                        │         │
  │      │ }                                            │         │
  │      └─────────────────────────────────────────────┘         │
  │                                                              │
  │  10a. Flow BSUID Handler — Trigger 2 dispara:                │
  │       Condition: [Message-2]type contains "contacts"?  SIM   │
  │       → HTTP POST → n8n /contact-shared               │
  │                                                              │
  │  11a. n8n workflow "Contato Compartilhado":                  │
  │       • Sanitize phone ("+57 300 1234" → "573001234")        │
  │       • CTE Merge:                                           │
  │         - UPDATE rastreio SET telefone=X WHERE bsuid=Y       │
  │         - identifier recalcula (bsuid → phone)               │
  │         - grava phone_shared_at + phone_shared_via           │
  │       → aplica tag `phone_resolvido` no lead                 │
  │                                                              │
  └─────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────┐
  │  ➋ Se cliente NÃO clica em 3min:                            │
  │                                                              │
  │  9b. Handler manda msg de reforço                            │
  │  10b. Reenvia botão (2º request_contact_info)                │
  │  11b. Espera 7min                                            │
  │                                                              │
  │  ➌ Se ainda não clicou:                                     │
  │                                                              │
  │  12b. Handler pede pra digitar: "escreve teu WA aqui"        │
  │  13b. text-input-message aguarda cliente digitar             │
  │  14b. HTTP POST → n8n /text-input-shared                      │
  │  15b. n8n regex → extrai dígitos → valida ≥10 → mesma CTE   │
  │       → aplica tag `phone_resolvido`                         │
  │                                                              │
  │  ➍ Se ainda ninguém: tag `lost_bsuid` (perdido)             │
  │                                                              │
  └─────────────────────────────────────────────────────────────┘

  12. Flows de PRODUÇÃO ativam via trigger tag-added:
      Trigger: tag `phone_resolvido` foi aplicada
      → Continua funil normal (webinar, follow-ups, checkout)
```

## Componentes

### DataCrazy (BSP)

| Componente | Papel |
|---|---|
| Flow **BSUID Handler** | 2 triggers (pedir contato + capturar share). 18 blocos, delays com retry, fallback text-input, aplica tags |
| Tag `phone_resolvido` | Aplicada quando phone é capturado. Ativa flows de produção |
| Tag `lost_bsuid` | Aplicada se não conseguir capturar em ~30min. Usada pra análise/retargeting |

### n8n (motor)

| Workflow | Webhook | Função |
|---|---|---|
| Pedir Contato (BSUID) | `POST /bsuid-request` | Envia Meta interactive. IF gate (só BSUID-only) |
| Contato Compartilhado | `POST /contact-shared` | Recebe share do cliente. CTE merge de identidade |
| Contato Digitado (fallback) | `POST /text-input-shared` | Parseia texto livre. Regex + validação |

### Postgres (source-of-truth)

Tabela `rastreio_whats.<cliente>` — schema com colunas:

- `telefone` (nullable) — phone quando existe
- `bsuid` (nullable) — BSUID sempre presente
- `identifier` GENERATED = `COALESCE(telefone, bsuid)` — chave lógica
- PK: `(identifier, webinar_slug)`
- `phone_requested_at`, `phone_shared_at`, `phone_shared_via` — métricas

### Meta Cloud API

- Endpoint: `POST /v22.0/{PHONE_NUMBER_ID}/messages`
- Interactive type: `request_contact_info`
- Requer janela 24h aberta pelo usuário

## Por que 2 triggers no DC (não 1 só)?

- **Trigger 1** dispara SÓ na 1ª mensagem CTWA (filtro por keyword). Chama n8n pra pedir contato.
- **Trigger 2** dispara em qualquer mensagem que chegar (sem keyword). Filtro `type=contacts` deixa passar só se for share.

São **2 momentos distintos**. Cliente pode entrar hoje (T1) e compartilhar amanhã (T2 — dentro da janela 24h).

## Por que o IF gate está no n8n e não no DC?

O DataCrazy não expõe um operator "campo é vazio" nas conditions dos flows. Alternativas testadas (`field-is-empty-condition`) retornam HTTP 501.

Solução: DC sempre chama o n8n em toda 1ª msg CTWA. n8n filtra:
- Se `leadPhone` preenchido: skip (cliente não é BSUID-only, ignora)
- Se `leadPhone` vazio E `bsuid_raw` preenchido: segue → envia Meta

Efeito colateral positivo: o n8n vira o único ponto onde a lógica vive. Se você quiser ajustar critério de disparo, muda 1 IF em 1 workflow, não N triggers no DC.

## Idempotência

- **INSERT no Postgres** com `ON CONFLICT (identifier, webinar_slug) DO UPDATE` — retries do DC (comum com timeouts) não duplicam
- **phone_requested_at** preservado no ON CONFLICT — se o mesmo cliente entrar de novo, mantém o timestamp original (importante pra medir tempo até resposta corretamente)
- **CTE merge** no contact-shared detecta caso onde já existe linha `(phone, slug)` E linha `(bsuid, slug)` — funde ambos e deleta a duplicata BSUID (evita violação de PK quando identifier recalcula)

## Gotcha crítico da migração de PK

Quando a PK muda de `(telefone, slug)` pra `(identifier, slug)` onde `identifier = COALESCE(telefone, bsuid)`:

Se cliente BSUID-only compartilhar telefone que JÁ EXISTE em outra linha da mesma campanha, o UPDATE `SET telefone` recalcula `identifier` de BSUID pra phone. Nova chave `(phone, slug)` colide com a linha existente → constraint violation.

**Solução no merge SQL:**

```sql
WITH existing_by_phone AS (
  SELECT * FROM contatos
  WHERE telefone = :in_tel AND webinar_slug = :in_slug LIMIT 1
),
bsuid_row AS (
  SELECT * FROM contatos
  WHERE bsuid = :in_bsuid AND webinar_slug = :in_slug AND telefone IS NULL LIMIT 1
),
consolidated AS (
  -- Ambas existem: funde bsuid+dados na linha_phone
  UPDATE contatos a SET
    bsuid = COALESCE(a.bsuid, (SELECT bsuid FROM bsuid_row)),
    ctwaclid = COALESCE(NULLIF(a.ctwaclid,''), (SELECT ctwaclid FROM bsuid_row)),
    -- ...
  WHERE a.telefone = :in_tel AND ...
    AND EXISTS (SELECT 1 FROM bsuid_row)
    AND EXISTS (SELECT 1 FROM existing_by_phone)
  RETURNING 'CONSOLIDATED'
),
deleted AS (
  -- Deleta a linha BSUID (dados já foram consolidados)
  DELETE FROM contatos WHERE bsuid = :in_bsuid AND telefone IS NULL
    AND EXISTS (SELECT 1 FROM consolidated)
),
simple_update AS (
  -- Só existe bsuid_row: UPDATE simples
  UPDATE contatos SET telefone = :in_tel
  WHERE bsuid = :in_bsuid AND telefone IS NULL
    AND NOT EXISTS (SELECT 1 FROM existing_by_phone)
  RETURNING 'UPDATED'
)
SELECT * FROM consolidated UNION ALL SELECT * FROM simple_update;
```

Detalhes completos em [`../postgres/migration.sql`](../postgres/migration.sql).
