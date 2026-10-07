# DOCUMENTAL-STORAGE-POLICY — 07/10/2026

## Base e evidência preservada

Branch preparada: fix/pacote-2-storage-supported-rollout-20261007, a partir exatamente de 8f609ef6fd5e31dc6dcdbc26db1f00725d7edbc0. O resultado real fornecido foi VALID_EXISTING_BACKUP_RESUME: backup privado, legível, completo e igual ao live; única falha era can_set=false para objects/buckets. Essa capacidade deixou de ser exigida. A baseline factual e os seis objetos do backup não foram regenerados. Nenhum acesso real foi feito nesta tarefa.

## Suporte e limite da evidência

O editor Storage cria policies PERMISSIVE e permite editar USING/WITH CHECK/roles/nome; não oferece criação RESTRICTIVE no código consultado. [Editor oficial](https://github.com/supabase/supabase/blob/master/apps/studio/components/interfaces/Storage/StoragePolicies/StoragePolicies.utils.ts).

A edição utiliza executeSql, como o SQL Editor; não há evidência de um executor privilegiado diferente. [Mutação oficial](https://github.com/supabase/supabase/blob/master/apps/studio/data/database-policies/database-policy-update-mutation.ts), [executor oficial](https://github.com/supabase/supabase/blob/master/apps/studio/data/sql/execute-sql-mutation.ts).

O mecanismo oficial de autorização sem ownership é supautils.policy_grants. Permite CREATE/ALTER/DROP POLICY sem membership de owner. [Implementação e contrato oficiais](https://github.com/supabase/supautils#table-ownership-bypass). O rollout NÃO instala/configura essa extensão nem modifica esses grants. O precheck recolhe a configuração em leitura; a disponibilidade efetiva neste projeto não foi confirmada nesta tarefa, que proíbe acesso real. can_set=false não decide essa disponibilidade. Se o Dashboard recusar com 42501, STOP e suporte Supabase; nenhuma tentativa de contorno.

## Operação exata futura (requer autorização)

Reutilizar aba autenticada do projeto Primeline-Obras. Storage → Policies → objects. EDITAR cada uma das 18 policies abaixo; não criar policy nova, não mudar nome, comando, PERMISSIVE nem role authenticated. Substituir somente a expressão indicada. Não limpar campos. Guardar uma policy de cada vez. Se login/MFA/consentimento surgir: STOP para Jordane. Se erro ou valor diferente: STOP. Não executar DDL de Storage pelo rollout SQL nem alterar buckets.

O JSON adjacente contém o mesmo contrato legível por testes. PostgreSQL pode acrescentar parênteses na representação canónica; o postcheck usa a expressão analisada pelo próprio PostgreSQL em clone TEMP vazio de postgres, não comparação aproximada de texto.

## Ordem obrigatória

1. documentos_rh_tenant_resume_precheck_20261007.sql (único precheck READ ONLY; VALID_EXISTING_BACKUP_RESUME; STORAGE_DASHBOARD_POLICY_REQUIRED). Verificar storage_dashboard_capability: OFFICIAL_POLICY_GRANTS_CONFIGURED identifica a configuração oficial para postgres/storage.objects. NOT_CONFIRMED_STOP_IF_DASHBOARD_REFUSES não confirma essa capacidade; obter confirmação do suporte Supabase antes da etapa SQL se o mecanismo não estiver configurado. Não configurar supautils nem alterar ownership/membership por conta própria. A classificação de baseline READY não certifica a conclusão da etapa externa.
2. documentos_rh_tenant.sql — public/RPC/helpers + evidência esperada, transação única. Nenhum Storage DDL/SET ROLE/ALTER OWNER/lock Storage. Os seis objetos do backup original ficam intactos.
3. documentos_rh_tenant_intermediate_postcheck.sql — READ ONLY; exige public/RPC novos e Storage original.
4. DOCUMENTAL-STORAGE-POLICY abaixo.
5. documentos_rh_tenant_postcheck.sql — READ ONLY; exige todas as alterações esperadas e nenhuma policy extra.
6. Apenas após autorização própria: folha_ponto_v2_precheck.sql → folha_ponto_v2_backup.sql → folha_ponto_v2.sql → folha_ponto_v2_gestao.sql → folha_ponto_v2_postcheck.sql.

Não repetir backup documental. Falha em qualquer etapa: STOP. A instalação public/RPC estreita acesso; depois cada policy muda P para P AND G. Pela distributividade, OR(P1 AND G,...,Pn AND G) = OR(P1,...,Pn) AND G. Não há UPDATE permissivo no catálogo congelado; continua recusado. As 18 policies são todos os caminhos authenticated de documentos/faturas. Nenhum estágio amplia acesso. Durante a edição parcial, a proteção Storage ainda não está completa: não continuar Folha/rollout até postcheck final.

A evidência de instalação fixa antecipadamente o catálogo final e fingerprints do backup; o postcheck nunca aprende nem aceita o catálogo live como referência nova. Owner/RLS/ACL/schema/bucket/objetos são comparados. O rollback tenant-safe mantém RPCs e Storage endurecidos; não restaura vulnerabilidades nem modifica Storage. Uma edição parcial deve parar e ser avaliada; não desfazer automaticamente.

## Policies — expressões exatas

### avaliacoes_storage_insert

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: INSERT. Role: authenticated.

USING: não existe; preservar assim.

WITH CHECK atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND ((storage.foldername(name))[2] = 'avaliacoes-subempreiteiro'::text) AND fn_pode_editar_obra(((storage.foldername(name))[1])::uuid))
```

WITH CHECK final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND ((storage.foldername(name))[2] = 'avaliacoes-subempreiteiro'::text) AND fn_pode_editar_obra(((storage.foldername(name))[1])::uuid))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

### documentos_empresa_storage_delete

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: DELETE. Role: authenticated.

USING atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'empresa'::text) AND ((storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'empresa'::text) AND ((storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### documentos_empresa_storage_insert

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: INSERT. Role: authenticated.

USING: não existe; preservar assim.

WITH CHECK atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'empresa'::text) AND ((storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())
```

WITH CHECK final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'empresa'::text) AND ((storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

### documentos_empresa_storage_select

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: SELECT. Role: authenticated.

USING atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'empresa'::text) AND ((storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'empresa'::text) AND ((storage.foldername(name))[2] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### documentos_obra_storage_delete

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: DELETE. Role: authenticated.

USING atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND fn_pode_editar_documentos_obra(((storage.foldername(name))[1])::uuid))
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND fn_pode_editar_documentos_obra(((storage.foldername(name))[1])::uuid))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### documentos_rh_storage_delete

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: DELETE. Role: authenticated.

USING atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'rh'::text) AND ((storage.foldername(name))[2] = ANY (ARRAY['colaborador'::text, 'viatura'::text, 'ausencia'::text])) AND ((storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'rh'::text) AND ((storage.foldername(name))[2] = ANY (ARRAY['colaborador'::text, 'viatura'::text, 'ausencia'::text])) AND ((storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### documentos_rh_storage_insert

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: INSERT. Role: authenticated.

USING: não existe; preservar assim.

WITH CHECK atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'rh'::text) AND ((storage.foldername(name))[2] = ANY (ARRAY['colaborador'::text, 'viatura'::text, 'ausencia'::text])) AND ((storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())
```

WITH CHECK final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'rh'::text) AND ((storage.foldername(name))[2] = ANY (ARRAY['colaborador'::text, 'viatura'::text, 'ausencia'::text])) AND ((storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

### documentos_rh_storage_select

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: SELECT. Role: authenticated.

USING atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'rh'::text) AND ((storage.foldername(name))[2] = ANY (ARRAY['colaborador'::text, 'viatura'::text, 'ausencia'::text])) AND ((storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] = 'rh'::text) AND ((storage.foldername(name))[2] = ANY (ARRAY['colaborador'::text, 'viatura'::text, 'ausencia'::text])) AND ((storage.foldername(name))[3] ~* '^[0-9a-f-]{36}$'::text) AND fn_e_administrativo())) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### documentos_storage_insert

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: INSERT. Role: authenticated.

USING: não existe; preservar assim.

WITH CHECK atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND (fn_pode_editar_obra(((storage.foldername(name))[1])::uuid) OR fn_e_administrativo()))
```

WITH CHECK final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND (fn_pode_editar_obra(((storage.foldername(name))[1])::uuid) OR fn_e_administrativo()))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

### documentos_storage_select

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: SELECT. Role: authenticated.

USING atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'::text) AND (fn_pode_ver_obra(((storage.foldername(name))[1])::uuid) OR (fn_e_encarregado_da_obra(((storage.foldername(name))[1])::uuid) AND ((storage.foldername(name))[2] = ANY (ARRAY['articulado_original'::text, 'articulado_tee'::text, 'desenho'::text, 'desenhos_preparacao'::text, 'plantas_projeto'::text, 'pdes_rfis'::text, 'pames'::text, 'atas_reuniao'::text, 'rnc'::text])))))
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'::text) AND (fn_pode_ver_obra(((storage.foldername(name))[1])::uuid) OR (fn_e_encarregado_da_obra(((storage.foldername(name))[1])::uuid) AND ((storage.foldername(name))[2] = ANY (ARRAY['articulado_original'::text, 'articulado_tee'::text, 'desenho'::text, 'desenhos_preparacao'::text, 'plantas_projeto'::text, 'pdes_rfis'::text, 'pames'::text, 'atas_reuniao'::text, 'rnc'::text])))))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### entidades_documentos_delete

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: DELETE. Role: authenticated.

USING atual:

```sql
((bucket_id = 'documentos'::text) AND (name ~~ 'entidades/%'::text) AND (fn_e_admin() OR fn_e_administrativo()))
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND (name ~~ 'entidades/%'::text) AND (fn_e_admin() OR fn_e_administrativo()))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### entidades_documentos_insert

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: INSERT. Role: authenticated.

USING: não existe; preservar assim.

WITH CHECK atual:

```sql
((bucket_id = 'documentos'::text) AND (name ~~ 'entidades/%'::text) AND (fn_e_admin() OR fn_e_administrativo()))
```

WITH CHECK final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND (name ~~ 'entidades/%'::text) AND (fn_e_admin() OR fn_e_administrativo()))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

### entidades_documentos_select

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: SELECT. Role: authenticated.

USING atual:

```sql
((bucket_id = 'documentos'::text) AND (name ~~ 'entidades/%'::text) AND (fn_e_admin() OR fn_e_administrativo()))
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND (name ~~ 'entidades/%'::text) AND (fn_e_admin() OR fn_e_administrativo()))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### faturas_anexos_storage_insert

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: INSERT. Role: authenticated.

USING: não existe; preservar assim.

WITH CHECK atual:

```sql
((bucket_id = 'faturas'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND ((storage.foldername(name))[2] = 'faturas-anexos'::text) AND (fn_pode_editar_obra(((storage.foldername(name))[1])::uuid) OR fn_e_financeiro()))
```

WITH CHECK final (substituir integralmente):

```sql
(((bucket_id = 'faturas'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND ((storage.foldername(name))[2] = 'faturas-anexos'::text) AND (fn_pode_editar_obra(((storage.foldername(name))[1])::uuid) OR fn_e_financeiro()))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

### faturas_read_authenticated

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: SELECT. Role: authenticated.

USING atual:

```sql
((bucket_id = 'faturas'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND (fn_pode_ver_obra(((storage.foldername(name))[1])::uuid) OR fn_e_financeiro()))
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'faturas'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND (fn_pode_ver_obra(((storage.foldername(name))[1])::uuid) OR fn_e_financeiro()))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### faturas_storage_delete_restrito

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: DELETE. Role: authenticated.

USING atual:

```sql
((bucket_id = 'faturas'::text) AND (fn_e_admin() OR (EXISTS ( SELECT 1
   FROM utilizadores u
  WHERE ((u.auth_user_id = auth.uid()) AND u.ativo AND (u.funcao = ANY (ARRAY['administrativo'::text, 'financeiro'::text, 'diretor_obra'::text, 'adjunto'::text, 'preparador'::text])))))))
```

USING final (substituir integralmente):

```sql
(((bucket_id = 'faturas'::text) AND (fn_e_admin() OR (EXISTS ( SELECT 1
   FROM utilizadores u
  WHERE ((u.auth_user_id = auth.uid()) AND u.ativo AND (u.funcao = ANY (ARRAY['administrativo'::text, 'financeiro'::text, 'diretor_obra'::text, 'adjunto'::text, 'preparador'::text])))))))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

WITH CHECK: não existe; preservar assim.

### faturas_upload_authenticated

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: INSERT. Role: authenticated.

USING: não existe; preservar assim.

WITH CHECK atual:

```sql
((bucket_id = 'faturas'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND ((((storage.foldername(name))[2] = 'guias-remessa'::text) AND fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)) OR (((storage.foldername(name))[2] <> 'guias-remessa'::text) AND fn_e_administrativo())))
```

WITH CHECK final (substituir integralmente):

```sql
(((bucket_id = 'faturas'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'::text) AND ((((storage.foldername(name))[2] = 'guias-remessa'::text) AND fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)) OR (((storage.foldername(name))[2] <> 'guias-remessa'::text) AND fn_e_administrativo())))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

### rnc_storage_insert

Tabela: storage.objects. Tipo: PERMISSIVE. Comando: INSERT. Role: authenticated.

USING: não existe; preservar assim.

WITH CHECK atual:

```sql
((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'::text) AND ((storage.foldername(name))[2] = 'rnc'::text) AND (fn_pode_editar_obra(((storage.foldername(name))[1])::uuid) OR fn_e_encarregado_da_obra(((storage.foldername(name))[1])::uuid)))
```

WITH CHECK final (substituir integralmente):

```sql
(((bucket_id = 'documentos'::text) AND ((storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'::text) AND ((storage.foldername(name))[2] = 'rnc'::text) AND (fn_pode_editar_obra(((storage.foldername(name))[1])::uuid) OR fn_e_encarregado_da_obra(((storage.foldername(name))[1])::uuid)))) AND primeline_documentos_rh_privado.objeto_empresa(bucket_id,name)
```

## Manutenção posterior

Ao contrário da guarda RESTRICTIVE, esta alternativa exige que qualquer policy permissiva futura preserve a mesma guarda. Uma nova policy sem guarda pode reabrir acesso e é recusada pelo postcheck (inclusive se o nome parecer correto). Não há prevenção automática contra futuras alterações privilegiadas fora deste contrato; repetir o gate após qualquer mudança de policy.

## Verificação local

PostgreSQL 17.6 efémero: executor postgres NOSUPERUSER/BYPASSRLS sem membership supabase_storage_admin; tentativa nativa de DDL owner-only recusa 42501. Backup sintético existente permanece com os mesmos dados/metadados. Todas as 18 policies congeladas são recriadas com linhas exclusivamente sintéticas. SQL public/RPC, postcheck intermédio, edição externa simulada, postcheck final, precheck/backup/core/gestão/postcheck Folha e rollbacks tenant-safe passam. O processo externo local representa a aplicação da policy; não comprova a capacidade real do Dashboard/supautils neste projeto.

Suite geral final: 1088 PASS / 0 FAIL / 1 SKIP preservado (ficheiro RH real ausente). Browser: 20 suites PASS, com repetição isolada da suite workforce-p1 após falha inicial de hit-test mobile; produto não alterado. A primeira execução geral também teve arranque PostgREST efémero exit=3; a repetição completa final passou. Logs das primeiras execuções preservados fora do Git.

Sequência crítica final: 13 PASS / 0 FAIL / 0 SKIP. Negativos: hardening ausente, caminho parcialmente desprotegido, OR permissiva extra, helper errado, owner alterado, bucket public e backup com índice adicional são recusados. SELECT/INSERT cross-tenant recusados; regressões de namespaces cobrem UPDATE/DELETE. Após commit, repetir a sequência crítica em segunda worktree limpa e informar o resultado na entrega.

Sweep factual: 19 scripts documentais/Folha/cutover, zero DDL gerido e zero SET ROLE Storage. Os cinco scripts Folha permanecem inalterados. Frontend/main/produção/Fase B não foram alterados.
