# 20 decisões revistas — Fase 2

Sem perguntas durante a missão. Nenhuma proposta foi implementada nem ausência de resposta tratada como autorização. Mantêm-se todos os Q01–Q20, mesmo quando consolidados.

## Classificação completa

| ID | Categoria | Estado factual / decisão restante | Alternativas e recomendação |
| --- | --- | --- | --- |
| Q01 | BLOQUEANTE para mitigação HR38 | Padrão separado de RH aprovado em princípio; fonte final não provada | Orçamento aprovado / tabela por empresa / fonte comercial autorizada. Recomenda-se fonte independente explicitamente aprovada, sem inferência das tarifas RH |
| Q02 | BLOQUEANTE para HR38 | Aprovador, função/nível e vigência do padrão precisam definição | Administrativo/RH ou Gestão com competência expressa; revisão histórica e classificação específica, nunca cargo formal=login automaticamente |
| Q03 | BLOQUEANTE para publicar mitigação HR38 | Confidencialidade RH é resolvida; formato técnico sem padrão ainda é proposta | NULL/pendente vs intervalo aprovado. Recomenda-se NULL/pendente, nunca tarifa RH/zero substituto; não se afirma que essa UI já foi autorizada |
| Q04 | BLOQUEANTE para N-FIN-05 | RPC parcial existente; diálogo chama antiga; excesso/estorno/crédito não definidos | Só integral provisório vs integrar parcial existente. Recomenda-se integração e saldo/movimentos por data; regra de excesso explícita antes de aceitar |
| Q05 | BLOQUEANTE para N-FIN-02 e reconciliação de mapas | Draft e avanço participam de um indicador chamado faturado | Renomear indicador vs decompor. Recomenda-se medido/aprovado/emitido/recebido/avanço separados com fontes explícitas |
| Q06 | SEM EVIDÊNCIA SUFICIENTE | Fallback de zero demonstrado; uso histórico de zero como ausência não demonstrado | Não fazer backfill. Primeiro inventário autorizado de zero/NULL/origem; se zero legítimo, fallback só em ausente. Não decidir por aparência |
| Q07 | BLOQUEANTE para N-FIN-06 | Tarefa permanece em_execucao após recusa do TEE | Suspender futuro / manter exceção aprovada. Recomenda-se preservar trabalho já feito e sinalizar futura autorização; apagar histórico não é alternativa recomendada |
| Q08 | BLOQUEANTE para alterar bases financeiras/comparativos | IVA/moeda/bases não são intercambiáveis | Sem IVA para custo/margem e com IVA para caixa, se regra aprovada; preferir indicadores identificados e desconhecido pendente, sem taxa inferida |
| Q09 | PODE AGUARDAR | Modelo mês-início existe; não foi declarado proibido | Manter identificado / cronograma / medição. Recomenda-se cronograma aprovado por origem; não distribuir uniformemente sem regra; meses fechados intactos |
| Q10 | BLOQUEANTE para unificar indicadores | Seleção de contrato/fallback varia | Fonte vigente por versão/data explicitamente escolhida; não selecionar pelo primeiro/último registo arbitrariamente |
| Q11 | PODE AGUARDAR; bloqueia apenas nova capability | Encarregado não ter preços hoje não é bug | Própria obra / interobra mesmo tenant / padrão. Recomenda-se DTO mínimo read-only, após decidir partilha; sem SELECT faturas ou escrita de compra |
| Q12 | PODE AGUARDAR; bloqueia novo comparador comercial | Unidades e fontes heterogéneas não provam comparabilidade | Proposto/adjudicado/faturado identificados; grupos por unidade/especificação/base. Recomenda-se proveniência explícita antes de ranking |
| Q13 | SEM EVIDÊNCIA SUFICIENTE | Duplicados reais de fornecedores não consultados | Governança humana por ID/NIF/FKs; diagnóstico factual autorizado antes de decidir mescla; nunca deduplicar só nome |
| Q14 | BLOQUEANTE para implementar administração direta 128 | Regra contratual real/valor final não disponível nesta missão | Fixo / recursos / unidade conforme contrato demonstrado. Não inventar margem ou fórmula comercial |
| Q15 | PODE AGUARDAR; bloqueia apenas futura apropriação | Horas existentes não devem ser copiadas como novos pontos | Referência a facto único com alocação limitada; compra≠entrega≠consumo. Recomenda-se vínculos factuais revisáveis e conferência, sem duplicação |
| Q16 | BLOQUEANTE para circuito incremental 128 | Aprovação técnica/comercial e artigos ainda precisam contrato | Etapas com fingerprints e limites/medição acumulada; revisão invalida aprovação dependente. Não assumir um cabeçalho resolve artigos |
| Q17 | PODE AGUARDAR | Flag enviar_email não prova entrega; in-app existe | Ficar in-app / serviço autorizado. Recomenda-se estado de envio e responsável/destinatários/limites antes de anunciar email como entregue |
| Q18 | RESOLVIDA POR REGRA DOCUMENTADA para Gestão | Gestão funcional superutilizador com tenant/auditoria preservados | Preparar correção RNC usando capability explícita; Gerência separada, sem extensão automática por helper admin. Não pedir nova aprovação da regra Gestão |
| Q19 | PODE AGUARDAR decisão de retenção; núcleo TÉCNICO | Orfandade é problema de integração, não decisão de negócio sobre atomicidade | Pending/finalize/reconciler auditado. Recomenda-se recuperação com proveniência; prazo/eliminação precisam aprovação. PDF obrigatório também precisa requisito documental |
| Q20 | RESOLVIDA quanto à necessidade TÉCNICA; execução continua sujeita a autorização | Manifest é engenharia de rollout; não requer nova regra financeira | Baselines/hash/owner/ACL/deps e abort em divergência. Catálogo real/ordem final/aplicação exigem tarefa autorizada; não há aprovação de rollout implícita |

