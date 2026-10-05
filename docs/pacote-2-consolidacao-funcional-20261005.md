# Pacote 2 — consolidação funcional, 05/10/2026

Este documento sucede a `pacote-2-folha-ponto-backend-fase-b-20261005.md`. Os resultados e limitações daquele checkpoint ficam preservados; as lacunas funcionais indicadas ali são atualizadas abaixo.

## A. Identificação e limites

Branch: `feat/adm-rh-fecho-folha-ponto-20261005`.
Base: `8f16c6e065c9a011b69f7adf12f8fa593be476e8`. O commit que contém este relatório identifica a consolidação final, sem auto-referência de SHA dentro do ficheiro.

Main de referência: `3df019a2f2813c0cbf7f36a8d13000431d33dd50`. Não foi alterada. Nenhum SQL foi aplicado à BD real, nenhum perfil/dado real foi alterado e não houve deploy ou Fase B. Os scripts foram executados apenas em PostgreSQL 17.6 efémero local, com fixtures sintéticas.

A instrução local antiga de frontend apenas em `instrucoes.txt` foi superada pelo pedido explícito desta tarefa para consolidar o modelo/backend v2 e os scripts locais. Isto não autoriza instalação em produção.

## B. Três lacunas corrigidas

1. Escritório representado explicitamente, com `obra_id NULL`, carga configurável e self-service restrito ao colaborador ligado ao utilizador Diretor/Adjunto/Preparador.
2. Ação coletiva de dia normal acrescentada aos modos progressivos existentes, usando o horário configurado, depois do fim da jornada completa, sem sobrescrever folhas e com execução atómica.
3. Identidade externa independente de obra. A mesma identidade empresa/fornecedor pode ser afetada a várias obras/datas autorizadas, sem criar colaborador ou facto económico.

## C. Matriz completa A–AN

PASS nesta matriz significa implementado e verificado localmente. Não significa instalado ou validado com contas reais. D = `attendance-domain.test.mjs`; PG = `attendance-backend-v2.test.mjs`; B = `attendance-sheet-browser.mjs`; C = `attendance-consolidation-browser.mjs`; S = `attendance-v2-static.test.mjs`.

