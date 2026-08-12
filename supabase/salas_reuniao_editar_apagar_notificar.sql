-- Edição/eliminação de reservas pelo criador ou Administrativo/Gerência.
-- Os avisos são pessoais, informativos e expiram com o horário da reunião.
begin;

drop policy if exists reservas_salas_participantes_select on public.reservas_salas_participantes;
create policy reservas_salas_participantes_select on public.reservas_salas_participantes
for select to authenticated using (
  utilizador_id = public.fn_utilizador_atual_id()
  or public.fn_e_admin() or public.fn_e_administrativo()
  or exists (select 1 from public.reservas_salas r where r.id = reserva_id and r.criado_por = public.fn_utilizador_atual_id())
);

create or replace function public.fn_editar_reserva_sala(
  p_reserva_id uuid, p_titulo text, p_data date, p_hora_inicio time,
  p_hora_fim time, p_participantes uuid[] default '{}'::uuid[]
) returns public.reservas_salas
language plpgsql security definer set search_path = public
as $function$
declare
  v_atual public.utilizadores; v_reserva public.reservas_salas;
  v_destinatario public.utilizadores; v_id uuid; v_destinatarios uuid[];
  v_expira_em timestamptz; v_data_anterior date; v_hora_anterior time;
begin
  select * into v_atual from public.utilizadores where id=public.fn_utilizador_atual_id() and coalesce(ativo,true);
  if not found then raise exception 'Utilizador autenticado sem perfil ativo.'; end if;
  select * into v_reserva from public.reservas_salas where id=p_reserva_id for update;
  if not found then raise exception 'A reserva já não existe.'; end if;
  if v_reserva.criado_por is distinct from v_atual.id and not public.fn_e_admin() and not public.fn_e_administrativo() then raise exception 'Sem permissão para editar esta reserva.'; end if;
  if nullif(btrim(p_titulo),'') is null then raise exception 'Indique o título da reunião.'; end if;
  if p_hora_fim <= p_hora_inicio then raise exception 'A hora de fim tem de ser posterior à hora de início.'; end if;
  v_data_anterior := v_reserva.data; v_hora_anterior := v_reserva.hora_inicio;

  select array_agg(distinct id) into v_destinatarios from (
    select utilizador_id id from public.reservas_salas_participantes where reserva_id=p_reserva_id
    union select unnest(coalesce(p_participantes,'{}'::uuid[]))
    union select v_reserva.criado_por
  ) x where id is not null and id <> v_atual.id;

  update public.alertas set expira_em=now(), estado='resolvido'
  where tipo='reserva_sala' and entidade_id in (select id from public.reservas_salas_participantes where reserva_id=p_reserva_id);
  delete from public.reservas_salas_participantes where reserva_id=p_reserva_id;
  update public.reservas_salas set titulo=btrim(p_titulo),data=p_data,hora_inicio=p_hora_inicio,hora_fim=p_hora_fim
  where id=p_reserva_id returning * into v_reserva;
  insert into public.reservas_salas_participantes(reserva_id,utilizador_id)
  select p_reserva_id,u.id from public.utilizadores u where u.id=any(coalesce(p_participantes,'{}'::uuid[]))
    and u.empresa_id=v_atual.empresa_id and u.auth_user_id is not null and coalesce(u.ativo,true)
  on conflict (reserva_id,utilizador_id) do nothing;

  v_expira_em := (p_data+p_hora_fim) at time zone 'Europe/Lisbon';
  foreach v_id in array coalesce(v_destinatarios,'{}'::uuid[]) loop
    select * into v_destinatario from public.utilizadores where id=v_id and empresa_id=v_atual.empresa_id and auth_user_id is not null and coalesce(ativo,true);
    if found then
      insert into public.alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,descricao,data_evento_referencia,antecedencia_dias,data_gatilho,destinatario_role,estado,enviar_email,destinatario_utilizador_id,expira_em)
      values(v_atual.empresa_id,null,'reserva_sala','reservas_salas',p_reserva_id,'Reunião alterada: '||v_reserva.titulo,
        'Reunião de '||to_char(v_data_anterior,'DD/MM/YYYY')||' às '||to_char(v_hora_anterior,'HH24:MI')||' foi alterada por '||v_atual.nome||'. Novos dados: '||to_char(p_data,'DD/MM/YYYY')||' · '||to_char(p_hora_inicio,'HH24:MI')||'–'||to_char(p_hora_fim,'HH24:MI')||'.',
        p_data,0,current_date,v_destinatario.funcao,'pendente',false,v_destinatario.id,v_expira_em);
    end if;
  end loop;
  return v_reserva;
