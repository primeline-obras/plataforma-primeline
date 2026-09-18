-- PRIMELINE GO | Agenda de compromissos com colegas
begin;

create table if not exists public.compromissos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas(id),
  titulo text not null,
  data date not null,
  hora_inicio time,
  hora_fim time,
  dia_inteiro boolean not null default false,
  categoria text not null default 'outro' check (categoria in ('reuniao','visita_obra','prazo','fornecedor','cliente','outro')),
  obra_id uuid references public.obras(id),
  responsavel_id uuid not null references public.utilizadores(id),
  criado_por uuid not null references public.utilizadores(id),
  local text,
  descricao text,
  prioridade text not null default 'normal' check (prioridade in ('normal','alta')),
  estado text not null default 'agendado' check (estado in ('agendado','concluido','cancelado')),
  lembrete_dias integer not null default 1 check (lembrete_dias in (0,1,7)),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  check ((dia_inteiro and hora_inicio is null and hora_fim is null) or (not dia_inteiro and hora_inicio is not null and hora_fim is not null and hora_fim > hora_inicio))
);

create table if not exists public.compromissos_participantes (
  compromisso_id uuid not null references public.compromissos(id) on delete cascade,
  utilizador_id uuid not null references public.utilizadores(id),
  criado_em timestamptz not null default now(),
  primary key (compromisso_id, utilizador_id)
);

create index if not exists compromissos_empresa_data_idx on public.compromissos(empresa_id,data,hora_inicio);
create index if not exists compromissos_participante_idx on public.compromissos_participantes(utilizador_id,compromisso_id);

alter table public.compromissos enable row level security;
alter table public.compromissos_participantes enable row level security;
revoke all on public.compromissos,public.compromissos_participantes from anon;
grant select on public.compromissos,public.compromissos_participantes to authenticated;

-- A RLS de utilizadores protege o diretório completo. Esta função expõe à
-- Agenda somente id, nome e função de contas ativas da mesma empresa.
create or replace function public.fn_listar_colegas_agenda()
returns table(id uuid,nome text,funcao text)
language sql stable security definer set search_path=public as $$
  select u.id,u.nome,u.funcao
  from public.utilizadores u
  join public.utilizadores atual on atual.id=public.fn_utilizador_atual_id()
  where coalesce(atual.ativo,true)
    and u.empresa_id=atual.empresa_id
    and coalesce(u.ativo,true)
    and u.id<>atual.id
  order by u.nome;
$$;
revoke all on function public.fn_listar_colegas_agenda() from public,anon;
grant execute on function public.fn_listar_colegas_agenda() to authenticated;

create or replace function public.fn_pode_ver_compromisso(p_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.compromissos c
    where c.id=p_id and c.empresa_id=(select empresa_id from public.utilizadores where id=public.fn_utilizador_atual_id())
      and (public.fn_e_admin() or c.criado_por=public.fn_utilizador_atual_id() or c.responsavel_id=public.fn_utilizador_atual_id()
        or exists(select 1 from public.compromissos_participantes p where p.compromisso_id=c.id and p.utilizador_id=public.fn_utilizador_atual_id()))
  );
$$;
revoke all on function public.fn_pode_ver_compromisso(uuid) from public,anon;
grant execute on function public.fn_pode_ver_compromisso(uuid) to authenticated;

drop policy if exists compromissos_select on public.compromissos;
create policy compromissos_select on public.compromissos for select to authenticated using (public.fn_pode_ver_compromisso(id));
drop policy if exists compromissos_participantes_select on public.compromissos_participantes;
create policy compromissos_participantes_select on public.compromissos_participantes for select to authenticated using (public.fn_pode_ver_compromisso(compromisso_id));

