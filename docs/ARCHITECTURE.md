# Arquitetura

## Visão end-to-end

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        FLUXO DE UM LEAD BSUID-ONLY                           │
└──────────────────────────────────────────────────────────────────────────────┘

  1. Cliente clica ad CTWA no Meta Ads
                    │
                    ▼
  2. WhatsApp abre no celular do cliente com msg pré-preenchida
                    │
                    ▼
  3. Cliente manda 1ª mensagem (keyword da campanha)
                    │
                    ▼
  4. Meta Cloud API envia webhook pro DataCrazy
     ┌─────────────────────────────────────────┐
     │ { "type": "text",                       │
     │   "from_user_id": "CO.13491208655...",  │  ← BSUID no lugar do wa_id
     │   "profile": { "name": "Juan" }         │
     │ }                                       │
     └─────────────────────────────────────────┘
                    │
                    ▼
  5. DataCrazy cria lead com phone="" e contactId="CO.xxx"
                    │
                    ▼
  6. Flow "BSUID Handler" — Trigger 1 dispara:
     ┌──────────────────────────────────────────────────┐
     │ H1: HTTP POST → n8n /bsuid-request               │
     └──────────────────────────────────────────────────┘
                    │
                    ▼
  7. n8n workflow "Pedir Contato":
     • IF gate: leadPhone vazio E bsuid preenchido? SIM
     • POST Meta Graph API type=interactive request_contact_info
                    │
                    ▼
  8. Cliente recebe no WA botão nativo "📇 Compartilhar contato"

  ┌─────────────────────────────────────────────────────────────┐
  │  ➊ Se cliente clica NA HORA:                                │
  │                                                              │
  │  9a. Meta envia webhook type=contacts pro DataCrazy         │
  │      ┌─────────────────────────────────────────────┐        │
  │      │ { "type": "contacts",                       │        │
  │      │   "from_user_id": "CO.13491208655...",      │        │
  │      │   "contacts": [{                            │        │
  │      │     "phones": [{"phone": "+57 300 1234"}],  │        │
  │      │     "name": {"formatted_name": "Juan"}      │        │
  │      │   }]                                        │        │
  │      │ }                                           │        │
  │      └─────────────────────────────────────────────┘        │
  │                                                              │
  │  10a. Flow BSUID Handler — Trigger 2 dispara:                │
  │       Condition: [Message-2]type contains "contacts"?  SIM   │
  │       → HTTP POST → n8n /contact-shared                      │
  │                                                              │
  │  11a. n8n workflow "Contato Compartilhado":                  │
  │       • Normaliza phone ("+57 300 1234" → "573001234")       │
  │       • Fallback nome: vCard > firstName > WA profile        │
  │       • Retorna JSON limpo pro DC                            │
  │                                                              │
  │  12a. DC bloco "atualizar lead" seta phone recebido          │
  │  13a. DC aplica tag `phone_resolvido`                        │
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
  │  14b. HTTP POST → n8n /text-input-shared                     │
  │  15b. n8n regex → extrai dígitos → valida ≥10                │
  │       → retorna phone limpo ou 400                           │
  │  16b. DC aplica tag `phone_resolvido`                        │
  │                                                              │
  │  ➍ Se ainda ninguém: tag `lost_bsuid` (perdido)             │
  │                                                              │
  └─────────────────────────────────────────────────────────────┘

  14. Flows de PRODUÇÃO ativam via trigger tag-added:
      Trigger: tag `phone_resolvido` foi aplicada
      → Continua funil normal (webinar, follow-ups, checkout)
```

## Componentes

### DataCrazy — cérebro

| Componente | Papel |
|---|---|
| Flow **BSUID Handler** | 2 triggers (pedir contato + capturar share). 18 blocos, delays com retry, fallback text-input, aplica tags |
| Tag `phone_resolvido` | Aplicada quando phone é capturado. Ativa flows de produção via trigger tag-added |
| Tag `lost_bsuid` | Aplicada se não conseguir capturar em ~30min. Usada pra análise/retargeting |
| Bloco "atualizar lead" | Salva phone recebido no lead do próprio DC |

### n8n — middleware stateless

| Workflow | Webhook | Função |
|---|---|---|
| Pedir Contato BSUID | `POST /bsuid-request` | IF gate (só BSUID-only) → envia Meta interactive |
| Contato Compartilhado | `POST /contact-shared` | Normaliza phone Meta format → retorna JSON limpo |
| Contato Digitado | `POST /text-input-shared` | Parseia + valida phone livre → retorna 200 ou 400 |

**Importante:** os workflows n8n são **stateless**. Não gravam em banco, não têm memória entre execuções. Toda persistência fica no DataCrazy (lead, tags, campos). Se você quiser plugar num banco/CRM externo (Postgres, Sheets, HubSpot etc), adicione um node no fim de cada workflow — mas isso é decisão de implementação, não faz parte do template.

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

Efeito colateral positivo: a lógica de filtro vive em 1 lugar (n8n). Ajustar critério = editar 1 IF, não N triggers no DC.

## Fluxo de handoff

O handler termina com a tag `phone_resolvido` aplicada no lead. Nos flows de produção (webinar, follow-up, checkout), adicione um **trigger novo do tipo tag-added** apontando pra essa tag. Assim quando o handler resolve o phone, o cliente entra automaticamente no funil real como se tivesse chegado normalmente.

Fluxo antigo (só phone-normal):
```
Trigger keyword CTWA → resto do flow
```

Fluxo novo (BSUID-aware):
```
Trigger keyword CTWA ──┐
                       ├→ resto do flow (mesma coisa)
Trigger tag phone_resolvido ──┘
```

Duas portas de entrada, mesmo destino.