| ID | Requisito aprovado | Estado | Implementação / evidência |
|---|---|---|---|
| A | Nome FOLHA DE PONTO | PASS | Nova secção, diálogos e painéis usam Folha de Ponto; B/C. Textos históricos dos scripts legados ficam preservados. |
| B | Pessoa + dia | PASS | Chave de pessoa/local/data, revisão e histórico; PG/D. |
| C | Sem herança da última alocação | PASS | Contexto procura alocação explícita na data; PG/D/B. |
| D | Ponto progressivo | PASS | Entrada com saída NULL, edição com intervalos reais; PG/D/B. |
| E | Ponto completo no final do dia | PASS | Intervalos reais completos, validação de horas futuras; PG/D/B. |
| F | Ação coletiva progressiva | PASS | Start/finish com hora efetiva, elegibilidade e atomicidade; PG/B. |
| G | Ação coletiva horário normal | PASS | `operation=normal`, validação da jornada completa, exclusões, preview e revisão; PG/D/C. |
| H | Não registado ≠ presente | PASS | Estado `none`, nenhum intervalo inventado; D/B/C. |
| I | Em aberto | PASS | Intervalo sem saída preservado, sem fecho implícito; PG/D/B. |
| J | Horas em falta | PASS | Minutos abaixo da carga, sem criar ausência; PG/D/C. |
| K | Horário configurável por obra | PASS | `folha_horarios`, RPC administrativa e formulário; PG/D/C. |
| L | 8h deslocadas não são HE | PASS | Minutos comparados com carga, não com hora de chegada; PG/D. |
| M | Escritório flexível | PASS | Tipo explícito, carga 480 configurável, intervalos livres e sem auto-HE; PG/D/C. |
| N | Diretor/Adjunto/Preparador próprio ponto | PASS | Vínculo único `colaboradores.utilizador_id`, tenant e utilizador ativo; PG/C. |
| O | Ponto normal sem aprovação | PASS | Save normal grava factos; aprovação só no ciclo HE; PG/B/C. |
| P | Adicionar pessoa sem alocação | PASS | Candidatos disponíveis/recentes/pesquisa, alocação explícita pelo núcleo controlado; PG/B. |
| Q | Manhã/tarde/dia inteiro | PASS | Períodos e horários correspondentes; PG/D/B. |
| R | Transferência direta Encarregado entre obras | PASS | Confirma origem, destino autorizado, revisão e tenant; mantém movimento/alertas previstos; PG/B. |
| S | Retirada da equipa do dia | PASS | UUIDs explícitos, sem folha/ausência/conflito, projeção `can_remove`; PG/B. |
| T | Histórico de movimentos | PASS | Núcleo Quadro preservado e histórico Folha antes/depois/autor/request; PG/B. |
| U | Férias = zero horas esperadas | PASS | Contexto e domínio reduzem carga a zero; PG/D/B. |
| V | Ausência + trabalho = regularização | PASS | Factos preservados; sem limpeza silenciosa; PG/D/B. |
| W | Motivo de correção opcional | PASS | Campo opcional nos consumidores e RPC, histórico normal; PG/S/B. |
| X | HE nasce da Folha | PASS | Origem folha/revisão única, geração opt-in, conflito com origem manual legado; PG/S. |
| Y | Diretor/Adjunto aprova potencial HE | PASS | Aprovar/rejeitar no âmbito autorizado; origem e minutos no painel; PG/C. |
| Z | Administrativo valida HE | PASS | Validação separada após aprovação, sem valores monetários; PG/C. |
| AA | Sem valor enquanto regra pendente | PASS | `validated_pending_rule`, nenhum cálculo/pagamento automático; PG/D/S/C. |
| AB | Dias especiais factuais sem regra financeira | PASS | Facto e estado pendente, calendário configurável, sem taxa inventada; PG/D/C. |
| AC | Externos separados | PASS | Identidade fornecedor/empresa, afetação diária, folhas/histórico separados; PG/S/B. |
| AD | Resumo do dia | PASS | Contagens derivadas dos factos Primeline e externos; PG/D/B/C. |
| AE | DIA COMPLETO | PASS | Indicador derivado de zero pendências, sem operação de fecho administrativo; PG/D/B/C. |
| AF | Histórico/auditoria | PASS | Antes/depois, autor, request, revisão e motivo; histórico imutável; PG/B/C. |
| AG | Idempotência | PASS | Request por ator/empresa, replay do mesmo payload, conflito se diferente; PG/D/B. |
| AH | Concorrência | PASS | Duas ligações PostgreSQL, revisão concorrente, replay e conflito legado/v2 nos dois sentidos; PG. |
| AI | Tenant | PASS | Ator ativo, empresa, obra/responsabilidade, pessoa e fornecedor verificados; helpers privados; PG/S/C. |
| AJ | Reporte ≠ conclusão | PASS | Encarregado cria reporte; não escreve o estado do Planeamento; PG/C. |
| AK | Planeamento conclui → reconciliação | PASS | Trigger confirma reporte, resolve só alerta pendente da origem conhecida e retira tarefa da lista ativa; PG. |
| AL | Férias não contíguas/atómicas | PASS | UI seleção/range/remoção, RPC com revisão/override/histórico/direito com fonte; PG/D/C. |
| AM | Vencimentos sem salário inventado | PASS | Rascunho com factos/ausências/pendências/manuais, sem fecho/exportação disponível; PG/D/C. |
| AN | Cargo RH ≠ perfil operacional | PASS | Autoriza por `utilizadores.funcao` e responsabilidades; cargo RH só apresentado; PG/C. |

São 40 requisitos aprovados implementados. A ativação financeira e os parâmetros ADM ainda pendentes estão separados na secção P; não foram usados para adiar requisitos já decididos.

## D. Self-service Escritório

`folha_registos` e `folha_historico` passam a guardar `tipo_local`. CHECK exige obra para `obra` e NULL para `escritorio`; externo não pode usar Escritório. A unicidade Primeline usa índice parcial com `NULLS NOT DISTINCT`, mantendo uma folha inequívoca por pessoa/local/data. Não foi criada obra fictícia.