create or replace function public.fn_guardar_compromisso(
  p_compromisso_id uuid,p_titulo text,p_data date,p_hora_inicio time,p_hora_fim time,p_dia_inteiro boolean,
  p_categoria text,p_obra_id uuid,p_responsavel_id uuid,p_local text,p_descricao text,p_prioridade text,
  p_lembrete_dias integer,p_participantes uuid[]
) returns public.compromissos language plpgsql security definer set search_path=public as $$
declare v_atual public.utilizadores;v_row public.compromissos;v_dest public.utilizadores;v_id uuid;v_expira timestamptz;
begin
  select * into v_atual from public.utilizadores where id=public.fn_utilizador_atual_id() and coalesce(ativo,true);
  if not found then raise exception 'Utilizador autenticado sem perfil ativo.';end if;
  if nullif(btrim(p_titulo),'') is null then raise exception 'Indique o título do compromisso.';end if;
  if p_data is null then raise exception 'Indique a data do compromisso.';end if;
  if p_categoria not in ('reuniao','visita_obra','prazo','fornecedor','cliente','outro') then raise exception 'Categoria inválida.';end if;
  if p_prioridade not in ('normal','alta') or p_lembrete_dias not in (0,1,7) then raise exception 'Configuração do compromisso inválida.';end if;
  if not p_dia_inteiro and (p_hora_inicio is null or p_hora_fim is null or p_hora_fim<=p_hora_inicio) then raise exception 'Indique um horário válido.';end if;
  if not exists(select 1 from public.utilizadores where id=p_responsavel_id and empresa_id=v_atual.empresa_id and coalesce(ativo,true)) then raise exception 'Responsável inválido ou inativo.';end if;
  if p_obra_id is not null and not exists(select 1 from public.obras where id=p_obra_id and empresa_id=v_atual.empresa_id) then raise exception 'A obra não pertence à empresa.';end if;
  if p_compromisso_id is null then
    insert into public.compromissos(empresa_id,titulo,data,hora_inicio,hora_fim,dia_inteiro,categoria,obra_id,responsavel_id,criado_por,local,descricao,prioridade,lembrete_dias)
    values(v_atual.empresa_id,btrim(p_titulo),p_data,case when p_dia_inteiro then null else p_hora_inicio end,case when p_dia_inteiro then null else p_hora_fim end,p_dia_inteiro,p_categoria,p_obra_id,p_responsavel_id,v_atual.id,nullif(btrim(p_local),''),nullif(btrim(p_descricao),''),p_prioridade,p_lembrete_dias) returning * into v_row;
  else
    select * into v_row from public.compromissos where id=p_compromisso_id for update;
    if not found or v_row.empresa_id<>v_atual.empresa_id then raise exception 'O compromisso já não existe.';end if;
    if v_row.criado_por<>v_atual.id and v_row.responsavel_id<>v_atual.id and not public.fn_e_admin() then raise exception 'Sem permissão para editar este compromisso.' using errcode='42501';end if;
    update public.compromissos set titulo=btrim(p_titulo),data=p_data,hora_inicio=case when p_dia_inteiro then null else p_hora_inicio end,hora_fim=case when p_dia_inteiro then null else p_hora_fim end,dia_inteiro=p_dia_inteiro,categoria=p_categoria,obra_id=p_obra_id,responsavel_id=p_responsavel_id,local=nullif(btrim(p_local),''),descricao=nullif(btrim(p_descricao),''),prioridade=p_prioridade,lembrete_dias=p_lembrete_dias,atualizado_em=now() where id=p_compromisso_id returning * into v_row;
  end if;
  update public.alertas set estado='resolvido',expira_em=now() where tipo='compromisso_agenda' and entidade_tipo='compromissos' and entidade_id=v_row.id and estado='pendente';
  delete from public.compromissos_participantes where compromisso_id=v_row.id;
  insert into public.compromissos_participantes(compromisso_id,utilizador_id)
  select v_row.id,u.id from public.utilizadores u where u.id=any(coalesce(p_participantes,'{}'::uuid[])) and u.empresa_id=v_atual.empresa_id and coalesce(u.ativo,true) on conflict do nothing;
  v_expira:=(p_data+coalesce(case when p_dia_inteiro then time '23:59' else p_hora_fim end,time '23:59')) at time zone 'Europe/Lisbon';
  for v_id in select distinct id from (select p_responsavel_id id union select unnest(coalesce(p_participantes,'{}'::uuid[]))) d where id is not null and id<>v_atual.id loop
    select * into v_dest from public.utilizadores where id=v_id and empresa_id=v_atual.empresa_id and coalesce(ativo,true);
    if found then insert into public.alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,descricao,data_evento_referencia,antecedencia_dias,data_gatilho,destinatario_role,estado,enviar_email,destinatario_utilizador_id,expira_em)
      values(v_atual.empresa_id,p_obra_id,'compromisso_agenda','compromissos',v_row.id,'Compromisso: '||v_row.titulo,to_char(p_data,'DD/MM/YYYY')||case when p_dia_inteiro then ' · dia inteiro' else ' · '||to_char(p_hora_inicio,'HH24:MI')||'–'||to_char(p_hora_fim,'HH24:MI') end||' · Marcado por '||v_atual.nome||'.',p_data,p_lembrete_dias,p_data-p_lembrete_dias,v_dest.funcao,'pendente',false,v_dest.id,v_expira);end if;
  end loop;
  return v_row;
