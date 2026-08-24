# WhatsApp BSUID Handler

> Recupera automaticamente o telefone de leads WhatsApp que vêm sem número (BSUID-only) usando o botão nativo `request_contact_info` da Meta Cloud API.

**Stack:** DataCrazy CRM + n8n + Meta Graph API v22.0

**Status:** rodando em produção desde agosto/2026 em cliente CTWA colombiano com ~19% dos leads BSUID-only.

---

## O problema

Em junho/2026 o WhatsApp começou a permitir que usuários adotassem **username** e ocultassem o telefone quando conversam com empresas. No lugar do phone, o business recebe um **BSUID** (Business-Scoped User ID) tipo `CO.13491208655302741918`.

Rollout começou pela Colômbia e México, expandindo globalmente ao longo de 2026.

**Impacto direto:**
- Match end-to-end quebra: cliente entra por CTWA sem phone → webinar/checkout Hotmart não conseguem casar de volta com o lead original
- Meta Ads perde otimização: sem `Purchase` retornando via CAPI amarrado ao `ctwa_clid`, o algoritmo fica cego
- Automações CRM que usam phone como chave primária param de funcionar em ~20% dos leads

## A solução

Fluxo end-to-end que a Meta recomenda oficialmente:

1. Cliente entra no WhatsApp via CTWA
2. Handler detecta que veio sem telefone (só BSUID)
3. Bot pede o contato via mensagem interativa nativa (`request_contact_info`)
4. Cliente toca em **"Compartilhar contato"** — 1 clique, sem digitação
5. Handler recebe o phone, aplica tag `phone_resolvido` no lead
6. Seus flows de produção pegam a partir dessa tag e continuam o funil normal

Se cliente não clicar na primeira, **retry 2× e fallback pra digitação livre** antes de marcar como perdido.

## O que está incluído

```
├── datacrazy/
│   └── bsuid-handler-flow.json      # Fluxo DC completo (18 blocos, tudo comentado)
├── n8n/
│   ├── 01-pedir-contato-bsuid.json           # Recebe do DC, chama Meta
│   ├── 02-contato-compartilhado.json         # Normaliza phone compartilhado
│   └── 03-contato-digitado.json              # Valida phone digitado (fallback)
└── docs/
    ├── WHY.md                       # Background do problema BSUID
    ├── ARCHITECTURE.md              # Desenho end-to-end + fluxo de dados
    ├── SETUP.md                     # Passo-a-passo de implementação
    └── META-INTERACTIVE.md          # Payload da API request_contact_info
```

## Como funciona (visão rápida)

**Componentes:**
- **DataCrazy** é o cérebro — tem trigger, delays, tags, lead state
- **n8n** é o middleware — só transforma dados entre DC e Meta (sem estado, sem banco)
- **Meta Cloud API** manda o botão nativo pro cliente

**Fluxo:**
```
Cliente clica CTWA → DC recebe
                      ↓
                  Handler flow dispara
                      ↓
                  HTTP → n8n → Meta (pede contato)
                      ↓
                  Cliente clica "Compartilhar"
                      ↓
                  DC recebe msg type=contacts
                      ↓
                  HTTP → n8n (normaliza phone)
                      ↓
                  DC aplica tag `phone_resolvido`
                      ↓
                  Seus flows de produção pegam daqui
```

## Quick start

1. Leia [`docs/WHY.md`](docs/WHY.md) pra entender o contexto BSUID
2. Importe os 3 workflows em [`n8n/`](n8n/) — configure Meta token + phone_number_id
3. Importe o flow do [`datacrazy/`](datacrazy/) — substitua placeholders `YOUR_XXX`
4. Nos flows de produção seus, adicione trigger `tag added = phone_resolvido`
5. Detalhes em [`docs/SETUP.md`](docs/SETUP.md)

## Requisitos

- **Meta Cloud API oficial** (WhatsApp Business App standalone não funciona). Se você usa DataCrazy com Coexistence Mode ou Cloud API integration, tá coberto
- **n8n** self-hosted ou cloud
- **DataCrazy CRM** com Cloud API ativa. Adaptável pra Chatwoot / Kommo / Wati com pouca mudança no flow visual

## Créditos

Implementado pela [Ever Growth](https://agenciaevergrowth.com.br) e compartilhado com a comunidade DataCrazy 🇧🇷.

Adaptações pra outros BSPs bem-vindas.

## Licença

MIT — use livremente.