end;$function$;

create or replace function public.fn_apagar_reserva_sala(p_reserva_id uuid)
returns boolean language plpgsql security definer set search_path = public
as $function$
declare
  v_atual public.utilizadores; v_reserva public.reservas_salas;
  v_destinatario public.utilizadores; v_id uuid; v_destinatarios uuid[];
  v_expira_em timestamptz;
begin
  select * into v_atual from public.utilizadores where id=public.fn_utilizador_atual_id() and coalesce(ativo,true);
  if not found then raise exception 'Utilizador autenticado sem perfil ativo.'; end if;
  select * into v_reserva from public.reservas_salas where id=p_reserva_id for update;
  if not found then raise exception 'A reserva já não existe.'; end if;
  if v_reserva.criado_por is distinct from v_atual.id and not public.fn_e_admin() and not public.fn_e_administrativo() then raise exception 'Sem permissão para apagar esta reserva.'; end if;
  select array_agg(distinct id) into v_destinatarios from (
    select utilizador_id id from public.reservas_salas_participantes where reserva_id=p_reserva_id
    union select v_reserva.criado_por
  ) x where id is not null and id <> v_atual.id;
  update public.alertas set expira_em=now(),estado='resolvido' where tipo='reserva_sala'
    and entidade_id in (select id from public.reservas_salas_participantes where reserva_id=p_reserva_id);
  v_expira_em := (v_reserva.data+v_reserva.hora_fim) at time zone 'Europe/Lisbon';
  delete from public.reservas_salas where id=p_reserva_id;
  foreach v_id in array coalesce(v_destinatarios,'{}'::uuid[]) loop
    select * into v_destinatario from public.utilizadores where id=v_id and empresa_id=v_atual.empresa_id and auth_user_id is not null and coalesce(ativo,true);
    if found then
      insert into public.alertas(empresa_id,obra_id,tipo,entidade_tipo,entidade_id,titulo,descricao,data_evento_referencia,antecedencia_dias,data_gatilho,destinatario_role,estado,enviar_email,destinatario_utilizador_id,expira_em)
      values(v_atual.empresa_id,null,'reserva_sala','reservas_salas',p_reserva_id,'Reunião cancelada: '||v_reserva.titulo,
        'Reunião de '||to_char(v_reserva.data,'DD/MM/YYYY')||' às '||to_char(v_reserva.hora_inicio,'HH24:MI')||' foi cancelada por '||v_atual.nome||'.',
        v_reserva.data,0,current_date,v_destinatario.funcao,'pendente',false,v_destinatario.id,v_expira_em);
    end if;
  end loop;
  return true;
end;$function$;

revoke all on function public.fn_editar_reserva_sala(uuid,text,date,time,time,uuid[]) from public,anon;
revoke all on function public.fn_apagar_reserva_sala(uuid) from public,anon;
grant execute on function public.fn_editar_reserva_sala(uuid,text,date,time,time,uuid[]) to authenticated;
grant execute on function public.fn_apagar_reserva_sala(uuid) to authenticated;
commit;

select
  to_regprocedure('public.fn_editar_reserva_sala(uuid,text,date,time without time zone,time without time zone,uuid[])') is not null as rpc_editar,
  to_regprocedure('public.fn_apagar_reserva_sala(uuid)') is not null as rpc_apagar;
