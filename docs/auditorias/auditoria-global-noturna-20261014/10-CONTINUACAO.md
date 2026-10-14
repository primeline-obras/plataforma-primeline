# Continuação — auditoria global noturna

## Checkpoint 0 — preparação (14/10/2026, cerca de 20h00 Lisboa)

- Base de produto: 2ae1f8a194f23d77bf0692d0a6d586566227298c.
- Base de auditoria: 12d86584c16ed640c3c0b5782f4c9cf839593149.
- Branch isolada: codex/auditoria-global-noturna-20261014.
- Worktree: C:/Users/conta/.codex/worktrees/auditoria-global-noturna-20261014/primeline-go-urgente.
- Branches e produto anteriores preservados; árvore inicial limpa.
- Apenas análise, documentação e testes sintéticos. Sem push, produção ou alterações funcionais.
- HR-38: reutilizar prova anterior; decisão de custos-padrão aprovada em princípio, fonte/aprovação/vigência pendentes. Não implementar HR-38/40/41/42.
- Backlog Mestre não localizado nos nomes de ficheiros do repositório; produzir inventário independente.

## Plano de blocos

1. Inventário/entrada/segurança estática.
2. Financeiro e cadeia MQT/TEE/autos/faturas/recebimentos.
3. Administrativo/RH/viaturas/documentos.
4. Fornecedores/compras/preços e proposta obra128.
5. Testes focados, decisões, backlog e consolidação.

A execução não garante temporizador. Não iniciar análise longa após 05h30 Lisboa; terminar em oportunidade segura às 06h00. Se concluída antes, não prolongar artificialmente.

## Checkpoint 1 — inventário e provas novas (14/10/2026)

- 56 JS, 265 SQL e 242 MJS do topo tests abrangidos pelo levantamento estático (não é revisão funcional exaustiva).
- 218 referências estáticas REST/RPC; 588 ocorrências CREATE FUNCTION, incluindo restauros/versões.
- 38 áreas inventariadas; os perfis CSV são autorização da vista, não concessão de cada ação.
- Financeiro: 108 PASS; novas provas finais: 9 PASS. PASS nas provas significa reprodução dos achados, não ausência de problema.
- Administrativo estático: 70 PASS; dois SKIPs de ambiente reexecutados com binários locais disponíveis.
- Reexecução nativa Medicina/Viaturas: 46 PASS /0 FAIL /0 SKIP. Não instalaram dependências.
- Achados novos: fatura/links não atómicos; parcial fecha recebimento; TEE revogado mantém tarefa; Gestão sem criar RNC. Sem correções.
- Provas aritméticas adicionais (zeros/faturado/dupla fonte) são contratos a reconciliar, não prova de dados reais errados.

## Checkpoint 2 — fornecedores e proposta obra128

- Diretório/histórico de preços existente inventariado; duplicados/cadastros reais NÃO VERIFICADOS.
- Proposta de leitor dedicado para Encarregado separa consulta de compra/adjudicação; nenhuma permissão alterada.
- Obra128: cadeia conceptual TEE→execução→conferência→valorização→auto; sem margens/preços/contrato inferidos e sem migrations.
- Browser isolado sem rede reproduziu N-SEC-01 no diálogo real de recebimento: elemento HTML + marcador executado; nenhuma exploração ou conta real.

## Checkpoint 3 — segurança/decisões/backlog

- 34 pendências específicas, com prioridade/classificação/evidência/dependências; inclui preparadas/standby sem duplicar implementação.
- 20 questões reunidas; nenhuma pergunta funcional enviada nem aprovação inferida.
- N-SEC-01 comprovado em browser; 234 PASS finais únicos/0 FAIL/0 SKIP, não contar reexecuções nem provas antigas HR38.
- Comparação normalizada confirmou submitBilling/openPaymentDialog e RNC iguais na main local e no candidato: não são demonstradas regressões do pacote Horas. Produção não consultada.
- Zero imports relativos JS em falta. Seeds excluídos do índice final: 258 SQL indexados de 265 ficheiros.

## Checkpoint 4 — consolidação

- Entregáveis 01–10 completos; índices/evidências11–19 anexados.
- Testes finais234PASS/0FAIL/0SKIP, com tipo/limites declarados; nenhum resultado antigo somado.
- Riscos reais desconhecidos são assinalados; missão não certifica segurança exaustiva de produção.
- Encerramento antecipado dos blocos locais disponíveis; não simula execução até06h00 nem mantém automação temporal. Questões restantes dependem de contrato/decisão/catálogo/UAT autorizados, não de nova implementação nesta missão.
- Nada publicado, enviado ao remoto, apagado ou aplicado na BD real.

