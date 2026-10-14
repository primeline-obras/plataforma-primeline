# Plano verificável de correções — Fase 2

## Estado

Plano proposto, não autorização de implementação. Os três P1 continuam abertos; HR38 preservado. Scripts de produto não foram criados/alterados; não existe rollout preparado para estas novas correções. Catálogo real não foi consultado.

`34-PENDENCIAS-CLASSIFICADAS.csv` contém os 34 IDs originais, evidência anterior, classificação técnica/funcional, componentes, dependências, critérios objetivos, testes, independência e risco. A coluna ordem_proposta é única de 0 a 33; é sequência de revisão recomendada, não um calendário nem aprovação.

## Ordem completa

| Ordem | ID | Trabalho / gate |
| ---: | --- | --- |
| 0 | N-SEC-03 | Manifest de fontes/dependências/hash/ACL antes de novos rollouts |
| 1 | N-SEC-01 | Saída HTML contextual, oito renderizadores confirmados; sem decisões financeiras |
| 2 | N-SEC-02 | Identificar scripts históricos perigosos; catálogo só quando autorizado |
| 3 | N-FIN-01 | Núcleo transacional cliente; filho N2-FIN-01 fornecedor; desenho Storage pendente |
| 4 | N-FIN-05 | Consolidar writers de recebimento e consumidores; filhos N2-FIN-02/03; decisão Q04 |
| 5 | HR-38 | Fonte de padrão independente e privacidade, após Q01–03 |
| 6 | DD-TENANT | Reutilizar pacote abc160d já preparado; autorização futura própria |
| 7 | N-FIN-07 | Fonte vigente de contrato/DTO completo, Q10 |
| 8 | N-FIN-02 | Métricas medido/emitido/recebido/avanço, Q05 |
| 9 | N-FIN-03 | Zero versus NULL, após diagnóstico Q06 |
| 10 | N-FIN-04 | Reconciliação factual de fontes, sem deduplicar por valor/texto |
| 11 | N-FIN-08 | Bases IVA/moeda aprovadas, Q08 |
| 12 | N-FIN-06 | Revogação TEE e autorização futura, Q07 |
| 13 | N-FIN-09 | Cronograma de compromisso, se substituir regra mês-início for aprovado |
| 14 | N-FIN-10 | Quantidades/artigos TEE→auto→fatura, Q16 |
| 15 | N-DOC-01 | Intenções de upload/finalização/recovery; retenção explícita |
| 16 | N-ADM-07 | Aplicar regra Gestão RNC; tenant e Gerência separados |
| 17 | N-ADM-08 | Dia civil Lisbon, sem FP28/29 |
| 18 | N-ADM-09 | Contexto empresa validado, depois de mapear ACL/contexto |
| 19 | N-FOR-02 | Paginação/completude e contagem |
| 20 | N-FOR-03 | Comparabilidade de unidade/base aprovada |
| 21 | N-FOR-05 | Proveniência/estado incompleto dos preços |
| 22 | N-SEC-04 | SRI/CSP/CDN com testes de compatibilidade |
| 23 | UAT-HOSTED | UAT por perfil para o lote que ficou corrigido; catálogo e autorização nova |
| 24 | N-OB128-01 | Contrato/preço/aprovação da administração direta, Q14 |
| 25 | N-OB128-02 | Apropriar factos únicos sem duplicar ponto/custo, Q15 |
| 26 | N-ADM-11 | Canal email se aprovado; nunca confundir flag com entrega |
| 27 | N-ARCH-02 | Inventário de reachability legado; writer CLOSED preservado |
| 28 | N-FOR-04 | Diagnóstico de cadastro real autorizado, sem mescla automática |
| 29 | N-ADM-10 | Documentos antigos marcados como históricos, links de fecho |
| 30 | PHASE-B | Revisão pacote b7bf4c1 separado; não consumir gate nem instalar |
| 31 | N-ARCH-01 | Extrações incrementais depois dos bloqueios, sem redesign |
| 32 | N-FOR-01 | Nova consulta comercial do Encarregado só se aprovada |
| 33 | FP-28/29 | Manter standby até decisão ADM/RH |

Itens documentais e diagnóstico independente podem ocorrer mais cedo; esta ordem exprime dependência/risco. UAT não precisa esperar funcionalidades futuras que não fazem parte do lote, mas não pode certificar um P1 aberto desse lote.

