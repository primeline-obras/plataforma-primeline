-- Salas de Reuniao: sala unica, participantes e avisos informativos pessoais.
begin;

create table if not exists public.reservas_salas_participantes (
  id uuid primary key default gen_random_uuid(),
  reserva_id uuid not null references public.reservas_salas(id) on delete cascade,
  utilizador_id uuid not null references public.utilizadores(id),
  criado_em timestamptz not null default now(),
  constraint reservas_salas_participantes_unico unique (reserva_id, utilizador_id)
);

alter table public.alertas
  add column if not exists destinatario_utilizador_id uuid references public.utilizadores(id),
  add column if not exists expira_em timestamptz;

alter table public.reservas_salas_participantes enable row level security;
revoke all on public.reservas_salas_participantes from anon;
grant select on public.reservas_salas_participantes to authenticated;

drop policy if exists reservas_salas_participantes_select on public.reservas_salas_participantes;
create policy reservas_salas_participantes_select
on public.reservas_salas_participantes for select to authenticated
using (
  utilizador_id = public.fn_utilizador_atual_id()
  or exists (
    select 1 from public.reservas_salas r
    where r.id = reserva_id and r.criado_por = public.fn_utilizador_atual_id()
  )
);

-- Encarregados deixam de consultar e criar reservas. Os restantes utilizadores
-- autenticados continuam com acesso à agenda da única sala.
drop policy if exists salas_reuniao_select on public.salas_reuniao;
create policy salas_reuniao_select on public.salas_reuniao for select to authenticated
using (not exists (
  select 1 from public.utilizadores u
  where u.id = public.fn_utilizador_atual_id() and u.funcao = 'encarregado'
));

drop policy if exists reservas_salas_select on public.reservas_salas;
create policy reservas_salas_select on public.reservas_salas for select to authenticated
using (not exists (
  select 1 from public.utilizadores u
  where u.id = public.fn_utilizador_atual_id() and u.funcao = 'encarregado'
));

drop policy if exists reservas_salas_insert on public.reservas_salas;
revoke insert on public.reservas_salas from authenticated;

create or replace function public.fn_criar_reserva_sala(
  p_titulo text,
  p_data date,
  p_hora_inicio time,
  p_hora_fim time,
  p_participantes uuid[] default '{}'::uuid[]
)
returns public.reservas_salas
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_atual public.utilizadores;
  v_destinatario public.utilizadores;
  v_reserva public.reservas_salas;
  v_sala_id uuid;
  v_utilizador_id uuid;
  v_participante_id uuid;
  v_expira_em timestamptz;
begin
  select * into v_atual from public.utilizadores
  where id = public.fn_utilizador_atual_id() and coalesce(ativo, true);
  if not found then raise exception 'Utilizador autenticado sem perfil ativo.'; end if;
  if v_atual.funcao = 'encarregado' then raise exception 'O Encarregado não tem acesso às Salas de Reunião.'; end if;
  if nullif(btrim(p_titulo), '') is null then raise exception 'Indique o título da reunião.'; end if;
  if p_hora_fim <= p_hora_inicio then raise exception 'A hora de fim tem de ser posterior à hora de início.'; end if;

  select id into v_sala_id from public.salas_reuniao
  where empresa_id = v_atual.empresa_id order by criado_em, id limit 1;
  if v_sala_id is null then raise exception 'Não existe uma sala de reunião configurada.'; end if;

  insert into public.reservas_salas (sala_id, titulo, data, hora_inicio, hora_fim, criado_por)
  values (v_sala_id, btrim(p_titulo), p_data, p_hora_inicio, p_hora_fim, v_atual.id)
  returning * into v_reserva;

  v_expira_em := (p_data + p_hora_fim) at time zone 'Europe/Lisbon';
  for v_utilizador_id in select distinct unnest(coalesce(p_participantes, '{}'::uuid[])) loop
    select * into v_destinatario from public.utilizadores
    where id = v_utilizador_id and empresa_id = v_atual.empresa_id
      and auth_user_id is not null and coalesce(ativo, true);
    if found then
      insert into public.reservas_salas_participantes (reserva_id, utilizador_id)
      values (v_reserva.id, v_destinatario.id)
      returning id into v_participante_id;

      insert into public.alertas (
        empresa_id, obra_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
        data_evento_referencia, antecedencia_dias, data_gatilho, destinatario_role,
        estado, enviar_email, destinatario_utilizador_id, expira_em
      ) values (
        v_atual.empresa_id, null, 'reserva_sala', 'reservas_salas_participantes',
        v_participante_id, 'Reunião: ' || v_reserva.titulo,
        to_char(p_data, 'DD/MM/YYYY') || ' às ' || to_char(p_hora_inicio, 'HH24:MI') ||
          ' · Marcada por ' || v_atual.nome || '.',
        p_data, 0, current_date, v_destinatario.funcao, 'pendente', false,
        v_destinatario.id, v_expira_em
      );
    end if;
  end loop;
  return v_reserva;
end;
$function$;

revoke all on function public.fn_criar_reserva_sala(text,date,time,time,uuid[]) from public, anon;
grant execute on function public.fn_criar_reserva_sala(text,date,time,time,uuid[]) to authenticated;

-- Os alertas de reunião são pessoais e deixam de ser visíveis quando a hora
-- final passa. Os restantes alertas mantêm exatamente as regras atuais.
drop policy if exists pl_alertas_select on public.alertas;
create policy pl_alertas_select on public.alertas for select to authenticated
using (
  (
    tipo = 'reserva_sala'
    and destinatario_utilizador_id = public.fn_utilizador_atual_id()
    and expira_em > now()
  )
  or (
    tipo is distinct from 'reserva_sala'
    and (
      public.fn_e_admin()
      or public.fn_e_administrativo()
      or (public.fn_e_financeiro() and destinatario_role in ('financeiro', 'tesouraria'))
      or (obra_id is not null and public.fn_pode_ver_obra(obra_id))
      or (
        entidade_tipo = 'utilizadores'
        and entidade_id = public.fn_utilizador_atual_id()
        and tipo in ('pedido_mensal_horas','pedido_semanal_horas','informacao_reuniao_semanal','informacao_reuniao_producao')
      )
    )
  )
);

do $$ begin
  if to_regprocedure('public.fn_registar_log_auditoria(text)') is not null then
    drop trigger if exists trg_auditoria_reservas_salas_participantes on public.reservas_salas_participantes;
    create trigger trg_auditoria_reservas_salas_participantes
    after insert or update or delete on public.reservas_salas_participantes
    for each row execute function public.fn_registar_log_auditoria('id');
  end if;
end $$;

commit;

select
  to_regclass('public.reservas_salas_participantes') is not null as tabela_participantes,
  to_regprocedure('public.fn_criar_reserva_sala(text,date,time,time,uuid[])') is not null as rpc_reserva,
  count(*) filter (where policyname = 'pl_alertas_select') as politica_alertas,
  count(*) filter (where policyname = 'reservas_salas_select') as politica_reservas
from pg_policies
where schemaname = 'public' and tablename in ('alertas', 'reservas_salas');
