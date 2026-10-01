# Pacote 1 — Quadro controlado e integração mínima com RH

## Estado e limites

Branch `feat/quadro-controlado-20261001`, baseada em `origin/main` no commit `9e0e6c40b439160201289823db8cfee0b9adad02`.

Implementação preparada e testada localmente. Nenhum SQL deste pacote foi aplicado à BD real. Nenhum dado de produção foi alterado. A publicação e aplicação dependem da varredura estrutural crítica separada e de autorização posterior.

Não inclui novo Ponto, Horas Extra, Férias, Mapa de Vencimentos, custos, Financeiro, Medicina, Viaturas ou Planeamento. No Ponto existente, as duas funções de leitura/gravação conservam o código funcional e passam somente a resolver alocações pela data exata; não há alteração de estados, horas, formulários ou aprovação.

## Inventário de escritores antes de fechar DML

A varredura leu o repositório, definições instaladas, funções SECURITY DEFINER, triggers, SQL dinâmico e dependências. A fixture `tests/fixtures/quadro-funcoes-instaladas.json` contém definições/metadados, sem linhas pessoais de produção.

| Escritor encontrado | Situação | Tratamento |
| --- | --- | --- |
| `src/app.js`, `saveWorkforceAllocation` | DELETE → POST, PATCH e INSERT diretos | Substituídos por preview + confirmação única de `fn_quadro_operar` |
| `src/app.js`, `removeWorkforceAllocation` | DELETE direto | RPC com IDs explícitos, revisão e request UUID |
| `src/app.js`, `renameWorkforceLine` | PATCH direto de descrição | Operação controlada de renomeação atómica |
| `fn_quadro_operar(text,jsonb,boolean,text)` instalada | INSERT/UPDATE/DELETE | Reimplementada sobre núcleo privado comum |
| `fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid)` instalada | INSERT inicial | Wrapper do construtor privado + mesmo núcleo |
| `fn_criar_colaborador_com_alocacao(text,text,date,date,text,uuid,text,numeric,text,text,text,text)` instalada | INSERT inicial | Mesmo tratamento, assinaturas preservadas |
| `fn_rh_guardar` / `fn_rh_importar` → `fn_rh_guardar_interno` | Escrita indireta pelo construtor | Cadeia preservada; construção passa pelo núcleo privado |
| `supabase/quadro_pessoal_alocacao_diaria.sql` | UPDATE histórico de preenchimento | Não reaplicado; não é escritor em runtime |
| `supabase/colaboradores_crud_alocacao_inicial.sql` e `supabase/colaboradores_campos_completos.sql` | Definições históricas dos construtores | Sobrescritas pelas definições completas da migration; não reaplicar scripts antigos |
| `fn_mgo_inserir_json_compativel(regclass,jsonb)` | INSERT dinâmico genérico | Privada, ACL do owner; nenhum chamador encontrado com destino Quadro. Não adaptada nem exposta. O trigger impede escrita em Quadro fora da permissão privada |

Foram encontrados três escritores diretos instalados, correspondentes às assinaturas acima. As restantes funções dinâmicas inventariadas pertencem a outros domínios e não escrevem em Quadro. `settings.js` menciona a tabela apenas para auditoria.

Triggers existentes preservados: `trg_00_quadro_proteger_escrita`, `trg_auditoria_quadro_pessoal_alocacao`, `trg_bloquear_quadro_pessoal_ausencia`, `trg_quadro_notificar_movimentacao_encarregado`, `trg_quadro_pessoal_movimentos`, `trg_validar_conflito_quadro_pessoal`. Os corpos da proteção e histórico são atualizados; não se adiciona um segundo histórico concorrente.

Após adaptar os escritores legítimos, a migration revoga INSERT/UPDATE/DELETE diretos em alocações e escrita direta em movimentos. Não existe exceção acionável por `set_config`. A escrita legítima exige uma permissão privada, limitada à transação, colaborador/data e autor. Tabelas privadas e helpers não têm EXECUTE/DML concedidos à aplicação.

## Núcleo e temporalidade

`fn_quadro_aplicar_interno(uuid,date,jsonb,jsonb,text,uuid,boolean)` recebe os estados anterior e proposto de um colaborador numa data explícita. Valida utilizador ativo, empresa, colaborador, todos os destinos, todas as origens, períodos, ausência e identidade. Usa lock da linha do colaborador e advisory locks por colaborador/data. Valida preview sem escrever e aplica alterações numa única transação.

`fn_quadro_resolver_data(date)` resolve apenas registos com `data = data solicitada`. É reutilizada pelo contexto do Quadro, pelo estado diário do núcleo e pelos dois consumidores existentes do Ponto. `obra_responsaveis` serve apenas para autorização; nunca cria presença.

A grelha deixou também de transportar visualmente a equipa do dia anterior. Um dia sem registo explícito fica vazio. Não há cópia de semana nem programação automática futura neste pacote.

Os 27 pares de sobreposição históricos e as duas coexistências ausência/alocação não são apagados nem corrigidos. Dias com sobreposição legada recusam novas alterações com `LEGACY_CONFLICT`; requerem decisão humana separada. As regras instaladas já recusam qualquer ausência registada, incluindo pendente; essa proteção mais restritiva foi preservada.

