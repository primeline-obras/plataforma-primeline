# Pacote 2 — ownership de Storage e retoma documental

## Estado e limites

Base exata: `cf0957447f171cfa274444d5437cbf587f0076ca`.
Branch: `fix/pacote-2-storage-owner-resume-20261007`.

Esta tarefa é local. Não consultou nem executou SQL no Supabase. Não alterou o backup real, dados, memberships reais, owners reais, frontend, main, deploy, cutover ou Fase B. A tentativa anterior permanece registada na evidência operacional privada fora do Git.

O backup documental real foi criado com sucesso antes da falha da migration anterior. Não deve ser repetido, substituído ou recalibrado. A capacidade real de assumir a role proprietária ainda precisa de confirmação pelo único SQL de retoma abaixo.

## Causa e correção

`postgres` foi tratado como proprietário de `storage.objects`. O objeto pertence a `supabase_storage_admin`. A instrução redundante `ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY` falhou com `42501`; a criação subsequente da policy também exigia owner.

As tabelas `storage.objects` e `storage.buckets` mantêm o owner aprovado `supabase_storage_admin` e RLS ativo. O SQL não transfere owners nem concede memberships. O gate exige executor normal `postgres`, owners/RLS esperados e `pg_has_role(session_user, 'supabase_storage_admin', 'SET')`.

