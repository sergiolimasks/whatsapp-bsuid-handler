# Setup

Passo-a-passo pra implementar o BSUID Handler no seu ambiente.

**Pré-requisitos:**
- DataCrazy CRM (ou BSP equivalente) com Meta Cloud API oficial configurada
- n8n self-hosted ou cloud
- Postgres 12+
- Meta System User token com scopes: `whatsapp_business_messaging`, `whatsapp_business_management`

---

## 1. Postgres

### 1a. Aplique a migração

```bash
psql -h SEU_HOST -U SEU_USER -d SEU_DB -f postgres/migration.sql
```

**IMPORTANTE:** edite `postgres/migration.sql` primeiro pra trocar `rastreio_whats.contatos` pelo seu schema.tabela.

A migração é **retrocompatível**: colunas antigas (`telefone`, resto do schema) continuam intactas e todos os workflows/queries existentes que usam telefone continuam funcionando.

### 1b. Sanity check

Depois da migração:

```sql
SELECT COUNT(*) FROM sua_tabela WHERE identifier IS NULL;
-- Deve retornar 0
```

---

## 2. Meta Cloud API — obtenha as credenciais

Você precisa de 3 valores do Meta Business Manager:

- **META_PHONE_NUMBER_ID** — ID do número WhatsApp Business (não é o número, é o ID interno). Achável em WhatsApp Manager → Configurações → Números → ID do número
- **META_WABA_ID** — ID da conta WhatsApp Business (WABA)
- **META_ACCESS_TOKEN** — System User token permanente com scopes `whatsapp_business_messaging` e `whatsapp_business_management`

Se você usa DataCrazy com Cloud API já integrada, o token DataCrazy é separado do seu — crie um novo System User token só pro n8n em Configurações da Empresa → Usuários do Sistema → Adicionar → Adicionar ativos → WABA → Token permanente.

---

## 3. n8n — importe os 3 workflows

### 3a. Credencial Postgres

1. n8n → Credenciais → Adicionar → Postgres
2. Preencha host/port/user/password/db
3. Salve. Anote o **ID da credencial** (aparece na URL depois de salvar)

### 3b. Importe os workflows

Pra cada arquivo em `n8n/`:

1. n8n → Workflows → Import from File
2. Escolha o `.json`
3. Nos nodes Postgres, substitua `REPLACE_WITH_YOUR_CREDENTIAL_ID` pela credencial que você criou (dropdown no node)
4. No workflow **Pedir Contato (BSUID)**, ache o node "Meta: request_contact_info" e substitua:
   - `YOUR_META_PHONE_NUMBER_ID` na URL pelo seu phone_number_id
   - `YOUR_META_ACCESS_TOKEN` no header Authorization pelo seu token
5. Ative os 3 workflows

### 3c. Anote os webhook URLs

Cada workflow tem 1 webhook. Depois de ativar, o n8n mostra a URL de produção tipo:

```
https://SEU-N8N.exemplo.com/webhook/bsuid-request
https://SEU-N8N.exemplo.com/webhook/contact-shared
https://SEU-N8N.exemplo.com/webhook/text-input-shared
```

---

## 4. DataCrazy — importe o flow

### 4a. Crie 2 tags no DataCrazy

Em Tags → Adicionar:

- **`phone_resolvido`** — verde `#10B981`. Aplicada quando phone é capturado. Ativa flows produção.
- **`lost_bsuid`** — vermelho `#EF4444`. Aplicada se cliente não respondeu em ~30min.

Anote os UUIDs de cada tag (aparecem na URL da tag ou via API `GET /api/crm/tags`).

### 4b. Importe o flow

O arquivo `datacrazy/bsuid-handler-flow.json` tem os 18 blocos do handler.

Como o DataCrazy não tem UI de import de flow oficial, use a API:

```bash
# 1. Cria o flow shell
curl -X POST 'https://crm.g1.datacrazy.io/api/crm/flows' \
  -H "Authorization: Bearer SEU_TOKEN_DC" \
  -H "Content-Type: application/json" \
  -d '{"name":"BSUID Handler","group":"WhatsApp","active":false}'
# Anote o "id" retornado — vamos chamar de <FLOW_ID>

# 2. Buscar a versão default (DC cria uma automática)
curl "https://crm.g1.datacrazy.io/api/crm/flows/<FLOW_ID>" \
  -H "Authorization: Bearer SEU_TOKEN_DC"
# Copia lastVersion.id — <VERSION_ID>

# 3. Substitua placeholders no bsuid-handler-flow.json:
#    - YOUR_DATACRAZY_INSTANCE_ID → ID da sua instance WA no DC
#    - YOUR_TAG_PHONE_RESOLVIDO_ID → UUID da tag que você criou
#    - YOUR_TAG_LOST_BSUID_ID → UUID da outra tag
#    - YOUR_N8N_WEBHOOK_HOST → seu host n8n
#    - YOUR_CLIENT-bsuid-request → path do seu webhook
#    - YOUR_CAMPAIGN_SLUG → identificador da campanha (ex "7usd", "20usd")

# 4. PATCH os blocks
curl -X PATCH "https://crm.g1.datacrazy.io/api/crm/flows/<FLOW_ID>/versions/<VERSION_ID>" \
  -H "Authorization: Bearer SEU_TOKEN_DC" \
  -H "Content-Type: application/json" \
  -d @datacrazy/bsuid-handler-flow.json
```

