# Setup

Passo-a-passo pra implementar o BSUID Handler no seu ambiente.

**Pré-requisitos:**
- DataCrazy CRM (ou BSP equivalente) com Meta Cloud API oficial configurada
- n8n self-hosted ou cloud
- Meta System User token com scopes: `whatsapp_business_messaging`, `whatsapp_business_management`

---

## 1. Meta Cloud API — obtenha as credenciais

Você precisa de 2 valores do Meta Business Manager:

- **META_PHONE_NUMBER_ID** — ID interno do número WhatsApp Business. Achável em WhatsApp Manager → Configurações → Números → ID do número
- **META_ACCESS_TOKEN** — System User token permanente com scopes `whatsapp_business_messaging` e `whatsapp_business_management`

Se você usa DataCrazy com Cloud API já integrada, o token DataCrazy é separado — crie um novo System User token só pro n8n em Configurações da Empresa → Usuários do Sistema → Adicionar → Adicionar ativos → WABA → Token permanente.

---

## 2. n8n — importe os 3 workflows

Pra cada arquivo em `n8n/`:

1. n8n → Workflows → Import from File
2. Escolha o `.json`
3. No workflow **Pedir Contato BSUID**, ache o node "Meta: request_contact_info" e substitua:
   - `YOUR_META_PHONE_NUMBER_ID` na URL pelo seu phone_number_id
   - `YOUR_META_ACCESS_TOKEN` no header Authorization pelo seu token
4. Ative os 3 workflows

### Anote os webhook URLs

Cada workflow tem 1 webhook. Depois de ativar, o n8n mostra a URL de produção tipo:

```
https://SEU-N8N.exemplo.com/webhook/bsuid-request
https://SEU-N8N.exemplo.com/webhook/contact-shared
https://SEU-N8N.exemplo.com/webhook/text-input-shared
```

Você vai usar essas URLs nos blocos HTTP do flow DataCrazy.

---

## 3. DataCrazy — crie tags e importe o flow

### 3a. Crie 2 tags no DataCrazy

Em Tags → Adicionar:

- **`phone_resolvido`** — verde `#10B981`. Aplicada quando phone é capturado. Ativa flows produção.
- **`lost_bsuid`** — vermelho `#EF4444`. Aplicada se cliente não respondeu em ~30min.

Anote os UUIDs de cada tag (aparecem na URL da tag ou via API `GET /api/crm/tags`).

### 3b. Importe o flow

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
#    - YOUR_CLIENT-bsuid-request → path do webhook (padrão bsuid-request)
#    - YOUR_CAMPAIGN_SLUG → identificador da campanha (ex "campanha_a")

# 4. PATCH os blocks
curl -X PATCH "https://crm.g1.datacrazy.io/api/crm/flows/<FLOW_ID>/versions/<VERSION_ID>" \
  -H "Authorization: Bearer SEU_TOKEN_DC" \
  -H "Content-Type: application/json" \
  -d @datacrazy/bsuid-handler-flow.json
```

### 3c. Ajuste a keyword do Trigger 1

Trigger 1 vem com keyword placeholder — ajuste pra keyword da sua campanha CTWA.

Vá no editor visual do DC → Trigger 1 → Palavras-chave → adicione as keywords que suas campanhas mandam automaticamente (ex: "Quiero información sobre el curso", "Quero saber mais").

Ou, pra pegar QUALQUER lead CTWA sem depender de keyword, use `type=any` e adicione uma condition antes do HTTP block: `[Message-1]referral.ctwa_clid contains "."`

### 3d. Ative o flow

DataCrazy → Flow BSUID Handler → toggle Active.

---

## 4. Ligue o handler aos seus flows de produção

O handler termina aplicando a tag `phone_resolvido`. Seus flows de produção (webinar, follow-up, etc) precisam de um **trigger novo** que ativa quando essa tag é aplicada.

Em cada flow de produção:

1. Adicione um trigger tipo `tag-added-trigger` no início
2. Selecione tag `phone_resolvido`
3. Ligue ao mesmo primeiro bloco do fluxo existente (que hoje é ativado pela keyword CTWA)

Assim quando o handler resolve o phone, o cliente entra automaticamente no funil real como se tivesse chegado normalmente.

---

## 5. Teste end-to-end

**Cenário 1: cliente com phone normal (>80% dos leads)**

1. Envie a keyword CTWA do teu telefone pro número do teu WhatsApp Business
2. Handler dispara → n8n IF gate detecta que você tem phone → skipa
3. Você não recebe request_contact_info
4. Flow de produção segue normal

**Cenário 2: forçar teste do request Meta**

Dispare o webhook n8n direto (bypassa o gate do IF), passando teu BSUID real no `bsuid_raw`:

```bash
curl -X POST 'https://SEU-N8N.exemplo.com/webhook/bsuid-request?leadId=TEST&leadPhone=&name=Teste&bsuid_raw=SEU_BSUID_REAL'
```

Descobre teu BSUID real olhando o webhook Meta que chega no teu DC (campo `from_user_id`).

Você recebe o botão nativo no WA. Clica em Compartilhar. Confirme no DC que o lead agora tem phone preenchido e a tag `phone_resolvido` foi aplicada.

---

## Troubleshooting

**Meta retorna erro 131009 "Parameter value is not valid":**
- O `to` do request_contact_info precisa ser BSUID real (não inventado) OU phone existente no WA. Teste com BSUIDs capturados de leads reais.

**IF gate do n8n sempre skipa:**
- Cliente tá vindo com `leadPhone` preenchido. Confirme via GET `/leads/{id}` no DataCrazy — se o `phone` tá vazio mas o `contacts[0].contactId` começa com prefixo tipo `CO.` ou `BR.`, o mapping DC → n8n query params tá errado. Confira que o merge tag no HTTP block DC é `{Telefone do lead|leadPhone}`.

**Cliente responde texto mas text-input não captura:**
- `text-input-message` do DC precisa do `parameter` setado (usamos `additional-field[phone_digitado]`). Se `parameter=""`, ele não salva. Verifique.

**Token DC expira em 1h:**
- Token Firebase JWT sim. Pra automação, extraia via securetoken API do Google usando o refreshToken armazenado. Pattern na doc oficial DataCrazy Integrations.
