# Alteração controlada do responsável de Viaturas

Estado: backend aplicado e validado no Supabase. Frontend de alteração do responsável implementado localmente, ainda não publicado.

## Base confirmada no preflight de 30/09/2026

- `viaturas.colaborador_atribuido_id` aceita NULL e referencia `colaboradores.id`.
- Colaborador ativo: `data_saida IS NULL`. O vínculo ao login é `colaboradores.utilizador_id`;
  não é condição para atribuir uma viatura.
- `trg_atualizar_destinatario_alerta_viatura` já retargeta Seguro/Inspeção pendentes,
  mantendo Administrativo e limpando os destinatários individuais quando a atribuição é NULL.
  Não altera alertas resolvidos. A migration exige este trigger ativo e não o redefine.
- Auditoria de Viaturas instalada: `fn_registar_log_auditoria`. O padrão é reutilizado no histórico novo.
- O preflight encontrou 21 viaturas: 14 atribuídas a ativos no cadastro, 7 sem atribuição, 0 a inativos.
  Vitor Lopes continua com `data_saida = NULL`; nenhuma correção ou exceção por nome é introduzida.
- RLS/grants atuais permitem edição de Viaturas por Administrativo/Gerência/admins.
  Permanecem intactos para os restantes campos.

## Ficheiros

- `supabase/viaturas_atribuicao_controlada.sql`: migration transacional, sem backfill de responsáveis.
- `supabase/viaturas_atribuicao_controlada_rollback.sql`: rollback estrutural que recusa histórico utilizado.
- `tests/fixtures/viaturas-atribuicao-base.sql`: dados sintéticos e reprodução local do schema/trigger relevante.
- `tests/vehicle-assignment.test.mjs`: testes de PostgreSQL em memória.
- `tests/vehicle-assignment-concurrency.test.mjs`: PostgreSQL 17.6 nativo, duas ligações independentes.

## Schema

`viaturas.atribuicao_revisao integer NOT NULL DEFAULT 0`, com CHECK não negativo.

`viaturas_atribuicoes_historico`: id UUID, viatura, colaborador anterior/novo (NULL permitido),
revisão anterior/nova, autor, instante, request_id UUID e motivo opcional.
PK/FKs com proteção de eliminação, UNIQUE request_id e UNIQUE (viatura_id,revisao_nova).
Revisão nova obrigatoriamente anterior + 1; anterior e novo responsáveis devem diferir.
O índice único por viatura/revisão também serve a consulta ordenada do histórico.

Só SELECT para `authenticated`, sujeito à RLS administrativa. Sem INSERT/UPDATE/DELETE direto.
Trigger impede UPDATE/DELETE mesmo para o proprietário; INSERT exige contexto da RPC.
A auditoria genérica regista a inserção, além das alterações da viatura pelo trigger já instalado.

## Contrato RPC v1

`fn_alterar_responsavel_viatura(p_version integer, p_viatura_id uuid,
p_novo_colaborador_id uuid, p_revisao_esperada integer, p_request_id uuid,
p_motivo text DEFAULT NULL)`

- Todos obrigatórios salvo motivo; novo colaborador aceita explicitamente NULL.
- Versão exatamente 1; revisão não negativa; request UUID não nulo.
- Permissões: os mesmos helpers `fn_e_admin()` / `fn_e_administrativo()` já usados por Viaturas,
  com identidade obtida pelo servidor via `fn_utilizador_atual_id()`. O cliente não escolhe o autor.
- Não exige login ao novo colaborador; exige existência, mesma empresa e `data_saida IS NULL`.
- Um pedido novo sem mudança efetiva é recusado, sem histórico/revisão fictícios.
- Motivo: espaços exteriores removidos; vazio equivale a NULL.

Resposta confirmada:

```json
{
  "version": 1,
  "committed": true,
  "idempotent": false,
  "viatura_id": "UUID",
  "colaborador_anterior_id": "UUID ou null",
  "colaborador_novo_id": "UUID ou null",
  "atribuicao_revisao": 1,
  "historico_id": "UUID"
}
```

Erros: `VALIDATION_FAILED` (SQLSTATE 22023), `FORBIDDEN` / `PROTECTED_ASSIGNMENT` /
`PROTECTED_HISTORY` (42501), `STALE_REVISION` (40001), `IDEMPOTENCY_CONFLICT` (22023).
Os nomes de negócio vêm no texto do erro; não são códigos SQLSTATE de PostgREST.
Sem confirmação de sucesso, o futuro frontend não deve atualizar o estado nem repetir automaticamente.