end;$$;

create or replace function public.fn_apagar_compromisso(p_compromisso_id uuid)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_atual public.utilizadores;v_row public.compromissos;
begin
  select * into v_atual from public.utilizadores where id=public.fn_utilizador_atual_id() and coalesce(ativo,true);
  if not found then raise exception 'Utilizador autenticado sem perfil ativo.';end if;
  select * into v_row from public.compromissos where id=p_compromisso_id and empresa_id=v_atual.empresa_id for update;
  if not found then raise exception 'O compromisso já não existe.';end if;
  if v_row.criado_por<>v_atual.id and v_row.responsavel_id<>v_atual.id and not public.fn_e_admin() then raise exception 'Sem permissão para apagar este compromisso.' using errcode='42501';end if;
  update public.alertas set estado='resolvido',expira_em=now() where tipo='compromisso_agenda' and entidade_tipo='compromissos' and entidade_id=p_compromisso_id and estado='pendente';delete from public.compromissos where id=p_compromisso_id;return true;end;$$;

revoke all on function public.fn_guardar_compromisso(uuid,text,date,time,time,boolean,text,uuid,uuid,text,text,text,integer,uuid[]) from public,anon;
revoke all on function public.fn_apagar_compromisso(uuid) from public,anon;
grant execute on function public.fn_guardar_compromisso(uuid,text,date,time,time,boolean,text,uuid,uuid,text,text,text,integer,uuid[]) to authenticated;
grant execute on function public.fn_apagar_compromisso(uuid) to authenticated;

drop policy if exists pl_alertas_select on public.alertas;
create policy pl_alertas_select on public.alertas for select to authenticated using (
  (tipo in ('reserva_sala','compromisso_agenda') and destinatario_utilizador_id=public.fn_utilizador_atual_id() and expira_em>now())
  or ((tipo is distinct from 'reserva_sala' and tipo is distinct from 'compromisso_agenda') and (public.fn_e_admin() or public.fn_e_administrativo() or (public.fn_e_financeiro() and destinatario_role in ('financeiro','tesouraria')) or (obra_id is not null and public.fn_pode_ver_obra(obra_id)) or (entidade_tipo='utilizadores' and entidade_id=public.fn_utilizador_atual_id() and tipo in ('pedido_mensal_horas','pedido_semanal_horas','informacao_reuniao_semanal','informacao_reuniao_producao'))))
);

do $$ begin
  if to_regprocedure('public.fn_registar_log_auditoria()') is not null then
    drop trigger if exists trg_auditoria_compromissos on public.compromissos;
    create trigger trg_auditoria_compromissos
    after insert or update or delete on public.compromissos
    for each row execute function public.fn_registar_log_auditoria('id');
    drop trigger if exists trg_auditoria_compromissos_participantes on public.compromissos_participantes;
    create trigger trg_auditoria_compromissos_participantes
    after insert or update or delete on public.compromissos_participantes
    for each row execute function public.fn_registar_log_auditoria('compromisso_id');
  end if;
end $$;

commit;
select
  to_regclass('public.compromissos') is not null as calendario_ativo,
  to_regprocedure('public.fn_guardar_compromisso(uuid,text,date,time without time zone,time without time zone,boolean,text,uuid,uuid,text,text,text,integer,uuid[])') is not null as colegas_ativos,
  to_regprocedure('public.fn_listar_colegas_agenda()') is not null as lista_colegas_ativa;
