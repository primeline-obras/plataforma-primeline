# Pacote 1 — correção dos alertas e pré-varredura local

Data: 02/10/2026. Branch: `feat/quadro-controlado-20261001`.

## Decisão

**GO LOCAL para uma nova auditoria independente. Sem GO para produção ou SQL real.**

O P1 de colisão de alertas foi corrigido e reproduzido com o índice capturado no levantamento anterior, em PostgreSQL 17.6 local. Não foram confirmados novos P0/P1 na revisão local descrita abaixo. As questões P2 e as limitações continuam explícitas; testes de caracterização de um comportamento P2 não significam que esse comportamento foi aprovado.

Base da correção: `b681d76cf6b32306e4f3302696de122b2e7a0cfc`. Auditoria anterior preservada: `audit/quadro-controlado-pacote1-critica3-20261001`, `610e2e6f10313ab9e724b0fdc5c6e6d2b1050776`.

**SHA da entrega:** consultar `git log -1 --format=%H` nesta branch. A cópia local final deste relatório, emitida após commit/push, contém os SHAs local/remoto exatos. Não é possível incluir o SHA de um commit no próprio conteúdo que determina esse SHA.

Só foram usados ficheiros/Git, clusters locais descartáveis e browsers offline com APIs simuladas. Não houve consulta ao Supabase, Chrome autenticado, produção ou Cloudflare. O índice e as definições anteriores têm origem em capturas já existentes; não são confirmação do estado atual da produção.

## Correção exata do P1

Alterados exclusivamente os dois emissores de notificações nas definições completas de A e forward-fix A:

- `fn_quadro_notificar_controlado_v1(uuid,date,uuid,uuid,uuid)`;
- `fn_quadro_notificar_movimentacao_encarregado()`.

Ambos passam a preencher `alertas.ocorrencia_chave`. Não foi alterado o índice global, schema de alertas, destinatários, condições de notificação, núcleo de alocação, RPC pública, frontend, RH ou Ponto. As assinaturas das funções continuam iguais. Uma comparação textual com b681d76, removendo apenas os corpos destes dois notificadores, confirmou que todo o restante SQL de A/forward-fix A permanece idêntico. Os dois corpos corrigidos também são idênticos entre A e forward-fix A.

A fixture de metadata instala nos testes o índice real capturado:

```sql
CREATE UNIQUE INDEX alertas_ocorrencia_unica_idx ON public.alertas USING btree
(tipo, entidade_tipo, entidade_id, data_evento_referencia,
 COALESCE(antecedencia_dias, '-1'::integer),
 COALESCE(ocorrencia_chave, '00000000-0000-0000-0000-000000000000'::uuid));
```

### Chave controlada

```sql
md5(jsonb_build_array(
 'quadro_movimento_alerta_v1',
 v_atual.empresa_id, v_request,
 p_colaborador, p_data, p_origem, p_destino, destinatario.id
)::text)::uuid
```

O request vem da permissão privada da transação, pessoa, data e autor, criada pelo núcleo. Se faltar, a emissão recusa com `CONTROLLED_NOTIFICATION_REQUIRED`; não fabrica uma identidade. O agrupamento já existente emite uma ocorrência por par origem/destino e destinatário. Num merge, o mesmo Administrativo pode receber dois pares distintos, com chaves diferentes.

A chave não depende do UUID aleatório da alocação ou do alerta: se uma falha reverter a criação e o pedido for confirmado novamente, a identidade do evento e do destinatário permanece igual. O teste de falha tardia captura as chaves tentadas via NOTICE, reverte a operação e compara as chaves do retry. Não usa ON CONFLICT DO NOTHING para suprimir destinatários.

Mesmo pedido/pessoa/data/par/destinatário produz a mesma chave; destinatário, par ou request diferente produz uma ocorrência distinta nos cenários testados. O ledger privado continua a impedir novas escritas no replay. MD5 serve para derivar UUID de ocorrência, não para autenticação ou assinatura de segurança.

### Compatibilidade legada da Fase A

A API antiga não transporta request UUID. O trigger usa a revisão seguinte da pessoa/dia:

```sql
md5(jsonb_build_array(
 'quadro_movimento_legado_v1',
 v_atual.empresa_id, NEW.colaborador_id, NEW.data,
 v_revisao_evento, v_origem_id, v_destino_id, destinatario.id
)::text)::uuid
```

