Fala pessoal, tudo certo?

Compartilhando aqui uma solução que a gente montou pra resolver o novo rollout de BSUID do WhatsApp, que tá batendo forte principalmente em Colômbia e México (mas vem pro Brasil).

*O problema*

Desde julho, o WhatsApp deixou o usuário adotar username e ocultar o telefone quando conversa com empresa. No lugar do phone, chega só um código tipo CO.13491208655302741918 (BSUID).

Impacto no funil:

- Rastreamento quebra (cliente que entra na live não casa com quem comprou)
- Meta perde atribuição (CAPI sem phone ou ctwa_clid não fecha)
- CRM fica sem chave única
- Automações de follow up param de disparar

Em cliente nosso rodando CTWA na Colômbia, cerca de 20 por cento dos leads viraram fantasmas.

*A solução*

Fluxo end to end que detecta o lead BSUID, pede o telefone via botão nativo do WhatsApp (interactive request_contact_info da Meta), com 3 tentativas mais fallback pra digitação livre, e no final aplica uma tag no lead pro seu funil de produção pegar dali.

O cliente vê uma mensagem tipo "compartilha teu WhatsApp" com um botão nativo. Toca uma vez, o próprio WhatsApp envia o telefone verificado. Zero fricção, zero digitação.

*O que tá no repo*

- Flow completo pra importar no DataCrazy (18 blocos, tudo comentado com cartezinhos)
- 3 workflows n8n prontos (pedir contato Meta, capturar share, fallback digitação)
- Documentação técnica separada da documentação pra cliente final

Stack: DataCrazy Cloud API oficial mais n8n mais Meta Graph API v22.

Aberto, MIT, adaptável pra Chatwoot, Kommo, Wati com mudanças pequenas.

Link: https://github.com/sergiolimasks/whatsapp-bsuid-handler

Se implementar e quiser trocar ideia, chama. Se ajudar aí, deixa uma star pra facilitar quem vier depois procurando.

Abraço.