## Contrato público

`fn_quadro_operar(p_acao text, p_dados jsonb, p_confirmar boolean, p_versao text)` conserva a assinatura instalada.

Operações: `alocar`, `adicionar`, `mover`, `corrigir`, `remover`, `renomear_linha`.

Exemplo de `p_dados` para alocação:

```json
{
  "version": 1,
  "colaborador_id": "<uuid>",
  "data": "2026-10-05",
  "periodo": "manha",
  "tipo_alocacao": "obra",
  "obra_id": "<uuid>",
  "descricao_livre": null,
  "expected_revision": 0,
  "request_id": "<uuid novo>"
}
```

Períodos permitidos: `manha`, `tarde`, `dia_inteiro`. Destinos: `obra`, `escritorio`, `garantia`, `pontual`. Destinos livres exigem descrição e `obra_id = NULL`. Remoção recebe `ids` explícitos. Renomeação recebe `version`, `request_id`, `tipo_alocacao`, `descricao_anterior`, `descricao_nova` e obtém o conjunto/revisões no preview.

Preview (`p_confirmar=false`) devolve `version=1`, `committed=false`, `versao`, revisão e estados. Confirmação envia os mesmos dados e `p_versao` devolvida. Sucesso exige `version=1`, `committed=true`, `idempotent`, `allocations`, `revision`, colaborador/data. Renomeação devolve `days`.

O snapshot exclui somente IDs/timestamps recém-gerados que não devem mudar entre preview e confirmação. A revisão diária deteta também A → B → A. Request ID usa lock próprio e registo privado de payload completo, autor, empresa e resultado: replay igual devolve o resultado confirmado; payload diferente devolve `IDEMPOTENCY_CONFLICT`.

Erros principais: `STALE_REVISION`, `IDEMPOTENCY_CONFLICT`, `LEGACY_CONFLICT`, `OVERLAP_CONFLICT`, `ABSENCE_CONFLICT`, `PERMISSION_DENIED`, `VALIDATION_ERROR`, `CONTRACT_VERSION`. O frontend faz uma confirmação, não repete automaticamente RPCs e recarrega perante STALE.

## Cadastro e Importação RH

Os dois construtores existentes mantêm assinaturas e usam `fn_quadro_criar_colaborador_interno`, que chama o mesmo núcleo do Quadro. Cadastro + alocação inicial + contratos/campos RH continuam na mesma transação. Falha da alocação reverte também a criação da pessoa.

A alocação inicial, quando pedida, existe somente em `data_admissao`, explicitamente fornecida, no período inicial já existente (`dia_inteiro`). Não se inferem dias seguintes nem presença por responsabilidade. Sem alocação inicial explícita, não se cria qualquer linha. `alocacao_tipo = NULL` exige obra NULL; nenhum formulário foi redesenhado para introduzir esta opção.

`fn_rh_guardar_interno` preserva as regras de contratação, EPI, Medicina e importação. A importação atual exige IDs existentes e não cria pessoas nem alocações iniciais. Não foi ampliada silenciosamente para criar colaboradores. Testes importam pessoas com e sem alocação, preservam as alocações e comprovam rollback integral perante erro numa linha.

Novas linhas geram o histórico normal com origem `cadastro_rh`; o núcleo aceita `importacao_rh` para chamadas internas explicitamente autorizadas, mas o contrato de importação atual não cria pessoas. Não se inventa histórico retroativo.

## Permissões e leitura

| Perfil | Consulta | Escrita |
| --- | --- | --- |
| Gestão da Plataforma / Gerência / Administrativo | Empresa atual | Global dentro da empresa; sempre auditada |
| Encarregado | Obras sob responsabilidade | Todas as origens e destinos devem ser obras autorizadas; sem poderes globais ou escritório |
| Diretor / Adjunto | Equipa das obras sob responsabilidade | Sem movimentação |
| Preparador | Sem novos poderes de Quadro | Sem movimentação |
| Utilizador inativo / outra empresa | Recusado | Recusado |

`fn_quadro_contexto(date,date)` devolve apenas o contexto permitido: obras, pessoas operacionais, alocações, revisões e capacidades. A UI depende deste contexto e bloqueia edição se a leitura essencial falhar. Não usa permissões calculadas apenas no browser. O Adjunto recebe somente a vista de consulta; os restantes poderes de RH não mudam.

## Schema proposto e instalação

Novas tabelas privadas: `quadro_dias_revisoes`, `quadro_operacoes`, `quadro_escrita_interna`. Novas colunas nullable em `quadro_pessoal_movimentos`: `origem_operacao`, `request_id`. As revisões começam implicitamente em zero e só recebem linha quando há operação; não há backfill de dados ou movimentos.

Ordem, somente após revisão e autorização:

1. `supabase/quadro_controlado_precheck.sql`: leitura de contagens, conflitos, ausências, writers, funções dinâmicas, triggers, policies e dependências. Divergência exige parar e rever.
2. `supabase/quadro_controlado_backup.sql`: cópia privada de alocações, movimentos, colaboradores, ausências, obras, responsáveis, definições, ACL, policies, triggers e constraints. Não executar novamente se as tabelas já existirem. Exportar para arquivo privado externo, nunca Git.
3. `supabase/quadro_controlado.sql`: transação completa. Exige backup igual ao estado atual e hashes das funções substituídas; recusa writer direto desconhecido.
4. `supabase/quadro_controlado_postcheck.sql`: prova de igualdade dos dados antigos, novas tabelas vazias e ausência de DML público.

`supabase/quadro_controlado_rollback.sql` contém a restauração completa das definições e permissões anteriores. Recusa rollback após uso do mecanismo controlado (operações ou revisões); não remove histórico novo nem recria permissões antigas silenciosamente após uso. O backup privado permanece.

Os scripts são completos e instaláveis; nenhum foi executado na BD real nesta tarefa.

## Testes

`tests/workforce-controlled.test.mjs`: PostgreSQL 17.6 local, duas ligações independentes, definições reais com dados sintéticos. Cobertura de instalação/backup/rollback; preservação de 227/98; diário explícito; mover/split/merge/remover; conflitos/ausências; tenants; perfis; DML e GUC falsificado; idempotência; A → B → A; três concorrências; RH com/sem alocação; falhas depois do INSERT da pessoa; importação atómica; renomeação.

Helpers periféricos não exercitados (notificações/Medicina, etc.) são stubs explícitos na fixture local. A suíte não prova a execução integral desses outros módulos; as funções RH/Ponto preservadas são verificadas também por comparação de código. A fixture instalada contém somente schema/definições; todas as pessoas/obras dos testes SQL são sintéticas.

`tests/workforce-allocation-client.test.mjs`: contrato, data exata, resposta não confirmada, preview inválido, erros/reload, ausência de retry e replay.

`tests/workforce-controlled-browser.mjs`: consumidor real do app e wrapper, API inteiramente interceptada offline. Testa mover/remover, dia seguinte vazio/sem seta, falhas preservando origem, STALE sem retry, perfis, ausência de DML direto, desktop/tablet/mobile e Console limpo. Screenshots privados temporários.

Regressões: testes existentes de workforce, access-control/Adjunto, wrapper colaboradores, férias/horas extra, Cadastro RH e dois browsers offline (Quadro e RH). O teste RH com o ficheiro externo real de 47 linhas fica skipped quando esse ficheiro não está disponível; não é contado como passado.

Variáveis de teste: `QUADRO_PG_BIN` aponta para os binários PostgreSQL 17.6; `QUADRO_TEST_DEPS` para `pg`; `RH_TEST_DEPS` para a pasta que contém `xlsx.full.min.js` e resolve PGlite/JSDOM; `PLANNING_PLAYWRIGHT` para Playwright. Não são dependências de produção.

## Riscos e próxima etapa

- A migration ainda não foi aplicada. O frontend novo falha de forma explícita se o backend controlado não estiver instalado; aplicar/publicar fora de ordem interromperia edição.
- As contagens reais de referência são 227/98/27/2. O precheck deve voltar a ser executado e revisto no momento autorizado; alterações legítimas entretanto exigem nova fotografia/backup, nunca ignorar o bloqueio.
- Conflitos e coexistências históricos requerem tarefa humana separada. Este pacote não oferece override para fabricar simultaneidade ou apagar conflitos.
- Ausências pendentes continuam sujeitas à proteção já instalada. O desenho futuro de Férias/Ausências poderá rever essa regra em tarefa própria.
- O helper legado de Medicina `fn_colaborador_na_obra_atual_encarregado` não foi alterado; não é usado pelo núcleo novo. A sua revisão pertence ao módulo correspondente.
- Renomeação de linha livre bloqueia o conjunto durante a transação e pode falhar em dias legados/ausentes; não faz correção parcial.
- Não revogar ou reintroduzir DML reaplicando scripts históricos. Novos escritores internos devem passar pelo núcleo, não pelo acesso direto.

GO técnico para a varredura estrutural crítica separada. NO-GO para aplicação/publicação antes dessa revisão e autorização. O pacote não está declarado encerrado.

### Resultado final desta execução

- PostgreSQL 17.6: **43 testes passaram**, zero falhas e zero skips, incluindo duas ligações independentes.
- Regressões Quadro/RH/permissões/wrapper: **60 passaram**, zero falhas; **1 skip** por ausência do ficheiro Excel externo real de 47 linhas.
- Navegador offline: Quadro controlado e frontend RH passaram; três larguras, Console limpo, sem pedidos a produção e sem DML direto de alocações.
- `git diff --check`: limpo.

No total: **103 testes passaram**, um skip documentado, mais os dois executáveis de navegador offline. Estes resultados não substituem a revisão estrutural crítica separada nem a validação autorizada de instalação real.

Leitura final da BD real, sem escrita: **227 alocações, 98 movimentos, 27 pares de sobreposição, 2 coexistências ausência/alocação**; `quadro_operacoes` ausente. A fotografia de referência permaneceu intacta e o pacote não estava instalado.