### 4c. Ajuste a keyword do Trigger 1

Trigger 1 vem com keyword vazia — ajuste pra keyword da sua campanha CTWA.

Vá no editor visual do DC → Trigger 1 → Palavras-chave → adicione as keywords que suas campanhas mandam automaticamente (ex: "Quiero información sobre el curso", "Quero saber mais").

Ou, pra pegar QUALQUER lead CTWA sem depender de keyword, use `type=any` e adicione uma condition antes do HTTP block: `[Message-1]referral.ctwa_clid contains "."`

### 4d. Ative o flow

DataCrazy → Flow BSUID Handler → toggle Active.

---

## 5. Ligue o handler aos flows de produção

O handler termina aplicando a tag `phone_resolvido`. Seus flows de produção (webinar, follow-up, etc) precisam de um **trigger novo** que ativa quando essa tag é aplicada.

Em cada flow de produção:

1. Adicione um trigger tipo `tag-added-trigger` no início
2. Selecione tag `phone_resolvido`
3. Ligue ao mesmo primeiro bloco do fluxo existente (que hoje é ativado pela keyword CTWA)

Assim quando o handler resolve o phone, o cliente entra automaticamente no funil real como se tivesse chegado normalmente.

---

## 6. Teste end-to-end

**Cenário 1: cliente com phone normal (>80% dos leads)**

1. Envie a keyword CTWA do teu telefone pro número Anderson
2. Handler dispara → n8n IF gate detecta que você tem phone → skipa
3. Você não recebe request_contact_info
4. Flow de produção segue normal

**Cenário 2: simular cliente BSUID-only**

1. INSERT manual no Postgres:

```sql
INSERT INTO rastreio_whats.contatos
  (bsuid, webinar_slug, nome, status, criado_em_br, criado_em_co)
VALUES ('BR.SEU_BSUID_REAL', 'teste_e2e', 'Teste', 'lead_bsuid', NOW(), NOW());
```

Descubra teu BSUID real fazendo curl e olhando `from_user_id` no webhook (ou via debug do handler).

2. Trigger o workflow diretamente:

```bash
curl -X POST 'https://SEU-N8N.exemplo.com/webhook/bsuid-request?leadId=TEST&leadPhone=&name=Teste&bsuid_raw=SEU_BSUID_REAL&webinar_slug=teste_e2e'
```

3. Você recebe o botão nativo no WA. Clica em Compartilhar.
4. Verifique no Postgres:

```sql
SELECT identifier, telefone, bsuid, phone_shared_at, phone_shared_via
FROM rastreio_whats.contatos WHERE bsuid = 'BR.SEU_BSUID_REAL' AND webinar_slug = 'teste_e2e';
```

Deve mostrar `telefone` preenchido, `phone_shared_at=NOW`, `phone_shared_via='native_button'`.

---

## 7. Monitoramento

Query pra dashboard:

```sql
SELECT
  DATE_TRUNC('day', phone_requested_at) AS dia,
  COUNT(*) AS pedidos,
  COUNT(phone_shared_at) AS respondidos,
  ROUND(100.0 * COUNT(phone_shared_at) / NULLIF(COUNT(*), 0), 1) AS taxa_conversao_pct,
  COUNT(*) FILTER (WHERE phone_shared_via = 'native_button') AS via_botao,
  COUNT(*) FILTER (WHERE phone_shared_via = 'text_input') AS via_digitacao,
  COUNT(*) FILTER (WHERE status = 'lost_bsuid') AS perdidos,
  ROUND(AVG(EXTRACT(EPOCH FROM (phone_shared_at - phone_requested_at))/60)::numeric, 2) AS tempo_medio_min
FROM rastreio_whats.contatos
WHERE phone_requested_at > NOW() - INTERVAL '30 days'
GROUP BY 1 ORDER BY 1 DESC;
```

Ver `docs/METRICS.md` pra mais queries de análise.

---

## Troubleshooting

**Meta retorna erro 131009 "Parameter value is not valid":**
- O `to` do request_contact_info precisa ser BSUID válido OU phone existente no WA. Teste com BSUIDs reais capturados de leads recentes.

**IF gate do n8n sempre skipa:**
- Cliente tá vindo com `leadPhone` preenchido. Confirme: `\GET /leads/{id}` no DataCrazy — se o `phone` tá vazio mas o `contacts[0].contactId` começa com prefixo tipo `CO.` ou `BR.`, o mapping DC → n8n query params tá errado. Confira que o merge tag no HTTP block DC é `{Telefone do lead|leadPhone}` e não outro.

**"duplicate key value violates unique constraint contatos_pkey":**
- Aconteceu: cliente compartilhou telefone que já existia em outra linha da mesma campanha. Solução: o CTE consolidated no workflow contact-shared deveria detectar. Se tá dando erro, verifique se `bsuid_row` e `existing_by_phone` estão sendo detectados corretamente. Debug ligando um Postgres node antes com SELECT.

**Cliente responde texto mas texto-input não captura:**
- text-input-message do DC precisa do parameter setado (usamos `additional-field[phone_digitado]`). Se `parameter=""` ele não salva. Verifique.

**Token DC expira em 1h:**
- Token Firebase JWT sim. Pra automação, extraia via securetoken API do Google usando o refreshToken armazenado. Ver script de referência em [datacrazy-api-firebase-token pattern](https://help.datacrazy.io/en/collections/11846718-integrations).
