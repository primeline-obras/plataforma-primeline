-- Classificação de 35 linhas explícitas do Excel de 24/09/2026.
-- Não insere lançamentos, não altera valores, horas, datas ou férias.
-- Executar APENAS depois de mgo_mao_obra_periodicidade.sql.
begin;
lock table public.lancamentos_mao_obra in share row exclusive mode;
create table if not exists public.mgo_mensais_20260924_backup (
 lancamento_id uuid primary key, antes jsonb not null,
 guardado_em timestamptz not null default now()
);
alter table public.mgo_mensais_20260924_backup enable row level security;
revoke all on public.mgo_mensais_20260924_backup from public,anon,authenticated;
create temp table mgo_mensais_fonte on commit drop as
select * from jsonb_to_recordset($fonte$[{"categoria":"mao_obra","linha":3,"obra_numero":"118","colaborador":"HENRIQUE BOGÉA","data":"2025-12-31","horas":7.6,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2025-12-01"},{"categoria":"mao_obra","linha":4,"obra_numero":"118","colaborador":"HENRIQUE BOGÉA","data":"2026-01-31","horas":26.4,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-01-01"},{"categoria":"mao_obra","linha":40,"obra_numero":"120","colaborador":"HENRIQUE BOGÉA","data":"2026-02-28","horas":60.8,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-02-01"},{"categoria":"mao_obra","linha":41,"obra_numero":"118","colaborador":"YNAÊ DE OLIVEIRA BOMFIM","data":"2026-02-28","horas":76,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-02-01"},{"categoria":"mao_obra","linha":120,"obra_numero":"122","colaborador":"JORDANE SILVESTRE","data":"2026-03-31","horas":52.8,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-03-01"},{"categoria":"mao_obra","linha":121,"obra_numero":"120","colaborador":"HENRIQUE BOGÉA","data":"2026-03-31","horas":88,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-03-01"},{"categoria":"mao_obra","linha":218,"obra_numero":"120","colaborador":"HENRIQUE BOGÉA","data":"2026-04-30","horas":117.6,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-04-01"},{"categoria":"mao_obra","linha":219,"obra_numero":"122","colaborador":"JORDANE SILVESTRE","data":"2026-04-30","horas":104.16,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-04-01"},{"categoria":"mao_obra","linha":220,"obra_numero":"118","colaborador":"JORDANE SILVESTRE","data":"2026-04-30","horas":6.72,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-04-01"},{"categoria":"mao_obra","linha":313,"obra_numero":"120","colaborador":"JORDANE SILVESTRE","data":"2026-05-31","horas":128,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-05-01"},{"categoria":"mao_obra","linha":314,"obra_numero":"122","colaborador":"JORDANE SILVESTRE","data":"2026-05-31","horas":12.8,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-05-01"},{"categoria":"mao_obra","linha":315,"obra_numero":"122","colaborador":"RAFAEL PIRES","data":"2026-05-31","horas":8,"valor_hora":29,"tipo_registo":"mensal","mes_referencia":"2026-05-01"},{"categoria":"mao_obra","linha":316,"obra_numero":"122","colaborador":"ANA CAROLINA SARAIVA","data":"2026-05-31","horas":76.15,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-05-01"},{"categoria":"mao_obra","linha":317,"obra_numero":"118","colaborador":"JOSÉ TRAVI","data":"2026-05-31","horas":24,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-05-01"},{"categoria":"mao_obra","linha":318,"obra_numero":"122","colaborador":"ANA CAROLINA SARAIVA","data":"2026-06-30","horas":69.66,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-06-01"},{"categoria":"mao_obra","linha":319,"obra_numero":"120","colaborador":"JORDANE SILVESTRE","data":"2026-06-30","horas":160,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-06-01"},{"categoria":"mao_obra","linha":320,"obra_numero":"118","colaborador":"JOSÉ TRAVI","data":"2026-06-30","horas":46.4,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-06-01"},{"categoria":"mao_obra","linha":321,"obra_numero":"122","colaborador":"RAFAEL PIRES","data":"2026-06-30","horas":42.42,"valor_hora":29,"tipo_registo":"mensal","mes_referencia":"2026-06-01"},{"categoria":"mao_obra","linha":322,"obra_numero":"120","colaborador":"HENRIQUE BOGÉA","data":"2026-06-30","horas":146.4,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-06-01"},{"categoria":"mao_obra","linha":578,"obra_numero":"122","colaborador":"ANA CAROLINA SARAIVA","data":"2026-07-31","horas":64,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-07-01"},{"categoria":"mao_obra","linha":579,"obra_numero":"120","colaborador":"HENRIQUE BOGÉA","data":"2026-07-31","horas":150.88,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-07-01"},{"categoria":"mao_obra","linha":580,"obra_numero":"118","colaborador":"JOSÉ TRAVI","data":"2026-07-31","horas":56.67,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-07-01"},{"categoria":"mao_obra","linha":581,"obra_numero":"122","colaborador":"RAFAEL PIRES","data":"2026-07-31","horas":70,"valor_hora":29,"tipo_registo":"mensal","mes_referencia":"2026-07-01"},{"categoria":"mao_obra","linha":582,"obra_numero":"122","colaborador":"KAMILA BATISTA GUTTERRES","data":"2026-07-31","horas":110,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-07-01"},{"categoria":"mao_obra","linha":583,"obra_numero":"120","colaborador":"JORDANE SILVESTRE","data":"2026-07-31","horas":84,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-07-01"},{"categoria":"mao_obra","linha":584,"obra_numero":"118","colaborador":"JORDANE SILVESTRE","data":"2026-07-31","horas":21,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-07-01"},{"categoria":"mao_obra","linha":585,"obra_numero":"122","colaborador":"JORDANE SILVESTRE","data":"2026-07-31","horas":12,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-07-01"},{"categoria":"mao_obra","linha":586,"obra_numero":"128","colaborador":"ANA CAROLINA SARAIVA","data":"2026-08-31","horas":94,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-08-01"},{"categoria":"mao_obra","linha":587,"obra_numero":"122","colaborador":"ANA CAROLINA SARAIVA","data":"2026-08-31","horas":32,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-08-01"},{"categoria":"mao_obra","linha":588,"obra_numero":"120","colaborador":"HENRIQUE BOGÉA","data":"2026-08-31","horas":151.2,"valor_hora":22.31,"tipo_registo":"mensal","mes_referencia":"2026-08-01"},{"categoria":"mao_obra","linha":589,"obra_numero":"118","colaborador":"JOSÉ TRAVI","data":"2026-08-31","horas":29.67,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-08-01"},{"categoria":"mao_obra","linha":590,"obra_numero":"122","colaborador":"KAMILA BATISTA GUTTERRES","data":"2026-08-31","horas":140,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-08-01"},{"categoria":"mao_obra","linha":591,"obra_numero":"120","colaborador":"JORDANE SILVESTRE","data":"2026-08-31","horas":101,"valor_hora":17.85,"tipo_registo":"mensal","mes_referencia":"2026-08-01"},{"categoria":"mao_obra","linha":592,"obra_numero":"122","colaborador":"RAFAEL PIRES","data":"2026-08-31","horas":41,"valor_hora":29,"tipo_registo":"mensal","mes_referencia":"2026-08-01"},{"categoria":"mao_obra","linha":593,"obra_numero":"120","colaborador":"RAFAEL PIRES","data":"2026-08-31","horas":5,"valor_hora":29,"tipo_registo":"mensal","mes_referencia":"2026-08-01"}]$fonte$::jsonb)
 as x(linha integer,obra_numero text,colaborador text,data date,horas numeric,valor_hora numeric,mes_referencia date);

