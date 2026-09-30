# Medicina do Trabalho — backend controlado

Estado: backend do commit `ba7f6d8d20dbe614dd9ceb881d16ef7d4c0a86b7`
aplicado em produção em 30/09/2026, com pós-check aprovado: 35 consultas,
IDs/valores legados e alertas preservados. **Não reaplicar os scripts.**

## Integração na ficha do colaborador

A branch de frontend parte de `5e02e5fd50adeec827efb84f5a267cdc5f8e889e`
e inclui os três commits autorizados do backend por cherry-pick. Os ficheiros
SQL mantêm exatamente o conteúdo do commit instalado; nenhum SQL foi executado
durante o desenvolvimento desta integração.

- Equipa → Colaboradores → Editar inclui Medicina após o formulário de cadastro.
  As operações médicas têm formulário próprio e não submetem o cadastro/contrato.
- A ficha e o painel global usam `fn_medicina_consultar_colaborador`. O campo
  `atual` é escolhido pelo backend; consultas futuras/anuladas não o substituem
  no frontend. O painel consulta até quatro pessoas em paralelo.
- Administrativo, Gerência e Gestão só recebem ações quando a RPC confirma
  `can_write=true`. Encarregado consulta apenas o resultado permitido pela RPC,
  sem acesso adicional a cadastro, documentos ou histórico privado.
- Nova consulta, correção e anulação usam exclusivamente as respetivas RPCs.
  Cada operação recebe um UUID; repetir uma resposta incerta conserva o mesmo
  payload/UUID e bloqueia a edição dos campos. Conflito recarrega os dados, sem
  repetir automaticamente a escrita.
- Inativos têm acesso à ficha sem reativação. Anulados permanecem visíveis.
- Documentos são lidos de `documentos`, filtrados pelo colaborador; fichas do
  tipo `ficha_aptidao` são destacadas. Downloads usam o acesso privado existente.
  Não foi criada relação consulta/documento nem novos campos clínicos.
- O estado visual mantém a janela existente de 30 dias para «a vencer».
  A RPC não devolve o parâmetro configurável de antecedência dos alertas; uma
  alteração desse parâmetro pode divergir do estado visual. A data corrente
  usada pelo browser é a de Europe/Lisbon; a BD continua a validar as datas.
- RPC ausente, permissão recusada ou erro de leitura são mostrados como
  indisponibilidade; não são convertidos em ausência de consulta ou sucesso.

### Validação do frontend

`node --test tests/medicine-client.test.mjs` e
`node tests/medicine-browser.mjs` (Playwright via `PLANNING_PLAYWRIGHT`).
O browser executa a aplicação real num servidor local com API simulada, incluindo
resposta perdida/replay, revisão obsoleta, histórico, anulação, inativos,
permissões e screenshots desktop/tablet/mobile. Não executa SQL nem usa sessão
de produção. `tests/rh-frontend-browser.mjs` verifica as regressões RH anteriores.

As secções abaixo registam a preparação e os testes anteriores do backend.

## Retoma e revisão

Retomado de `origin/feat/medicina-trabalho-controlada-20260930`, checkpoint
`255b44b309a2d55f7f0b8007e620dec925cc8e57`, num checkout inicialmente limpo.
Os outros worktrees e branches locais foram preservados. Não houve alterações
em main, frontend, Storage ou dados reais.

Os oito ficheiros do checkpoint foram revistos, incluindo as seis definições
instaladas guardadas em `tests/fixtures/medicina-funcoes-instaladas.json`.
Esse JSON permanece intacto: contém definições SQL, não dados de colaboradores.
O pedido explícito de concluir este backend prevalece sobre a orientação
genérica de `instrucoes.txt` para não gerar SQL.

O checkpoint já tinha RPCs, histórico, proteção de escrita, reconciliação,
compatibilidade com admissão e testes de idempotência/revisão. A execução inicial
passou 24 de 25 testes; a comparação textual falhou em Windows por CRLF.

Correções concluídas:

- Normalização dos fins de linha na leitura dos testes, mantendo os hashes SQL.
- Revalidação de empresa/permissão após obter o lock da pessoa, inclusive no replay.
- Leitura do histórico pela RPC respeita a empresa da operação, como a sua RLS.
- Verificação da empresa nas duas assinaturas de ciclo de vida.
- Lock da pessoa também na admissão compatível com o cadastro antigo.
- Reativação gera outra ocorrência de alerta, preservando os resolvidos; suporta
  saídas/reativações repetidas sem nova consulta.
- Snapshots privados com RLS e sem acesso de clientes/service_role.
- Revogação de escrita direta/TRUNCATE de service_role nos objetos protegidos.
- Locks de instalação, backup e rollback; timeout explícito para não esperar
  indefinidamente por atividade operacional.
