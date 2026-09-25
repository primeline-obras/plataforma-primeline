-- Distingue custo mensal de presença diária. Não importa nem elimina horas/férias.
begin;
alter table public.lancamentos_mao_obra
  add column if not exists tipo_registo text not null default 'diario',
  add column if not exists mes_referencia date;
do $$
begin
 if not exists(select 1 from pg_constraint where conrelid='public.lancamentos_mao_obra'::regclass and conname='mao_obra_periodo_check') then
  alter table public.lancamentos_mao_obra add constraint mao_obra_periodo_check check(
    (tipo_registo='diario' and mes_referencia is null) or
    (tipo_registo='mensal' and mes_referencia is not null
      and mes_referencia=date_trunc('month',data)::date));
 end if;
end $$;

create or replace function public.fn_mgo_validar_periodo_mao_obra(
 p_linha jsonb,p_colaborador uuid,p_obra uuid,p_id uuid default null
) returns text language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_tipo text:=coalesce(nullif(btrim(p_linha->>'tipo_registo'),''),'diario');
 v_data date:=(p_linha->>'data')::date;
 v_mes date:=nullif(p_linha->>'mes_referencia','')::date;
 v_horas numeric:=(p_linha->>'horas')::numeric;
 v_nome text; v_obra text; v_erro text; v_ausencia record;
begin
 select nome into v_nome from public.colaboradores where id=p_colaborador;
 select numero::text into v_obra from public.obras where id=p_obra;
 if v_tipo not in ('diario','mensal') then v_erro:='Tipo de registo deve ser diario ou mensal.';
 elsif v_data is null or v_horas is null or v_horas<0 then v_erro:='Data e horas não negativas são obrigatórias.';
 elsif v_tipo='mensal' then
   if v_mes is null or v_mes<>date_trunc('month',v_data)::date then
     v_erro:='Indique o primeiro dia do mês de referência, correspondente à data do lançamento.';
   elsif v_horas>extract(day from (v_mes+interval '1 month - 1 day'))*24 then
     v_erro:='Horas superiores à duração do mês.';
   elsif exists(select 1 from public.lancamentos_mao_obra l where l.colaborador_id=p_colaborador and l.obra_id=p_obra
     and l.id is distinct from p_id and date_trunc('month',l.data)=v_mes) then
     v_erro:='Já existem horas nesta obra/mês. Rever antes de somar um total mensal para evitar dupla contagem.';
   end if;
 else
   if v_mes is not null then v_erro:='Lançamento diário não deve ter mês de referência.';
   elsif v_horas>24 then v_erro:='Mais de 24 horas num lançamento diário; indique mensal explicitamente se for um total do mês.';
   else
     select a.tipo,a.estado into v_ausencia from public.ausencias a
       where a.colaborador_id=p_colaborador and a.data=v_data order by a.id limit 1;
     if found then v_erro:=format('Conflito com ausência: %s (%s).',v_ausencia.tipo,v_ausencia.estado);
     elsif exists(select 1 from public.lancamentos_mao_obra l where l.colaborador_id=p_colaborador and l.obra_id=p_obra
       and l.id is distinct from p_id and l.tipo_registo='mensal' and l.mes_referencia=date_trunc('month',v_data)::date) then
       v_erro:='Já existe total mensal nesta obra/mês; não somar ponto diário ao mesmo custo.';
     end if;
   end if;
 end if;
 if v_erro is null then return null; end if;
 return format('Linha %s · %s · Obra %s · %s: %s',coalesce(p_linha->>'linha','—'),v_nome,v_obra,v_data,v_erro);
end $$;
revoke all on function public.fn_mgo_validar_periodo_mao_obra(jsonb,uuid,uuid,uuid) from public,anon,authenticated;

create or replace function public.fn_bloquear_mao_obra_em_ausencia()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_erro text;
begin
 perform pg_advisory_xact_lock(hashtextextended('mgo-horas:'||new.colaborador_id::text||':'||date_trunc('month',new.data)::text,0));
 v_erro:=public.fn_mgo_validar_periodo_mao_obra(to_jsonb(new),new.colaborador_id,new.obra_id,new.id);
 if v_erro is not null then raise exception '%',v_erro; end if;
 return new;
end $$;
revoke all on function public.fn_bloquear_mao_obra_em_ausencia() from public,anon,authenticated;
drop trigger if exists trg_bloquear_mao_obra_ausencia on public.lancamentos_mao_obra;
create trigger trg_bloquear_mao_obra_ausencia before insert or update of colaborador_id,obra_id,data,horas,tipo_registo,mes_referencia
 on public.lancamentos_mao_obra for each row execute function public.fn_bloquear_mao_obra_em_ausencia();

