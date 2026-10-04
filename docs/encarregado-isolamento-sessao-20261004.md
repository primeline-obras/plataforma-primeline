# Isolamento de sessão e âmbito do Encarregado — 04/10/2026

Base: `d6db2c3c9e48170a3d4c6ec937b5f7ad76e411fb` (main).
Branch: `codex/encarregado-isolamento-sessao-20261004`.
Estado: correção frontend local; **não fecha os P1 de autorização da BD**.
Nenhuma escrita real, migration, marker B, backup B, Fase B ou teste real do Encarregado.

## Diagnóstico antes da alteração

Na aba normal da produção, depois de Gestão → logout → Encarregado, a identificação
já era Encarregado, mas o Quadro mantinha 11 obras. A RPC autorizava somente Obra 120.
Um único reload retirou as outras obras. Não confundir com o incidente visual anterior
da aba criada pelo MCP: aqui houve reutilização comprovada de dados de outra sessão.

`app.js` limpava apenas `works`, `suppliers`, `subcontracts` e `invoices` no logout,
depois de aguardar o pedido remoto. `teamData.loadedWeek` podia evitar novo carregamento;
`session-expired` só mostrava o login. Os módulos continuavam instanciados. Não havia
barreira para respostas em trânsito ou refresh que concluíssem depois da troca.

O teste adversarial novo, executado contra o main sem correção, falhou em
`old protected DOM remains after logout`. O mesmo teste passa na branch corrigida.

## Inventário de estado dependente da sessão

O destino de todos os estados abaixo é o mesmo: destruir o documento/ambiente JS
na transição, instanciando os módulos de raiz. Nenhuma closure antiga é reutilizada.

| Proprietário | Estado/cache/seleções a descartar |
|---|---|
| `app.js` — acesso | `session`, `accessContext`/perfil/admin, `activeView`, permissões e DOM de navegação |
| `app.js` — diretórios | `works`, `suppliers`, `subcontracts`, `collaborators` e seletores derivados |
| `app.js` — obra | `selectedWorkId`, `selectedWorkTab`, todo `workDetails` (contrato, investimento, TEEs, fases, autos, pagamentos, documentos, desenhos, RFI, PAME, prorrogações, segurança), `localWorkDocumentFiles` |
| `app.js` — financeiro | `invoices`, `financeInvoices`, guias/anexos, débitos e lançamentos, rastreio/erro, filtros, IDs expandidos/em edição, ficheiros selecionados, extração e URLs de PDF |
| `app.js` — equipa/Quadro | `teamData` completo, `loadedWeek`, `quadroContext`/revisões, `quadroReady`, semana, mês de férias, aba, filtros, pessoa/entidade/viatura selecionada, inativos, ausências, contratos, horas extra, documentos e `localEntityDocumentFiles` |
| `app.js` — escrita Quadro | edição/saving, pessoa, data/período/linha/IDs de origem, destino, linhas pendentes; closures de preview/confirmação |
| `planning.js` | obra, tarefas/fases/dependências, custos, orçamento, originais, Sets de expansão/saving, preview/importação, flags loaded/dependenciesLoaded/batchSaving |
| `production-dashboard.js` | `overviewState` incluindo alertas/responsabilidades/financeiro, `meetingState`, reunião/retorno, edição de custos, `rspLoadVersion` |
| `action-plan.js` | itens, fases, mês, loading/erro |
| `documents.js` | obra/secção, `data`, loading, `localFiles`, ficheiros e diálogos |
| `rnc.js` | obra, RNCs/anexos/fases/subempreitadas/utilizadores, permissões, formulário e ID em edição |
| `medicine.js` | por ficha: dados atuais/histórico, documentos, geração, busy/unresolved, intenção/request e erro; cliente de lista não tem cache próprio |
| `rh-cadastro.js` | instância da ficha/grelha, registos, revisões, importação, edição e diálogos/DOM |
| `vehicles.js` | viaturas, eventos, sinistros/multas e anexos, query/seleção, loaded/loading/erro |
| `vehicle-assignment.js` | Maps de pessoas/históricos, geração, snapshot da atribuição, candidatos, intenção/request e confirmação |
| `vehicle-validity.js` | estado de cada operação/diálogo e callback, sem diretório global próprio |
| `financial-map.js` | ano, contratos, investimentos, previsões, ajustes, débitos/lançamentos, edição e loaded/loading |
| `management-map.js` | linhas, modo, importação/preview/progresso, loaded/loading |
| `procurement.js` | obra/loadedWorkId, consultas, orçamento/artigos/candidatos, especialidades/aliases, permissões, formulários/importação |
| `comparative-map.js` | obra, mapas/propostas/artigos/preços/ajustes, expansão, edição/eliminação, importação/ficheiro/preview |
| `subcontractors.js` | fornecedores/subempreitadas/avaliações, especialidades/zonas, preços/pesquisa, filtros/abas, formulário, debounce e carregamento |
| `projects.js` | projetos, contratos, investimentos, selectedId, loaded |
| `consolidated-view.js` | loading e DOM com agregados; Maps locais de cálculo não são cache persistente |
| `settings.js` | utilizadores/responsabilidades/admins/empresa, parâmetros/feriados, ano, auditoria, abas e flags loaded |
| `calendar.js` | eventos/participantes/utilizadores/obras, mês/data/edição e loaded/loading |
| `meeting-rooms.js` | salas/reservas/participantes/utilizadores, mês/data/sala/edição e loaded/loading |
| `properties.js` | imóveis/reuniões/anexos, selectedId, loaded/loading |
| `budget-requests.js` | pedidos/versões/anexos, selectedId, loaded/loading |
| `company-documents.js` | documentos/loaded/loading e Map local de ficheiros |
| `xlsx-operational-import.js` | módulo, contexto, ficheiro/linhas, busy e diálogo |
| `platform-dialogs.js` | DOM e promises de confirmação/prompt pendentes |
| DOM/transitórios | sidebar, páginas ocultas, formulários, modais, alertas/toasts, eventos, timers, ficheiros e object URLs |
| `supabase-browser.js` | sessão por separador, refresh em voo, identidade conhecida, geração e respostas REST/Storage pendentes |