- Backup obrigatório e igualdade integral de consultas/alertas antes de instalar.
- Rollback restaura policies e grants efetivamente capturados, incluindo service_role;
  recusa perder operações, autoria, revisões ou alertas alterados.
- Índices para selecionar consulta corrente, operações e histórico por colaborador.
- Testes adicionais de atomicidade, inativação, reativação, empresa, backup e concorrência.

## Contrato das RPCs

Todas recebem `p_version=1`. Identidade/autoria vem de `fn_utilizador_atual_id()`.
Administrativo, Gerência e Gestão da Plataforma ativos podem gerir pessoas da
própria empresa. Encarregado tem apenas leitura da pessoa da sua obra atual.

| RPC | Parâmetros, pela ordem da assinatura |
|---|---|
| `fn_medicina_registar_consulta` | `p_version integer, p_colaborador_id uuid, p_data_consulta date, p_resultado text, p_proxima_consulta date, p_request_id uuid` |
| `fn_medicina_corrigir_consulta` | `p_version integer, p_consulta_id uuid, p_data_consulta date, p_resultado text, p_proxima_consulta date, p_revisao_esperada integer, p_request_id uuid, p_motivo text` |
| `fn_medicina_anular_consulta` | `p_version integer, p_consulta_id uuid, p_revisao_esperada integer, p_request_id uuid, p_motivo text` |
| `fn_medicina_consultar_colaborador` | `p_version integer, p_colaborador_id uuid` |

Escrita devolve `{version:1, committed:true, idempotent:false, consulta, historico_id}`.
Repetição exata devolve a resposta guardada com `idempotent:true`. Em chamadas
diretas SQL dentro de uma transação maior, o COMMIT externo continua obrigatório;
uma resposta não autoriza ignorar falha/rollback posterior.

Leitura de RH devolve `{version:1, can_write:true, atual, consultas, historico}`.
Encarregado recebe `{version:1, can_write:false, atual}` sem autoria/histórico.
`atual` pode ser null. A leitura direta legada mantém apenas as seis colunas
existentes; novos consumidores devem usar a RPC para obter a consulta corrente.

Erros: `PERMISSION_DENIED`/42501, `VALIDATION_FAILED`/22023 ou CHECK,
`IDEMPOTENCY_CONFLICT`/22023, `STALE_REVISION`/40001 e proteção de histórico/42501.
Após erro de serialização/deadlock, anular a transação completa e repetir com
o mesmo request_id em READ COMMITTED. Revisão obsoleta exige recarregar os dados.

## Histórico, validade e compatibilidade

- Nova consulta cria nova linha; correção incrementa revisão e guarda motivo,
  antes/depois e autor. Anulação preserva a linha e impede novas correções.
- Os 35 registos legados mantêm valores/IDs. Autoria/request anteriores ficam NULL,
  revisão começa em zero; não se atribui autoria fictícia.
- Consulta corrente: não anulada, data realizada não futura e intervalo coerente;
  ordenação por data da consulta, criado_em e UUID, todos descendentes.
- Data futura antiga continua no histórico e não satisfaz primeira consulta.
  Nova consulta futura é recusada. Resultado continua texto livre existente;
  não se acrescentam campos clínicos.
- O registo de consulta histórica para pessoa inativa continua possível para RH;
  não gera alertas pendentes enquanto a pessoa estiver inativa.
- `fn_rh_guardar` e o seu corpo interno não são reescritos. O INSERT inicial da
  admissão mantém compatibilidade através de triggers, com autoria e histórico.
- `fn_verificar_primeiras_consultas_medicina` e o ramo médico de
  `fn_verificar_alertas_vencimento` usam a reconciliação. Ramos não médicos
  permanecem iguais ao snapshot; `fn_executar_rotinas_diarias` não é alterada.
- As duas funções de ciclo de vida resolvem alertas médicos, sem os apagar;
  mantêm o tratamento não médico anterior e passam a verificar a empresa.
- Rotina diária não reabre nem duplica um alerta resolvido manualmente.

## Concorrência e segurança

Request_id é serializado por advisory lock transacional; operações da pessoa
são serializadas por `FOR UPDATE` no colaborador, seguido do lock da consulta.
A autorização é repetida depois da espera. A revisão esperada evita correções
perdidas. Reconciliação usa o mesmo lock da pessoa. Escrita e reconciliação
exigem READ COMMITTED para não trabalhar com um snapshot antigo após a espera.

GUC de fluxo não é uma credencial: o trigger também exige o proprietário da
função controlada. Clientes não recebem DML nem EXECUTE dos helpers internos.
Proprietário/superutilizador capaz de alterar DDL continua autoridade de confiança.
O executor da migration deve ser o proprietário do cadastro RH existente.

## Scripts completos e ordem futura

1. `supabase/medicina_trabalho_precheck.sql`: somente leitura. Rever contagem 35,
   datas, funções/hashes, policies, grants, triggers e índice de ocorrências de alertas.
