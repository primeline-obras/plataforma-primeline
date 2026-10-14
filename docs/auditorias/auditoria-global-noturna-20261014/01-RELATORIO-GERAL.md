# Primeline GO — auditoria global noturna de 14/10/2026

## Resumo executivo

**Auditoria transversal local concluída nos blocos disponíveis; não é certificação exaustiva de produção.** Inventário independente pronto para reconciliação com o Backlog Mestre, que não foi localizado no repositório.

A missão acrescentou provas de três problemas P1 no código/circuito financeiro: HTML ativo no número de fatura, criação não atómica de fatura/links e recebimento parcial tratado como pagamento completo. A vulnerabilidade HR-38 anterior foi preservada sem repetir a prova. Também surgiram inconsistências de TEE/Planeamento, capability de Gestão em RNC, data civil UTC e dependências/cálculos com fontes divergentes.

**Nenhuma correção funcional foi feita.** Não houve SQL real, acesso a dados pessoais reais, push, merge, alteração de main, deploy/preview Cloudflare ou mudança de permissões. Seis scripts de auditoria/testes e documentação/evidências sintéticas são as únicas alterações. As branches anteriores e a main local permanecem intactas.

## Entregáveis

| Ficheiro | Conteúdo |
| --- | --- |
| `02-INVENTARIO-PLATAFORMA.csv` | 38 áreas; funções/perfis de vista/componentes/tabelas e RPCs de exemplo/dependências/testes/pendências/evidência |
| `03-FINANCEIRO.md` | Circuito MQT→custos→previsão→TEE→autos→faturação→recebimentos, fontes e novos achados |
| `04-ADMINISTRATIVO-RH-VIATURAS.md` | Cadastro, contrato, Medicina, ausências/FALTOU, conferência, Vencimentos, documentos, frota, alertas e restantes áreas |
| `05-FORNECEDORES-COMPRAS.md` | Diretório, fontes de preço, comparabilidade e proposta de consulta para Encarregado |
| `06-OBRA128-ADMINISTRACAO-DIRETA.md` | Reutilização, fluxo, entidades conceptuais e proposta tablet; contrato real não inferido |
| `07-SEGURANCA-PERMISSOES.md` | XSS local, permissões, tenant, writers, RLS/ACL, Storage, migrations, HR38 e custos-padrão |
| `08-PENDENCIAS-PARA-BACKLOG.csv` | 34 itens específicos classificados; preparados/standby distinguidos de desenvolvimento novo |
| `09-QUESTOES-PARA-DECISAO.md` | 20 decisões com alternativas/recomendação/dependências, sem interromper Jordane |
| `10-CONTINUACAO.md` | Checkpoints, base/branch, testes, limites e retoma |
| `11` a `20` | Referências REST/RPC e SQL, cobertura, provas sintéticas, comparação main/candidato e resultados |

Os CSVs usam UTF-8, vírgula e campos quoted. Podem ser importados com esse delimitador; não contêm dados pessoais nem linhas de negócio reais.

## Prioridades novas

| ID | Gravidade / classificação | Prova e condição | Recomendação |
| --- | --- | --- | --- |
| N-SEC-01 | P1 CONFIRMADO três sinks/browser local; produção NÃO VERIFICADA | `openPaymentDialog` interpola número de fatura sem escaping em innerHTML. Browser isolado executa marcador sintético; nomes de obra/fornecedor também expõem sinks ativos. | Corrigir escaping contextual e rever sinks em tarefa autorizada; hardening CSP não substitui a correção |
| N-FIN-01 | P1 CONFIRMADO código + fixture HTTP | Fatura grava num POST e links noutro; erro deixa draft e retry produz outro | Operação transacional backend e idempotência; upload/meta com estado/reconciliação |
| N-FIN-05 | P1 CONFIRMADO SQL atual do hotfix em PG sintético | 100 de 1000 marca pago; os 900 restantes são recusados | Decidir/implementar suporte seguro de parciais/saldos, sem compensações inventadas |
| N-FIN-06 | P2 CONFIRMADO trigger local | TEE aprovado→recusado mantém tarefa em_execucao | Política de suspensão/regularização que preserve horas/executado histórico |
| N-ADM-07 | P2 CONFIRMADO render | Gestão não tem criar RNC; Gerência tem | Aplicar capability de superutilizador conforme regra existente, sem bypass tenant |
| N-ADM-08 | P2 CONFIRMADO cenário civil | Agenda/Viaturas “hoje UTC” divergem de Lisboa na primeira hora do verão | Unificar data civil/testes DST sem alterar factos/horas |
| N-ADM-09 | P2 CONFIRMADO acoplamento | Empresa global fixa no app para vários componentes/uploads | Contexto autenticado explícito; não alegar exposição entre tenants sem backend proof |

N-FIN-02/03/04/07/08/09/10: semântica de faturado, zero/ausência, dupla origem económica, fonte contratual/fallback, IVA, distribuição mensal e granularidade TEE/auto. Comportamentos/arquitetura identificados, algumas condições funcionais/dados reais são PROVÁVEIS ou NÃO VERIFICADOS. Não transformar uma possibilidade em bug de dados confirmado.

