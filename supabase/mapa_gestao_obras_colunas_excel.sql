-- PRIMELINE | Mapa de Gestão de Obras — colunas compatíveis com o Excel
-- Migração aditiva: preserva todos os lançamentos existentes.

begin;

alter table public.gestao_obras_lancamentos
  add column if not exists unidade_medida text,
  add column if not exists quantidade numeric,
  add column if not exists valor_unitario numeric,
  add column if not exists data_pagamento date;

do $$
begin
  if not exists(select 1 from pg_constraint where conname='gestao_obras_lancamentos_quantidade_check' and conrelid='public.gestao_obras_lancamentos'::regclass) then
    alter table public.gestao_obras_lancamentos add constraint gestao_obras_lancamentos_quantidade_check check(quantidade is null or quantidade>=0);
  end if;
  if not exists(select 1 from pg_constraint where conname='gestao_obras_lancamentos_valor_unitario_check' and conrelid='public.gestao_obras_lancamentos'::regclass) then
    alter table public.gestao_obras_lancamentos add constraint gestao_obras_lancamentos_valor_unitario_check check(valor_unitario is null or valor_unitario>=0);
  end if;
end $$;

drop function if exists public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,numeric);
drop function if exists public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric);

create function public.fn_guardar_lancamento_gestao_obras(
  p_id uuid,p_obra_id uuid,p_categoria text,p_data_lancamento date,p_entidade_nome text,p_descricao text,p_documento text,
  p_unidade_medida text,p_quantidade numeric,p_valor_unitario numeric,p_data_pagamento date,p_valor numeric
) returns public.gestao_obras_lancamentos language plpgsql security definer set search_path=public,pg_temp as $$
declare row_out public.gestao_obras_lancamentos;
begin
  if not public.fn_pode_editar_mapa_gestao_obras() then raise exception 'Só o Administrativo e a Gestão da Plataforma podem alterar lançamentos.' using errcode='42501'; end if;
  if p_categoria not in ('materiais','mao_obra','estaleiro') then raise exception 'Categoria não editável neste ecrã.'; end if;
  if not exists(select 1 from public.obras where id=p_obra_id) then raise exception 'Obra não encontrada.'; end if;
  if p_quantidade is not null and p_quantidade<0 then raise exception 'A quantidade não pode ser negativa.'; end if;
  if p_valor_unitario is not null and p_valor_unitario<0 then raise exception 'O valor unitário não pode ser negativo.'; end if;
  if p_id is null then
    insert into public.gestao_obras_lancamentos(obra_id,categoria,data_lancamento,entidade_nome,descricao,documento,unidade_medida,quantidade,valor_unitario,data_pagamento,valor)
    values(p_obra_id,p_categoria,p_data_lancamento,btrim(p_entidade_nome),btrim(p_descricao),nullif(btrim(p_documento),''),
      nullif(btrim(p_unidade_medida),''),p_quantidade,p_valor_unitario,p_data_pagamento,greatest(coalesce(p_valor,0),0)) returning * into row_out;
  else
    update public.gestao_obras_lancamentos set obra_id=p_obra_id,categoria=p_categoria,data_lancamento=p_data_lancamento,
      entidade_nome=btrim(p_entidade_nome),descricao=btrim(p_descricao),documento=nullif(btrim(p_documento),''),
      unidade_medida=nullif(btrim(p_unidade_medida),''),quantidade=p_quantidade,valor_unitario=p_valor_unitario,data_pagamento=p_data_pagamento,
      valor=greatest(coalesce(p_valor,0),0),atualizado_por=public.fn_utilizador_atual_id(),atualizado_em=now()
      where id=p_id returning * into row_out;
    if not found then raise exception 'Lançamento não encontrado.'; end if;
  end if;
  return row_out;
end $$;

revoke all on function public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric) from public,anon;
grant execute on function public.fn_guardar_lancamento_gestao_obras(uuid,uuid,text,date,text,text,text,text,numeric,numeric,date,numeric) to authenticated;

commit;

select
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='gestao_obras_lancamentos' and column_name='unidade_medida') as unidade_medida,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='gestao_obras_lancamentos' and column_name='quantidade') as quantidade,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='gestao_obras_lancamentos' and column_name='valor_unitario') as valor_unitario,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='gestao_obras_lancamentos' and column_name='data_pagamento') as data_pagamento;