`folha_privado.local` verifica ator ativo, empresa e vínculo único. Diretor/Adjunto/Preparador só podem escrever o próprio colaborador. A gravação bloqueia as linhas pertinentes e revalida disponibilidade/vínculo. Administrativo/Gestão/Gerência preservam administração dentro da empresa; Encarregado não obtém Escritório global.

Carga inicial autorizada: 480 minutos, configurável de 1 a 1440. Exemplos deslocados são válidos; abaixo da carga há horas em falta. Acima da carga não nasce auto-HE de Escritório, mesmo com geração automática de obra ativa. O histórico inclui local NULL sem confundir obra e Escritório. Retroativos não administrativos exigem janela configurada; não há default inventado.

## E. Ações coletivas

Mantêm-se MARCAR EQUIPA PRESENTE e COMPLETAR EQUIPA, com hora efetiva no próprio dia. REGISTAR EQUIPA — DIA NORMAL calcula intervalos configurados por período; exige fim de **todos** os intervalos da jornada da obra, inclusive quando a pessoa está só de manhã. A mesma regra existe no cliente e na RPC.

Férias/ausências, conflito, falta de autorização, janela inválida e folha existente excluem a pessoa. Preview indica número selecionado/excluído e motivos gerais; o token contém snapshot e payload. Confirmação repete guardas e revisões; qualquer erro aborta o conjunto. Não grava horas futuras nem sobrescreve exceções. Depois, cada folha pode ser corrigida individualmente conforme permissão.

## F. Externos normalizados

`folha_externos` não tem obra fixa. Identidade: empresa Primeline + fornecedor + nome operacional; índice impede duplicação acidental do nome normalizado nesse âmbito. `folha_externos_dias` representa obra/data, e `folha_registos` contém intervalos/revisão/autoria.

Reutilização exige ID existente, nome e fornecedor coerentes. Fornecedor diferente não reutiliza a identidade; nova identidade noutro fornecedor é separada. Homónimos exigem identificação operacional distinta, sem merge automático. Cross-company é recusado. Identidade inativa pode conservar factos/histórico, mas não apresenta ação de escrita. Não insere RH, vencimento, fatura, auto ou pagamento.

## G. HE UI

Painel HORAS EXTRA mostra pessoa, data, intervalos de origem, minutos, folha/revisão e estado. Diretor/Adjunto responsável aprova ou rejeita potencial; Administrativo/Gestão/Gerência valida o aprovado. Alteração da origem invalida a revisão antiga e impede validação stale. Regra financeira pendente permanece explícita, sem euros/taxas ou pagamento.

## H. Férias UI

Painel administrativo com colaborador, seleção de dias, intervalo, remoção, histórico antes/depois/autor e direito anual com fonte obrigatória. Override é opção explícita e preserva conflitos como regularização; não os elimina. Seleção é limpa após confirmação para evitar reutilização acidental na operação seguinte. Histórico da pessoa continua disponível com uma obra selecionada. Consumo de dias especiais não é deduzido sem regra.

## I. Vencimentos UI

Rascunho por pessoa/competência com factos atuais da Folha, férias/ausências, folhas em aberto/em falta, datas alocadas sem ponto e datas legadas por reconciliar. Campos manuais permitidos: Prémio, Km, Ajudas de Custo, Observações. Dados externos ficam excluídos. Guardar rascunho não calcula salário.

FECHAR e EXPORTAR permanecem indisponíveis. Backend também exige readiness/ausência de pendências para fechar e recusa exportação enquanto não existir exportador oficial. Não se apresenta fecho/exportação como implementados ou aprovados para uso real.

## J. Tarefas/reportes

Encarregado dispõe de REPORTAR CONCLUSÃO; Diretor/Adjunto vê o reporte e pode abrir o Planeamento existente. Esta UI não duplica o writer de Planeamento nem altera percentagem/estado. Conclusão real pelo fluxo autorizado aciona trigger: reporte confirmado com revisão/histórico, alerta conhecido pendente resolvido, resolvidos antigos preservados. Tarefa concluída sai de `tasks`; `task_reports` conserva o histórico. Uma percentagem de 100% isolada não conclui tarefa.

## K. Backend, RLS e grants

Seis RPCs públicas v2: `fn_folha_contexto_v2`, `fn_folha_pessoas_v2`, `fn_folha_operar_v2`, `fn_folha_historico_v2`, `fn_folha_gestao_contexto_v2`, `fn_folha_gestao_v2`. Escritas usam preview/confirmação, mesmo request, token e revisão; não há sucesso simulado.

