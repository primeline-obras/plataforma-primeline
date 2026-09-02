-- PRIMELINE | Obra 118 — subempreitadas confirmadas no articulado
-- Fonte validada: folha 4_Subempreitadas da Obra 118 · SABÓIA 37.
-- A folha contém cinco linhas adjudicadas ainda ausentes da plataforma.
begin;

do $migration$
declare
  v_obra_id uuid;
  v_empresa_id uuid;
begin
  select o.id, o.empresa_id
    into v_obra_id, v_empresa_id
  from public.obras o
  where o.numero::text = '118'
  limit 1;

  if v_obra_id is null then
    raise exception 'Obra 118 não encontrada.';
  end if;

  -- Estes dois nomes constam como entidades próprias no articulado.
  insert into public.fornecedores (empresa_id, nome)
  select v_empresa_id, dados.nome
  from (values ('AEG'), ('Decorpita/Mantovani')) as dados(nome)
  where not exists (
    select 1
    from public.fornecedores f
    where f.empresa_id = v_empresa_id
      and lower(btrim(f.nome)) = lower(btrim(dados.nome))
  );

  insert into public.subempreitadas (
    obra_id,
    fase_id,
    fornecedor_id,
    especialidade,
    valor_adjudicado,
    estado
  )
  select
    v_obra_id,
    fase.id,
    fornecedor.id,
    dados.especialidade,
    dados.valor_adjudicado,
    'adjudicado'
  from (values
    ('F10', 'António Carneiro',       'Carpintaria',              24255.00::numeric),
    ('F11', 'AEG',                    'Equipamentos Cozinha',       276.00::numeric),
    ('F05', 'Decorpita/Mantovani',    'Revestimentos Parede',      2376.83::numeric),
    ('F08', 'Richimi',                'Revestimentos Pavimento',   1305.07::numeric),
    ('F11', 'CesarINOX',              'Serralharia / Inox',        3682.99::numeric)
  ) as dados(codigo_fase, fornecedor_nome, especialidade, valor_adjudicado)
  join public.fases fase
    on fase.obra_id = v_obra_id
   and fase.codigo = dados.codigo_fase
  join public.fornecedores fornecedor
    on fornecedor.empresa_id = v_empresa_id
   and lower(btrim(fornecedor.nome)) = lower(btrim(dados.fornecedor_nome))
  where not exists (
    select 1
    from public.subempreitadas existente
    where existente.obra_id = v_obra_id
      and existente.fornecedor_id = fornecedor.id
      and lower(btrim(coalesce(existente.especialidade, ''))) = lower(btrim(dados.especialidade))
      and existente.valor_adjudicado = dados.valor_adjudicado
  );
end;
$migration$;

commit;

select
  f.nome as fornecedor,
  s.especialidade,
  s.valor_adjudicado,
  s.estado,
  fase.codigo as fase
from public.subempreitadas s
join public.obras o on o.id = s.obra_id
join public.fornecedores f on f.id = s.fornecedor_id
left join public.fases fase on fase.id = s.fase_id
where o.numero::text = '118'
  and lower(btrim(f.nome)) in (
    lower('António Carneiro'),
    lower('AEG'),
    lower('Decorpita/Mantovani'),
    lower('Richimi'),
    lower('CesarINOX')
  )
order by fase.codigo, f.nome;