-- Modificação guardada da RPC instalada: mantém permissões e regras das outras categorias.
do $patch$
declare original text; changed text; anchor text; replacement text;
begin
 original:=pg_get_functiondef('public.fn_importar_mapa_gestao(jsonb,boolean)'::regprocedure);
 if position('-- mgo-periodicidade-v1' in original)>0 then return; end if;
 anchor:='    v_chaves:=array_append(v_chaves,v_chave); v_criar:=v_criar+1;';
 replacement:=$inject$
    -- mgo-periodicidade-v1: mesma validação na simulação e gravação, após deduplicação.
    if v_categoria='mao_obra' then
      v_dados:=jsonb_build_object('erro',public.fn_mgo_validar_periodo_mao_obra(v_linha,v_colaborador.id,v_obra.id));
      if nullif(v_dados->>'erro','') is not null then
        v_erros:=v_erros||jsonb_build_array(v_dados->>'erro'); continue;
      end if;
      if exists(select 1 from jsonb_array_elements(p_linhas) other
        where other->>'categoria'='mao_obra'
          and lower(btrim(other->>'colaborador'))=lower(btrim(v_linha->>'colaborador'))
          and other->>'obra_numero'=v_linha->>'obra_numero'
          and left(other->>'data',7)=left(v_linha->>'data',7)
          and ('mensal' in (other->>'tipo_registo',v_linha->>'tipo_registo'))
          and (
            coalesce(nullif(other->>'tipo_registo',''),'diario')<>coalesce(nullif(v_linha->>'tipo_registo',''),'diario')
            or other->>'data' is distinct from v_linha->>'data'
            or (other->>'horas')::numeric is distinct from (v_linha->>'horas')::numeric
            or (other->>'valor_hora')::numeric is distinct from (v_linha->>'valor_hora')::numeric
          )) then
        v_erros:=v_erros||jsonb_build_array(format('Linha %s: mais de um lançamento ou mistura de diário e mensal para %s na obra/mês.',v_linha->>'linha',v_colaborador.nome)); continue;
      end if;
    end if;
    v_chaves:=array_append(v_chaves,v_chave); v_criar:=v_criar+1;$inject$;
 if position(anchor in original)=0 then raise exception 'RPC de importação diferente da versão esperada; migração cancelada.'; end if;
 changed:=replace(original,anchor,replacement);
 anchor:=$anchor$      perform public.fn_mgo_inserir_json_compativel('public.lancamentos_mao_obra'::regclass,v_dados);$anchor$;
 replacement:=$inject$      v_dados:=v_dados||jsonb_build_object('tipo_registo',coalesce(nullif(v_linha->>'tipo_registo',''),'diario'),
        'mes_referencia',nullif(v_linha->>'mes_referencia',''));
      perform public.fn_mgo_inserir_json_compativel('public.lancamentos_mao_obra'::regclass,v_dados);$inject$;
 if position(anchor in changed)=0 then raise exception 'Inserção de horas diferente da versão esperada; migração cancelada.'; end if;
 changed:=replace(changed,anchor,replacement);
 execute changed;
end $patch$;

-- Rótulo visível no MGO sem mudar a data nem a chave de deduplicação legada.
do $patch$
declare original text; changed text; anchor text;
begin
 original:=pg_get_functiondef('public.fn_mapa_gestao_obras_excel()'::regprocedure);
 if position('-- mgo-periodicidade-v1' in original)>0 then return; end if;
 anchor:='    entidade_nome:=base.entidade_nome; descricao:=base.descricao; documento:=base.documento;';
 if position(anchor in original)=0 then raise exception 'Leitura Excel diferente da versão esperada; migração cancelada.'; end if;
 changed:=replace(original,anchor,anchor||$label$
    -- mgo-periodicidade-v1
    if base.categoria='mao_obra' and dados->>'tipo_registo'='mensal' then
      descricao:=concat('TOTAL MENSAL ',to_char((dados->>'mes_referencia')::date,'MM/YYYY'),' · ',base.descricao);
    end if;$label$);
 execute changed;
end $patch$;
commit;
select to_regprocedure('public.fn_mgo_validar_periodo_mao_obra(jsonb,uuid,uuid,uuid)') is not null as validacao_diario_mensal_ativa,
 position('-- mgo-periodicidade-v1' in pg_get_functiondef('public.fn_importar_mapa_gestao(jsonb,boolean)'::regprocedure))>0 as previsualizacao_ausencias_ativa;
