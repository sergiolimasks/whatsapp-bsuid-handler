# Por que este projeto existe

## Timeline da mudança

- **Junho/2026** — Meta libera **usernames** no WhatsApp em rollout gradual, começando por Colômbia e México
- **Julho/2026** — Business Scoped User IDs (**BSUIDs**) começam a aparecer nos webhooks Meta Cloud API mesmo pra usuários que ainda não adotaram username
- **Agosto/2026** — em mercados de rollout ativo, 15-25% dos leads CTWA passam a chegar **sem telefone**, só com BSUID no lugar
- **Fim de 2026** — rollout global esperado

## O que é BSUID

Um identificador único por par **usuário↔business portfolio** gerado pela Meta:

```
CO.13491208655302741918
BR.1890869588965887
```

Formato: prefixo ISO 3166 de 2 letras + ponto + até 128 caracteres alfanuméricos.

Características:
- **Estável** — não muda se o usuário remover ou trocar o username
- **Único por par** — o mesmo usuário conversando com 2 businesses tem 2 BSUIDs diferentes
- **Sempre presente** — vem em todos os webhooks, mesmo pra usuários que não adotaram username (a Meta já preenche pra preparar o ecossistema)

## O que muda no webhook Meta

**Antes:**

```json
{
  "contacts": [{"profile": {"name": "Juan"}, "wa_id": "573001234567"}],
  "messages": [{"from": "573001234567", "type": "text"}]
}
```

**Depois** (usuário com username adotado):

```json
{
  "contacts": [
    {
      "profile": {"name": "Juan", "username": "juan.trading"},
      "user_id": "CO.13491208655302741918"
      // wa_id ausente
    }
  ],
  "messages": [{"from_user_id": "CO.13491208655302741918", "type": "text"}]
}
```

O campo `wa_id` some. `from` também. No lugar entram `user_id` e `from_user_id`.

## Por que isso quebra funis reais

A maioria dos funis de vendas WhatsApp assume telefone como chave primária:

- **CRM** — usa phone pra identificar lead único
- **Webinar/Live** — inscrição pede telefone, dispara mensagem WA no phone
- **Checkout externo** (Hotmart, Kiwify, Greenn) — pede telefone e retorna webhook com phone pra fazer match reverso
- **Meta Conversions API** — precisa do `ph` (phone hash) OU `ctwa_clid` pra reportar Purchase de volta pro anúncio
- **Automações email** — sincronia CRM ↔ ferramenta email usa phone como matching key

Quando o phone some, cada uma dessas etapas quebra individualmente. Resultado prático em produção:

- **CPA sobe** — Meta para de otimizar porque não recebe eventos de conversão amarrados ao ad clicado
- **Retargeting quebra** — custom audiences por phone match não pega os BSUID-only
- **Follow-up para** — bots que disparam mensagem em phone específico não conseguem enviar pra quem só tem BSUID
- **Attribution vira sopa** — 15-20% dos leads viram "sem origem" nos dashboards

## Como a Meta espera que seja resolvido

Documentação oficial: [Meta for Developers — Business-scoped user IDs](https://developers.facebook.com/documentation/business-messaging/whatsapp/business-scoped-user-ids/)

A Meta introduziu junto com o rollout um mecanismo **nativo** pra recuperar o phone:

- **Interactive message tipo `request_contact_info`** — envia botão nativo pro cliente. Cliente toca 1×, phone verificado é entregue no webhook
- **Template com button `REQUEST_CONTACT_INFO`** — mesma coisa, mas dentro de template aprovado (funciona fora da janela 24h)

O business é responsável por:

1. Detectar leads BSUID-only
2. Pedir o phone via um dos 2 mecanismos acima
3. Casar o phone recebido com o BSUID original
4. Continuar o funil normal usando o phone

Este projeto implementa exatamente isso.

## Referências

- [BSUID technical docs](https://developers.facebook.com/documentation/business-messaging/whatsapp/business-scoped-user-ids/)
- [Interactive messages — request_contact_info](https://developers.facebook.com/documentation/business-messaging/whatsapp/business-scoped-user-ids/#requesting-phone-numbers-from-users)
- [CM.com — Guia BSUID pra businesses](https://www.cm.com/blog/whatsapp-usernames-for-business-what-you-need-to-know/)
- [360dialog — Migração de webhooks](https://docs.360dialog.com/docs/resources/phone-numbers/usernames-and-bsuid)