`v_revisao_evento` = revisão atual + 1. O trigger de notificação roda antes de `trg_quadro_pessoal_movimentos`, que incrementa essa revisão; os nomes/ordem dos triggers capturados e usados no teste preservam isso. O lock global serializa os escritores compatíveis. A→B→A gera eventos diferentes. Rollback reverte também a revisão, preservando a identidade no novo ensaio do mesmo evento.

A API legada autorizada para Encarregado é `minha_obra`; `adicionar` continua reservado aos gestores conforme o contrato anterior. O teste não amplia a autorização antiga.

## Testes específicos de destinatários

`tests/workforce-alerts.test.mjs`: **28 testes aprovados**, zero falhas/skips, PostgreSQL 17.6, A e B, índice real capturado instalado.

| Caso | Resultado local |
| --- | --- |
| Um destinatário | Uma ocorrência; eventos sucessivos têm chaves diferentes |
| Administrativo + Diretor | Duas linhas/chaves, sem 23505 |
| Dois Administrativos | Ambos recebem, sem colisão |
| Vários Diretores / Encarregado origem | Destinatários únicos; prioridade origem preservada |
| Autor também responsável | Autor excluído |
| Zero elegíveis | Gravação funciona sem alertas |
| ADM/Gestão | Nenhum alerta de movimentação por estes autores |
| Adicionar/mover A→B→A | Ocorrências distintas; sem alterar identidade persistente da alocação |
| Split / merge | Pares corretos, inclusive dois pares para o mesmo ADM |
| Remover / escritório / renomear | Sem novos alertas; avisos anteriores preservados |
| Preview | Zero alertas/escritas persistentes |
| Replay | Resultado idempotente; snapshot de todas as tabelas permanece igual |
| Falha depois de alertas/histórico/revisão | Rollback de alocações, revisões, histórico, alertas, operações, auditoria e permit |
| Retry depois dessa falha | Mesmas chaves; pedido não consumido |
| Duas ligações de Encarregado, mesmo pedido | Uma confirmação, segunda idempotente; dois alertas e um movimento |
| RPC antiga / A | Vários destinatários e movimentos sucessivos funcionam |

Os constraints capturados permitem vários responsáveis distintos da mesma obra/papel. A fixture constrói esses cenários deliberadamente; não inventa um limite de destinatários nem altera os filtros reais.

## Regressão completa executada nesta entrega

**347 testes aprovados, zero falhas, um skip conhecido**, em 348 testes contabilizados pelo runner. O skip é o caso opcional de Excel externo de 47 linhas sem `RH_XLSX`. Não foi contado como aprovado. Inclui os 28 testes de alertas e 29 de pré-varredura adicional; não somar novamente os ensaios isolados.

Áreas: Quadro, cliente de alocação, Cadastro/Importação RH, conformidade/ciclo de vida dos colaboradores, permissões/tenant, Ponto legado, Férias, Medicina, atribuição e validades de Viaturas, wrapper de colaboradores, Planeamento/importação/lote/pesos/safeupdate.

**Oito browsers offline passaram:**

1. Quadro controlado: datas explícitas, scopes, falhas, desktop/tablet/mobile, console.
2. RH frontend: 49 combinações de permissões, histórico/identidades, console.
3. Cadastro RH original: campos, guardar único, Excel sintético, preview/confirmação/reimportação, desktop/mobile.
4. **Medicina original:** consumidor e teste originais, consulta/correção/anulação/replay/roles, três viewports, console.
5. Planeamento: dependências/arquivo/pesos/preview/falhas.
6. Seleção do Planeamento: refresh/ID inválido/prioridade de workId.
7. Atribuição de Viaturas: identidades/ativos/RPC/concorrência/permissões/histórico.
8. Validades de Viaturas: 1/2 anos/Outra, correção, histórico protegido/caminho antigo.

O browser de Cadastro RH foi executado com bootstrap temporário de caminhos Windows/Edge, já existente, e `RH_TEST_DEPS`. A primeira tentativa sem essa variável recusou iniciar; foi repetida com a configuração correta e passou. Nenhum código de RH/Medicina foi alterado para fazer a regressão passar.

Execução reproduzível dos testes Node:

```powershell
$regFiles = Get-ChildItem tests -Filter '*.test.mjs' |
 Where-Object { $_.Name -match '^(workforce-|foreman-global-workforce|rh-cadastro|collaborator-|active-collaborators|adjunto-access|access-control|medicina-trabalho|medicine-client|vehicle-|vehicles-module|supabase-collaborators|planning-)' } |
 ForEach-Object { 'tests/' + $_.Name }
node --test @regFiles
```

Usados os runtimes PostgreSQL 17.6/pg/PGlite locais previamente instalados, sem instalar dependências nem usar serviços externos. As variáveis `QUADRO_PG_BIN`, `QUADRO_TEST_DEPS`, `QUADRO_PGLITE`, `RH_TEST_DEPS`, `VIATURAS_PG_BIN`, `VIATURAS_PG_MODULE`, `MEDICINA_PG_BIN`, `MEDICINA_TEST_DEPS` e `PLANNING_PLAYWRIGHT` apontam para esses runtimes. Logs e screenshots locais ficam em `%TEMP%`; não contêm dados reais.

`git diff --check`: aprovado.

## Rollout e gate privado

| Combinação | Prova local |
| --- | --- |
| Antigo / antigo | INSERT autorizado funciona |
| Antigo / A | INSERT/PATCH/DELETE e RPC antiga funcionam; Encarregado/minha_obra com índice funciona |
| Novo / A | Preview, confirmação, revisão e alertas funcionam |
| Novo / B | Mesmo contrato, operações e RH funcionam com DML fechado |
| Antigo / B | Escrita recusada; nenhuma corrupção/fallback direto |

O gate foi reexecutado integralmente no teste PostgreSQL: PUBLIC/anon/authenticated/service_role não podem ler/escrever o controlo privado nem executar os helpers/marcação. GUC e payload não substituem prova. Marcador ausente, contrato/release/instalação/fingerprint/data incoerentes, helper/ACL adulterados ou marcador duplicado recusam B. Falha depois do consumo reverte consumo e DDL juntos. Rollback B invalida o marcador e exige nova marcação operacional antes de forward-fix B.

O fingerprint é recalculado pela instalação A após a definição dos notificadores corrigidos. Não foram relaxados checks nem alteradas versões públicas do contrato para contornar o gate. A prova privada autoriza uma tentativa; não prova que todos os separadores reais já estão atualizados.

## Pré-varredura estrutural completa local

Além da leitura do SQL/frontend/documentação, `tests/workforce-preflight-local.test.mjs` executa **29 testes adicionais**, A e B, PostgreSQL 17.6 com duas ligações. Testes de caracterização P2 estão identificados pelo nome.

| Área | Verificado / limite |
| --- | --- |
| Writers | Scan de todo `supabase/*.sql`, frontend `src/*.js`, funções capturadas e escritores instalados localmente; inventário abaixo |
| SECURITY DEFINER | Owner/search_path/ACL nos postchecks; helpers privados recusados; CREATE público negado à aplicação na fixture |
| Tenant | Pessoas/obras/request de outra empresa recusados; destinatário de outra empresa excluído |
| Grants/RLS | B fecha tabela/coluna DML e RPC antiga; SELECT scoped; tabelas privadas sem policies/grants públicos |
| Origem/destino | Encarregado não retira origem alheia; só obras próprias, sem escritório/global override |
| Gerência | Leitura/RH mantidos; escrita global nova do Quadro recusada |
| Diretor/Adjunto/Preparador | Não obtêm escrita com payload/GUC; leitura de Diretor/Adjunto permanece scoped |
| Períodos | Manhã/tarde distintas; split/merge; conflito legado não corrigido automaticamente |
| Disponibilidade | Antes da admissão/inativo/ausente recusados ao alocar; remoção explícita permitida |
| Estado vazio | Última manhã/tarde/dia inteiro → vazio → reload → nova revisão; concorrência detetada |
| Revisão/idempotência | A→B→A, mesmo request, payload divergente, request de outro autor/empresa; uma confirmação simultânea |
| Lock global | Escritas v1/legadas usam a mesma serialização; preview legado espera operação v1; B deteta revisão alterada |
| Cadastro RH | Núcleo comum, data explícita, sem alocação, atomicidade em falha posterior e empresa/ausência divergentes |
| Importação RH | Contrato atual exige pessoas já cadastradas; lote mantém alocações, falha reverte integralmente |
| Ponto legado | Definições antigas comparadas ao backup; herança atual preservada e explicitamente pendente |
| Notificações | Índice real capturado, recipients, chaves, rollback tardio e replay em duas sessões |
| Backup A/B | Scripts integrais usados no PG local; cópias/grants/definições/controlo; falha sem backup recusada |
| Postchecks A/B | Executados; grant/helper exposto/policy permissiva recusados; owner/ACL e consumidores comparados |
| Rollback A/B | Preservam dados/histórico; B restaura A; A fecha v1 e restaura funções anteriores |
| Forward-fix A/B | Reexecutados; dados preservados, revisões/gate invalidados/revalidados conforme fase |
| Gate privado | Ataques/consumo/rollback descritos acima; nenhuma dependência de GUC |