`SET` verifica a capacidade de assumir uma role; `MEMBER` não substitui essa verificação. Referência: [PostgreSQL 17 — funções de privilégios](https://www.postgresql.org/docs/17/functions-info.html).

A única policy nova de Storage continua restritiva, aplicada por AND às permissivas existentes:

1. `postgres` concede temporariamente USAGE no schema privado ao owner de Storage, apenas para resolução do nome da função na definição da policy;
2. `SET LOCAL ROLE supabase_storage_admin`;
3. cria `rh_storage_empresa_guard`;
4. `RESET ROLE`;
5. revoga o USAGE temporário antes de COMMIT.

Não é concedido EXECUTE adicional nem criada policy permissiva. O privilégio temporário e a sua revogação pertencem à mesma transação. A role normal executa todas as restantes alterações públicas. A definição final de helpers/schema/ACL entra no fingerprint instalado.

Durante a migration, locks SHARE nas tabelas documentais e Storage impedem alterações concorrentes dos conjuntos comparados. O lock de Storage é adquirido sob a sua role proprietária e não altera dados. `lock_timeout = 10s` faz a operação abortar em vez de esperar indefinidamente.

## Modelo de retoma

| Estado | Significado | Retoma atual |
|---|---|---|
| CLEAN_START | Nenhum backup nem objetos novos | Bloqueada: este não é o estado real esperado |
| VALID_EXISTING_BACKUP_RESUME | Backup privado, estrutura esperada, dados e catálogo iguais, sem instalação parcial | Elegível, sujeito aos restantes gates |
| PARTIAL_OR_UNKNOWN_STATE | Backup/estrutura/ACL/dados/RPCs divergentes ou instalação parcial | Bloqueada |

O novo precheck conserva integralmente o catálogo factual congelado de 273 funções e 166 relações. Não remove owners dos fingerprints. Acrescenta capability, privacy/shape e comparação do backup existente.

Compara em ambas as direções, com `EXCEPT ALL`:

- documentos;
- anexos de ausências;
- objetos Storage;
- policies originais dos três objetos protegidos;
- OID/RLS/ACL das tabelas guardadas;
- assinaturas, definições, owners, ACL/config das 13 RPCs.

Verifica os seis snapshots esperados, tipos/ordem de colunas, ausência de constraints/defaults/triggers/índices inesperados, owner e ACL privados. A comparação dinâmica só é executada quando estrutura, privacidade, acesso de leitura e visibilidade integral sem filtragem RLS estão disponíveis; caso contrário, o resultado é BLOCKED. Não mostra documentos, URLs, nomes pessoais ou montantes.

Deteta schema privado, policies novas, `backup.instalacao` ou drift das RPCs. A migration repete a verificação do backup antes de criar o primeiro objeto novo. O script de backup continua reservado a CLEAN START e recusa um schema já existente.

## Próximo e único SQL manual

`supabase/documentos_rh_tenant_resume_precheck_20261007.sql`

Executar integralmente no projeto Primeline-Obras, ref `znttyadndpkxuekhjamd`. É REPEATABLE READ READ ONLY, devolve uma única linha JSON `resume_precheck` e termina em ROLLBACK. Não depende de NOTICE e não executa SET ROLE.

O resultado inclui executor, owners/RLS/capacidade, estado e privacidade do backup, comparação integral, instalação parcial, hashes RPC, correspondência de catálogo, fingerprints e todos os blockers. O veredicto é `READY_TO_RESUME_DOCUMENTAL_MIGRATION` ou `BLOCKED`.

Se faltar SET ROLE, o blocker é `STORAGE_OWNER_CAPABILITY_BLOCKED`. Parar e apresentar o resultado; não conceder memberships, mudar owners ou tentar a migration.

## Sequência após READY e autorização expressa

1. `supabase/documentos_rh_tenant.sql` corrigido;
2. `supabase/documentos_rh_tenant_postcheck.sql`;
3. `supabase/folha_ponto_v2_precheck.sql`;
4. `supabase/folha_ponto_v2_backup.sql`;
5. `supabase/folha_ponto_v2.sql`;
6. `supabase/folha_ponto_v2_gestao.sql`;
7. `supabase/folha_ponto_v2_postcheck.sql`.

**Não repetir `documentos_rh_tenant_backup.sql`.** Parar em qualquer falha, confirmar rollback da transação quando aplicável e não improvisar correções reais. Frontend e cutover continuam fora desta sequência.

## Postcheck e rollback

Os postchecks documentais são READ ONLY e executam com a role normal. Verificam explicitamente owners/RLS de ambas as tabelas Storage, além do catálogo completo instalado, helpers, policies, ACL, bucket privado e igualdade integral dos dados.

O rollback documental continua de compatibilidade: conserva as 13 RPCs protegidas e as guardas restritivas; restaura apenas a policy pública anterior sob essas guardas. Não executa DDL em Storage nem necessita de SET ROLE. O postcheck do rollback certifica esse estado tenant-safe. Não restaura a vulnerabilidade original.

## Sweep do rollout

Inventário reproduzível: `docs/pacote-2-storage-owner-inventory-20261007.json` e `tests/documentos-rh-storage-ownership-inventory.mjs`.

Abrange 18 scripts documentais, Folha e cutover, incluindo os scripts principais. Cada ocorrência tem ficheiro, linha, excerto e classificação READ_ONLY_OK / POSTGRES_OWNED_OK / REQUIRES_STORAGE_OWNER / UNSUPPORTED_REMOVE.

Resultado final: 224 ocorrências (92 READ_ONLY_OK, 131 POSTGRES_OWNED_OK e 1 REQUIRES_STORAGE_OWNER); uma policy requer Storage owner; zero operações geridas sem suporte. O ALTER RLS redundante removido também está identificado. Os scripts Folha/cutover leem catálogo Storage e usam DDL apenas nos objetos públicos/privados próprios. Não alteram diretamente auth, extensions, realtime ou vault. Os gates `current_user=postgres` nesses scripts referem-se aos objetos públicos/privados que o executor possui, e não pressupõem ownership de Storage.

## Testes e evidência local

A suite `documentos-rh-storage-resume.test.mjs` inicializa PostgreSQL 17.6 com bootstrap separado. O executor `postgres` é NOSUPERUSER, com BYPASSRLS para reproduzir a capacidade técnica normal de leitura. Storage pertence a `supabase_storage_admin`; a membership sintética é SET TRUE / INHERIT FALSE. Essa membership existe apenas na montagem da fixture, nunca nos scripts do rollout.

Verificações:

- ALTER/policy sem capacidade devolvem 42501;
- precheck e migration bloqueiam antes de criar objetos quando falta SET ROLE;
- migration antiga exata de Git falha e faz rollback, preservando o backup;
- precheck factual recusa o catálogo sintético reduzido;
- com baseline explicitamente sintética apenas no teste, retoma existente devolve READY;
- alterações de dados, backup, ACL, coluna, owner, RLS, RPC ou schema parcial são recusadas;
- migration/postcheck preservam owners, RLS, ACL, dados, bucket e role normal;
- USAGE temporário foi revogado;
- visibilidade filtrada pelo RLS não pode ser certificada como comparação integral;
- sequência Folha completa e rollbacks tenant-safe passam com executor sem superuser.

As oito suites existentes que carregam a camada documental também recebem a fixture com owners reais de Storage. O teste estático exige inventário atualizado e mantém a baseline real inalterada.

Resultados finais locais:

- 146 suites Node descobertas: 1087 PASS / 0 FAIL / 1 SKIP preservado. O SKIP depende do ficheiro RH real não disponível; não foi introduzido nesta tarefa.
- 20 suites browser: PASS, incluindo Folha, sessão, Quadro, RH, Medicina, Planeamento, RNC e Viaturas.
- Suite crítica final: 20 PASS / 0 FAIL, reunindo ownership/resume, inventário e rollout consolidado. Inclui o teste negativo de visibilidade filtrada por RLS.
- `git diff --check`: PASS.
- A primeira execução completa encontrou dois asserts desatualizados de drift do bucket e falha de arranque do PostgREST local. Os asserts agora alteram RLS ativo para desativado e esperam o gate explícito de owner/RLS. A repetição integral passou; nenhuma falha foi transformada em SKIP.

Segunda worktree limpa: `C:\Users\conta\.codex\worktrees\pacote2-documental-verificacao\primeline-go-urgente`, reutilizada após confirmar ausência de alterações.

Commit da implementação testado: `55188a6e9170b7f6e52d7b108fb739a13ae3be6c`.
Ownership/resume + inventário + sequência PostgreSQL consolidada: **20 PASS / 0 FAIL / 0 SKIP**, `git diff --check` PASS. O commit posterior regista apenas esta evidência documental; os ficheiros executáveis mantêm os mesmos blobs testados.

Logs sintéticos fora do Git: `primeline-owner-complete-final` (Node), `primeline-owner-complete` (browser) e `primeline-owner-second-worktree.log`, no diretório temporário local.

## Gates reais restantes

GO LOCAL: nenhum P0/P1/P2 conhecido permanece nesta correção de ownership/retoma. O P1 documental original continua na produção até aplicar o hotfix; não foi considerado corrigido por testes locais.

A correção local não prova SET ROLE no Supabase real. O próximo precheck deve confirmar essa capacidade e que o backup continua integralmente igual ao estado instalado. Qualquer BLOCKED é NO-GO para a migration. Não foi executada nenhuma nova consulta real nesta tarefa.
