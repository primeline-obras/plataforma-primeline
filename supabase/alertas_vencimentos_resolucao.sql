-- PRIMELINE | Alertas de vencimento e resolução explícita.
-- Executar uma vez no SQL Editor com uma conta owner.

begin;

-- Reflete no repositório a alteração já aplicada diretamente no Supabase.
alter table public.documentos
  drop constraint if exists documentos_entidade_tipo_check;
alter table public.documentos
  add constraint documentos_entidade_tipo_check
  check (entidade_tipo = any (array[
    'colaborador'::text, 'viatura'::text, 'empresa'::text,
    'auto_medicao'::text, 'autos_medicao'::text, 'faturacao'::text
  ]));

-- O trigger antigo eliminava/recriava alertas pendentes ao editar o documento.
-- A partir daqui, ver/editar nunca resolve alertas; só a RPC abaixo o pode fazer.
drop trigger if exists trg_alerta_validade_documento on public.documentos;

create or replace function public.fn_resolver_alerta(p_alerta_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_alerta public.alertas%rowtype;
begin
  select * into v_alerta
  from public.alertas
  where id = p_alerta_id
  for update;

  if not found then
    raise exception 'Alerta não encontrado.';
  end if;

  if not (
    public.fn_e_admin()
    or public.fn_e_administrativo()
    or (v_alerta.destinatario_role in ('financeiro', 'tesouraria') and public.fn_e_financeiro())
    or (v_alerta.obra_id is not null and public.fn_pode_editar_obra(v_alerta.obra_id))
  ) then
    raise exception 'Sem permissão para resolver este alerta.';
  end if;

  if v_alerta.estado = 'pendente' then
    update public.alertas
    set estado = 'resolvido'
    where id = p_alerta_id;
  end if;

  select * into v_alerta from public.alertas where id = p_alerta_id;
  return to_jsonb(v_alerta);
end;
$$;

revoke all on function public.fn_resolver_alerta(uuid) from public, anon;
grant execute on function public.fn_resolver_alerta(uuid) to authenticated;

create or replace function public.fn_verificar_alertas_vencimento()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empresa_id uuid;
  v_inseridos integer := 0;
  v_linhas integer := 0;
begin
  select id into v_empresa_id from public.empresas order by id limit 1;
  if v_empresa_id is null then
    raise exception 'Não existe empresa configurada para associar os alertas.';
  end if;

  -- Documentos pessoais: 30 dias.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    d.empresa_id, 'validade_documento', 'documentos', d.id,
    'Documento a vencer: ' || c.nome,
    d.tipo_documento || ' · validade em ' || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade, 30, d.data_validade - 30, 'administrativo', 'pendente'
  from public.documentos d
  join public.colaboradores c on c.id = d.entidade_id and c.data_saida is null
  where d.entidade_tipo = 'colaborador'
    and d.data_validade is not null
    and d.data_validade - 30 <= current_date
    and not exists (
      select 1 from public.alertas a
      where a.tipo = 'validade_documento'
        and a.entidade_tipo = 'documentos' and a.entidade_id = d.id
        and a.antecedencia_dias = 30
        and a.data_evento_referencia = d.data_validade
    );
  get diagnostics v_linhas = row_count;
  v_inseridos := v_inseridos + v_linhas;

  -- Documentos da empresa: alertas independentes a 15, 7 e 3 dias.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    d.empresa_id, 'validade_documento_empresa', 'documentos', d.id,
    'Documento da empresa a vencer em ' || limiar.dias || ' dias',
    d.tipo_documento || ' · validade em ' || to_char(d.data_validade, 'DD/MM/YYYY'),
    d.data_validade, limiar.dias, d.data_validade - limiar.dias,
    'administrativo', 'pendente'
  from public.documentos d
  cross join (values (15), (7), (3)) as limiar(dias)
  where d.entidade_tipo = 'empresa'
    and d.data_validade is not null
    and lower(d.tipo_documento) ~ '(certid|rcbe|inpi|seguro.*acidente|seguro.*responsabilidade)'
    and d.data_validade - limiar.dias <= current_date
    and not exists (
      select 1 from public.alertas a
      where a.tipo = 'validade_documento_empresa'
        and a.entidade_tipo = 'documentos' and a.entidade_id = d.id
        and a.antecedencia_dias = limiar.dias
        and a.data_evento_referencia = d.data_validade
    );
  get diagnostics v_linhas = row_count;
  v_inseridos := v_inseridos + v_linhas;

  -- EPI: 30 dias.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    v_empresa_id, 'validade_epi', 'epis', e.id,
    'EPI a vencer: ' || c.nome,
    coalesce(e.tipo_equipamento, 'EPI') || ' · validade em ' || to_char(e.data_validade, 'DD/MM/YYYY'),
    e.data_validade, 30, e.data_validade - 30, 'administrativo', 'pendente'
  from public.epis e
  join public.colaboradores c on c.id = e.colaborador_id and c.data_saida is null
  where e.data_validade is not null
    and e.data_validade - 30 <= current_date
    and not exists (
      select 1 from public.alertas a
      where a.tipo = 'validade_epi' and a.entidade_tipo = 'epis' and a.entidade_id = e.id
        and a.antecedencia_dias = 30 and a.data_evento_referencia = e.data_validade
    );
  get diagnostics v_linhas = row_count;
  v_inseridos := v_inseridos + v_linhas;

  -- Medicina do trabalho: 30 dias antes da próxima consulta.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    v_empresa_id, 'medicina_trabalho_vencimento', 'medicina_trabalho', m.id,
    'Consulta de medicina a vencer: ' || c.nome,
    'Próxima consulta em ' || to_char(m.data_proxima_consulta, 'DD/MM/YYYY'),
    m.data_proxima_consulta, 30, m.data_proxima_consulta - 30,
    'administrativo', 'pendente'
  from public.medicina_trabalho m
  join public.colaboradores c on c.id = m.colaborador_id and c.data_saida is null
  where m.data_proxima_consulta is not null
    and m.data_proxima_consulta - 30 <= current_date
    and not exists (
      select 1 from public.alertas a
      where a.tipo = 'medicina_trabalho_vencimento'
        and a.entidade_tipo = 'medicina_trabalho' and a.entidade_id = m.id
        and a.antecedencia_dias = 30
        and a.data_evento_referencia = m.data_proxima_consulta
    );
  get diagnostics v_linhas = row_count;
  v_inseridos := v_inseridos + v_linhas;

  -- Inspeção de viaturas: 15 dias, usando data_inspecao_proxima.
  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    v.empresa_id, 'inspecao_viatura', 'viaturas', v.id,
    'Inspeção da viatura a vencer: ' || coalesce(v.matricula, v.marca_modelo, 'Viatura'),
    coalesce(v.marca_modelo || ' · ', '') || 'inspeção em ' || to_char(v.data_inspecao_proxima, 'DD/MM/YYYY'),
    v.data_inspecao_proxima, 15, v.data_inspecao_proxima - 15,
    'administrativo', 'pendente'
  from public.viaturas v
  where v.data_inspecao_proxima is not null
    and v.data_inspecao_proxima - 15 <= current_date
    and not exists (
      select 1 from public.alertas a
      where a.tipo = 'inspecao_viatura' and a.entidade_tipo = 'viaturas' and a.entidade_id = v.id
        and a.antecedencia_dias = 15
        and a.data_evento_referencia = v.data_inspecao_proxima
    );
  get diagnostics v_linhas = row_count;
  v_inseridos := v_inseridos + v_linhas;

  return v_inseridos;
end;
$$;

revoke all on function public.fn_verificar_alertas_vencimento() from public, anon, authenticated;

-- Substitui a versão do Bloco 1: nunca elimina o alerta automaticamente.
-- Depois de criado, só fn_resolver_alerta pode retirar-lhe o estado pendente.
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
  select id into v_empresa_id from public.empresas order by id limit 1;
  if v_empresa_id is null then
    raise exception 'Não existe empresa configurada para associar os alertas de medicina do trabalho.';
  end if;

  insert into public.alertas (
    empresa_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
    data_evento_referencia, antecedencia_dias, data_gatilho,
    destinatario_role, estado
  )
  select
    v_empresa_id, 'primeira_consulta_medicina', 'colaboradores', c.id,
    'Marcar primeira consulta: ' || c.nome,
    'O colaborador completou 30 dias desde a admissão sem registo em Medicina do Trabalho.',
    c.data_admissao + 30, 0, c.data_admissao + 30, 'administrativo', 'pendente'
  from public.colaboradores c
  where c.data_saida is null
    and c.data_admissao is not null
    and c.data_admissao + 30 <= current_date
    and not exists (
      select 1 from public.medicina_trabalho m where m.colaborador_id = c.id
    )
    and not exists (
      select 1 from public.alertas a
      where a.tipo = 'primeira_consulta_medicina'
        and a.entidade_tipo = 'colaboradores' and a.entidade_id = c.id
        and a.data_evento_referencia = c.data_admissao + 30
    );

  get diagnostics v_inseridos = row_count;
  return v_inseridos;
end;
$$;

revoke all on function public.fn_verificar_primeiras_consultas_medicina()
  from public, anon, authenticated;

-- Consolida todas as verificações no único job diário já existente.
create or replace function public.fn_executar_rotinas_diarias()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_primeiras_consultas integer := 0;
  v_vencimentos integer := 0;
begin
  perform public.fn_verificar_congelamentos_pendentes();
  v_primeiras_consultas := public.fn_verificar_primeiras_consultas_medicina();
  v_vencimentos := public.fn_verificar_alertas_vencimento();
  return jsonb_build_object(
    'primeiras_consultas', v_primeiras_consultas,
    'alertas_vencimento', v_vencimentos
  );
end;
$$;

revoke all on function public.fn_executar_rotinas_diarias() from public, anon, authenticated;

do $migration$
declare
  v_job_id bigint;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise exception 'pg_cron não está ativo. A migração foi cancelada.';
  end if;

  if not exists (
    select 1 from cron.job
    where jobname = 'primeline-congelar-baselines-diario' and active
  ) then
    raise exception 'O job diário existente não está ativo. A migração foi cancelada.';
  end if;

  -- Remove o job separado do Bloco 1: a função passa para a rotina consolidada.
  for v_job_id in
    select jobid from cron.job where jobname = 'primeline-alertar-primeira-consulta-diario'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  for v_job_id in
    select jobid from cron.job where jobname = 'primeline-congelar-baselines-diario'
  loop
    perform cron.unschedule(v_job_id);
  end loop;

  perform cron.schedule(
    'primeline-congelar-baselines-diario',
    '15 3 * * *',
    $job$select public.fn_executar_rotinas_diarias();$job$
  );
end;
$migration$;

-- Ativa imediatamente todos os alertas cujo limiar já foi atingido.
select public.fn_verificar_alertas_vencimento();

commit;

select jobname, schedule, active, command
from cron.job
where jobname like 'primeline-%diario'
order by jobname;
