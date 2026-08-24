# O que foi feito e como funciona agora

Documento pra você entender a mudança que aconteceu no seu WhatsApp — sem parte técnica.

## O problema que a gente resolveu

Nas últimas semanas, o WhatsApp mudou uma coisa importante em alguns países (Colômbia entre eles): agora **1 em cada 5 clientes** que chega no seu WhatsApp vem **sem o número de telefone**. No lugar do telefone, aparece só um código estranho tipo `CO.99999999999999999`.

Isso quebrava várias coisas do seu funil:
- O rastreamento **não conseguia ligar** o cliente que entrou na live com o cliente que comprou
- Você **não sabia mais** de qual anúncio veio a venda
- O **CPA subia** porque o Meta parava de otimizar direito
- Cerca de **20% dos leads viravam "fantasmas"** no dashboard

## O que a gente fez

Montamos uma automação nova que:

1. **Detecta** quando o cliente chegou sem telefone
2. **Pede o telefone** pra ele — usando um botão nativo do próprio WhatsApp (1 clique, sem digitação)
3. Se ele **não clicar em 3 minutos**, mandamos uma segunda mensagem reforçando
4. Se **ainda não clicar em 10 minutos**, pedimos pra ele digitar o número direto no chat
5. Assim que o telefone chega, **encaixa ele de volta no funil normal** — o resto continua igual

Tudo automático. Você não precisa fazer nada manualmente.

## O que o cliente vê

Quando ele entra sem telefone, recebe uma mensagem tipo:

> Hola Juan 👋
> Para reservarte el enlace de la clase, necesito tu WhatsApp verificado — es 1 toque abajo, no tienes que escribir nada 👇
>
> [ 📇 Compartir contacto ]

Ele toca uma vez, o WhatsApp confirma "Compartilhar contato com este business?" e pronto. Nós recebemos o telefone verificado dele.

## Se o cliente não responder

Passou 30 minutos e o cara não clicou em nada nem digitou o número? A gente coloca uma **etiqueta "lost_bsuid"** no cadastro dele.

Isso é ouro pra analisar depois:
- Quantos você tá perdendo por causa dessa mudança do WhatsApp
- Se a copy da mensagem precisa mudar
- Pra reativar mais tarde via campanha de retargeting

## O que muda pra você no dia a dia

**Nada.** Você continua operando exatamente como antes. As automações antigas continuam ligadas do jeito que estavam. A única diferença é que agora o telefone dos clientes "invisíveis" também aparece.

O único **cuidado novo**: se a Meta liberar mais campanhas suas ou você mudar keyword, avisa a gente pra ajustar a automação. Ela hoje escuta a keyword `"SUA_KEYWORD_DA_CAMPANHA"` — se campanha nova mandar outra frase, precisa incluir na configuração.

## O que dá pra medir agora

- **Quantos leads chegam sem telefone por dia**
- **Quantos desses respondem** ao pedido de contato (taxa de conversão)
- **Quanto tempo em média** demora pra responder
- **Se preferem o botão ou digitar** (indica se a UX tá boa)
- **Quantos você perde** por não responder

## Materiais entregues

Além dessa automação:

- **Documentação técnica completa** (pra caso você troque de agência ou queira auditar)
- **Templates prontos** pra publicar como projeto open-source (a gente vai compartilhar com a comunidade DataCrazy — outros vão passar pelo mesmo problema no rollout global do WhatsApp)
- **Queries SQL** pra dashboard de conversão do handler

Qualquer dúvida técnica, chama.

— Ever Growth
