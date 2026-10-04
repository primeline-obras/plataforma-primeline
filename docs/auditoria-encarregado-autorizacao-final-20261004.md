# Auditoria independente de autorização — 04/10/2026

**Resultado: NO-GO LOCAL para aplicar o candidato como fecho consolidado de autorização.** Os quatro P0 originais foram reproduzidos na baseline e bloqueados no candidato. Permanecem seis entradas financeiras que permitem escrever noutra empresa e uma exposição de alertas a utilizador inativo. Testes que reproduzem vulnerabilidades passam quando confirmam o defeito; não significam aprovação do produto.

O candidato foi preservado e enviado sem alterações: `origin/fix/encarregado-autorizacao-final-20261004 = ff949e64f6d56986a3de6ac979c567cf745cfdb3`. A branch desta auditoria, `audit/encarregado-autorizacao-final-20261004`, nasceu exatamente desse SHA. Acrescenta somente testes, inventário e este relatório. O SHA da auditoria consta da entrega Git; não é incluído no próprio commit para evitar autorreferência.

## Método e limites da evidência

A investigação utilizou PostgreSQL **17.6 real e efémero**, PostgREST **16.4 local**, JWTs sintéticos e browser com respostas simuladas. O PostgREST foi iniciado em localhost; não se afirma que a versão seja igual à de produção. As definições, owners, ACLs, RLS, policies e views vieram do catálogo capturado em `tests/fixtures/encarregado-catalogo-real-20261004.json`, complementado pelos snapshots de privilégios, autorização e integridade. O relatório anterior não foi utilizado como prova de ausência de defeitos.

O ambiente recompõe o catálogo de 247 funções e tabelas com dados sintéticos, não uma cópia completa de produção. Nem todos os defaults, NOT NULL e FKs são instalados nesse harness. Os testes financeiros usam linhas existentes, estados válidos e os triggers reais capturados de `faturas` e `faturacao`, além dos triggers relevantes de obras, planeamento, comparativos e previsão. Portanto, as escritas demonstradas não dependem de inserir registos inválidos por uma RPC vulnerável.

Não foi executada qualquer consulta ou escrita em produção durante esta auditoria. Não houve migration real, merge em main, marker B ou Fase B. Os testes de rollout A/B executados pelas suites de regressão são exclusivamente locais/sintéticos.

## P0 que permanecem: escrita financeira entre empresas

Um utilizador sintético ativo com função **Financeiro**, da empresa A, conseguiu alterar registos da empresa B conhecendo os UUIDs. Não era administrador. As funções são SECURITY DEFINER, owner `postgres`, executáveis por `authenticated`. A guarda de papel `fn_e_financeiro()` não impõe correspondência da empresa do ator com a obra do registo recebido.

| Entrada | Efeito comprovado sobre registo da empresa B | Canal |
|---|---|---|
| `fn_marcar_fatura_paga(uuid,date)` | `estado_pagamento: por_pagar → pago` | PostgreSQL com papel authenticated |
| `fn_desmarcar_fatura_paga(uuid)` | `pago → por_pagar` | PostgreSQL com papel authenticated |
| `fn_devolver_fatura_financeiro(uuid,text)` | `estado_aprovacao: aprovado → pendente` | PostgreSQL com papel authenticated |
| `fn_avancar_estado_fluxo_fatura(uuid,text,date,text)` | passagem para `paga`, pagamento persistido | HTTP `/rpc`, resposta 200, confirmada por SELECT |
| `fn_marcar_faturacao_auto_paga(uuid,date,numeric)` | `valor_recebido: 0 → 543` | PostgreSQL com papel authenticated |
| `fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)` | `valor_recebido: 0 → 10` | PostgreSQL com papel authenticated |

São seis entradas para uma causa comum: autorização financeira por função sem autorização do recurso/empresa. As cinco provas SQL verificaram o efeito antes de ROLLBACK; a prova HTTP confirmou uma escrita efetivamente concluída e depois removeu somente dados sintéticos. Os triggers reais não impediram a passagem entre empresas.

O modelo legado concede ao Financeiro acesso amplo em algumas policies. Se esse acesso global for uma decisão de negócio, precisa de confirmação explícita e de um contrato de autorização consistente. Até lá, o critério desta tarefa exige isolamento por empresa, pelo que estas entradas são classificadas P0. Não são novas permissões introduzidas pelo hotfix; são falhas residuais que impedem declará-lo um fecho completo.

Evidência executável: testes `FINDING` em `tests/audit-encarregado-cases.mjs`. Ator, obras e faturas usam exclusivamente UUIDs sintéticos. Nenhuma correção de produto foi feita.