## Concorrência e idempotência

1. Lock transacional por hash do request UUID (mesmo pedido serializado, inclusive entre viaturas).
2. Lock `FOR UPDATE` da viatura.
3. Procurar histórico do request **antes** de comparar a revisão corrente.
4. Replay compara viatura, novo colaborador, revisão esperada, motivo normalizado e autor.
   Mesmo pedido devolve exatamente o resultado original com `idempotent=true`, sem novas escritas,
   mesmo se já houve outras trocas ou o colaborador deixou de estar ativo.
5. Pedido novo compara revisão e valida o colaborador com `FOR SHARE`, evitando saída ou mudança
   de empresa concorrente durante a operação. O novo trigger de saída impede a inativação posterior
   enquanto houver qualquer viatura atribuída.
6. Atualizar apenas responsável/revisão; trigger legado retargeta alertas; inserir histórico.
   Qualquer falha reverte tudo, incluindo auditoria e alertas.

A revisão deteta A → B → A. Não usar ciclos de validade nem `criado_em` como revisão.
A resposta de replay é a confirmação histórica; não representa necessariamente a atribuição corrente.

## Proteção do caminho direto

Trigger `BEFORE UPDATE OF colaborador_atribuido_id, atribuicao_revisao` exige contexto local
`primeline.atribuicao_viatura_rpc` e `current_user` igual ao proprietário da RPC SECURITY DEFINER.
O trigger é SECURITY INVOKER intencionalmente: `set_config(...,'on',true)` por authenticated
não é suficiente. Revoga-se EXECUTE público das funções de proteção e da RPC, concedendo
EXECUTE da RPC apenas a authenticated. O contexto anterior é restaurado após a operação;
falhas revertem o contexto juntamente com a transação/subtransação.

A proteção aplica-se à alteração de atribuições existentes (UPDATE), incluindo escrever novamente
os mesmos campos. Não muda as regras atuais de criação/eliminação de viaturas. Proprietários da BD
com poderes de DDL continuam fora da fronteira de segurança da aplicação.
O antigo editor escondido de Equipa deixará de poder enviar PATCH destes campos; o novo frontend utiliza exclusivamente a RPC. Outros PATCHs que não incluam estes campos continuam sujeitos às regras atuais.

## Rollback

Adquire locks exclusivos antes de verificar uso. Só remove a estrutura quando o histórico está vazio
**e** todas as revisões estão a zero. Com uso, falha com `ROLLBACK_BLOCKED`; não apaga histórico nem
reverte responsáveis/alertas. Uma reversão operacional depois de uso exige plano específico.
Sem uso, remove apenas os objetos desta migration e restaura o caminho legado de UPDATE.
Não usa CASCADE e não redefine os triggers/funções legados. Scripts destinam-se a execução única;
reaplicação acidental da migration falha atomicamente, sem sobrescrever estruturas existentes.

## Testes locais

Usa PGlite (PostgreSQL em memória), sem URL, password ou endpoint Supabase. Configurar
`QUADRO_PGLITE` com o caminho local de `@electric-sql/pglite/dist/index.js` e executar:

```
node --test tests/vehicle-assignment.test.mjs
node --test tests/vehicles-module.test.mjs tests/vehicle-validity.test.mjs tests/vehicle-deadlines.test.mjs
node tests/vehicle-validity-browser.mjs
git diff --check
```

O teste de navegador usa dados sintéticos e bloqueia pedidos externos; configurar
`PLANNING_PLAYWRIGHT` se Playwright não estiver no node_modules do projeto.

Cobertura: regras de elegibilidade, desatribuição, histórico, revisão antiga/A→B→A, replay e
conflitos de pedido, permissões/RLS, spoofing do contexto, UPDATE de outros campos, constraints/FKs,
retarget de pendentes, preservação de resolvidos e do legado, falha atómica e rollback seguro.
A fixture testa as regras reais em PostgreSQL, mas não reproduz todo o schema de produção.
PGlite tem uma sessão; a concorrência é testada separadamente em PostgreSQL nativo 17.6,
com duas ligações e confirmação dos bloqueios através de `pg_blocking_pids`.

### Resultado desta preparação

- 32 resultados TAP funcionais/regressão aprovados, zero falhas.
- 9 resultados TAP no PostgreSQL 17.6 nativo aprovados, zero falhas/skip (8 cenários e agregador).
- Teste offline `vehicle-validity-browser.mjs`: PASS.
- `git diff --check`: sem erros. Ficheiros novos também verificados individualmente.
- Resultado da preparação original; posteriormente o backend foi aplicado e validado na BD real, com testes sintéticos revertidos integralmente.

