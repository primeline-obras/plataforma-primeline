# Auditoria final de autorização — 04/10/2026

**NO-GO LOCAL para rollout real.** As suites existentes confirmaram as correções dos quatro P0 originais, das seis RPCs financeiras e dos alertas de inativos. A revisão de código identificou autorização de empresa incompleta em outros writers do domínio. A validação dinâmica adicional desses achados ficou **VALIDAÇÃO BLOQUEADA PELO AMBIENTE**, conforme a restrição expressa na retoma. Não foram criadas novas provas, técnicas ou caminhos de bypass, nem corrigido o candidato.

## Checkpoint e âmbito efetivamente concluído

Candidato preservado e enviado: `origin/fix/autorizacao-financeira-cross-tenant-20261004 = a3d250820d3d745e5fbeaba1b88117e757803450`. Auditoria anterior preservada: `10f065a1fb1645dec3bc43e02489557a06374325`. Branch desta auditoria: `audit/autorizacao-financeira-cross-tenant-final-20261004`, criada exatamente do candidato. O SHA final do relatório consta da entrega Git.

O último checkpoint antes da retoma era o push confirmado, a criação da branch e a leitura estática de funções de custos/comparativos. Nenhum teste novo desses caminhos havia sido criado ou executado. A continuação respeitou a restrição: revisão de código, ACL/policies/grants, scripts e execução de suites já existentes. Não se tentou contornar a proteção reportada pelo utilizador. Não se conhece o detalhe interno dessa proteção e não se atribui a ela um erro técnico de ferramenta que não foi observado.

O catálogo é o snapshot capturado em `tests/fixtures/encarregado-catalogo-real-20261004.json`, complementado pelos snapshots de autorização/integridade e pelo SQL do candidato. Não se fez diagnóstico novo da BD real. Main local permanece `d6db2c3c9e48170a3d4c6ec937b5f7ad76e411fb`; produção é a referência fornecida pelo utilizador, não uma nova validação de deploy.

Foram concluídas revisão de definições e dependências, comparação de grants, avaliação das suites preparadas, regressões e leitura integral do pacote de rollout. Os relatórios anteriores serviram como lista de verificação, sem serem usados como prova de aprovação. Nesta retoma, as provas dinâmicas são reexecuções das suites existentes; não se afirma que foram concebidos novos testes independentes.

## P0/P1 ainda identificados

**P0 novo reproduzido nesta auditoria: nenhum.** Isso não equivale a comprovar ausência de P0: a reprodução dinâmica adicional está bloqueada.

**P1 confirmado por revisão de código: guarda de empresa ausente em 12 writers adicionais.** Os corpos capturados continuam no candidato, pois não são redefinidos na migration. São SECURITY DEFINER, owner postgres, search_path `public, pg_temp`, com EXECUTE de authenticated e postgres. Recebem IDs de entidades/obras e escrevem no domínio económico. As guardas descritas abaixo não comparam a empresa do ator com a empresa do alvo.

| Assinatura | Guarda existente | Escrita indicada pelo corpo |
|---|---|---|
| `fn_concluir_custo_pl(uuid,numeric)` | `fn_e_diretor_obra(obra)` | custo real/estado de componente PL |
| `fn_concluir_custo_pl_fase(uuid,numeric)` | Gestão ou `fn_e_diretor_obra(obra)` | custo real/estado de orçamento de fase |
| `fn_concluir_custos_pl_tarefa(uuid)` | `fn_pode_editar_obra(obra)` | conclusão dos componentes PL da tarefa |
| `fn_confirmar_custo_real_pl(uuid,numeric)` | `fn_pode_editar_obra(obra)` | valor real e confirmação PL da tarefa |
| `fn_confirmar_remocao_custo_estimado_subempreitada(uuid)` | `fn_e_diretor_obra(obra)` | confirmação de remoção do estimado |
| `fn_guardar_componente_custo(uuid,text,numeric,text,numeric,uuid)` | `fn_e_diretor_obra(obra)` | criação/alteração de componente económico |
| `fn_eliminar_proposta_comparativo(uuid)` | `fn_pode_editar_obra(obra)` | eliminação da proposta e recálculo do mapa |
| `fn_criar_fornecedor_comparativo(uuid,text)` | `fn_pode_editar_obra(obra)` | criação de fornecedor na empresa da obra alvo |
| `fn_importar_proposta_comparativo(uuid,uuid,jsonb,jsonb)` | `fn_pode_editar_obra(obra)` | proposta, itens e preços |
| `fn_criar_subempreitada_do_comparativo(uuid,uuid,uuid,date,date,text)` | `fn_pode_editar_obra(obra)` | adjudicação/subempreitada |
| `fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric)` | `fn_pode_editar_mapa_gestao_obras()` | criação/alteração de lançamento económico |
| `fn_apagar_lancamento_gestao_obras(uuid)` | `fn_pode_editar_mapa_gestao_obras()` | eliminação de lançamento económico |

