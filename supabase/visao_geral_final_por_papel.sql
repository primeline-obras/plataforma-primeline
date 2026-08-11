-- Primeline | Visão Geral final por papel e lembretes da Equipa Técnica
-- Executar uma vez no SQL Editor do Supabase.

begin;

-- Alertas globais da Equipa Técnica são pessoais. Os restantes continuam
-- limitados à obra, ao Financeiro ou à Administração/Gerência.
drop policy if exists pl_alertas_select on public.alertas;
create policy pl_alertas_select
on public.alertas for select to authenticated
using (
  public.fn_e_admin()
  or public.fn_e_administrativo()
  or (
    public.fn_e_financeiro()
    and destinatario_role in ('financeiro', 'tesouraria')
  )
  or (
    obra_id is not null
    and public.fn_pode_ver_obra(obra_id)
  )
  or (
    entidade_tipo = 'utilizadores'
    and entidade_id = public.fn_utilizador_atual_id()
    and tipo in (
      'pedido_mensal_horas',
      'pedido_semanal_horas',
      'informacao_reuniao_semanal',
      'informacao_reuniao_producao'
    )
  )
);

create or replace function public.fn_criar_lembretes_equipa_tecnica(
  p_data date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_primeiro_util date;
  v_horas integer := 0;
  v_rsp integer := 0;
begin
  v_primeiro_util := date_trunc('month', p_data)::date;
  if extract(isodow from v_primeiro_util) = 6 then
    v_primeiro_util := v_primeiro_util + 2;
  elsif extract(isodow from v_primeiro_util) = 7 then
    v_primeiro_util := v_primeiro_util + 1;
  end if;

  if p_data = v_primeiro_util then
    insert into public.alertas (
      empresa_id, obra_id, tipo, entidade_tipo, entidade_id, titulo,
      descricao, data_evento_referencia, antecedencia_dias, data_gatilho,
      destinatario_role, estado, enviar_email
    )
    select distinct
      u.empresa_id, null, 'pedido_mensal_horas', 'utilizadores', u.id,
      'Enviar horas ao Administrativo',
      'Envie ao Administrativo as horas relativas ao mês anterior.',
      p_data, 0, p_data, u.funcao, 'pendente', true
    from public.utilizadores u
    where coalesce(u.ativo, true)
      and exists (
        select 1 from public.obra_responsaveis r
        where r.utilizador_id = u.id
          and r.papel in ('diretor_obra', 'adjunto', 'preparador')
      )
    on conflict do nothing;
    get diagnostics v_horas = row_count;
  end if;

  -- Quinta-feira (ISO 4): pedido de preparação dos dados da RSP.
  if extract(isodow from p_data) = 4 then
    insert into public.alertas (
      empresa_id, obra_id, tipo, entidade_tipo, entidade_id, titulo,
      descricao, data_evento_referencia, antecedencia_dias, data_gatilho,
      destinatario_role, estado, enviar_email
    )
    select distinct
      u.empresa_id, null, 'informacao_reuniao_semanal', 'utilizadores', u.id,
      'Enviar dados para a RSP',
      'Atualize e envie os dados necessários para a Reunião Semanal de Produção.',
      p_data, 0, p_data, u.funcao, 'pendente', true
    from public.utilizadores u
    where coalesce(u.ativo, true)
      and exists (
        select 1 from public.obra_responsaveis r
        where r.utilizador_id = u.id
          and r.papel in ('diretor_obra', 'adjunto', 'preparador')
      )
    on conflict do nothing;
    get diagnostics v_rsp = row_count;
  end if;

  return jsonb_build_object('horas', v_horas, 'rsp', v_rsp);
end;
$function$;

revoke all on function public.fn_criar_lembretes_equipa_tecnica(date)
from public, anon, authenticated;

-- Mantém todas as verificações diárias já existentes e acrescenta os dois
-- lembretes acima. Cada chamada opcional é protegida para instalações parciais.
create or replace function public.fn_executar_rotinas_diarias()
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_baselines jsonb := null;
  v_primeiras_consultas integer := 0;
  v_vencimentos integer := 0;
  v_seguros integer := 0;
  v_equipa_tecnica jsonb := '{}'::jsonb;
  v_imoveis_orcamentos jsonb := '{}'::jsonb;
begin
  if to_regprocedure('public.fn_verificar_congelamentos_pendentes()') is not null then
    execute 'select to_jsonb(public.fn_verificar_congelamentos_pendentes())' into v_baselines;
  end if;
  if to_regprocedure('public.fn_verificar_primeiras_consultas_medicina()') is not null then
    v_primeiras_consultas := public.fn_verificar_primeiras_consultas_medicina();
  end if;
  if to_regprocedure('public.fn_verificar_alertas_vencimento()') is not null then
    v_vencimentos := public.fn_verificar_alertas_vencimento();
  end if;
  if to_regprocedure('public.fn_verificar_alertas_seguro_viaturas()') is not null then
    v_seguros := public.fn_verificar_alertas_seguro_viaturas();
  end if;
  if to_regprocedure('public.fn_verificar_alertas_fim_contrato()') is not null then
    perform public.fn_verificar_alertas_fim_contrato();
  end if;
  if to_regprocedure('public.fn_verificar_alertas_imoveis_orcamentos(date)') is not null then
    v_imoveis_orcamentos := public.fn_verificar_alertas_imoveis_orcamentos(current_date);
  end if;

  v_equipa_tecnica := public.fn_criar_lembretes_equipa_tecnica(current_date);

  return jsonb_build_object(
    'baselines', v_baselines,
    'primeiras_consultas_criadas', v_primeiras_consultas,
    'alertas_vencimento_criados', v_vencimentos,
    'alertas_seguro_criados', v_seguros,
    'contratos_trabalho_verificados', true,
    'equipa_tecnica', v_equipa_tecnica,
    'imoveis_orcamentos', v_imoveis_orcamentos
  );
end;
$function$;

revoke all on function public.fn_executar_rotinas_diarias()
from public, anon, authenticated;

commit;

select
  to_regprocedure('public.fn_criar_lembretes_equipa_tecnica(date)') is not null as lembretes_equipa_tecnica,
  to_regprocedure('public.fn_executar_rotinas_diarias()') is not null as rotina_diaria,
  exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'alertas'
      and policyname = 'pl_alertas_select'
  ) as politica_alertas;
