# Encarregado — candidato consolidado de autorização

## Estado da entrega

- Checkpoint anterior: `108a6e4ed9301f47236cb2bb6ab5c1adc025422a`, commit/push confirmado em `fix/encarregado-escopo-backend-20261004`.
- Branch consolidada: `fix/encarregado-autorizacao-final-20261004`, criada desse checkpoint.
- Inclui por ancestralidade o isolamento de sessão `c1bcf3e2de956744e0526a3b4561e25b3cda67ad`.
- Nenhuma migration, backup, alteração de dados, publicação, merge, teste real de escrita, alerta, marcador ou Fase B foi executado em produção.
- Não foi iniciada auditoria independente. Este documento prepara o candidato para essa auditoria.

## Evidência real e método

Catálogo reconfirmado em 04/10/2026, na aba Supabase existente do projeto `znttyadndpkxuekhjamd`: PostgreSQL **17.6**, 156 tabelas/views e 247 funções. Consultas remotas envolveram apenas catálogo, papéis distintos e metadados de agendamento, sempre com `BEGIN READ ONLY` e `read_only: true`. Nenhuma linha operacional real foi copiada para o repositório.

Fontes em `tests/fixtures/`:

- `encarregado-catalogo-real-20261004.json`: definições completas, tabelas, colunas, policies, owners, ACLs e views.
- `encarregado-catalogo-privilegios-20261004.json`: privilégios efetivos, schema ACL, memberships e estrutura dos alvos iniciais.
- `encarregado-autorizacao-real-20261004.json`: confirmação do writer prioritário e EXECUTE efetivo das 247 funções, incluindo service_role.
- `encarregado-autorizacao-integridade-20261004.json`: triggers públicos e constraints dos alvos de escrita reproduzidos.
- `encarregado-autorizacao-inventario-20261004.json`: inventário integral, chamadas, guardas, classificação e fundamento por assinatura.

Fingerprint anterior bruto: `ad93cec96f207f7e622c41821eb38cf0`, inalterado na reconferência. O fingerprint usado pelos scripts consolidados é **`2be961099e9694bdd29ba95d3cc10173`**, também calculado na BD real por SELECT. A diferença é só a normalização das ACLs de funções: expansão de NULL para o ACL predefinido e ordenação dos aclitems. Não representa alteração em produção.

O backup conserva adicionalmente a ACL bruta de cada função. O rollback verifica igualdade de definições, owners, tabelas, policies, grants de coluna e privilégios de execução. Para funções cujo `proacl` era NULL, a reposição deixa explícito o mesmo ACL predefinido; **não promete identidade byte a byte do campo interno `pg_proc.proacl`**. Não escreve no catálogo do sistema para forçar NULL.

## P0 confirmados e corrigidos localmente

As quatro entradas seguintes aceitaram execução por `anon` e alteraram linhas sintéticas conhecidas de outra empresa, com os corpos reais instalados no PostgreSQL 17.6 local:

| Assinatura | Efeito reproduzido | Correção |
|---|---|---|
| `fn_ajustar_saida_prevista_mensal(uuid,date,numeric)` | Saída prevista de outra empresa: 10 → 510 | Retirar EXECUTE de PUBLIC/anon/authenticated |
| `fn_atualizar_melhor_preco_comparativo(uuid)` | Melhor preço de mapa alheio: 999 → 0 | Mesma restrição |
| `fn_congelar_planeamento_baseline(uuid)` | Marca obra alheia como congelada | Mesma restrição |
| `fn_verificar_congelamentos_pendentes()` | Aciona o congelamento de todas as quatro obras sintéticas elegíveis | Mesma restrição |

Os quatro corpos permanecem iguais. `postgres` e `service_role` conservam EXECUTE. Não há alteração de cálculo, temporalidade ou regras de Planeamento. A rotina agendada real que referencia o congelamento executa como `postgres`; continua autorizada. Triggers internos SECURITY DEFINER também continuam a chamar os helpers como owner.

### Writer financeiro prioritário

`public.fn_ajustar_saida_prevista_mensal(p_obra_id uuid,p_mes date,p_variacao numeric) RETURNS void`:

- Owner `postgres`; SECURITY DEFINER; `search_path=public`.
- ACL real NULL: PUBLIC EXECUTE predefinido; anon/authenticated/service_role com execução efetiva.
- Escreve `previsao_financeira_mensal`, por UPDATE ou INSERT, nas saídas previstas sem/com IVA do mês normalizado.
- Nenhuma verificação de identidade, papel, empresa ou autorização sobre a obra. UUID de outra empresa é aceite.
- A proteção de mês fechado é uma regra económica; não é uma autorização.
- Chamadores internos identificados: sincronização de previsão por subempreitada/TEE. Nenhum consumidor frontend direto encontrado.
- Reprodução local positiva por anon, seguida de rollback do teste; depois da correção, EXECUTE recusado para anon e todos os perfis authenticated testados. Chamada pelo owner continua funcional.
- Não foi invocada em produção nesta tarefa.

## P1 confirmados e corrigidos localmente

| Exposição | Fecho |
|---|---|
| Ficha ampla de colaboradores, incluindo campos RH/económicos | Policy restritiva de SELECT; diretório operacional por RPCs autorizadas |
| Três bypasses de pessoas | Contexto v1 sem ramo global de Encarregado; duas RPCs globais antigas sem EXECUTE authenticated |
| Subempreitadas globais/comerciais | Policy restritiva; RNC usa projeção `id/obra_id/fornecedor_id/especialidade` da obra autorizada |
| Fornecedores, aliases e histórico de mesclagens | SELECT direto bloqueado ao Encarregado; sem criar diretório novo sem decisão funcional |
| Avaliações internas globais | SELECT direto bloqueado ao Encarregado |
| Férias/ausências globais e comentários | SELECT direto bloqueado; RPC mínima da própria equipa, sem comentário/anexo/justificação |
| Alocações legadas globais | Policy restritiva ALL, bloqueando SELECT/INSERT/UPDATE/DELETE diretos do Encarregado |
| RPC antiga do Quadro | Recusa Encarregado antes de locks/preview; restantes perfis mantêm caminho legado necessário na Fase A |
| Pesquisa de faturas por UUID/valor | Ambas as assinaturas verificam perfil ativo e autorização em cada obra devolvida |
| `fn_custo_real_ligado(uuid,uuid,uuid)` | Verifica utilizador ativo, empresa e acesso financeiro/obra antes do agregado |

A guarda direta também recusa identidades sem perfil ativo reconhecido. Os sete outros papéis definidos no catálogo permanecem permitidos pela guarda; as policies existentes continuam a limitar o acesso efetivo.

### Ausências — contrato e frontend

`fn_ausencias_equipa_encarregado(p_inicio date,p_fim date)` devolve somente `id,colaborador_id,data,tipo,estado`. `tipo` é `ferias` ou `ausencia`, sem revelar categoria clínica/justificativa. Intervalo válido até 93 dias. Exige perfil Encarregado ativo, obra atribuída da mesma empresa e colaborador ativo da equipa segundo `fn_colaborador_na_obra_atual_encarregado`, já usado pela Medicina.

Não introduz nova temporalidade nem o seletor do Pacote 2. Pessoas cuja última alocação já não pertence ao âmbito atual não entram nesta projeção. O Quadro v1 mantém a sua regra própria de datas exatas.

Os dois consumidores de Equipa usam a nova RPC apenas para Encarregado. Os restantes perfis continuam nos endpoints existentes. RPC ausente, recusada ou malformada produz erro; não há fallback para `ausencias`.

## Inventário de writers e P2

Das 247 funções: 219 SECURITY DEFINER; 138 writers SECURITY DEFINER no fecho conservador de chamadas. Destes, 20 são triggers, 22 são rotinas sem EXECUTE anon/authenticated e 96 são entradas executáveis por authenticated. Os corpos completos e a classificação por assinatura acompanham o candidato.

A revisão distingue chamada transitiva, overloads, SQL dinâmico e triggers. Um trigger não pode ser chamado como RPC comum. Helpers privados como `fn_mgo_inserir_json_compativel` e `fn_recalcular_planeamento_cascata` não tinham EXECUTE de cliente e não foram alterados. Wrappers de Medicina/RH delegam a autorização aos helpers internos. Writers de faturas, comparativos, custos, fornecedores e RNC usam guardas de papel/obra ou propriedade; as quatro entradas acima eram as exceções sem autorização encontradas.

Limite da evidência: o inventário não significa execução dinâmica de todos os ramos das 247 funções. Os testes dinâmicos concentram-se nas exposições e nos caminhos de regressão desta entrega; os restantes corpos/ACLs foram analisados estaticamente e ficam disponíveis para auditoria independente.