`fn_e_diretor_obra` e `fn_pode_editar_obra` incluem a alternativa `fn_e_admin()` sem empresa. `fn_pode_editar_mapa_gestao_obras` verifica utilizador ativo e função Gestão/Administrativo, sem receber ou resolver empresa do recurso. Na gravação de lançamento, a existência de p_obra_id não prova âmbito; na edição/eliminação, a empresa da linha original também não é verificada.

Nas funções de comparativo, verificar que proposta/fornecedor/fase pertence ao mapa/obra garante coerência entre as entidades recebidas, mas não a empresa autorizada do ator. As policies restritivas novas não substituem a autorização interna dessas funções SECURITY DEFINER de owner postgres.

A lacuna de código é confirmada. O efeito transacional real, os estados adicionais exigidos por triggers e o resultado HTTP para cada uma destas 12 entradas **não foram reproduzidos nesta retoma**. Classificação atual: P1 de autorização incompleta; possível impacto crítico económico pendente de validação. Não apresentar como 12 explorações P0 comprovadas.

A regra expressa da tarefa exige empresa da entidade nas escritas económicas, inclusive quando o papel é administrativo. Se existir intenção de administração entre empresas, precisa de decisão explícita; o relatório não presume essa exceção.

## Quatro P0 originais

| Entrada | Resultado nas suites existentes |
|---|---|
| `fn_ajustar_saida_prevista_mensal(uuid,date,numeric)` | PASS: execução externa revogada; owner/service_role e trigger técnico preservados |
| `fn_atualizar_melhor_preco_comparativo(uuid)` | PASS: execução externa revogada; trigger e wrapper legítimo preservados |
| `fn_congelar_planeamento_baseline(uuid)` | PASS: execução externa revogada; execução técnica preservada |
| `fn_verificar_congelamentos_pendentes()` | PASS: execução externa revogada; chamada técnica local preservada |

As suites existentes reproduzem o estado anterior por SQL e testam os privilégios efetivos no candidato, incluindo utilizadores sem âmbito/inativos. Não foi feita nova prova HTTP independente das quatro entradas nesta retoma. As funções de trigger e chamadas técnicas foram exercitadas localmente; nenhum job de produção foi executado. PUBLIC não concede EXECUTE externo após as revogações; anon/authenticated não recuperam esse acesso através da ACL.

## Seis RPCs financeiras

| Entrada | Resultado local preparado |
|---|---|
| `fn_marcar_fatura_paga(uuid,date)` | PASS |
| `fn_desmarcar_fatura_paga(uuid)` | PASS |
| `fn_devolver_fatura_financeiro(uuid,text)` | PASS |
| `fn_avancar_estado_fluxo_fatura(uuid,text,date,text)` | PASS |
| `fn_marcar_faturacao_auto_paga(uuid,date,numeric)` | PASS |
| `fn_registar_recebimento_parcial(integer,uuid,date,numeric,text,numeric)` | PASS |

Para cada uma, o teste existente fez baseline HTTP entre empresas, recusa equivalente no candidato, operações próprias por Financeiro/Gestão/Gerência, inativo, papel errado, ausência de perfil, anon e UUID inexistente. Comparações de estado confirmaram ausência de escrita parcial nas recusas. PUBLIC/service_role foram verificados por privilégios efetivos; authenticated conserva execução com autorização interna. Administrativo não ganhou pagamento: segue o contrato existente de papel, embora mantenha seus fluxos próprios.

A revisão confirma resolução da obra a partir da entidade, empresa derivada de auth.uid(), atividade obrigatória, locks no documento/ator/obra e helper privado. No recebimento parcial, o recurso é autorizado antes de devolver um replay. Concorrência e replay simultâneo da suite passaram. Os contratos de estado/payload foram preservados.

