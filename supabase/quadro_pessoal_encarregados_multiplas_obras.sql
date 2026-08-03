-- Primeline | Encarregados em várias obras no mesmo dia
-- Aplicar uma vez no SQL Editor do Supabase.

alter table public.quadro_pessoal_alocacao
  drop constraint if exists quadro_pessoal_alocacao_colaborador_data_periodo_key;

drop index if exists public.quadro_pessoal_alocacao_colaborador_data_periodo_key;

alter table public.colaboradores
  add column if not exists permite_multiplas_obras boolean not null default false;

-- Compatibilidade com a classificação operacional já usada no Quadro.
-- A coluna permite gerir futuras exceções sem depender do nome da pessoa.
update public.colaboradores
set permite_multiplas_obras = true
where lower(coalesce(funcao, '')) like '%encarregado%'
   or split_part(lower(trim(nome)), ' ', 1) in (
     'manuel', 'paulo', 'regivaldo', 'vitor', 'wanderson', 'william', 'alessandro'
   );

create or replace function public.fn_validar_conflito_quadro_pessoal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_funcao text;
  v_permite_multiplas_obras boolean := false;
begin
  select lower(coalesce(c.funcao, '')), coalesce(c.permite_multiplas_obras, false)
    into v_funcao, v_permite_multiplas_obras
  from public.colaboradores c
  where c.id = new.colaborador_id;

  -- Nem encarregados nem outros colaboradores podem repetir exatamente
  -- a mesma colocação.
  if exists (
    select 1
    from public.quadro_pessoal_alocacao q
    where q.colaborador_id = new.colaborador_id
      and q.data = new.data
      and q.periodo = new.periodo
      and q.obra_id is not distinct from new.obra_id
      and q.tipo_alocacao is not distinct from new.tipo_alocacao
      and q.descricao_livre is not distinct from new.descricao_livre
      and q.id is distinct from new.id
  ) then
    raise exception 'O colaborador já está colocado nessa linha, data e período.';
  end if;

  -- Encarregados podem acompanhar várias obras simultaneamente.
  if v_permite_multiplas_obras or v_funcao like '%encarregado%' then
    return new;
  end if;

  -- Para os restantes colaboradores mantém-se uma única colocação por
  -- período. Dia inteiro também entra em conflito com manhã ou tarde.
  if exists (
    select 1
    from public.quadro_pessoal_alocacao q
    where q.colaborador_id = new.colaborador_id
      and q.data = new.data
      and q.id is distinct from new.id
      and (
        new.periodo = 'dia_inteiro'
        or q.periodo = 'dia_inteiro'
        or q.periodo = new.periodo
      )
  ) then
    raise exception 'O colaborador já tem uma alocação incompatível nesta data e período.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_validar_conflito_quadro_pessoal
  on public.quadro_pessoal_alocacao;

create trigger trg_validar_conflito_quadro_pessoal
before insert or update of colaborador_id, data, periodo, obra_id, tipo_alocacao, descricao_livre
on public.quadro_pessoal_alocacao
for each row
execute function public.fn_validar_conflito_quadro_pessoal();
