# Encarregado — diagnóstico real e correção local dos dois P1

> Registo do checkpoint anterior, preservado no commit `108a6e4ed9301f47236cb2bb6ab5c1adc025422a` e enviado à branch indicada abaixo. O estado final, a ampliação de âmbito e os scripts consolidados estão em [encarregado-autorizacao-final-20261004.md](encarregado-autorizacao-final-20261004.md). As indicações de alterações pendentes deste relatório descrevem o momento anterior ao checkpoint.

## Estado e limites

Diagnóstico em 04/10/2026 no projeto `znttyadndpkxuekhjamd`, PostgreSQL **17.6**, através da aba Supabase autenticada existente. Todas as consultas remotas usaram `BEGIN READ ONLY` e a opção `read_only: true`. Não foram invocadas funções de escrita/alertas, nem executados backup, migration, marcador ou Fase B em produção. Nenhuma linha operacional foi exportada.

A instrução explícita desta tarefa autoriza preparar SQL local, exceção ao `instrucoes.txt`. Não autoriza aplicar esse SQL.

- Frontend preservado e enviado: `origin/codex/encarregado-isolamento-sessao-20261004`, SHA `c1bcf3e2de956744e0526a3b4561e25b3cda67ad`.
- Branch de trabalho: `fix/encarregado-escopo-backend-20261004`, criada desse SHA.
- Correção backend e consumidor RNC: alterações locais ainda sem commit/push.
- Main e produção não foram modificados nesta tarefa.

## Catálogo efetivamente instalado

As fixtures `tests/fixtures/encarregado-catalogo-real-20261004.json` e `encarregado-catalogo-privilegios-20261004.json` contêm metadata real: 156 tabelas/views, 247 definições de funções, owners, RLS, policies completas, ACL de tabela/coluna, grants efetivos, views e os triggers/constraints/índices das duas tabelas alvo. Não contêm linhas de colaboradores, fornecedores ou valores económicos reais.

Nas nove tabelas prioritárias: owner `postgres`, RLS ativo, FORCE RLS desativado. `authenticated` não tem BYPASSRLS; `postgres` e `service_role` têm. Não foram encontradas memberships para anon/authenticated/service_role. No schema public: postgres USAGE/CREATE; anon/authenticated USAGE; service_role USAGE/CREATE. Os defaults de tabelas/sequências não concedem acesso a authenticated.

| Tabela | Grants authenticated de tabela | Policies relevantes efetivas de SELECT |
|---|---|---|
| colaboradores | SELECT/INSERT/UPDATE/DELETE | `pl_admin_total`, `pl_colaboradores_rh`, `pl_colaboradores_seguranca_select` |
| subempreitadas | SELECT/INSERT/UPDATE/DELETE | `pl_admin_total`, `pl_subempreitadas_diretorio_select`; restritiva `bloquear_financeiro_operacional` |
| avaliacoes_subempreiteiro | SELECT/INSERT/UPDATE/DELETE | `pl_admin_total`, `pl_avaliacoes_diretorio_select`: `auth.uid() IS NOT NULL` |
| fornecedores | SELECT/INSERT/UPDATE/DELETE | `pl_admin_total`, `pl_fornecedores_select`: `auth.uid() IS NOT NULL` |
| consultas_subempreitada | SELECT/INSERT/UPDATE/DELETE | `pl_consultas_select`, também ALL `pl_consultas_write`; restritiva de Financeiro |
| pagamentos_subempreitada | SELECT/INSERT/UPDATE/DELETE | `pl_pagamentos_subempreitada_select`, através da subempreitada e `fn_pode_ver_obra`; restritiva de Financeiro |
| faturas | SELECT/INSERT/DELETE | `pl_faturas_select`: `fn_pode_ver_obra OR fn_e_financeiro`; admin ALL |
| faturas_itens | SELECT/INSERT | **duas** permissivas: `faturas_itens_select` e `pl_faturas_itens_select`, combinadas por OR |
| contratos | SELECT/INSERT/UPDATE/DELETE | `pl_contratos_select`: `fn_pode_ver_obra OR fn_e_financeiro`; admin ALL |