Categorias principais: **10 bloqueantes, 6 podem aguardar, 2 resolvidas quanto ao núcleo e 2 sem evidência suficiente**. Bloqueante é relativo à correção dependente, não impedimento de escapar HTML ou documentar manifest. A falta de Q14 não bloqueia um bug de toast.

## Consolidação sem perder perguntas

### Grupo D1 — Q01/Q02/Q03, custos-padrão

Uma decisão coerente deve identificar fonte, aprovador, classificação, vigência e comportamento quando falta padrão. Não implementar mínimo de trabalhadores, ocultação temporal ou granularidade nova para contornar HR38 sem aprovação. Alternativa padrão independente preserva mapas técnicos, mas exige manutenção explícita e testes de que não deriva de salários/tarifas RH.

### Grupo D2 — Q04/Q05, dinheiro e indicadores

Decidir parcelas/excesso/estornos e nomes/fontes dos indicadores em conjunto. Não precisa decidir toda administração direta para obter atomicidade. Recomenda-se reutilizar RPC parcial com revisão e adaptar todos consumidores para movimentos. Sobrepagamento como crédito separado é alternativa, não regra aprovada. Conciliação de recebimentos antigos não será feita por inferência.

### Grupo D3 — Q06/Q08/Q09/Q10, bases e vigência

Q10 escolhe fonte vigente; Q08 define bases. Q06 precisa evidência de dados. Q09 pode aguardar enquanto a previsão atual estiver identificada. Não confundir pendência de decisão com obrigação de mudar toda fórmula agora.

### Grupo D4 — Q11/Q12/Q13, preços e qualidade

Autorização comercial, origem/unidades e governança são decisões relacionadas, mas distintas. Primeiro diagnóstico/proveniência; só depois nova capability. Não usar esta auditoria para conceder acesso a preços ao Encarregado.

### Grupo D5 — Q14/Q15/Q16 (+Q08), obra 128

Contrato/preço/limites e aprovação por artigo precedem modelo. Referenciar recursos existentes sem duplicar factos. Sem dados reais/contrato, o pacote fica proposta; não inventar preço final nem margem.

### Grupo D6 — Q17/Q19/Q20, integrações e rollout

SMTP/retensão são escolhas de operação; transação/idempotência/manifest são requisitos técnicos. Reutilizar componentes seguros existentes. Nada nesta consolidação autoriza envio de emails, apagar objetos ou SQL real.

### Q18 — executar regra existente em futura correção

Gestão não deve perder permissões nem ganhar bypass de tenant. Corrigir a UI/capability local só quando essa tarefa for autorizada. A revisão independente de Gerência utiliza as regras existentes, não uma equiparação à Gestão.

## Ordem para Jordane decidir

1. D1 para fechar inferência HR38, se publicação da Gestão de Horas for o objetivo.
2. D2 para recebimentos/indicadores, prioritário com as três falhas monetárias novas.
3. Q10/Q08 e Q07 conforme frente escolhida.
4. D5 antes de administração direta 128; D4 antes de preços para Encarregado.
5. Email, distribuição mensal e retenção podem aguardar sem alterar funcionalidades atuais; integrar atomicidade técnica primeiro.

Regras preservadas: confidencialidade RH, perfil operacional distinto de cargo formal, Gestão superutilizador funcional com tenant, factos históricos imutáveis, Folha V2 existente, FP28/29 standby. Não fazer novas funcionalidades para resolver perguntas sem resposta.
