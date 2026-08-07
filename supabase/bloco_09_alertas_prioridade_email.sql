-- PRIMELINE | Bloco 9 - canal dos alertas e pedidos semanais de horas.
-- O envio SMTP NÃO é configurado por esta migração. `enviar_email` é apenas
-- a sinalização consumível pelo serviço de email quando este for instalado.

begin;

alter table public.alertas
  add column if not exists enviar_email boolean not null default false;

create or replace function public.fn_definir_canal_alerta()
returns trigger
language plpgsql
set search_path = public
as $function$
begin
  new.enviar_email := new.tipo = any (array[
    'pedido_semanal_horas'::text,
    'informacao_reuniao_semanal'::text,
    'informacao_reuniao_producao'::text
  ]);
  return new;
end;
$function$;

drop trigger if exists trg_definir_canal_alerta on public.alertas;
create trigger trg_definir_canal_alerta
before insert or update of tipo, enviar_email
on public.alertas
for each row
execute function public.fn_definir_canal_alerta();

-- Corrige também os registos preexistentes: só estas duas famílias de alerta
-- ficam preparadas para email.
update public.alertas
set enviar_email = tipo = any (array[
  'pedido_semanal_horas'::text,
  'informacao_reuniao_semanal'::text,
  'informacao_reuniao_producao'::text
]);

create or replace function public.fn_criar_pedidos_horas_semanais(
  p_data date default current_date
)
returns integer
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_inseridos integer := 0;
begin
  -- Sexta-feira (ISO 5). A data é parâmetro para permitir testes controlados.
  if extract(isodow from p_data) <> 5 then
    return 0;
  end if;

  insert into public.alertas (
    empresa_id,
    obra_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado,
    enviar_email
  )
  select
    o.empresa_id,
    o.id,
    'pedido_semanal_horas',
    'obras',
    o.id,
    'Registo semanal de horas · Obra ' || coalesce(o.numero::text, 'sem número'),
    'Confirme e registe as horas da equipa relativas à semana que termina em '
      || to_char(p_data, 'DD/MM/YYYY') || '.',
    p_data,
    0,
    p_data,
    'diretor_obra',
    'pendente',
    true
  from public.obras o
  where o.situacao = 'em_curso'
    and exists (
      select 1
      from public.obra_responsaveis r
      where r.obra_id = o.id
        and r.papel = 'diretor_obra'
    )
  on conflict do nothing;

  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$function$;

revoke all
on function public.fn_criar_pedidos_horas_semanais(date)
from public, anon, authenticated;

-- Ponto de entrada para as futuras informações da Reunião Semanal. Cria o
-- alerta na plataforma e marca-o para email, sem efetuar qualquer envio.
create or replace function public.fn_criar_alerta_reuniao_semanal(
  p_obra_id uuid,
  p_titulo text,
  p_descricao text,
  p_data_gatilho date default current_date
)
returns uuid
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_alerta_id uuid;
  v_empresa_id uuid;
begin
  if not (
    public.fn_e_admin()
    or public.fn_pode_editar_obra(p_obra_id)
  ) then
    raise exception 'Sem permissão para comunicar informações desta obra.';
  end if;

  if nullif(btrim(p_titulo), '') is null then
    raise exception 'O título da informação é obrigatório.';
  end if;

  select o.empresa_id
    into v_empresa_id
  from public.obras o
  where o.id = p_obra_id;

  if v_empresa_id is null then
    raise exception 'Obra não encontrada.';
  end if;

  insert into public.alertas (
    empresa_id,
    obra_id,
    tipo,
    entidade_tipo,
    entidade_id,
    titulo,
    descricao,
    data_evento_referencia,
    antecedencia_dias,
    data_gatilho,
    destinatario_role,
    estado,
    enviar_email
  ) values (
    v_empresa_id,
    p_obra_id,
    'informacao_reuniao_semanal',
    'obras',
    p_obra_id,
    btrim(p_titulo),
    nullif(btrim(p_descricao), ''),
    p_data_gatilho,
    0,
    p_data_gatilho,
    'diretor_obra',
    'pendente',
    true
  )
  on conflict (
    tipo,
    entidade_tipo,
    entidade_id,
    data_evento_referencia,
    (coalesce(antecedencia_dias, -1))
  ) do update
    set titulo = excluded.titulo,
        descricao = excluded.descricao,
        data_gatilho = excluded.data_gatilho,
        estado = 'pendente',
        enviar_email = true
  returning id into v_alerta_id;

  return v_alerta_id;
end;
$function$;

revoke all
on function public.fn_criar_alerta_reuniao_semanal(uuid, text, text, date)
from public, anon;
grant execute
on function public.fn_criar_alerta_reuniao_semanal(uuid, text, text, date)
to authenticated;

-- Integra o pedido semanal no mesmo job diário já existente.
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
  v_pedidos_horas integer := 0;
begin
  if to_regprocedure(
    'public.fn_verificar_congelamentos_pendentes()'
  ) is not null then
    execute
      'select to_jsonb(public.fn_verificar_congelamentos_pendentes())'
    into v_baselines;
  end if;

  if to_regprocedure(
    'public.fn_verificar_primeiras_consultas_medicina()'
  ) is not null then
    v_primeiras_consultas :=
      public.fn_verificar_primeiras_consultas_medicina();
  end if;

  if to_regprocedure(
    'public.fn_verificar_alertas_vencimento()'
  ) is not null then
    v_vencimentos :=
      public.fn_verificar_alertas_vencimento();
  end if;

  if to_regprocedure(
    'public.fn_verificar_alertas_seguro_viaturas()'
  ) is not null then
    v_seguros :=
      public.fn_verificar_alertas_seguro_viaturas();
  end if;

  if to_regprocedure(
    'public.fn_verificar_alertas_fim_contrato()'
  ) is not null then
    perform public.fn_verificar_alertas_fim_contrato();
  end if;

  v_pedidos_horas := public.fn_criar_pedidos_horas_semanais(current_date);

  return jsonb_build_object(
    'baselines', v_baselines,
    'primeiras_consultas_criadas', v_primeiras_consultas,
    'alertas_vencimento_criados', v_vencimentos,
    'alertas_seguro_criados', v_seguros,
    'contratos_trabalho_verificados', true,
    'pedidos_horas_criados', v_pedidos_horas
  );
end;
$function$;

revoke all
on function public.fn_executar_rotinas_diarias()
from public, anon, authenticated;

commit;

select
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'alertas'
      and column_name = 'enviar_email'
  ) as coluna_email,
  to_regprocedure(
    'public.fn_criar_pedidos_horas_semanais(date)'
  ) is not null as pedidos_semanais,
  to_regprocedure(
    'public.fn_criar_alerta_reuniao_semanal(uuid,text,text,date)'
  ) is not null as alerta_reuniao,
  to_regprocedure(
    'public.fn_executar_rotinas_diarias()'
  ) is not null as rotina_diaria,
  false as smtp_configurado;