## Proteção da saída de colaboradores

Incluída na mesma migration aplicada, para instalar atomicamente a RPC e a invariável.
`trg_impedir_saida_colaborador_com_viaturas` chama
`fn_impedir_saida_colaborador_com_viaturas()` antes de UPDATE de `data_saida`, exclusivamente
quando o valor anterior é NULL e o novo está preenchido.

Conta todas as viaturas atribuídas e recusa com `VEHICLE_ASSIGNMENT_PENDING` / SQLSTATE 23514,
incluindo a quantidade e a indicação de reatribuir ou deixar “Sem atribuição” pela RPC.
Não altera responsáveis, não gera transferências, não escreve histórico nem toca em alertas.
Sem viaturas, permite a saída. Alterações a outros campos e data preenchida → outra data
não são bloqueadas por esta regra. SECURITY DEFINER permite contar as viaturas independentemente
da RLS do autor; não dá permissões adicionais para editar colaboradores.

A RPC mantém `FOR SHARE` no colaborador até ao fim da transação. O UPDATE de saída obtém um
lock incompatível nessa linha antes do trigger. Em READ COMMITTED, o SELECT do trigger VOLATILE
vê o commit que libertou o lock: atribuição primeiro bloqueia a saída; saída primeiro bloqueia
posteriormente a atribuição. Nenhum lock de viatura é tomado pelo trigger de saída.

Snapshots fixos poderiam não ver uma atribuição recém-confirmada. Por isso a RPC e a transição
de saída exigem READ COMMITTED; REPEATABLE READ/SERIALIZABLE recebem SQLSTATE 40001 com instrução
para repetir em READ COMMITTED, em vez de aceitar uma decisão baseada num snapshot antigo.
A rejeição é técnica/repetível e não desatribui nada. Esta condição faz parte do contrato de instalação.
O rollback remove o novo trigger/função de saída e adquire também lock em colaboradores.

## Executar a concorrência nativa

Requer binários locais **PostgreSQL 17.6**, `pg` e Node. O teste valida `postgres --version` e
`server_version_num = 170006`, cria diretório temporário e cluster novos, com porta aleatória,
escuta só em `127.0.0.1`, e para o cluster no final. Não instala serviço Windows e não aceita URL
ou host externos. Artefactos temporários ficam disponíveis para diagnóstico.

Neste computador, dependências de teste em `%TEMP%\primeline-viaturas-test`:
`@embedded-postgres/windows-x64@17.6.0-beta.15` (binário PostgreSQL 17.6) e `pg`.

```bat
set VIATURAS_PG_BIN=%TEMP%\primeline-viaturas-test\node_modules\@embedded-postgres\windows-x64\native\bin
set VIATURAS_PG_MODULE=%TEMP%\primeline-viaturas-test\node_modules\pg
node --test tests/vehicle-assignment-concurrency.test.mjs
```

Cenários reais: mesma revisão; mesmo request com payload igual/diferente; atribuição antes da saída;
saída antes da atribuição; PATCH direto/spoofing/RPC legítima/outro campo; contagem de várias viaturas,
saída após desatribuição; recusa segura de snapshots fixos. Os cenários concorrentes esperam o lock
comprovado antes de confirmar a primeira transação, sem depender apenas de pausas temporizadas.

## Vitor — procedimento posterior, sem correção nesta etapa

O preflight confirmou Vitor Lopes com `data_saida = NULL`; a BD ainda o considera ativo.
Depois de disponibilizar o fluxo:
1. Reatribuir/desatribuir o FIAT FIORINO `79-VO-20`, n.º 5, pela RPC de Viaturas.
2. Só depois corrigir a saída de Vitor no cadastro, quando a data correta estiver confirmada.

Nenhum dado de Vitor foi alterado nem foi criada uma exceção pelo nome.

## Frontend local

A ficha resolve responsáveis por UUID, incluindo inativos. Novos destinos são ativos da mesma empresa. A capacidade de gestão existente controla o botão. O modal envia revisão e UUID por intenção; mantém o UUID numa repetição incerta e nunca repete automaticamente. STALE_REVISION/40001 recarrega o responsável e exige nova confirmação. Após confirmação, recarrega viatura e histórico somente leitura. Nenhum dado real foi alterado durante a implementação frontend.
