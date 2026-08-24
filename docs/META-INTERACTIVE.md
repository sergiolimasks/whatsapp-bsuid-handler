# Meta interactive `request_contact_info`

Detalhes técnicos do mecanismo Meta pra pedir telefone de forma nativa.

## Payload de envio

```http
POST https://graph.facebook.com/v22.0/{PHONE_NUMBER_ID}/messages
Authorization: Bearer {ACCESS_TOKEN}
Content-Type: application/json
```

```json
{
  "messaging_product": "whatsapp",
  "recipient_type": "individual",
  "to": "CO.13491208655302741918",
  "type": "interactive",
  "interactive": {
    "type": "request_contact_info",
    "body": {
      "text": "Antes de te mandar os materiais, ¿compartes tu WhatsApp?"
    },
    "action": {
      "name": "request_contact_info"
    }
  }
}
```

**Campo `to`:** aceita BSUID (`CO.xxx`) OU phone (`155500012340`). Se você tem o phone, use phone. Se só tem BSUID (caso típico do handler), passe BSUID direto.

**Restrição da janela 24h:** só funciona se o usuário mandou msg pro seu business nos últimos 24h. Se saiu da janela, use TEMPLATE com button `REQUEST_CONTACT_INFO` (aprovação Meta 24-48h, mas funciona a qualquer momento).

## Resposta esperada

Sucesso:

```json
{
  "messaging_product": "whatsapp",
  "contacts": [{"input": "CO.13491208655302741918", "user_id": "CO.13491208655302741918"}],
  "messages": [{"id": "wamid.HBgL..."}]
}
```

Guarde o `messages[0].id` — dá pra correlacionar com webhook de status depois.

## Erros comuns

| Código | Motivo | Como resolver |
|---|---|---|
| 131009 | `to` inválido (não é phone nem BSUID real) | Verifique formato — BSUIDs válidos vêm dos webhooks reais do Meta, não podem ser inventados |
| 131047 | Fora da janela 24h | Use TEMPLATE com REQUEST_CONTACT_INFO ao invés de interactive |
| 131026 | Recipient não tem WhatsApp válido | Cliente pode ter desativado a conta — nada a fazer |
| 190 | Token expirado ou inválido | Verifique scopes do System User token: precisa `whatsapp_business_messaging` |

## Webhook de resposta (quando cliente clica em "Compartilhar")

Meta envia webhook tipo `contacts`:

```json
{
  "entry": [{
    "changes": [{
      "field": "messages",
      "value": {
        "metadata": {
          "phone_number_id": "YOUR_META_PHONE_NUMBER_ID",
          "display_phone_number": "15550001234"
        },
        "messaging_product": "whatsapp",
        "messages": [{
          "from": "15550001234",
          "from_user_id": "CO.13491208655302741918",
          "id": "wamid.HBgL...",
          "type": "contacts",
          "contacts": [{
            "origin": "contact_request",
            "name": {
              "first_name": "Juan",
              "formatted_name": "Juan Carlos"
            },
            "phones": [{
              "phone": "+57 300 1234567",
              "type": "MOBILE",
              "wa_id": "573001234567"
            }]
          }],
          "timestamp": "1780324175"
        }],
        "contacts": [{
          "profile": {"name": "Juan", "username": "juan.trading"},
          "user_id": "CO.13491208655302741918",
          "wa_id": "573001234567"
        }]
      }
    }]
  }]
}
```

Campos importantes:
- **`messages[0].type = "contacts"`** — filtro pra reconhecer que é uma resposta ao request
- **`contacts[0].origin = "contact_request"`** — confirma que veio do botão nativo (não é cliente compartilhando outro contato aleatório)
- **`contacts[0].phones[0].wa_id`** — phone verificado (só dígitos, formato E.164 sem `+`)
- **`contacts[0].phones[0].phone`** — mesmo phone mas formatado (`+55 19 99...`)
- **`from_user_id`** — BSUID do remetente (o mesmo do request original — usado pra fazer match)
- **`contacts[0].name.formatted_name`** — nome do vCard (mais confiável que profile name)

## Como o DataCrazy expõe

Nas merge tags do flow DC, os paths que funcionam:

```
{tipo|[Message-2]type}                           → "contacts"
{bsuid|[Message-2]from_user_id}                  → "CO.13491208655302741918"
{tel|[Message-2]contacts[0].phones[0].phone}     → "+57 300 1234567"
{nm|[Message-2]contacts[0].name.formatted_name}  → "Juan Carlos"
{fn|[Message-2]contacts[0].name.first_name}      → "Juan"
```

**Gotcha:** paths com ponto tipo `[Message-2].type` NÃO funcionam — retornam vazio. Use SEM ponto após o `]`. Descoberta empírica.

## Alternativa: TEMPLATE com REQUEST_CONTACT_INFO

Se você precisa pedir contato **fora da janela 24h** (ex: 3 dias depois do cliente sumir), use template pré-aprovado:

```http
POST https://graph.facebook.com/v22.0/{WABA_ID}/message_templates
```

```json
{
  "name": "solicitar_contacto",
  "language": "es_CO",
  "category": "UTILITY",
  "components": [
    {
      "type": "BODY",
      "text": "Hola {{1}} 👋 Necesito confirmar tu WhatsApp para enviarte los materiales. Toca abajo:",
      "example": {"body_text": [["amigo"]]}
    },
    {
      "type": "BUTTONS",
      "buttons": [{"type": "REQUEST_CONTACT_INFO"}]
    }
  ]
}
```

Aprovação Meta: 1-24h. Depois de aprovado, envia via API normal:

```json
{
  "messaging_product": "whatsapp",
  "to": "CO.13491208655302741918",
  "type": "template",
  "template": {
    "name": "solicitar_contacto",
    "language": {"code": "es_CO"},
    "components": [{"type": "body", "parameters": [{"type": "text", "text": "Juan"}]}]
  }
}
```

Este handler usa a versão interactive (dentro da janela 24h) porque é mais rápido de implementar e cobre 100% dos casos CTWA que chegam frescos. Se seu use case é retargeting frio, migre pra template.

## Referências

- [Meta docs — BSUID](https://developers.facebook.com/documentation/business-messaging/whatsapp/business-scoped-user-ids/)
- [Meta docs — interactive messages](https://developers.facebook.com/documentation/business-messaging/whatsapp/reference/whatsapp-business-phone-number/message-api)
- [Gupshup — BSUID technical impl](https://support.gupshup.io/hc/en-us/articles/55873677826713-Username-Business-Scoped-User-ID)