Não foi feita uma análise formal de todos os schedules possíveis. Os helpers periféricos não exercitados da fixture continuam identificados como stubs; há testes próprios de Medicina/Viaturas/RH, mas isso não equivale a restaurar toda a BD real num único cluster.

### Inventário dos escritores

Definições anteriores capturadas com DML direto:

- `fn_quadro_operar(text,jsonb,boolean,text)`;
- `fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid)`;
- `fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid,text,numeric,text,text,text,text)`.

Cadeia RH: `fn_rh_guardar` / `fn_rh_importar` → `fn_rh_guardar_interno` → wrappers de criação → construtor/núcleo controlado. Não há segunda implementação de regras de alocação no RH. Criação sem alocação continua possível; criação com alocação é atómica e só usa a data explícita. Importação existente não cria pessoas novas.

| Escritor / definição fonte | Situação |
| --- | --- |
| Frontend atual `workforce-allocation.js` | Apenas `rpc/fn_quadro_operar_v1`; nenhum DML direto |
| Frontend antigo | Compatibilidade deliberada em A; DML revogado em B |
| `fn_quadro_aplicar_interno` em A/forward-fix A | Único escritor direto funcional em B; privado, controlado, usado por Quadro e RH |
| RPC antiga em A/forward-fix A | Compatibilidade/lock/revisão; substituída por recusa em B |
| Dois wrappers de criação RH | Adaptados ao construtor privado/núcleo, mantendo assinatura/ACL anteriores |
| `colaboradores_crud_alocacao_inicial.sql`, `colaboradores_campos_completos.sql` | Definições históricas anteriores; não reaplicar sobre o candidato |
| `quadro_pessoal_alocacao_diaria.sql` | Backfill histórico; não aplicar novamente |
| SQL dinâmico dos scripts de backup/rollback/grants | Metadados/DDL/restauro estrutural; não opera alocações reais para simular rollback |
| `fn_mgo_inserir_json_compativel(regclass,jsonb)` identificado no levantamento anterior | Helper genérico privado; nenhuma chamada legítima de Quadro encontrada no repo; em B o guard não aceita escrita sem permit do núcleo |

O inventário das funções localmente instaladas é exercitado pelos pre/postchecks. Os scans de texto não conseguem provar ausência de SQL dinâmico arbitrário futuro. A nova leitura do catálogo real e dependências dinâmicas permanece obrigatória antes de aplicar/revogar permissões reais.

## Novos P0/P1

- **P0 novo confirmado:** nenhum nesta pré-varredura local.
- **P1 novo confirmado:** nenhum nesta pré-varredura local.
- **P1 anterior:** corrigido no candidato, com prova local A/B e caminho legado A.

Não declarar inexistência universal de falhas, nem aprovação de instalação/produção. A auditoria independente continua obrigatória.

## P2/P3 e riscos preservados

### P2-L01 — replay depois de perda de papel/âmbito

Confirmado localmente em A/B: Encarregado confirma um pedido; passa a Preparador e perde responsabilidades; contexto atual recusa leitura, mas repetir exatamente o pedido e token originais devolve o receipt antigo como idempotente. A RPC verifica utilizador ativo/empresa/autor/payload antes do ledger, mas a autorização atual de obra/papel vem depois do retorno do replay.

Limite do impacto: apenas o próprio utilizador ativo, na mesma empresa, com request/payload/token originais; não há nova escrita, acesso a pedidos de outros autores nem atravessamento de tenant. O snapshot contém IDs/dia/período/destino da operação que o autor já executou. Classificado P2 para definir política de recibos versus revogação de acesso; auditoria independente deve confirmar a severidade. Não corrigido neste escopo.