## Como reproduzir sem produção

1. Checkout desta branch local, ler os relatórios; não executar nenhum SQL histórico no Supabase.
2. Metadados: `node tests/night-global-inventory.mjs`; `node tests/night-global-modules.mjs`; `node tests/night-global-baseline.mjs`; `node tests/night-global-backlog.mjs`. Apenas Git/source/artefactos locais.
3. Provas: definir QUADRO_PG_BIN para TEMP/primeline-doc-guard-pg176/package/native/bin e QUADRO_TEST_DEPS para TEMP/primeline-medicina-test-deps/runtime/node_modules; `node --test tests/night-global-findings.test.mjs` (9 PASS). Guardar resultados; clusters param localhost, trust apenas efémero, teardown stop.
4. Browser: PLANNING_PLAYWRIGHT para instalação local Playwright existente, PLANNING_CHROMIUM_EXE para Edge existente; `node --test tests/night-global-browser-security.test.mjs` (1 PASS). Rede bloqueada; sem login/servidor remoto.
5. Medicina: MEDICINA_PG_BIN/MEDICINA_TEST_DEPS nos mesmos binários/deps. Viaturas: VIATURAS_PG_BIN e VIATURAS_PG_MODULE apontando ao módulo pg existente. Scripts/listas completos em 19-TESTES-E-LIMITES.json. Não instalar dependências globais só para contornar falta; nesse caso registar SKIP.
6. Os dois grupos de regressão usam os ficheiros listados no JSON. Priorizar apenas grupo relevante para mudança futura; não repetir centenas sem necessidade.

## Próximos passos

- Reconciliar 34 itens com Backlog Mestre, mantendo IDs; distinguir novo/confirmado/provável/não verificado/preparado/standby.
- Aprovar tarefas de correção dos três P1 novos (HTML/draft/saldo), sem editar main por esta auditoria.
- Fechar Q01–03 antes de implementar HR38/40/41/42; demais decisões em09.
- Financeiro e FaseB preparados continuam em branches originais; não repetir trabalho nem assumir autorização real.
- Contrato/preços/dados reais da obra128 e fornecedores ficam para consulta autorizada futura; proposta06 não autoriza implantação.
- Não há novas correções funcionais, SQL preparado para implantação ou mudança de permissões neste pacote.

## Preservação final

SHA desta auditoria: commit que contém este checkpoint (`git rev-parse HEAD` na branch), comunicado na entrega. Sem referência circular de hash no próprio ficheiro.

Todas as alterações desta missão são docs/auditorias/auditoria-global-noturna-20261014 e tests/night-global*.mjs. Working tree final deve ficar limpa após commit; conferir git status e git diff--check. Main1c5fa5b, candidato2ae1f8a e auditoria12d8658 preservados. Não houve push; commits existem apenas nesta máquina e não estarão noutro computador só com fetch.

## Checkpoint 5 — aprofundamento dos sinks

- Mesma classe N-SEC-01 agora provada em3 renderizadores: diálogo de recebimento, lista de obras, cartão Financeiro com nome de fornecedor.
- Provas somente about:blank, sem rede, marcadores sintéticos; não acessar sessão nem executar writers.
- Resultado final atualizado: 236 PASS/0FAIL/0SKIP (9 novos casos de domínio/PG +3 browser; demais grupos preservados).
- As quatro funções comparadas e RNC permanecem iguais à main local; mudanças de Horas não são causa demonstrada desses achados.

## Verificação final de entrega — 2026-10-14 20:45:15 Lisboa

- Dez entregáveis obrigatórios presentes; seis CSVs com colunas consistentes; JSON parse/UTF-8 PASS; 34 IDs de backlog únicos.
- Inventário38 áreas; índices56JS/258SQL sem seeds; análise e provas classificadas sem certificação de produção.
- Total final236 PASS/0FAIL/0SKIP; HR38 anterior não repetido nem contado.
- Diff de produto/src/index/supabase/config contra12d8658 vazio; main1c5fa5b, candidato2ae1f8a e auditoria12d8658 preservados.
- Worktree original de Horas limpa no último check; worktree isolada de auditoria limpa após o commit de fecho.
- Sem push. Entrega antecipada às20h45 de14/10, não um trabalho garantido até06h00. Sem automação a correr depois da entrega.