Grants não significam que o DML seja permitido: as policies continuam a decidir. Nas duas tabelas alvo não há ACL explícita de coluna; o SELECT de tabela permite pedir qualquer coluna das linhas visíveis. Em faturas há ainda INSERT explícito em obra_id, tipo_origem, fornecedor_id, numero_doc, data_fatura, valor, arquivo_url, subempreitada_id e condicao_pagamento. A lista exata e todos os WITH CHECK estão nas fixtures.

`fn_pode_ver_obra` e `fn_pode_editar_obra` **não** autorizam o Encarregado: autorizam os papéis técnicos Diretor/Adjunto/Preparador com responsabilidade, além das exceções administrativas definidas. Logo, as policies dessas tabelas financeiras não equivalem à policy global de subempreitadas.

Os nove triggers das tabelas alvo estão ativos (`O`): seis de subempreitadas e três de colaboradores. A correção não os altera. `consultas_pendentes_planeamento` é SECURITY INVOKER; `vw_previsao_mensal` e `vw_tees_resumo` não têm SELECT de authenticated. Não foi encontrado bypass destas tabelas através das três views públicas instaladas.

## Causas raiz e caminhos alternativos

### P1 colaboradores

`pl_colaboradores_seguranca_select` exige apenas pessoa ativa e existência de qualquer `obra_responsaveis` para o utilizador atual. Não relaciona a pessoa com a obra/equipa e não limita a projeção. O grant SELECT abrange também NIF, morada e valor_hora. As outras permissivas são combinadas por OR.

Bypasses SECURITY DEFINER confirmados pelo código realmente instalado:

1. `fn_quadro_contexto_v1(date,date)`: o predicado `OR u.funcao='encarregado'` inclui todos os ativos da empresa em `people`.
2. `fn_quadro_ferias_encarregado_global(date,date)`: devolve obras, colaboradores ativos, alocações, férias, responsáveis e utilizadores globais.
3. `fn_equipa_obra_encarregado(date,uuid)`: equipa escopada, mas `candidatos` inclui ativos da empresa, sem alocação e noutras obras.

As duas últimas não têm consumidor no frontend atual; são reservadas ao Encarregado pelo corpo e têm EXECUTE de authenticated. A migration retira esse EXECUTE, conservando as definições. Não implementa o seletor futuro da Folha de Ponto.

### P1 subempreitadas

`pl_subempreitadas_diretorio_select USING (auth.uid() IS NOT NULL)` dá todas as linhas/colunas. A restritiva `bloquear_financeiro_operacional` bloqueia Financeiro, não Encarregado. Ocultar o menu não protege o endpoint REST.

O consumidor operacional atual é `src/rnc.js`: precisa só de `id`, `obra_id`, `fornecedor_id`, `especialidade`. Os leitores económicos do app, consolidated-view, production-dashboard, procurement, projects, financial-map e subcontractors não são a fonte operacional do Encarregado.

As RPCs `fn_resumo_custos_obra`, `fn_resumo_componentes_custo_obra` e `fn_resumo_controle_subempreitadas_obra` verificam os helpers técnicos/financeiros que recusam o Encarregado. Esta recusa também foi executada com dados sintéticos.

## Alteração mínima preparada

- Duas policies **restritivas SELECT** `encarregado_sem_select_direto`, uma por tabela alvo. Participam por AND e prevalecem sobre outras permissivas, incluindo ALL e grants de coluna. Não é necessário apagar as permissivas antigas para atingir esta restrição. Os restantes perfis conservam exatamente as policies/grants anteriores.
- Helper `fn_encarregado_acesso_direto_bloqueado()`, SECURITY DEFINER, search_path pg_catalog, identifica o papel real na BD. Um utilizador inativo ainda identificado como Encarregado também fica bloqueado.
- `fn_quadro_contexto_v1`: remove apenas o bypass global de people; preserva as datas/temporalidade e restantes campos.
- Revogação das duas RPCs globais antigas, exclusivamente de authenticated.
- RPC `fn_subempreitadas_operacionais_obra(p_obra_id uuid)`: exige utilizador ativo, mesma empresa e obra atribuída ao Encarregado; para outros papéis exige `fn_pode_ver_obra`.

Contrato da nova RPC:

```json
{"p_obra_id":"UUID da obra"}
```

Resposta: array de `{id: uuid, obra_id: uuid, fornecedor_id: uuid, especialidade: text|null}`. Sem valores/condições de pagamento. Obra nula, externa, de outra empresa ou sessão inválida: SQLSTATE 42501 com `PERMISSION_DENIED`. Chamada POST REST em `rpc/fn_subempreitadas_operacionais_obra` é leitura STABLE; não grava.

RNC usa essa RPC apenas para Encarregado. Os outros perfis mantêm o endpoint anterior. Uma RPC ausente causa erro explícito, sem fallback à tabela. Cache versions: rnc v5, app v175. Publicar esse consumidor depende da instalação autorizada do backend.

## Matriz final local

| Perfil | colaboradores direto | subempreitadas direto | Operacional RNC | Medicina/Ponto |
|---|---|---|---|---|
| Encarregado | zero linhas, incluindo PII | zero linhas, incluindo económico | quatro campos, só obra atribuída e mesma empresa | RPCs atuais preservadas, Medicina só leitura |
| Administrativo/Gestão/Gerência | comportamento anterior | comportamento anterior | caminho anterior | comportamento anterior |
| Diretor/Adjunto/Preparador | comportamento anterior, sem ampliação | comportamento anterior, sem ampliação | caminho anterior | comportamento anterior |
| Financeiro | comportamento anterior | restritiva antiga preservada | sem novo acesso | comportamento anterior |
| anon | sem acesso novo | sem acesso novo | sem EXECUTE | sem acesso novo |

Não se afirma que todos os acessos antigos dos outros perfis estejam corretos: foram preservados dentro do escopo autorizado.

## Outras exposições — documentadas, não corrigidas

| Prioridade | Objeto | Evidência / impacto |
|---|---|---|
| P1 | avaliacoes_subempreiteiro | SELECT global por sessão autenticada, incluindo observações; reproduzido localmente em obras 120/118/122/outra empresa |
| P1 | fornecedores | diretório global com NIF/contactos/condições/notas; sem predicado de empresa na policy |
| P1 | ausencias | `ausencias_ferias_select` permite todas as férias, incluindo comentário; sem âmbito de obra/empresa |
| P1 | quadro_pessoal_alocacao | SELECT legado `fn_pode_consultar_quadro()` autoriza Encarregado sem filtro da linha; expõe UUIDs/locais/datas globais. Fase B continua pendente; esta entrega não a antecipa |
| P1 | fn_verificar_fatura_semelhante, 4 e 5 argumentos | SECURITY DEFINER + EXECUTE authenticated; valida perfil ativo/empresa, mas não função/obra; pode devolver valores/documentos de outras obras da empresa |
| P1 | fn_custo_real_ligado(uuid,uuid,uuid) | SECURITY DEFINER, EXECUTE PUBLIC (anon/authenticated efetivamente true), sem autorização; agrega custos ligados. Não executada na BD real |
| P1 crítico | fn_ajustar_saida_prevista_mensal(uuid,date,numeric) | SECURITY DEFINER, EXECUTE PUBLIC efetivo, corpo UPDATE/INSERT sem autorização de utilizador/obra. Risco de escrita económica independente. **Não foi chamada**, nem sequer como teste real |

Outras permissivas amplas inventariadas: empresas, especialidades, feriados_empresa, fornecedores_especialidades e parametros_operacionais. Este último tem uma policy admin coexistindo com `parametros_select USING(true)`; por OR, a policy admin não restringe a outra. Fornecedores_aliases/mesclagens/zonas têm âmbito de empresa, mas não restrição por função. Exigem avaliação de necessidade antes de alteração.

Grants owner-only em `fn_mgo_inserir_json_compativel`, helpers internos de Medicina, Quadro e rotina diária foram confirmados: não confundir função SECURITY DEFINER existente com RPC executável por authenticated. Consultas, pagamentos, contratos/faturas e seus anexos mantêm os predicados técnicos instalados; não foi confirmada exposição direta desses valores ao Encarregado pelas policies atuais.

## Scripts e sequência futura (NÃO executada)