do $check$
declare r record; n integer;
begin
 if (select count(*) from mgo_mensais_fonte)<>35 then raise exception 'Manifesto inesperado.'; end if;
 for r in select * from mgo_mensais_fonte loop
  select count(*) into n from public.colaboradores c
   where c.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'
    and lower(btrim(c.nome))=lower(btrim(r.colaborador));
  if n<>1 then raise exception 'Correspondência não única para %. Não foi alterado nenhum lançamento.',r.colaborador; end if;
  select count(*) into n from public.obras o
   where o.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add' and o.numero::text=r.obra_numero;
  if n<>1 then raise exception 'Correspondência não única para obra %.',r.obra_numero; end if;
 end loop;
end $check$;

create temp table mgo_mensais_correspondencias on commit drop as
select f.linha,f.mes_referencia,l.id,to_jsonb(l) as antes
from mgo_mensais_fonte f
join public.colaboradores c on c.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'
 and lower(btrim(c.nome))=lower(btrim(f.colaborador))
join public.obras o on o.empresa_id=c.empresa_id and o.numero::text=f.obra_numero
join public.lancamentos_mao_obra l on l.colaborador_id=c.id and l.obra_id=o.id
 and l.data=f.data and l.horas=f.horas and l.valor_hora=f.valor_hora;

do $check$
begin
 if exists(select 1 from mgo_mensais_correspondencias group by linha having count(*)>1)
  or exists(select 1 from mgo_mensais_correspondencias group by id having count(*)>1) then
   raise exception 'Correspondência ambígua. Nada foi alterado.';
 end if;
 if exists(select 1 from mgo_mensais_correspondencias
  where antes->>'tipo_registo' not in ('diario','mensal')
   or (antes->>'tipo_registo'='mensal' and (antes->>'mes_referencia')::date is distinct from mes_referencia)) then
  raise exception 'Classificação existente divergente. Nada foi alterado.';
 end if;
end $check$;

insert into public.mgo_mensais_20260924_backup(lancamento_id,antes)
 select id,antes from mgo_mensais_correspondencias where antes->>'tipo_registo'='diario'
on conflict(lancamento_id) do nothing;

update public.lancamentos_mao_obra l set tipo_registo='mensal',mes_referencia=m.mes_referencia
from mgo_mensais_correspondencias m
where l.id=m.id and l.tipo_registo='diario';

do $check$
begin
 if exists(select 1 from mgo_mensais_correspondencias m
  join public.lancamentos_mao_obra l on l.id=m.id
  where (to_jsonb(l)-'tipo_registo'-'mes_referencia') is distinct from
        (m.antes-'tipo_registo'-'mes_referencia')) then
  raise exception 'Uma coluna financeira ou identificação mudou. Transação anulada.';
 end if;
end $check$;

select 35 as linhas_mensais_no_ficheiro,
 count(*) as ja_existentes,
 count(*) filter(where antes->>'tipo_registo'='diario') as classificados_agora,
 35-count(*) as ainda_nao_gravados,
 true as valores_datas_horas_preservados
from mgo_mensais_correspondencias;
commit;
