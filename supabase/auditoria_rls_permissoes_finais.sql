-- PRIMELINE | Auditoria sem escrita da matriz final de permissões.
-- Executar depois de supabase/rls_permissoes_finais.sql.

-- 1. Deve devolver as cinco funções usadas pela matriz.
select
  p.proname as funcao,
  p.prosecdef as security_definer,
  pg_get_functiondef(p.oid) as definicao
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'fn_e_admin',
    'fn_e_administrativo',
    'fn_e_financeiro',
    'fn_pode_ver_obra',
    'fn_pode_editar_obra'
  )
order by p.proname;

-- 2. Inventário integral das políticas finais.
select schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where (schemaname = 'public' and policyname like 'pl_%')
   or (schemaname = 'storage' and policyname in (
     'faturas_read_authenticated',
     'faturas_upload_authenticated',
     'documentos_storage_select',
     'documentos_storage_insert'
   ))
order by schemaname, tablename, cmd, policyname;

-- 3. Não deve devolver linhas: políticas antigas nas tabelas protegidas.
select schemaname, tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in (
    'obras', 'faturas', 'faturas_guias', 'contratos', 'fases',
    'autos_medicao', 'alteracoes_tee', 'itens_orcamento',
    'planeamento_fases_resumo', 'planeamento_itens',
    'planeamento_itens_dependencias', 'consultas_subempreitada',
    'consultas_subempreitada_itens', 'consultas_subempreitada_candidatos',
    'consultas_subempreitada_candidatos_itens', 'documentos_obra',
    'colaboradores', 'medicina_trabalho', 'viaturas', 'ausencias',
    'colaboradores_contratos', 'horas_extraordinarias',
    'quadro_pessoal_alocacao'
  )
  and policyname not like 'pl_%';

-- 4. Deve mostrar RLS ativo em todas as tabelas existentes desta lista.
select
  c.relname as tabela,
  c.relrowsecurity as rls_ativo,
  c.relforcerowsecurity as rls_forcado
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname in (
    'obras', 'faturas', 'faturas_guias', 'fornecedores', 'subempreitadas',
    'avaliacoes_subempreiteiro', 'planeamento_itens',
    'planeamento_itens_dependencias', 'documentos_obra', 'colaboradores',
    'medicina_trabalho', 'viaturas', 'ausencias',
    'colaboradores_contratos', 'horas_extraordinarias',
    'quadro_pessoal_alocacao'
  )
order by c.relname;

-- 5. Contas disponíveis para testar cada papel no frontend.
select
  papel,
  count(u.id) as utilizadores_ativos,
  count(u.auth_user_id) as contas_auth_ligadas,
  count(distinct r.obra_id) as obras_associadas
from unnest(array[
  'gerencia',
  'administrativo',
  'financeiro',
  'diretor_obra',
  'preparador'
]) as papeis(papel)
left join public.utilizadores u
  on u.funcao = papel and coalesce(u.ativo, true)
left join public.obra_responsaveis r
  on r.utilizador_id = u.id
group by papel
order by array_position(
  array['gerencia','administrativo','financeiro','diretor_obra','preparador'],
  papel
);

-- 6. Administradores mantêm acesso total independentemente da função.
select
  a.utilizador_id,
  u.nome,
  u.email,
  u.funcao,
  u.ativo,
  u.auth_user_id
from public.administradores_plataforma a
left join public.utilizadores u on u.id = a.utilizador_id
order by u.nome nulls last;

-- 7. UPDATE direto em faturas deve estar revogado; as operações sensíveis
-- são feitas exclusivamente pelas duas funções concedidas a authenticated.
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where specific_schema = 'public'
  and routine_name in ('fn_decidir_fatura', 'fn_marcar_fatura_paga')
order by routine_name, grantee;

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'faturas'
  and grantee in ('anon', 'authenticated')
order by grantee, privilege_type;