Novas tabelas têm RLS ativo e sem DML/SELECT direto concedido a authenticated, anon ou service_role. RPCs têm EXECUTE só para authenticated. Helpers ficam privados; SECURITY DEFINER usa `search_path=pg_catalog` e objetos qualificados. Contexto administrativo não concede lista global de pessoas a perfis operacionais. Projeção de tarefas contém só campos operacionais, sem JSON económico completo do Planeamento.

Serialização com o núcleo v1 e triggers nos writers legados evita mistura silenciosa; operação exige READ COMMITTED. Isolamentos com snapshots antigos são recusados com repetição explícita, não promovidos a PASS. Historicamente sobreposições/coexistências/valores são preservados.

## L. Scripts Fase B revistos

Os cinco `quadro_fase_b_pos_hotfix_{precheck,backup,migration,postcheck,rollback}.sql` foram revistos após a consolidação e exercitados em PG sintético. Não foi necessário alterar estes ficheiros: o gate compara catálogo completo, incluindo novas colunas/helpers e definições finais v2. Aprovação antiga com drift aborta.

Ordem futura: PRECHECK READ ONLY → BACKUP privado → MIGRATION → POSTCHECK READ ONLY. Gate exige aprovação independente de instalação/catálogo/assets/readiness. Esta entrega não cria essa aprovação nem marca frontend validado.

B fecha DML/writers antigos do Quadro, conserva policies pós-hotfix/v1/Cadastro RH e o Ponto legado. Não fecha o Ponto antes de reconciliação e readiness. Rollback B restaura estado pós-hotfix, não estado anterior vulnerável. Rollback Folha é explícito, sem CASCADE e recusa apagar factos/configuração/histórico persistentes; havendo uso real exige plano específico.

## M. Testes finais

Resultados distintos, sem somar repetições:

| Suite | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| Folha backend PostgreSQL + domínio + estáticos | 66 | 0 | 0 |
| Quadro/Medicina/âmbito Encarregado/financeiro cross-tenant/compatibilidade B, PostgreSQL local | 355 | 0 | 0 |
| 19 ficheiros frontend/contratos | 71 | 0 | 3 |
| **Total Node** | **492** | **0** | **3** |

Browser, não somado ao total Node:

- Folha existente: 45 grupos PASS, zero pageErrors.
- Consolidação: 48 grupos PASS, zero pageErrors; seis perfis × desktop 1440×900, tablet 820×1180, mobile 390×844. Escritório próprio, dia normal, HE, seleção/range/override/remoção férias, direito com fonte, rascunho, reporte e navegação Planeamento, isolamento de ações e ausência de DML direto.
- Sessão: 7 cenários PASS; Planeamento/custos: 33 PASS; Medicina: PASS; RH-01/02/08/15: PASS, incluindo 49 combinações de autorização; RNC e Viaturas: PASS.
- Screenshots sintéticos fora do Git em `%TEMP%\primeline-folha-consolidation-synthetic`, com styles/visual-phase2/visual-identity-final/Folha. Desktop/mobile inspecionados; testes verificam largura e ações nos três tamanhos. São evidências do módulo local, não de produção autenticada.

Backend cobre self-service de cada papel, pessoa/empresa/vínculo/inatividade, ausência de auto-HE escritório mesmo com geração ativa, cargas menores, horários 08–17 e 09–18, antes/depois do fim, janela retroativa nullable, atomicidade/no-overwrite, externo reutilizado em obras distintas, fornecedor/tenant, histórico separado, revisão/replay, duas conexões concorrentes e legado/v2 nos dois sentidos. Scripts locais têm instalação/postcheck/rollback e recusa de drift testados.

`git diff --check` e sintaxe JS: PASS. Nenhum ficheiro gerado de log/screenshot/credencial/backup real incluído.

## N. SKIPs

Três testes RH opcionais continuam SKIP por ausência de PGlite/jsdom em `RH_TEST_DEPS`: cadastro/migração/lote; formulário; aviso contratual/células vazias. Não são PASS. Os testes RH browser e PostgreSQL acima são evidências separadas, não substituição silenciosa destes testes.