Os caminhos alternativos já corrigidos passaram nas suites existentes: aprovação de fatura/faturação, devolução administrativa, vínculo de subempreitada, dois overloads de edição pendente, remoção de guia/anexo e eliminação de mapa/item. DELETE REST financeiro externo fica sem linhas alteradas. As 24 expressões de policies foram avaliadas para recurso próprio/externo; isso não é prova HTTP de todas as combinações de INSERT/UPDATE/DELETE nessas tabelas.

## Alertas e matriz de Encarregado

Alertas: **PASS nos testes existentes**. O utilizador inativo recebe zero linhas por REST para destinatário próprio, agenda, viatura e responsabilidade residual; o ativo autorizado mantém leitura. A policy restritiva `alertas_sessao_ativa` impede que uma policy permissiva por papel/destinatário autorize o inativo. `fn_resolver_alerta` verifica atividade antes de resolver como SECURITY DEFINER. A revisão dos consumidores confirmou leitura REST e RPC de resolução; não foi criado novo teste de RPC/listagem de alerta nesta retoma.

| Área | Resultado e limite |
|---|---|
| Colaboradores/RH | PASS: SELECT e colunas sensíveis recusados; equipa operacional limitada; RPCs globais antigas sem execução |
| Ausências/férias | PASS: projeção mínima da equipa, sem justificações/anexos indevidos |
| Alocações | PASS: DML legado recusado, contexto v1 limitado e fluxo preparado preservado |
| Medicina | PASS: equipa autorizada, fora do âmbito recusado, can_write=false |
| Subempreitadas | PASS: obra própria e quatro campos operacionais, sem valores |
| Fornecedores/aliases/mesclagens | PASS nas tentativas preparadas de leitura global; não equivale a testar todas as referências económicas possíveis de mesclagem |
| Avaliações | PASS nos testes preparados de acesso direto |
| Faturas/financeiro como Encarregado | PASS nos RPCs/views/listagens/custos e UUIDs preparados; revisão dos writers adicionais permanece bloqueadora do fecho geral |
| RNC/documentos | PASS: operações de leitura legítimas e negativas preparadas preservadas |

## SECURITY DEFINER: revisão focada

O inventário de 247 funções foi usado como mapa. Foram revistos os writers de faturas/recebimentos, custos, comparativos, previsão e congelamento, além das guardas e ACLs de alertas. Não houve exploração ilimitada nem geração de novos caminhos de prova.

Classificação da revisão: OK no âmbito dos testes para as seis RPCs e os caminhos já corrigidos; OK para os quatro helpers técnicos retirados do canal externo; P1 para os 12 writers da tabela; P2 para cobertura incompleta de ramos/constraints fora das suites e os limites dos gates descritos abaixo. Triggers são dependências de writers, não RPCs de aplicação só porque têm ACL implícita.

`fn_mgo_inserir_json_compativel` está sem execução externa no catálogo; a importação legítima deriva empresa e resolve recursos nela. Mesclagem de fornecedores verifica empresa dos dois fornecedores; o alcance de todas as referências históricas não foi dinamicamente expandido. Nenhuma dessas observações é certificado de todos os ramos dessas funções.

## Sessão e browser

PASS nos sete cenários browser existentes: Gestão → Encarregado, Encarregado → Gestão, Diretor → Encarregado, logout de Medicina/Obra, expiração e mudança de identidade sem logout. O browser bloqueia deliberadamente respostas da segunda sessão e verifica remoção do sentinela privado e seleção de obra antiga antes de liberar essas respostas.

Os testes unitários existentes de fronteira também confirmam que uma resposta REST/corpo atrasado é abortado e que refresh antigo não restaura a sessão anterior. Estes são testes locais com identidades simuladas e tráfego interceptado; não uma nova troca real de contas de produção.

## Scripts de rollout e ACL

Leitura integral dos cinco scripts `supabase/encarregado_escopo_{precheck,backup,migration,postcheck,rollback}.sql` e execução somente local:

| Script | Resultado |
|---|---|
| Precheck | PASS no catálogo reconstruído; BEGIN READ ONLY; drift preparado de coluna/policy/grant/definer aborta |
| Backup | PASS local; schema privado e snapshot completo do catálogo considerado, funções/ACL/owner/search_path/grants/policies/views; não contém backup das linhas operacionais |
| Migration | PASS local; conserva dados da fixture; cobre alterações declaradas, sem ampliação de EXECUTE público; não cobre os 12 writers identificados |
| Postcheck | PASS local estrutural e nas guardas puras; não invoca RPCs de escrita; passar não prova fecho dos writers adicionais |
| Rollback | PASS local; catálogo canónico e acessos anteriores restaurados; exige instalação sem drift e não usa CASCADE |