## Lotes de trabalho e aceitação

### Lote A — Segurança de saída e cadeia de rollout

N-SEC-01/02/03. Sem mudança de dados/permissões. Pré-condição: preservar fontes e criar baseline de saída. Aceitação: nenhum campo livre confirmado cria nó/handler; textos/ícones/tabela/ações preservados; mensagens de erro literais; todos imports e tablet funcionam; scripts antigos inequivocamente históricos. Provas negativas/positivas browser. CSP/SRI é hardening posterior, não compensação do HTML inseguro.

### Lote B — Faturas atómicas

N-FIN-01 + N2-FIN-01 + integração mínima N-DOC-01. Definir PDF obrigatório/opcional sem inventar. RPC cabeçalho+linhas, vínculo validado, lock/revisão/idempotência. Storage intent/finalize separado. Aceitação: falhas BD sem cabeçalho/linhas parciais; resposta perdida recupera mesma operação; concorrência mesmo auto perde integralmente; itens fornecedor falhados não aparentam sucesso; exceções atuais de duplicado preservadas. Testar actor/tenant/obra e replays com payload diferente. Reconciliação de órfãos reais numa tarefa futura autorizada, sem delete automático.

### Lote C — Recebimentos coerentes

N-FIN-05 + N2-FIN-02/03 + Q04/Q05. Primeiro inventariar instalação da RPC parcial/ledger/grants (tarefa read-only futura), depois decidir excesso/estorno/legado. Reutilizar mecanismo seguro existente; não ligar a UI enquanto a API antiga puder sobrescrever. Aceitação: 100/900 mantêm saldo e fecham integralmente; outubro/novembro 100/900 nos mapas; ledger e cabeçalho iguais; estados pagamento/aprovação independentes; concorrência/replay/centavos/revogação; dados antigos sem movimentos ficam explícitos, não reconstruídos por inferência.

### Lote D — Inferência HR38

Não repetir o desenvolvimento da Gestão de Horas nem reabrir HR29. Fonte-padrão independente aprovada, revisão/vigência e ausência de fallback RH. Aceitação: mudar tarifa individual RH não muda o custo técnico padrão; consultas autorizadas não revelam evidência confidencial; singleton/diferença/composição testados; padrão em falta tem estado aprovado. Depende Q01–03. Sem alteração de salários/FP28/29.

### Lotes E/F — Dados e funcionalidades posteriores

E: indicadores/fonte/vigência, após Q05/06/08/09/10. F: compras/preços/administração direta, após Q11–16 e dados factuais. Paginação/data civil/documentação podem ser tarefas pequenas independentes. Não usar problemas de qualidade não comprovados para apagar cadastros ou retirar custos.

## Gate de cada futura correção

1. Branch isolada a partir da base reconciliada, preserving fixes anteriores e diff limitado.
2. Prova anterior reproduzida; correção e provas que agora recusam o estado inválido.
3. Aceitação por campo/consumidor/perfil; regressões e concorrência necessárias, sem testar escrita real por conveniência.
4. Se BD: precheck read-only/baseline; backup específico; migration transacional; postcheck; rollback preparado/testado. Storage não promete atomicidade com SQL.
5. Revisão independente; inventário real autorizado; STOP em divergência/ambiguidade; aprovação expressa para etapa real.
6. Só depois integração/deploy/smoke autorizado. Nenhuma destas etapas foi autorizada por este plano.

## Pacotes anteriores preservados

- DD-TENANT: `fix/despesas-gerais-tenant-20261011`, `abc160d33328e305dfdd4d4748a2973765c18c0d`. Precheck real PASS foi informado previamente; não foi reexecutado. Não significa backup/migration autorizados.
- Fase B: `chore/fase-b-readiness-20261011`, `b7bf4c158e93cf455cc307097eef83d90e9c6a77`. Preparado/revisão pendente; nenhuma Fase B real.
- AD13/14/15 e Gestão de Horas: preservar correções e contratos preparados; nenhum cálculo salarial ou regra diária foi modificado.

## GO/NO-GO

**GO para revisão e criação futura de tarefas controladas. NO-GO para publicação deste diagnóstico como se os P1 estivessem fechados.** A entrega é documentação, testes e evidências locais. Não houve correção do produto.
