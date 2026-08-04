-- PRIMELINE | Ativação do log de auditoria.
-- Usa a tabela public.log_auditoria já existente e não altera as suas colunas.
-- Cada UPDATE cria uma linha por campo realmente alterado.
-- INSERT e DELETE usam, respetivamente, os campos especiais __INSERT__ e __DELETE__.

begin;

create or replace function public.fn_registar_log_auditoria()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_anterior jsonb;
  v_novo jsonb;
  v_registo jsonb;
  v_registo_id uuid;
  v_utilizador_id uuid;
  v_campo text;
  v_campos_sensiveis constant text[] := array[
    'password', 'senha', 'palavra_passe', 'access_token', 'refresh_token',
    'token', 'secret', 'service_role_key', 'anon_key'
  ];
begin
  if tg_op = 'INSERT' then
    v_novo := to_jsonb(new);
    v_registo := v_novo;
  elsif tg_op = 'UPDATE' then
    v_anterior := to_jsonb(old);
    v_novo := to_jsonb(new);
    v_registo := v_novo;
  else
    v_anterior := to_jsonb(old);
    v_registo := v_anterior;
  end if;

  v_registo_id := nullif(v_registo ->> coalesce(nullif(tg_argv[0], ''), 'id'), '')::uuid;

  -- Uma tabela sem UUID identificável não pode alimentar a estrutura existente.
  -- Os triggers abaixo são instalados apenas em tabelas com coluna id UUID.
  if v_registo_id is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_utilizador_id := public.fn_utilizador_atual_id();

  if tg_op = 'INSERT' then
    insert into public.log_auditoria (
      tabela_afetada, registo_id, campo, valor_anterior, valor_novo,
      utilizador_id, criado_em
    ) values (
      tg_table_schema || '.' || tg_table_name,
      v_registo_id,
      '__INSERT__',
      null,
      (v_novo - v_campos_sensiveis)::text,
      v_utilizador_id,
      now()
    );
    return new;
  end if;

  if tg_op = 'DELETE' then
    insert into public.log_auditoria (
      tabela_afetada, registo_id, campo, valor_anterior, valor_novo,
      utilizador_id, criado_em
    ) values (
      tg_table_schema || '.' || tg_table_name,
      v_registo_id,
      '__DELETE__',
      (v_anterior - v_campos_sensiveis)::text,
      null,
      v_utilizador_id,
      now()
    );
    return old;
  end if;

  for v_campo in
    select campo
    from (
      select jsonb_object_keys(v_anterior) as campo
      union
      select jsonb_object_keys(v_novo) as campo
    ) campos
    where not (campo = any(v_campos_sensiveis))
      and v_anterior -> campo is distinct from v_novo -> campo
    order by campo
  loop
    insert into public.log_auditoria (
      tabela_afetada, registo_id, campo, valor_anterior, valor_novo,
      utilizador_id, criado_em
    ) values (
      tg_table_schema || '.' || tg_table_name,
      v_registo_id,
      v_campo,
      case when v_anterior ? v_campo then (v_anterior -> v_campo)::text else null end,
      case when v_novo ? v_campo then (v_novo -> v_campo)::text else null end,
      v_utilizador_id,
      now()
    );
  end loop;

  return new;
end;
$$;

revoke all on function public.fn_registar_log_auditoria() from public, anon, authenticated;

-- O log só pode ser alimentado pelos triggers e consultado por Gerência/admin.
alter table public.log_auditoria enable row level security;
revoke all on table public.log_auditoria from anon;
revoke insert, update, delete, truncate on table public.log_auditoria from authenticated;
grant select on table public.log_auditoria to authenticated;

drop policy if exists log_auditoria_admin_select on public.log_auditoria;
create policy log_auditoria_admin_select
on public.log_auditoria for select to authenticated
using (public.fn_e_admin());

create index if not exists log_auditoria_criado_em_idx
  on public.log_auditoria (criado_em desc);
create index if not exists log_auditoria_tabela_registo_idx
  on public.log_auditoria (tabela_afetada, registo_id, criado_em desc);
create index if not exists log_auditoria_utilizador_idx
  on public.log_auditoria (utilizador_id, criado_em desc)
  where utilizador_id is not null;

-- Instalação idempotente: tabelas ausentes são ignoradas e só são aceites
-- tabelas reais/particionadas com uma coluna id do tipo UUID.
do $$
declare
  v_tabela text;
  v_tabelas constant text[] := array[
    -- Acessos e responsabilidades
    'utilizadores', 'administradores_plataforma', 'obra_responsaveis',
    -- Obras, contratos e planeamento
    'obras', 'contratos', 'fases', 'planeamento_fases_resumo',
    'planeamento_itens', 'planeamento_itens_dependencias', 'alteracoes_tee',
    'investimentos', 'impactos_obra',
    -- Compras, subempreitadas e pagamentos
    'consultas_subempreitada', 'consultas_subempreitada_itens',
    'consultas_subempreitada_candidatos',
    'consultas_subempreitada_candidatos_itens',
    'subempreitadas', 'pagamentos_subempreitada',
    -- Faturação e tesouraria
    'faturas', 'faturas_itens', 'faturas_guias',
    'faturacao', 'faturacao_autos_medicao',
    'autos_medicao', 'autos_medicao_itens',
    'debitos_diretos', 'debitos_diretos_lancamentos',
    'despesas_estaleiro', 'lancamentos_mao_obra',
    -- Equipa e distribuição operacional
    'colaboradores', 'colaboradores_contratos', 'ausencias',
    'horas_extraordinarias', 'quadro_pessoal_alocacao', 'viaturas'
  ];
begin
  foreach v_tabela in array v_tabelas loop
    if exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      join pg_attribute a on a.attrelid = c.oid
      join pg_type t on t.oid = a.atttypid
      where n.nspname = 'public'
        and c.relname = v_tabela
        and c.relkind in ('r', 'p')
        and a.attname = 'id'
        and not a.attisdropped
        and t.typname = 'uuid'
    ) then
      execute format('drop trigger if exists %I on public.%I',
        'trg_auditoria_' || v_tabela, v_tabela);
      execute format(
        'create trigger %I after insert or update or delete on public.%I '
        'for each row execute function public.fn_registar_log_auditoria(''id'')',
        'trg_auditoria_' || v_tabela,
        v_tabela
      );
    end if;
  end loop;
end;
$$;

commit;

-- Validação: deve devolver policy_ativa=true e uma lista de triggers.
select
  exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'log_auditoria'
      and policyname = 'log_auditoria_admin_select'
  ) as policy_ativa,
  count(*) filter (where not t.tgisinternal) as total_triggers,
  array_agg(c.relname order by c.relname)
    filter (where not t.tgisinternal) as tabelas_auditadas
from pg_trigger t
join pg_class c on c.oid = t.tgrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and t.tgname like 'trg_auditoria_%';