## P1 que permanece: alertas para Encarregado inativo

O teste HTTP `FINDING: inactive Encarregado retains targeted alerts` devolveu 200 e a descrição de um alerta dirigido a um utilizador inativo. A policy permissiva `quadro_movimentacao_pessoal_select` verifica destinatário, mas não atividade. `fn_utilizador_atual_id()` resolve esse utilizador sem exigir `ativo`.

Isto prova leitura de alerta próprio por uma sessão ainda válida de utilizador inativo. Não prova leitura global de alertas. Revogar a UI ou limpar caches não substitui a negação no backend. Outras policies por destinatário merecem revisão da mesma condição; não são aqui apresentadas como explorações dinamicamente demonstradas.

O postcheck atual passa apesar dos seis P0 financeiros. A falta de testes negativos de empresa nesses writers é uma lacuna P1 do gate, associada às falhas acima, sem contar como um sétimo exploit.

## Quatro P0 originais: baseline e candidato

Todas as quatro funções eram SECURITY DEFINER, owner `postgres`, com `proacl NULL` e EXECUTE efetivo para PUBLIC, anon, authenticated e service_role na baseline. O `search_path` era `public`, exceto no comparativo, que era `public, pg_temp`.

| Assinatura | Prova HTTP anon na baseline | Resultado no candidato |
|---|---|---|
| `fn_ajustar_saida_prevista_mensal(uuid,date,numeric)` | obra sintética da empresa B: saída mensal 10 → 17 | recusado |
| `fn_atualizar_melhor_preco_comparativo(uuid)` | mapa da empresa B: melhor preço 999 → 0 | recusado |
| `fn_congelar_planeamento_baseline(uuid)` | obra da empresa B: baseline congelada false → true | recusado |
| `fn_verificar_congelamentos_pendentes()` | congelamento global: quatro obras sintéticas atingidas | recusado |

Cada chamada anon foi feita pelo PostgREST e o efeito foi confirmado por SELECT posterior. Os UUIDs foram escolhidos pelo chamador, sem uma autorização de obra. A quarta entrada não recebe ID e alcança obras por consulta interna. Cada uma é P0 na baseline.

No candidato, cada entrada foi testada por HTTP sem JWT, como Encarregado, utilizador de outra empresa, inativo e authenticated sem perfil correspondente. Os resultados foram 401/403/404, conforme o canal e a visibilidade no schema cache. Um papel de prova que herda somente PUBLIC também não possui EXECUTE. UUIDs de outra empresa não contornam a revogação. `service_role` e owner conservam execução técnica; os corpos das quatro funções não foram alterados.

Os consumidores legítimos foram testados: o trigger de sincronização de subempreitada continua a atualizar a previsão; o trigger de preço recalcula o comparativo; o wrapper autorizado `fn_eliminar_item_comparativo` continua a invocar o helper; o owner executa os quatro helpers. A chamada técnica do scheduler foi exercitada como owner. Não se executou um job de produção nem se afirma ter testado o serviço cron remoto.

## Inventário independente

`tests/audit-encarregado-inventario.json` contém as 247 funções anteriores e as 250 posteriores, recolhidas de `pg_proc` no ambiente reconstruído. Inclui assinatura, owner, SECURITY DEFINER, search_path, ACL bruta, EXECUTE efetivo anon/authenticated/service_role, resultado, chamadas, escrita direta/transitiva, linhas de guardas, referência explícita a empresa e classificação.

A análise identificou 138 SECURITY DEFINER com escrita direta ou transitiva em ambos os estados. Excluindo triggers, 96 eram executáveis por anon ou authenticated antes, e 92 depois. A redução corresponde aos quatro helpers retirados do canal externo.

O grafo é conservador: reconhece chamadas por nome e pode reunir overloads; SQL dinâmico e semântica de todos os ramos não são provados por regex. `tenant_explicit` indica presença de `empresa_id`, não certifica autorização. Funções ainda classificadas `REVISÃO ESTÁTICA` não estão aprovadas individualmente. Foi feita varredura de todos os corpos e seguida a matriz dos consumidores, mas não existe prova dinâmica exaustiva de cada ramo dos 247 corpos. Esta limitação fica explícita e é mais um motivo para não emitir aprovação total. O inventário anterior não foi reutilizado como resultado desta varredura.

## Matriz de Encarregado