Os sinks e o draft não atómico são **iguais entre main local `1c5fa5b` e candidato `2ae1f8a`**, assim como `rnc.js` (`18-BASE-IMPORTS.json`). Não foram apresentados como regressões novas da Gestão de Horas. Essa comparação é Git; assets servidos em produção não foram consultados nesta missão.

## Pendências já conhecidas — não duplicar

- HR-38: P1 de inferência comprovado antes. Custos-padrão independentes aprovados em princípio; fonte, aprovação, vigência/classificação ainda por fechar. HR-38/40/41/42 NÃO implementados.
- Financeiro Débitos: branch `fix/despesas-gerais-tenant-20261011`, SHA `abc160d33328e305dfdd4d4748a2973765c18c0d`; pacote local separado, precheck real PASS reportado por Jordane. Não executar backup/migration nem retirar bloqueio com base nisso.
- Fase B: branch `chore/fase-b-readiness-20261011`, SHA `b7bf4c158e93cf455cc307097eef83d90e9c6a77`; preparada, não instalada nesta missão. Preservar V2 e comportamento Encarregado.
- Gestão Integrada de Horas/AD13/14/15/AD03: desenvolvimento e auditorias preservados; não reimplementar.
- FP28/29, tolerância e almoço: standby. HE monetária/cálculos salariais e exportadores não alterados.
- Assets/smoke anteriormente fechados não foram reabertos como pendência: o histórico fornecido diz 63/63 PASS e smoke de leitura PASS. O presente candidato local e a auditoria global não fazem nova verificação de deploy.

## Cobertura e método

- 56 JavaScript de `src` levantados; interfaces/rotas inline do app incluídas; 38 áreas lógicas no CSV.
- 265 ficheiros SQL existentes, 258 indexados para declarações; 7 artefactos de seed excluídos do índice final. 588 ocorrências CREATE FUNCTION incluem versões/rollback/restauros — não são 588 funções instaladas.
- 218 referências estáticas REST/RPC e 79 referências de importação; zero imports relativos JS inexistentes nesta varredura.
- 241 MJS preexistentes no topo tests da base; 6 scripts novos de auditoria =247 no snapshot. Nem todos executados.
- Código e testes foram revistos por blocos e com provas novas; scripts históricos comparados por definição/referência. Não houve execução de todos os scripts SQL nem auditoria funcional completa de toda combinação/perfil/estado.
- Nenhum dataset real de colaboradores/fornecedores/contratos/documents/obra128 foi exportado. Artefactos não contêm tokens ou segredos. Leitura inicial de SQL para indexação extraiu somente declarações, sem copiar valores; seeds excluídos da revisão funcional e indexação final.
- Documentação histórica pode estar desatualizada; por exemplo diagnóstico RH23/09 contém lacunas já implementadas. Não deve ser convertido automaticamente em tarefas novas.

## Testes desta missão

| Bloco | PASS | FAIL | SKIP final | Natureza |
| --- | ---: | ---: | ---: | --- |
| Financeiro/Planeamento/Compras/MGO — 34 ficheiros | 108 | 0 | 0 | Maioria contratos estáticos e funções puras |
| Administrativo/RH/documentos/interfaces — 28 ficheiros | 70 | 0 | 0 | Contratos estáticos e clientes sintéticos |
| Medicina/Viaturas — 2 suites nativas | 46 | 0 | 0 | PG17.6 descartável, duas conexões, tenant/revisão/concorrência |
| Provas novas | 9 | 0 | 0 | Função real frontend, cálculos, PG nativo e render/data civil |
| HTML ativo — 3 testes browser | 3 | 0 | 0 | Browser real isolado, rede bloqueada, dados sintéticos |
| **Total final Node** | **236** | **0** | **0** | Inclui parents/subtests conforme contador Node |

Dois SKIPs iniciais de env Medicina/Viaturas foram resolvidos com paths de binários/deps já existentes, sem instalar/alterar ambiente global. Um erro inicial do harness projetou função volátil composta várias vezes; corrigido para chamada única to_jsonb, sem alterar produto/expectativa. Reexecuções e resultados antigos de 308/376 testes não foram somados. PASS das provas negativas significa que o risco foi reproduzido — não GO de segurança.

## Limites / estado por ambiente

CONFIRMADO: fontes e resultados locais apresentados. NÃO VERIFICADO: catálogo/RLS/ACL/owners atuais em produção, dados/saldos reais, CSP/headers real, SMTP/jobs, limites REST, UAT Auth hospedada completa, preços/duplicados de fornecedores e contrato da obra128. O writer legado não foi reaberto; estado CLOSED é histórico fornecido e não nova confirmação SQL.

Esta auditoria não autoriza rollout nem define nova regra de custo/permissão. Recomenda priorizar os três achados P1 novos, decisão HR38 e integridade financeira, depois fontes/semânticas e propostas. Não recomendar publicação de alterações destes circuitos sem fechar os respectivos gates. A produção existente não foi modificada nem se recomenda rollback automático.

## Retoma

Ler primeiro 10-CONTINUACAO e 08-PENDENCIAS-PARA-BACKLOG; reconciliar com Backlog Mestre mantendo IDs/estado/evidência. Branch isolada `codex/auditoria-global-noturna-20261014`; SHA final na entrega/HEAD do commit que contém este pacote. Tudo permanece local, sem push. Worktree original de Horas e main local preservadas.