2. `supabase/medicina_trabalho_backup.sql`: após autorização, copia consultas,
   alertas, definições/ACL de funções, policies e estrutura para schema privado.
   Os nomes existentes provocam erro; nunca sobrescrever um backup anterior.
   Exportar também para arquivo privado externo, fora do Git.
3. `supabase/medicina_trabalho_controlada.sql`: transação única. Locks com timeout,
   verificação das seis definições instaladas, RLS, policies, ausência de grants
   por coluna e igualdade com o backup. Qualquer divergência exige novo preflight.
4. `supabase/medicina_trabalho_postcheck.sql`: somente leitura, antes de operar.
   Confirma mesmas 35 linhas/alertas, metadados neutros, históricos vazios,
   RLS, privilégios e triggers. Sem chamar rotinas que criem alertas para testar.
5. `supabase/medicina_trabalho_controlada_rollback.sql`: só antes de existirem
   operações ou alterações posteriores. Obtém locks, verifica os snapshots,
   restaura funções/policies/grants e remove apenas a camada nova, sem CASCADE.
   Preserva as tabelas do backup privado. Com utilização real, exige recuperação
   específica e nunca apaga histórico para conseguir executar o rollback.

Backup e DDL foram executados apenas em fixtures locais. Nada foi aplicado à BD real.

## Testes e reprodução

PostgreSQL 17.6 portátil local, cliente `pg@8.16.3`, host fixo 127.0.0.1 e porta
livre. Cada execução cria cluster novo na pasta temporária e encerra-o no final.

```powershell
$env:MEDICINA_PG_BIN = '<pasta dos binários PostgreSQL 17.6>'
$env:MEDICINA_TEST_DEPS = '<pasta node_modules que contém pg>'
node --test tests/medicina-trabalho.test.mjs
```

Resultado final: **37 testes aprovados, zero falhas e zero omissões** (inclui
agregador e teste estático). Cobertura inclui scripts de precheck/backup/migration/
postcheck/rollback, RH real, isolamento, Encarregado, autoria, revisão, ausência de
escrita parcial, falha da auditoria, alertas e sete cenários com sessões independentes:

1. Mudança de empresa durante a espera recusa a operação.
2. Primeiro request faz rollback; o segundo cria uma única consulta.
3. Mesmo request/payload confirmado produz replay.
4. Mesmo request com payload diferente é recusado.
5. Duas correções com a mesma revisão: segunda recebe STALE_REVISION.
6. Consulta primeiro, depois inativação: nenhum alerta pendente de inativo.
7. Inativação primeiro, depois consulta: mesma garantia.

Os testes esperam por `pg_blocking_pids`, não simulam concorrência sequencialmente.

Regressões adicionais:

```powershell
$env:RH_TEST_DEPS = '<runtime com PGlite, jsdom e xlsx.full.min.js 0.20.3>'
node --test tests/rh-cadastro.test.mjs tests/collaborator-lifecycle.test.mjs tests/collaborator-rh-conformity.test.mjs
```

**22 aprovados, zero falhas e uma omissão:** caso opcional que exige ficheiro real
de 47 linhas. Não foram usados dados pessoais reais para substituir esse ficheiro.

`tests/rh-work-finance-crossing.test.mjs` também foi executado e falha na asserção
antiga que proíbe `workforce` ao Encarregado. O teste e `src/access-control.js`
são idênticos ao checkpoint; a falha não foi causada por esta alteração. Não foi
alterada a navegação/frontend nem essa asserção nesta tarefa de backend.

## Decisão técnica e limites

**GO técnico condicionado** para revisão/aplicação autorizada deste backend após
precheck real atualizado e backup correspondente. **Não há autorização de aplicação
nesta tarefa.** Não se voltou a consultar a BD real; as definições de referência
são as do checkpoint. Se contagens, funções, policies ou grants divergirem, parar.

As fixtures usam helpers de autenticação/alocação sintéticos; os corpos instalados
das funções relevantes são reais. Os testes não certificam integrações externas,
cron real, a navegação atual nem um ficheiro de dados pessoais não fornecido.
A integração futura da UI com as novas RPCs e o tratamento de revisão/request_id
continua tarefa separada. Não existe fallback para PATCH/DELETE de consultas.

## Atualização da fotografia de produção — 30/09/2026

Contagem esperada atualizada para 35, conforme confirmação manual fornecida pelo
utilizador: novo registo criado em 30/09/2026 17:38:45+00, sem duplicação.
Esta atualização não resulta de nova consulta à BD real. A próxima consulta NULL
é permitida pelas regras existentes; o teste integrado preserva os 34 cenários
anteriores e acrescenta uma consulta sintética com essa condição. O cenário de
rollback acompanha a contagem esperada pelos scripts de produção.