O postcheck detecta presença textual das guardas nos corpos alterados, owner/search_path/privilégios, policy de atividade e contagem das 24 policies, além da igualdade com a instalação e comparação fora do allowlist. As chamadas de guards puras por utilizador/obra são somente leitura. **Não é prova semântica completa de cada RPC nem de todas as funções que ficaram fora da alteração.** Esta lacuna de cobertura é P1 como gate de fecho consolidado, ligada aos writers restantes, sem contar como exploit adicional.

P2 persistente: o fingerprint não cobre ACL do schema, atributos/membros de roles, defaults/NOT NULL, constraints/triggers/índices. A retoma não criou novos ensaios de drift; a revisão confirma esses campos ausentes do fingerprint. O precheck é válido para o catálogo que inclui, não para todo o ambiente PostgreSQL.

ACL implícita → explícita: o rollback das quatro funções originalmente com proacl NULL concede novamente PUBLIC. A equivalência efetiva é confirmada pela restauração canónica local. A representação bruta pode ficar diferente, sem alteração de acldefault. O precheck canónico atual continua compatível; futuros prechecks baseados em proacl bruto podem recusar essa fotografia. Classificação P2. Não existe garantia geral sobre prechecks futuros desconhecidos. Não se recomenda manipular pg_catalog ou recriar funções para esconder a diferença.

## Execuções e preservação dos resultados

| Grupo reexecutado nesta retoma | Resultado |
|---|---|
| `financeiro-cross-tenant.test.mjs`, PostgreSQL 17.6 + PostgREST 16.4 local | 75 PASS, zero skip |
| Quadro/Cadastro RH + Medicina, PostgreSQL 17.6 | 197 PASS, zero skip |
| 22 ficheiros unitários/estáticos/PGlite | 63 PASS, 4 SKIP, zero fail |
| Browser sessão | 7 cenários PASS |
| Browser RNC | 7 cenários PASS |
| Browser Quadro | 3 grupos PASS; desktop/tablet/mobile |
| Browser Medicina | PASS: quatro perfis, três viewports, histórico/inativos e operações simuladas |
| Browser Viaturas | PASS: permissões, revisão e desktop/mobile |

Total formal Node: **339 testes, 335 PASS, 4 SKIP, zero falhas finais**. Não foram somadas iterações anteriores. Browser é apresentado separadamente, sem inventar uma contagem por interação. Os quatro skips por dependência RH continuam sem aprovação.

Regressões cobriram Quadro, RH, Medicina, Ausências/Férias, Subempreitadas, fornecedores no catálogo/matriz, Financeiro/faturas, Planeamento, RNC, documentos, Viaturas, alertas, access-control e sessão. O grupo de 22 ficheiros mistura unit/static/PGlite; não foi apresentado como PostgreSQL nativo ou browser.

Os resultados anteriores foram preservados nas branches originais. Nesta execução, os logs de testes existentes foram mantidos localmente em `%TEMP%/primeline-final-audit-existing-security.log`, `primeline-final-audit-native.log` e `primeline-final-audit-unit.log`; os resultados browser constam da saída da execução e deste relatório. Não foram introduzidos dados reais ou credenciais no Git.

## Validação bloqueada e decisão

**VALIDAÇÃO BLOQUEADA PELO AMBIENTE:** novas provas dinâmicas dos 12 writers identificados por revisão, expansão de cenários negativos e verificação independente de todos os ramos relevantes além dos testes já existentes. A proteção foi reportada pelo utilizador, que restringiu expressamente a retoma. Não houve tentativa de contornar, nem nova prova criada.

Concluído: preservação do candidato, revisão de código/ACL/policies/grants, suites existentes, regressões browser/funcionais, comparação de scripts e análise de rollback. Não houve falha nas suites reexecutadas. O candidato não foi alterado.

**NO-GO LOCAL**, com base na lacuna estática de autorização e na validação essencial ainda bloqueada. Não se emite a frase de aptidão para rollout real. Os PASS das correções exercitadas ficam válidos, mas não justificam declarar ausência de P0/P1 no domínio completo.

Nenhum SQL aplicado em produção, nenhum merge em main, frontend publicado, marker B, backup B ou Fase B. Esta branch contém somente o relatório, conforme a retoma; nenhum novo teste ofensivo foi criado.