| Área | Resultado local | Evidência/limite |
|---|---|---|
| Colaboradores/RH | PASS | SELECT direto e colunas NIF/NISS/morada/valor-hora negados; equipa operacional limitada; RPCs globais antigas sem EXECUTE |
| Ausências/férias | PASS | RPC com projeção mínima da equipa; sem justificações/anexos; outra empresa, inativo e sem responsabilidade recusados |
| Alocações | PASS | leitura global e DML legado bloqueados; contexto v1 limitado; operação antiga de Encarregado encaminha para v1 |
| Subempreitadas | PASS | RPC operacional apenas obra autorizada e quatro campos; sem montantes/condições/pagamentos |
| Fornecedores/aliases/mesclagens | PASS | SELECT direto e tentativas de contornar por grants de coluna/policies OR recusados |
| Avaliações | PASS | sem leitura global indevida; consumidores internos preservados |
| Faturas/financeiro como Encarregado | PASS | pesquisa, custos, views e writers financeiros recusados, incluindo UUID válido externo |
| RNC/documentos | PASS | leituras operacionais autorizadas; obra externa recusada; browser RNC preservado |
| Medicina | PASS | leitura autorizada; escrita e pessoa externa recusadas; histórico e inativos nas regressões |
| Ponto | PASS | consulta da equipa autorizada preservada; obra externa recusada |
| Alertas com utilizador inativo | FAIL / P1 | sessão válida ainda lê alerta dirigido ao próprio |

As contagens de SELECT dos sete outros perfis foram comparadas antes/depois e preservadas. Isso comprova a amostra e as policies exercitadas, não todos os fluxos possíveis desses perfis. A escrita financeira de outro tenant por Financeiro permanece FAIL mesmo quando os testes do Encarregado passam.

## PostgREST e isolamento de sessão

O servidor local exercitou REST direto, seleção de colunas sensíveis, filtros manipulados, UUIDs conhecidos externos, anon sem JWT e authenticated. As quatro entradas P0 foram reproduzidas antes e negadas depois. Foram exercitados PATCH/DELETE/INSERT legados e os RPCs operacionais mínimos. Nenhuma chave ou token real foi utilizado.

Os sete testes browser de fronteira de sessão cobriram Gestão → Encarregado, Encarregado → Gestão, Diretor → Encarregado, logout, expiração, mudança de auth_user_id e resposta atrasada. Os testes unitários de sessão/cache também passaram. Não ficou DOM/cache protegido da sessão anterior nos cenários simulados. Não se fez nova validação autenticada em produção.

## Scripts de rollout

Os cinco scripts `supabase/encarregado_escopo_{precheck,backup,migration,postcheck,rollback}.sql` foram lidos e executados somente no PostgreSQL efémero.

| Script | Conclusão |
|---|---|
| Precheck | hash canónico do catálogo e owner/major verificados; drift de coluna, policy, grant e SECURITY DEFINER aborta; não depende de uma contagem fixa operacional |
| Backup | snapshot privado de definições, owners, search_path, ACL de funções, grants de tabela/coluna, RLS, policies e views; contém catálogo, não backup de linhas operacionais |
| Migration | exige backup privado e fingerprint, usa transação/locks; alterações limitadas a policies, funções e grants previstos; nenhuma linha operacional alterada nos testes |
| Postcheck | verifica catálogo instalado, privilégios e amostra de perfis; recusa drift posterior; **não cobre os seis writers financeiros entre empresas nem REST por si só** |
| Rollback | aborta perante drift posterior; restaura definições e privilégios efetivos do escopo; fingerprint canónico original recuperado; diferença de ACL bruta descrita abaixo |

P2 confirmado: `GRANT CREATE ON SCHEMA public TO authenticated`, aplicado numa transação local e revertido, não mudou o fingerprint e o precheck passou. O hash não inclui ACL do schema, atributos/membros de roles, defaults, NOT NULL, constraints, triggers e índices. Esses itens existem parcialmente nos snapshots auxiliares, mas não fazem parte do mesmo gate automático. O teste demonstra uma lacuna de deteção de drift, não uma escalada de privilégios por si só.

O backup deve ser entendido como reversão do escopo de autorização, não como proteção integral contra qualquer alteração estrutural futura. A implantação não está autorizada por este relatório enquanto houver P0/P1.

## Rollback: ACL implícita para explícita — P2

A baseline tinha `pg_proc.proacl IS NULL` nas quatro funções, equivalente a `acldefault('f', owner)`. O rollback faz REVOKE/GRANT e deixa ACL explícita com EXECUTE PUBLIC. O teste confirmou simultaneamente que `proacl IS NULL` deixa de ser verdadeiro, que anon recupera EXECUTE efetivo e que o catálogo canónico inteiro volta ao hash esperado `2be961099e9694bdd29ba95d3cc10173`.

