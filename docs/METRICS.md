# Métricas do handler

Queries prontas pra acompanhar performance da recuperação de contato.

## Coluna base

- `phone_requested_at` — quando pedimos o contato pro cliente (Meta interactive enviado)
- `phone_shared_at` — quando cliente respondeu (NULL se ainda não respondeu ou virou lost)
- `phone_shared_via` — `native_button` | `text_input` | NULL
- `status` — `lead_bsuid` (ativo) | `lost_bsuid` (perdido) | `orphan_contact_shared` (edge case)

## Taxa de conversão geral

```sql
SELECT
  COUNT(*) AS pedidos_total,
  COUNT(phone_shared_at) AS respondidos,
  ROUND(100.0 * COUNT(phone_shared_at) / NULLIF(COUNT(*), 0), 1) AS taxa_pct,
  COUNT(*) FILTER (WHERE status = 'lost_bsuid') AS perdidos
FROM rastreio_whats.contatos
WHERE phone_requested_at IS NOT NULL;
```

## Conversão dia-a-dia (últimos 30d)

```sql
SELECT
  DATE_TRUNC('day', phone_requested_at) AS dia,
  COUNT(*) AS pedidos,
  COUNT(phone_shared_at) AS respondidos,
  ROUND(100.0 * COUNT(phone_shared_at) / NULLIF(COUNT(*), 0), 1) AS taxa_pct,
  COUNT(*) FILTER (WHERE phone_shared_via = 'native_button') AS via_botao,
  COUNT(*) FILTER (WHERE phone_shared_via = 'text_input') AS via_digitacao,
  COUNT(*) FILTER (WHERE status = 'lost_bsuid') AS perdidos
FROM rastreio_whats.contatos
WHERE phone_requested_at > NOW() - INTERVAL '30 days'
GROUP BY 1 ORDER BY 1 DESC;
```

## Tempo médio até resposta

```sql
SELECT
  ROUND(AVG(EXTRACT(EPOCH FROM (phone_shared_at - phone_requested_at))/60)::numeric, 2) AS min_media,
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (phone_shared_at - phone_requested_at))/60)::numeric, 2) AS min_mediana,
  ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (phone_shared_at - phone_requested_at))/60)::numeric, 2) AS min_p90
FROM rastreio_whats.contatos
WHERE phone_shared_at IS NOT NULL
  AND phone_requested_at > NOW() - INTERVAL '30 days';
```

## Split por via de resposta

Quanto do funil recupera via botão vs quantos precisaram digitar?

```sql
SELECT
  phone_shared_via,
  COUNT(*) AS total,
  ROUND(AVG(EXTRACT(EPOCH FROM (phone_shared_at - phone_requested_at))/60)::numeric, 1) AS min_media
FROM rastreio_whats.contatos
WHERE phone_shared_at IS NOT NULL
GROUP BY 1;
```

Se `text_input` for >30% dos casos, considere melhorar a copy do 1º pedido pra reduzir fricção do botão.

## Impacto no funil (BSUID vs phone-normal)

Compare conversão do funil (webinar → compra) entre leads que vieram BSUID vs leads phone-normal.

```sql
WITH bsuid_leads AS (
  SELECT identifier, entrou_sala, comprou
  FROM rastreio_whats.contatos
  WHERE bsuid IS NOT NULL AND phone_shared_at IS NOT NULL
    AND criado_em_br > NOW() - INTERVAL '30 days'
),
phone_leads AS (
  SELECT identifier, entrou_sala, comprou
  FROM rastreio_whats.contatos
  WHERE bsuid IS NULL AND telefone IS NOT NULL
    AND criado_em_br > NOW() - INTERVAL '30 days'
)
SELECT
  'BSUID' AS tipo,
  COUNT(*) AS leads,
  ROUND(100.0*COUNT(*) FILTER (WHERE entrou_sala) / NULLIF(COUNT(*),0), 1) AS taxa_entrou_pct,
  ROUND(100.0*COUNT(*) FILTER (WHERE comprou) / NULLIF(COUNT(*),0), 1) AS taxa_comprou_pct
FROM bsuid_leads
UNION ALL
SELECT
  'phone-normal', COUNT(*),
  ROUND(100.0*COUNT(*) FILTER (WHERE entrou_sala) / NULLIF(COUNT(*),0), 1),
  ROUND(100.0*COUNT(*) FILTER (WHERE comprou) / NULLIF(COUNT(*),0), 1)
FROM phone_leads;
```

Se BSUID converte MENOS que phone-normal (esperado — fricção do request extra), você tem quanto está perdendo em cada etapa e pode iterar.

## Leads perdidos pra retargeting

```sql
SELECT identifier, bsuid, nome, ctwaclid, criado_em_br,
       phone_requested_at, phone_requested_at + INTERVAL '30 minutes' AS perdido_em
FROM rastreio_whats.contatos
WHERE status = 'lost_bsuid'
  AND criado_em_br > NOW() - INTERVAL '7 days'
ORDER BY phone_requested_at DESC;
```

Esses leads têm `ctwa_clid` — você pode:

1. Criar um **Custom Audience Meta** com esses BSUIDs (via Audience Network se disponível) pra retargeting
2. Rodar campanha com `REQUEST_CONTACT_INFO` template (fora da janela 24h) tentando recuperar
3. Analisar copy da 1ª msg pra descobrir onde tá o gap

## Benchmark inicial (implementação de referência)

Cliente Anderson (edtech trading, Colômbia), pouco tempo em produção:

| Métrica | Valor |
|---|---|
| Leads BSUID / total | ~19% |
| Handler executions/dia | ~30 (crescendo) |
| _Taxa conversão early_ | _pendente 7 dias_ |
| _Tempo médio_ | _pendente 7 dias_ |

Se você implementar e tiver dados, PR bem-vindo pra atualizar aqui.