## O. Divergências adicionais corrigidas e varreduras

- Escritório NULL não tinha chave/reader/uniqueness compatíveis: corrigidos conjuntamente, incluindo histórico e cliente.
- Identidade externa dependia da obra: retirada dessa dependência sem backfill, pois o backend v2 ainda não foi instalado.
- Dia normal de meia jornada podia terminar antes da jornada completa: guardas cliente/backend corrigidas.
- Retirada mostrava ação com base em escrita de ponto: passa a exigir `can_remove` específico, uma alocação, obra em curso, disponibilidade e ausência de outros factos/ausências/conflitos.
- UI administrativa não existia para modos já aprovados: consumidor único v2 acrescentado, sem duplicar DML.
- Seleção de férias permanecia depois de gravar: limpa após confirmação.
- Histórico administrativo com obra selecionada ocultava eventos de férias sem obra: corrigido para pessoa selecionada dentro do tenant.
- Conclusão exigia confirmação extra do reporte e continuava na lista ativa: reconciliação automática e separação entre ativo/histórico.
- Contexto de tarefa usava JSON completo: substituído por projeção operacional.
- Externo inativo podia apresentar edição: projeção de permissão alinhada com recusa backend.
- Estados internos no novo painel passam a ter texto legível.

Varredura segurança: RPCs/helpers/EXECUTE/search_path/tenant/revisão/DML revisados; suites estáticas e PG passam. Não há novo writer cliente de tabela direta, helper aberto ou externo introduzido em RH/financeiro.

Varredura funcional: matriz A–AN comparada com modelo, leitores, writers, triggers, UI, chaves/FKs/índices e rollback. Não permanece FAIL conhecido de requisito já decidido. Esta revisão do autor prepara a auditoria independente; não a substitui.

## P. Pendências ADM reais

Janela de correção retroativa e ativação; calendário/feriados verificados; consumo de férias nos dias especiais; regras financeiras HE/vencimentos; direito anual efetivo com fonte; modelo oficial e exportador. Não se inventa 22 dias, taxa, salário, pagamento ou autorização retroativa. Os consumidores factuais/draft já estão implementados; estas pendências limitam ativação/cálculo, não justificam omitir UI aprovada.

## Q. Gate catálogo real

**REAL_CATALOG_VALIDATION_REQUIRED.** Feita uma única tentativa, conforme limite do pedido. A revisão automática bloqueou a execução da consulta porque o método proposto extraía token de sessão do localStorage para chamada manual à API Supabase; essa reutilização de credencial não estava especificamente autorizada. Não se executou a consulta, não se contornou a proteção e não houve nova tentativa/troubleshooting.

Catálogo anterior/fixtures não são apresentados como estado real atual. Antes de rollout: reconfirmar tipos, definição/owner/grants/RLS/ACL de coluna, helpers/RPCs/triggers/índices, origens de alertas e hotfix/v1 instalado; validar precheck estrito e preservar dados. Divergência aborta, sem regenerar fingerprint para obter PASS.

## R. Riscos restantes

- Sem catálogo real reconfirmado, instalação/publicação continuam NO-GO.
- Auditoria independente e preview autenticado real ainda não realizados nesta consolidação.
- Lock global privilegia consistência; medir carga/latência antes de produção.
- Legado permanece preservado e pode bloquear edição v2 para regularização autorizada; não foi migrado/reinterpretado.
- Intervalos atravessando meia-noite exigem regra separada; não suportados silenciosamente.
- Nomes externos operacionais precisam distinguir homónimos; não há reconciliação automática de identidade.
- Fecho/exportação salarial e efeitos financeiros permanecem bloqueados onde dependem de regra/modelo/exportador.
- Rollback com factos reais não pode apagar evidência; exige plano de preservação específico.

## S. Decisão

**GO LOCAL para UMA auditoria independente final do candidato consolidado.** As três lacunas e os consumidores aprovados foram implementados; 492 PASS, zero FAIL e três SKIPs explícitos, com regressões browser aprovadas.

**NO-GO para produção/Fase B.** Exige catálogo real, auditoria independente, autorização de instalação e testes autenticados/readiness; depois, autorização separada para B. Nenhum marcador, backup B ou Fase B real foi executado.