1. `supabase/encarregado_escopo_precheck.sql`: READ ONLY, exige postgres, PG17 e fingerprint real `ad93cec96f207f7e622c41821eb38cf0`.
2. `supabase/encarregado_escopo_backup.sql`: futuro backup privado apenas de catálogo em `primeline_encarregado_20261004.snapshot`. Sem linhas operacionais. Aborta se já existir schema ou se houver drift.
3. `supabase/encarregado_escopo_migration.sql`: transação única, repete precheck, exige backup privado, instala apenas a lista acima. Lock timeout 5s. Guarda catálogo instalado em tabela privada.
4. `supabase/encarregado_escopo_postcheck.sql`: READ ONLY, compara catálogo instalado, garante que só as policies/funções autorizadas mudaram; testa identidades reais em SELECT com SET LOCAL ROLE/claims e ROLLBACK. Não imprime PII.
5. `supabase/encarregado_escopo_rollback.sql`: exige que o catálogo ainda corresponda à instalação; restaura função/ACL/policies exatamente, sem CASCADE; conserva snapshot privado. Restaura também as vulnerabilidades antigas, pelo que exige decisão explícita.

O fingerprint cobre todas as tabelas/views públicas (nomes, tipos de coluna, ACL de tabela/coluna, owner, RLS, policies e view definition) e todas as funções públicas (definição, ACL e owner), com ordenação C de assinaturas. Não pretende substituir um dump completo: defaults/constraints/índices/triggers das tabelas alvo foram inventariados à parte e não são alterados por nenhum destes scripts. Roles, grants de schema/default privileges estão na evidência complementar.

Falha de qualquer script: interromper; confirmar ROLLBACK da transação antes de outra ação. Não repetir automaticamente. A existência de snapshot privado não constitui autorização para aplicar.

## Testes e evidência

- PostgreSQL **17.6** efémero, só 127.0.0.1: **18/18**, zero skips. Fixture reconstitui todas as 156 tabelas/views e 247 funções do catálogo, policies e ACL reais; todas as linhas são sintéticas. Não dispara triggers/FKs/defaults operacionais, que não são objeto da alteração.
- Cobre precheck real exato, drift, backup ausente, reprodução anterior, SELECT sensível bloqueado, OR permissivo e grant de coluna adversariais, RPC operacional 120/118/122/outra empresa, pessoa livre/inativa/externa, RPCs antigas, summaries financeiros, Medicina e Ponto, anon, regressão de sete outros papéis, dados sintéticos intactos e rollback exato.
- `tests/encarregado-rnc-browser.mjs`: seis perfis + RPC ausente: **7/7**, browser real com respostas sintéticas, sem fallback direto nem DML.
- Regressões unitárias: session-boundary, foreman-scope, session-isolation, supabase-collaborators, medicine-client, login-redirect-theme, access-control, workforce-allocation-client: **37/37**.
- `tests/session-boundary-browser.mjs`: **7/7**. Gestão→Encarregado, inversa, Diretor→Encarregado, logout, expiração e mudança de identidade; a sessão anterior desaparece antes de terminar a resposta nova.
- `git diff --check`: sem erros.

Limitação explícita: não existe PostgREST local disponível. O SELECT direto foi testado no PostgreSQL com o mesmo papel/claims de authenticated e as RPCs no motor real; o consumidor HTTP foi testado com mocks. **Não se marca como PASS um ensaio de gateway REST real após a correção**, que ainda não foi instalada. Nenhum teste real de escrita de Encarregado foi feito.

## Gate

**GO LOCAL para auditoria independente** dos scripts e testes, com as limitações declaradas. **NO-GO para declarar isolamento global concluído, publicar/aplicar esta correção automaticamente, teste real de escrita ou Fase B**: subsistem os P1 adicionais, revisão independente e validação de gateway/produção após eventual autorização.

P0 confirmado: nenhum classificado; a função de escrita PUBLIC merece tratamento prioritário separado. P1: os dois originais corrigidos apenas localmente, bypasses cobertos e achados adicionais acima. P2: validar compatibilidade do deployment coordenado RNC/RPC e gateway. P3: nomenclatura/UX Folha de Ponto no Pacote 2; nenhuma reformulação nesta entrega.