Os privilégios efetivos recuperados são iguais. `acldefault` não é modificado. Há diferença persistente em `pg_proc.proacl`; não foi demonstrada alteração de `relacl` das tabelas pelo rollback. Um precheck futuro que use ACL bruta, em vez da equivalência canónica, pode recusar essa fotografia. O hash antigo bruto não deve ser reutilizado depois desse rollback sem recolher nova baseline.

Não há comando DDL normal para repor diretamente `proacl = NULL`. Atualizar catálogos do PostgreSQL seria uma alteração não suportada; DROP/CREATE pode alterar OIDs e quebrar dependências. As alternativas seguras são manter a ACL explícita com comparação canónica documentada, ou planear reconstrução controlada das funções e dependências numa tarefa própria. Para este rollback, a diferença é P2: não invalida a recuperação de acesso, mas deve permanecer registada e refletida nos próximos gates.

## Testes e regressões

Os números abaixo contam a última execução concluída de cada suite, sem acumular repetições durante a investigação.

| Grupo | Resultado |
|---|---|
| Auditoria PostgreSQL 17.6 + PostgREST local | **53/53 PASS**, zero skip; inclui testes que confirmam falhas residuais |
| Quadro controlado + Medicina, PostgreSQL 17.6 | **197/197 PASS**, zero skip; inclui concorrência, idempotência, RH e rollback locais |
| Regressões de 22 ficheiros | **63 PASS, 4 SKIP, 0 FAIL**, total 67 |
| Browser fronteira de sessão | **7/7 PASS**, mocks locais |
| Browser RNC Encarregado | **7/7 PASS**, mocks locais |
| Browser Quadro | **3 grupos PASS**, desktop/tablet/mobile |
| Browser Medicina independente | **PASS**, suite com mocks, histórico, correção/anulação, inativos, perfis e três viewports |
| Browser Viaturas | **PASS**, suite com mocks, atribuição, revisão e layouts |

Total das três execuções Node com contagem de testes: **317 testes, 313 aprovados, 4 ignorados, zero falhas finais**. Os grupos browser são apresentados separadamente, sem inventar uma contagem por interação. Os quatro skips por dependência RH não foram considerados aprovados. Cadastro/RH teve cobertura nativa na suite do Quadro, mas isso não transforma os skips em PASS.

As regressões cobriram Quadro, Cadastro RH, Medicina, Ausências/Férias, Subempreitadas, Financeiro/faturas, Planeamento, RNC, Documentos, Viaturas, alertas e sessão/access-control. O grupo de 22 ficheiros mistura testes unitários, estáticos e PGlite; não deve ser apresentado como 67 testes de PostgreSQL nativo ou de browser.

O browser original de Medicina falhou porque o mock classificava a nova chamada de leitura `fn_ausencias_equipa_encarregado` como escrita desconhecida. A cópia independente acrescentou apenas a resposta de leitura simulada, e passou. O teste original e o produto não foram alterados. Também foram corrigidos somente os estados das faturas sintéticas na cópia dos testes: uma recusa por estado inválido não prova autorização, pelo que os testes negativos passaram a usar estado válido antes de verificar a recusa por permissão.

Comandos principais: `node --test tests/audit-encarregado-autorizacao.test.mjs`; `node --test tests/workforce-controlled.test.mjs tests/medicina-trabalho.test.mjs`; suites browser `session-boundary-browser`, `encarregado-rnc-browser`, `workforce-controlled-browser`, `audit-medicine-browser` e `vehicle-assignment-browser`. Os binários são parametrizados por `QUADRO_PG_BIN`, `QUADRO_TEST_DEPS`, `QUADRO_POSTGREST`, `MEDICINA_PG_BIN`, `MEDICINA_TEST_DEPS` e `PLANNING_PLAYWRIGHT`. Não contêm credenciais reais.

## Decisão

**NO-GO LOCAL.** O candidato corrige as quatro entradas anónimas e os caminhos de Encarregado exercitados, mas não satisfaz o critério de nenhum P0/P1 restante. A próxima tarefa de produto deve tratar a autorização de recurso/empresa nos seis writers financeiros e a leitura de alertas por utilizador inativo, e ampliar os gates correspondentes. Este relatório e os testes preservam as provas; não implementam essas correções.

Não se aplicou nada em produção, não se mergeou main e não se executou marker B/Fase B. O candidato remoto permaneceu exatamente no SHA aprovado para auditoria.