Helpers de cálculo/formatos/PDF não mantêm autorização independente; as suas closures,
downloads e eventuais caches de assets também desaparecem com o documento.

### Persistência

- `sessionStorage.primeline_supabase_session`: removida no logout/expiração/início de login;
  só a resposta válida da tentativa corrente pode instalar uma sessão nova.
- `localStorage.primeline_supabase_session`: chave antiga removida, como antes.
- `localStorage.primeline_planning_work_id`: eliminada na fronteira de sessão.
- `primeline_theme`, `primeline_tv_mode`, `primeline_sidebar_collapsed`: preferências
  visuais neutras preservadas. Não contêm IDs, nomes ou dados de negócio.
- `sessionStorage.primeline_login_failed`: novo sinal booleano, consumido uma vez;
  sem email, password ou texto vindo do servidor.
- URL: a navegação automática remove query/fragmento/seleções da conta anterior.
- Recuperação de password: página separada, não instala o token de recuperação na
  sessão de aplicação; nenhum dado da aplicação é transportado por esse fluxo.

## Reset central implementado

`session-boundary.js` recebe um único callback do módulo de autenticação. Retira
imediatamente o DOM protegido e oculta o documento antigo. Na conclusão do login,
logout, expiração ou mudança efetiva de identidade, usa navegação automática no
mesmo separador para criar um novo documento. Não exige reload manual nem abre abas.
O início do login já coloca o documento em quarentena antes do pedido de credenciais.

Esta escolha elimina todos os estados inventariados, incluindo módulos sem método
`reset`, em vez de introduzir dezenas de callbacks incompletos. O custo é um novo
carregamento do shell por transição. Um refresh de token da mesma identidade não
reinicia a aplicação. Se a rede falhar, o documento antigo continua oculto.