P2/decisões pendentes, sem correção automática:

- `fn_confirmar_compromisso_subempreitada(uuid)` tem EXECUTE PUBLIC, mas valida `fn_pode_editar_obra` antes de escrever. Não foi reproduzido bypass.
- `fn_verificar_limite_fatura_subempreitada` pode distinguir fatura inexistente de fatura sem subempreitada antes da autorização financeira delegada; não devolve valor nesse ramo. Endurecimento da informação de existência fica pendente.
- Taxonomias/associações de especialidades de fornecedores continuam no desenho existente. Não foi criado um diretório operacional novo; necessidade e campos dependem de decisão funcional.
- Alertas pessoais e agenda conservam as policies existentes. Algumas usam destinatário sem verificar atividade diretamente; esta entrega não redesenha revogação global de sessões/agenda.
- `search_path=public` permanece em rotinas legadas. O catálogo atual não dá CREATE no schema a anon/authenticated; não foi demonstrada escalada por esse caminho.
- Não se inventou nova regra para transferência, HE, disponibilidade futura ou Folha de Ponto.

## Matriz final de acesso do Encarregado

Resultado abaixo refere-se ao candidato local, com catálogo real e dados sintéticos. Produção ainda não recebeu estas correções.

| Recurso | REST direto | RPC/âmbito | Campos/escrita | Evidência |
|---|---|---|---|---|
| Obras | Obras atribuídas | Helpers existentes | Campos atuais; sem gestão global | SQL com own/other-company |
| Colaboradores | Bloqueado | Ponto/contexto/Medicina autorizados | Projeções operacionais; sem NIF/NISS/morada/custo/contrato | SQL + HTTP + sessão browser |
| Alocações | SELECT/DML bloqueados | Contexto/operar v1 no âmbito existente | Escrita só contrato v1; legado recusado | SQL + HTTP + cliente/browser |
| Ausências/férias | Bloqueado | Nova RPC, equipa atual autorizada | Cinco campos; leitura | SQL + HTTP + frontend mock |
| Medicina | Sem DML direto | RPC instalada por colaborador autorizado | Ocupacional; `can_write=false` | SQL + cliente/session browser |
| Documentos RH | Bloqueado | Sem nova RPC | Nenhuma abertura da ficha RH | SQL com linha positiva |
| Documentos obra | Desenhos/plantas da obra atribuída | Regras existentes | Leitura conforme policy | SQL own/other/financeiro |
| RNC | Própria obra | RPCs existentes + projeção operacional | Criação existente preservada; sem gestão técnica indevida | SQL de leitura + browser |
| Subempreitadas | Bloqueado | RPC operacional da obra autorizada | Quatro campos; leitura | SQL + HTTP + browser |
| Fornecedores | Registo bruto/aliases/mesclagens bloqueados | Nenhuma projeção nova | Sem condições/comercial/PII | SQL + HTTP; taxonomia pendente |
| Avaliações | Bloqueado | Nenhuma necessidade operacional atual identificada | Sem avaliação interna global | SQL + HTTP |
| Contratos | Sem linhas | Guardas existentes | Sem valores | SQL com linhas positivas + HTTP |
| Faturas/itens | Sem linhas | Pesquisa recusa; rastreio filtra | Sem valores/pagamentos/alterações | SQL + HTTP com UUID conhecido |
| Pagamentos | Sem linhas | Funções de pagamento recusam | Sem escrita | SQL/HTTP com linhas positivas |
| Financeiro | RLS/ACL existentes | Custo agregado protegido; quatro writers sem EXECUTE | Views financeiras sem SELECT authenticated | SQL/HTTP |
| Alertas | Apenas destinatário/âmbito das policies existentes | Sem mudança | Não foram gerados alertas reais | SQL com destinatários sintéticos |

## Scripts controlados

Os cinco ficheiros `supabase/encarregado_escopo_{precheck,backup,migration,postcheck,rollback}.sql` foram **consolidados**. Aplicam-se diretamente ao baseline real reconfirmado; não se deve aplicar primeiro a versão anterior do checkpoint.

