-- Gestão confirmou trabalho em 27, 28 e 29/05/2026.
-- Executar no SQL Editor. Não reativa colaborador nem importa horas.
begin;
create table if not exists public.rh_correcao_ferias_202605_backup (
  ausencia_id uuid primary key,
  dados_originais jsonb not null,
  motivo text not null,
  arquivado_em timestamptz not null default now(),
  sessao_sql text not null default session_user
);
alter table public.rh_correcao_ferias_202605_backup enable row level security;
revoke all on public.rh_correcao_ferias_202605_backup from public,anon,authenticated;
create temp table _ferias_alvos(id uuid primary key,data date) on commit drop;
insert into _ferias_alvos values
 ('bb9b21d0-2ca8-4d85-90cd-1575719064ca','2026-05-27'),
 ('776681d6-2b08-433d-b208-1da0cea1e147','2026-05-28'),
 ('07a25e9b-670c-4093-84e8-00d608ad6a5e','2026-05-29');
lock table public.ausencias in share row exclusive mode;
lock table public.ausencias_anexos in share row exclusive mode;
do $correcao$
declare v_existem integer; v_validos integer; v_apagados integer;
begin
 select count(*) into v_existem from public.ausencias a join _ferias_alvos t on t.id=a.id;
 if v_existem=0 then
   if (select count(*) from public.rh_correcao_ferias_202605_backup b join _ferias_alvos t on t.id=b.ausencia_id)=3 then
     return; -- Reexecução sem alterações.
   end if;
   raise exception 'Registos já ausentes sem arquivo completo. Nada foi alterado.';
 end if;
 select count(*) into v_validos
 from public.ausencias a join _ferias_alvos t on t.id=a.id and t.data=a.data
 join public.colaboradores c on c.id=a.colaborador_id
 where c.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'::uuid
   and lower(btrim(c.nome))='adilson semedo'
   and a.tipo='ferias' and a.estado='confirmada';
 if v_existem<>3 or v_validos<>3 then
   raise exception 'Os três registos mudaram; rever antes de corrigir. Nada foi alterado.';
 end if;
 if exists(select 1 from public.ausencias_anexos x join _ferias_alvos t on t.id=x.ausencia_id) then
   raise exception 'Existem anexos associados. Preservar e rever antes da correção.';
 end if;
 -- Outras dependências destrutivas não conhecidas exigem revisão prévia.
 if exists(select 1 from pg_constraint
   where contype='f' and confrelid='public.ausencias'::regclass
     and conrelid<>'public.ausencias_anexos'::regclass and confdeltype in ('c','n','d')) then
   raise exception 'Existe outra relação com eliminação em cascata/alteração automática. Rever antes da correção.';
 end if;
 insert into public.rh_correcao_ferias_202605_backup(ausencia_id,dados_originais,motivo)
 select a.id,to_jsonb(a),'Correção autorizada pela Gestão: considerar trabalho nas três datas; preservar saída do colaborador.'
 from public.ausencias a join _ferias_alvos t on t.id=a.id;
 delete from public.ausencias a using _ferias_alvos t where a.id=t.id;
 get diagnostics v_apagados=row_count;
 if v_apagados<>3 then raise exception 'Correção incompleta; operação revertida.'; end if;
end $correcao$;
select
 (select count(*) from public.rh_correcao_ferias_202605_backup b join _ferias_alvos t on t.id=b.ausencia_id) as registos_preservados_em_backup,
 (select count(*) from public.ausencias a join _ferias_alvos t on t.id=a.id) as ferias_incorretas_restantes;
commit;