Uma geração de sessão impede que REST, leitura de bodies/clones, downloads Storage,
refresh antigo ou login concorrente repovoem a aplicação ou substituam a nova conta.
401 autenticado sem recuperação termina a sessão; 403 de permissão não termina.
`pagehide/pageshow` impede restaurar conteúdo autenticado antigo por BFCache.

## Medicina: origem, âmbito e classificação

**P1 de autorização/privacidade confirmado na BD; mitigação frontend local.**

- Com Encarregado após reload, `GET colaboradores?select=id` devolveu **39** IDs.
- Antes da correção, `loadData` pedia `id,nome,funcao,nivel,valor_hora,nif,email,
  contacto,morada,data_nascimento,data_admissao,permite_multiplas_obras`.
- `medicineClient.list(collaborators)` consultava todos; o painel desenhava o nome
  mesmo quando a RPC individual devolvia 403. Logo havia exposição visual, não só
  tentativas internas. Não era cache: repetiu-se na sessão Encarregado recarregada.
- `pl_colaboradores_seguranca_select` permite todos os ativos quando existe qualquer
  responsabilidade do utilizador. O predicado não relaciona cada colaborador à sua
  equipa. Grants SELECT de `valor_hora`, `nif` e `morada` também estão presentes.
- `fn_quadro_contexto_v1` também entrega um diretório de ativos ao Encarregado.
- A RPC de Medicina usa `fn_colaborador_na_obra_atual_encarregado(uuid)` e recusa
  fora do âmbito; para autorizado devolve `can_write=false` e campos ocupacionais.

Correção frontend: deixa de pedir o diretório RH global. Usa as obras/equipas das
RPCs existentes de consulta de ponto e confirma o predicado instalado da Medicina
antes de chamar a RPC médica. O Quadro filtra o diretório retornado para pessoas
da equipa atual ou de alocações autorizadas no intervalo. Erro de âmbito falha fechado.
Não amplia permissões nem usa 403 para descobrir pessoas. Não atribui valor/hora,
NIF, morada ou campos RH à lista operacional.

Limite: a API ampla continua acessível fora deste frontend. Uma política/contrato
de diretório operacional restrito é necessário antes de declarar este P1 fechado.
O predicado atual da Medicina e a seleção do ponto têm semânticas temporais diferentes;
a correção usa o predicado real para Medicina, não infere autorização pelo histórico.

## Subempreitadas / Financeiro

**P1 confirmado: acesso a outras obras e colunas económicas.**

- `GET subempreitadas?select=id,obra_id`, na sessão Encarregado, devolveu **19**
  registos de **Obras 118, 120 e 122**. O âmbito autorizado do Quadro é somente 120.
- `pl_subempreitadas_diretorio_select` é permissiva: `auth.uid() IS NOT NULL`.
  A restritiva `bloquear_financeiro_operacional` só impede Financeiro; não impede
  Encarregado. `pl_admin_total` não explica nem é necessária para este acesso.
- Grants confirmam SELECT de `valor_adjudicado`, `tipo_pagamento` e
  `condicao_pagamento`. Não foi necessário recolher valores financeiros.
- O preload antigo pedia `id,obra_id,fornecedor_id,especialidade,valor_adjudicado,
  estado,tipo_pagamento,fase_id,mapa_comparativo_id`, mesmo com menu financeiro oculto.
- RNC utiliza uma consulta operacional específica da obra com
  `id,obra_id,fornecedor_id,especialidade`. Essa consulta permanece; não necessita
  de valores, pagamentos ou margem.
- `GET faturas?select=id,obra_id` devolveu zero linhas nesta sessão. Isto não prova
  segurança geral de todas as tabelas financeiras. Não se recolheram pagamentos,
  margens ou contratos; não afirmar exposição concreta desses conteúdos.

Correção frontend: remove preload de fornecedores, subempreitadas económicas,
faturas/guias/anexos para Encarregado. As consultas operacionais de RNC mantêm o filtro
por obra e campos reduzidos. O menu administrativo/financeiro continua indisponível.