### P2-L02 — alertas anteriores após remoção

Confirmado A/B: remover a última alocação deixa os dois avisos anteriores intactos, com `entidade_id` já sem linha atual. Histórico e auditoria continuam consultáveis. Essa preservação já existia e foi requerida pela correção; não apagar/resolver retroativamente em silêncio. Falta decidir UX/resolução/navegação desses alertas. Não foi introduzida FK nova nem limpeza automática.

### Outros P2 já conhecidos / limites operacionais

- Ausência introduzida depois de uma alocação: o Quadro verifica ausência durante a operação; não adiciona uma invariável inversa global ao escritor de ausências. Rever num pacote separado. Esta sessão não certifica todos os triggers de ausências da BD atual.
- Cadastro novo de RH não ganhou idempotência geral de criação de pessoa; preservou o contrato atual. Retry de uma criação após perda de resposta merece desenho próprio.
- Situação de obra encerrada e datas/períodos/intenções de UX mantêm as regras atuais; não foi inventada nova proibição de destino.
- Ponto continua com herança temporal legada. O Quadro usa data exata e não propaga alocação; isso não torna o Ponto temporalmente corrigido.
- Rollback A restaura o notifier anterior: se o índice real continuar igual ao capturado, a colisão antiga pode reaparecer no caminho legado. É uma limitação explícita de retorno ao estado anterior, não uma correção silenciosa fora do escopo. Forward-fix A reinstala a correção.
- Depois de forward-fix A, o backup B anterior pertence a outra instalação e deve ser arquivado/recriado conforme documentação. O script de backup com nomes fixos não faz rotação automática. B recusa backup antigo; nunca apagar backup para forçar instalação.
- Lock global conservador serializa todo o Quadro; medir contensão/tempo em ambiente autorizado. Os testes locais demonstram espera e serialização, não carga real.
- A chave legada depende da ordem dos triggers/revisão. Novos triggers/DDL que alterem essa ordem devem ser rejeitados/revistos; o fingerprint captura os triggers conhecidos.

P3: duplicação das definições completas A/forward-fix exige revisão conjunta. Nesta entrega ambas receberam exatamente a mesma correção; não foi refatorado o SQL de instalação para reduzir essa duplicação.

## VALIDAÇÃO REAL PENDENTE

1. Nova varredura independente do SHA entregue, inclusive severidade dos P2 e política de receipts.
2. Reconfirmar schema/índice de alertas, owners/ACL/RLS/schema CREATE, triggers/ordem e todos os escritores/funções dinâmicas **atualmente** instalados.
3. Repetir prechecks contra a fotografia atual autorizada: alocações/movimentos/conflitos/ausências/RH/Ponto. Não reutilizar contagens antigas como se fossem atuais.
4. Backup privado real e exportação externa verificável; validar a estratégia de rotação se já houver backups do mesmo nome.
5. Autorizações separadas para A, validação operacional do frontend e B. Nenhum script real foi executado nesta entrega.
6. Validar no browser autenticado recipients/alertas/visibilidade/RLS/UX de Encarregado e roles em desktop/tablet/mobile. Os browsers desta sessão são offline.
7. Confirmar atualização efetiva dos clientes antes de o owner marcar a prova privada de B; medir locks/contensão e plano de rollback.
8. Excel externo opcional `RH_XLSX`, se se pretender certificar aquele ficheiro específico.

## Entrega e estado da branch

Ficheiros da correção/entrega:

- `supabase/quadro_controlado_fase_a.sql`;
- `supabase/quadro_controlado_fase_a_forward_fix.sql`;
- `tests/workforce-controlled.test.mjs`;
- `tests/workforce-alerts.test.mjs`;
- `tests/workforce-preflight-local.test.mjs`;
- `tests/fixtures/quadro-alertas-indice-real.json`;
- `docs/quadro-controlado-pacote1-20261001.md`;
- este relatório.

Commit/push exclusivamente do candidato, sem main/merge/deploy/SQL real. Os SHAs e o working tree final são registados na cópia local pós-commit e na resposta de entrega. A branch de auditoria anterior permanece preservada. Logs locais e clusters sintéticos não são versionados.