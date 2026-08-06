-- PRIMELINE | Alerta diário para a primeira consulta de medicina do trabalho.
-- Executar uma vez no SQL Editor com uma conta owner.
-- A migração exige pg_cron ativo e falha explicitamente se o mecanismo não existir.

begin;

create or replace function public.fn_verificar_primeiras_consultas_medicina()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa_id uuid;
  v_inseridos integer := 0;
begin
  select id into v_empresa_id
  from public.empresas
  order by id
  limit 1;

  if v_empresa_id is null then
    raise exception 'Não existe empresa configurada para associar os alertas de medicina do trabalho.';
  end if;

  -- Se a pessoa sair ou já tiver consulta, o lembrete pendente deixa de fazer sentido.
  delete from public.alertas a
  using public.colaboradores c
  where a.tipo = 'primeira_consulta_medicina'
    and a.entidade_tipo = 'colaboradores'
    and a.entidade_id = c.id
    and a.estado = 'pendente'
    and (
      c.data_saida is not null
      or exists (
        select 1
        from public.medicina_trabalho m
        where m.colaborador_id = c.id
      )
    );

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    v_empresa_id,
    'primeira_consulta_medicina',
    'colaboradores',
    c.id,
    'Marcar primeira consulta: ' || c.nome,
    'O colaborador completou 30 dias desde a admissão sem registo em Medicina do Trabalho.',
    c.data_admissao + 30,
    0,
    c.data_admissao + 30,
    'administrativo',
    'pendente'
  from public.colaboradores c
  where c.data_saida is null
    and c.data_admissao is not null
    and c.data_admissao + 30 <= current_date
    and not exists (
      select 1
      from public.medicina_trabalho m
      where m.colaborador_id = c.id
    )
    and not exists (
      select 1
      from public.alertas a
      where a.tipo = 'primeira_consulta_medicina'
        and a.entidade_tipo = 'colaboradores'
        and a.entidade_id = c.id
    );

  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$$;

revoke all on function public.fn_verificar_primeiras_consultas_medicina()
  from public, anon, authenticated;

do $migration$
declare
  v_job_id bigint;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception 'pg_cron não está ativo. A migração foi cancelada sem criar uma alternativa de agendamento.';
  end if;

  if not exists (
    select 1 from cron.job
    where jobname = 'primeline-congelar-baselines-diario'
      and active
  ) then
    raise exception 'O job diário de baseline não está ativo. Confirme o pg_cron antes de agendar alertas de medicina.';
  end if;

  for v_job_id in
    select jobid from cron.job where jobname = 'primeline-alertar-primeira-consulta-diario'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'primeline-alertar-primeira-consulta-diario',
    '20 3 * * *',
    $job$select public.fn_verificar_primeiras_consultas_medicina();$job$
  );
end;
$migration$;

-- Cria imediatamente os lembretes já vencidos; execuções futuras ficam a cargo do cron.
select public.fn_verificar_primeiras_consultas_medicina();

commit;

select
  j.jobname,
  j.schedule,
  j.active,
  j.command
from cron.job j
where j.jobname in (
  'primeline-congelar-baselines-diario',
  'primeline-alertar-primeira-consulta-diario'
)
order by j.jobname;
