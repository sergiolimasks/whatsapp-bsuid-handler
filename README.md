# WhatsApp BSUID Handler

> Recupera automaticamente o telefone de leads WhatsApp que vêm sem número (BSUID-only) usando o botão nativo `request_contact_info` da Meta Cloud API.

**Stack:** DataCrazy CRM + n8n + Postgres + Meta Graph API v22.0

**Status:** rodando em produção desde 2026-08-24 em cliente com ~19% dos leads CTWA colombianos vindo como BSUID-only.

---

## O problema

Em junho/2026 o WhatsApp começou a permitir que usuários adotassem **username** e ocultassem o telefone quando conversam com empresas. No lugar do phone, o business recebe um **BSUID** (Business-Scoped User ID) tipo `CO.13491208655302741918`.

Rollout começou pela Colômbia e México, expandindo globalmente ao longo de 2026.

**Impacto direto:**
- Match end-to-end quebra: cliente entra por CTWA sem phone → webinar/checkout Hotmart não conseguem casar de volta com o lead original
- Meta Ads perde a capacidade de otimizar: sem `Purchase` retornando via CAPI amarrado ao `ctwa_clid`, o algoritmo fica cego
- Automações CRM (RD, ActiveCampaign, HubSpot) que usam phone como chave primária param de funcionar em ~20% dos leads

## A solução

Este projeto implementa o fluxo oficial que a Meta recomenda:

1. Cliente entra no WhatsApp via CTWA
2. Detector identifica que veio sem telefone (só BSUID)
3. Bot pede o contato via mensagem interativa nativa (`request_contact_info`)
4. Cliente toca em **"Compartilhar contato"** — 1 clique, sem digitação
5. Sistema recebe o phone, casa com o BSUID, e aplica uma tag
6. Automações de produção continuam pelo caminho normal

Se cliente não clicar na primeira, **retry 2× e fallback pra digitação livre** antes de marcar como perdido.

## O que está incluído

```
├── datacrazy/
│   └── bsuid-handler-flow.json      # Fluxo DC completo (18 blocos, 18 notes)
├── n8n/
│   ├── B4uSYI9a-pedir-contato.json           # Recebe do DC, chama Meta
│   ├── NlV8VWlq-contato-compartilhado.json   # Salva phone quando cliente clica
│   └── 19arHsjI-contato-digitado.json        # Fallback text_input
├── postgres/
│   └── migration.sql                # ALTER TABLE + índices + colunas de métrica
└── docs/
    ├── WHY.md                       # Background do problema BSUID
    ├── ARCHITECTURE.md              # Desenho end-to-end + fluxo de dados
    ├── SETUP.md                     # Passo-a-passo de implementação
    ├── META-INTERACTIVE.md          # Payload da API request_contact_info
    └── METRICS.md                   # Como medir conversão do handler
```

## Quick start

1. Leia [`docs/WHY.md`](docs/WHY.md) pra entender o contexto se você não conhece BSUID
2. Rode [`postgres/migration.sql`](postgres/migration.sql) no banco do seu funil
3. Importe os 3 workflows do [`n8n/`](n8n/) — configure credencial Postgres + Meta token
4. Importe o flow do [`datacrazy/`](datacrazy/) — substitua os placeholders `YOUR_XXX`
5. Detalhes em [`docs/SETUP.md`](docs/SETUP.md)

## Requisitos

- **Meta Cloud API oficial** (não funciona com WhatsApp Business App standalone). Se você usa DataCrazy, WhatsApp Coexistence Mode conta como Cloud API oficial
- **n8n** self-hosted ou cloud (usado o `n8neditor.sykedigital.com.br` na implementação de referência)
- **Postgres 12+** (usa GENERATED COLUMN STORED)
- **DataCrazy CRM** com Cloud API integration ativa. Adaptável pra Chatwoot / Kommo / Wati com pouca alteração no flow visual

## Créditos

Implementado pela [Ever Growth](https://agenciaevergrowth.com.br) pra cliente de trading em edtech colombiano. Compartilhado com a comunidade DataCrazy 🇧🇷.

Contribuições/adaptações pra outros BSPs bem-vindas.

## Licença

MIT — use livremente, atribua se ajudar.