1. **PRECHECK:** PostgreSQL major 17, executor postgres, fingerprint completo esperado. Divergência aborta.
2. **BACKUP:** schema privado `primeline_encarregado_20261004`, sem reutilização silenciosa; snapshot de catálogo/owners/ACLs/colunas/policies/views/corpos/search_path e ACL bruta das funções. Nenhuma linha operacional.
3. **MIGRATION:** transação, lock timeout, locks dos alvos, repete fingerprint e valida backup privado. Instala somente guardas, projeções e ACLs. Guarda catálogo instalado privado. Não modifica dados operacionais.
4. **POSTCHECK:** READ ONLY; compara catálogo instalado, preservação de tudo fora da lista autorizada, corpos dos quatro writers inalterados, privilégios, policies e consultas sob perfis reais ativos sem emitir PII. Não chama writers.
5. **ROLLBACK:** só se catálogo ainda igual ao instalado; restaura corpos e privilégios anteriores, remove objetos desta entrega sem CASCADE e verifica fingerprint original normalizado. Conserva backup privado. Não desfaz dados operacionais porque a migration não os altera.

Rollback de autorização reabre deliberadamente as exposições anteriores; necessita de decisão operacional, nunca execução automática. Repositório/frontend também deve ser considerado num eventual rollback de rollout. A nova RPC deve estar instalada antes da publicação do consumidor; sem ela o frontend falha fechado.

## Testes e reprodução

Ferramentas locais: PostgreSQL **17.6**, driver `pg`, PostgREST portátil oficial **16.4**, Playwright/Edge headless. PostgREST escuta somente `127.0.0.1`; JWT e dados são sintéticos. A versão do gateway local não é alegada como a versão exata do gateway Supabase.

Configurar `QUADRO_PG_BIN`, `QUADRO_TEST_DEPS`, `QUADRO_POSTGREST` e PATH com as DLLs PostgreSQL; para browser, `PLANNING_PLAYWRIGHT`.

```text
node --test tests/encarregado-escopo.test.mjs
node --test tests/session-boundary.test.mjs tests/session-isolation.test.mjs tests/foreman-scope.test.mjs tests/medicine-client.test.mjs tests/workforce-allocation-client.test.mjs
node tests/session-boundary-browser.mjs
node tests/encarregado-rnc-browser.mjs
node tests/workforce-controlled-browser.mjs
git diff --check
```

O harness reconstrói todas as funções, tipos de colunas, policies, ACLs e views; instala os triggers reais alcançados pelos UPDATEs P0. Não é um clone físico de produção: os dados são sintéticos e nem todos os defaults/FKs/constraints da aplicação são recriados. As reproduções P0 usam UPDATE de linhas existentes e os triggers correspondentes; não dependem de inventar valores NULL para contornar uma constraint real.

Cobertura: Gestão, Administrativo, Gerência, Diretor, Adjunto, Preparador, Financeiro, Encarregado da obra, Encarregado sem responsabilidade, inativo, outra empresa, anon e JWT authenticated sem perfil. IDs conhecidos, filtros manipulados, policy OR, grants de coluna, RLS, RPCs, wrappers financeiros, REST real local e rollback. Todas as tabelas operacionais sintéticas são comparadas antes/depois.

Frontend: sete cenários de troca de sessão; sete cenários RNC incluindo RPC ausente; Quadro controlado em três viewports, preview/confirmação, falha sem simular sucesso e ausência de DML direto. Tráfego externo interceptado nos testes browser. Console sem erros nos cenários executados.

Resultados finais desta ronda:

| Verificação | Resultado |
|---|---|
| PostgreSQL 17.6 + PostgREST 16.4 | 33 testes, 33 PASS, 0 falhas, 0 skips |
| Clientes, limites de sessão e projeções | 34 testes, 34 PASS |
| Trocas de sessão no browser | 7/7 PASS |
| RNC por perfil e RPC ausente | 7/7 PASS |
| Quadro browser | 3 grupos PASS; três viewports, console limpo e ausência de DML direto |
| Preservação de dados sintéticos | Todas as tabelas operacionais iguais antes/depois |
| Rollback | Catálogo normalizado e acessos anteriores restaurados |
| git diff --check, incluindo ficheiros novos | PASS |

Nenhuma regressão foi encontrada nos cenários executados. A suíte não substitui a auditoria independente nem a futura validação real autorizada.

## Gate

**GO LOCAL para auditoria independente** se a suíte indicada e `git diff --check` passarem no commit candidato. Nenhum GO de instalação/publicação decorre deste relatório. Não executar teste real do Encarregado, marcador, backup B ou Fase B. A instalação backend, publicação frontend e validação real continuam a exigir autorização específica.