Necessidade demonstrada: revisão de RLS e projeção operacional de colunas, preservando
consumidores legítimos de outros perfis. **Não basta adicionar uma policy permissiva
mais estreita**: a permissiva global continuaria a autorizar por OR. RLS também não
oculta colunas económicas por si só. É necessária uma mudança backend separada,
revista com os consumidores atuais e testes de perfis. Não foi gerada/aplicada SQL;
`instrucoes.txt` limita este repositório a frontend e proíbe gerar/correr migrations.

## Pacote 2 — requisitos obrigatórios, não implementados

- Nome **FOLHA DE PONTO** em menu/título/textos/documentação. Atual “PONTO DE OBRA”:
  `app.js` botão `data-team-tab=attendance`; “PONTO DIÁRIO” no título e `attendance.js`.
- Experiência própria do Encarregado: uma obra, um dia, lista vertical nome/função,
  Registado/Não registado, REGISTAR/EDITAR e + ADICIONAR PESSOA À OBRA.
- Tablet/mobile primeiro, poucos passos e alvos grandes; sem grelha semanal/ímanes
  como UX diária, nem scroll horizontal obrigatório.
- Seletor com disponíveis e recentes/frequentes; pesquisa como apoio.
- Contexto pontual Sem alocação / Obra / Escritório, sem matriz global.
- Adição de pessoa livre poderá criar alocação explícita e abrir o ponto;
  transferência de outra obra continua pendente de decisão.
- Eliminar herança temporal do ponto no Pacote 2. Não foi alterada nesta correção.

## Verificação e limites

Antes: suite adversarial no main reproduziu DOM privado após logout (FAIL esperado).
Depois: Gestão→Encarregado, Encarregado→Gestão, Diretor→Encarregado, logout Quadro/
Medicina/Obra, expiração e mudança de identidade sem reload manual. Respostas API da
segunda identidade são suspensas deliberadamente; DOM anterior ausente antes delas.
Testes unitários adicionais: respostas/bodies atrasados, refresh concorrente, login
concorrente, 401/403, download privado atrasado e falha de âmbito.

Regressões verificadas localmente: RH/Inativos/Viaturas, Medicina (histórico, inativo,
replay, correção/anulação sintética, permissões, três viewports), Quadro e autenticação.
Todos os testes browser interceptam tráfego externo e usam apenas dados sintéticos.
O mock de Medicina foi atualizado para as duas RPCs de leitura agora consumidas;
o teste estático foi ajustado para exigir a filtragem de âmbito antes da consulta.

Resultados locais:

- `node --test` sobre session-boundary, foreman-scope, session-isolation,
  supabase-collaborators, medicine-client, login-redirect-theme, access-control,
  workforce-allocation-client, rh-cadastro e vehicle-assignment-client:
  **41 PASS, 0 FAIL, 3 SKIP**. Os três skips são verificações opcionais preexistentes
  de RH (PostgreSQL/DOM condicionado a dependências), não testes do reset central.
- `session-boundary-browser.mjs`: **7 cenários PASS**, cobrindo A–H da tarefa
  (login sem reload manual incluído nas trocas de perfil).
- `rh-frontend-browser.mjs`: **PASS**, 49 combinações de permissão, Inativos,
  escape de HTML, fluxo controlado de Viaturas, três viewports e consola limpa.
- `medicine-browser.mjs`: **PASS**, quatro perfis, três viewports, histórico,
  replay/conflito/anulação sintéticos, inativo, RPC ausente e consola limpa.
- `git diff --check`: **PASS**.

Produção permaneceu com **227 alocações, 100 movimentos e 2 operações** na leitura
de reconfirmação. Nenhum teste de escrita real foi efetuado.

**GO local** para revisão e validação isolada desta correção em preview após aprovação.
**NO-GO para fechar âmbito, teste real do Encarregado ou Fase B** enquanto os dois P1
de backend permanecerem. Nenhum P0 confirmado. Nenhum push/publicação nesta tarefa.
