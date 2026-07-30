-- Teste não destrutivo do trigger trg_bloquear_conclusao.
-- Executar no SQL Editor depois de subempreitadas_mapa_comparativo_workflow.sql.
--
-- O teste escolhe uma subempreitada ainda não concluída e sem avaliação.
-- A tentativa de conclusão decorre num sub-bloco transacional: se o trigger
-- bloquear, a alteração é automaticamente revertida e o teste termina com sucesso.

do $$
declare
  v_subempreitada_id uuid;
  v_erro text;
begin
  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.subempreitadas'::regclass
      and tgname = 'trg_bloquear_conclusao'
      and not tgisinternal
      and tgenabled <> 'D'
  ) then
    raise exception 'TESTE FALHOU: trg_bloquear_conclusao não existe ou está desativado.';
  end if;

  select s.id
  into v_subempreitada_id
  from public.subempreitadas s
  where s.estado <> 'concluido'
    and not exists (
      select 1
      from public.avaliacoes_subempreiteiro a
      where a.subempreitada_id = s.id
    )
  order by s.criado_em
  limit 1;

  if v_subempreitada_id is null then
    raise exception
      'TESTE NÃO EXECUTADO: não existe uma subempreitada não concluída e sem avaliação.';
  end if;

  begin
    update public.subempreitadas
    set estado = 'concluido'
    where id = v_subempreitada_id;
  exception
    when others then
      get stacked diagnostics v_erro = message_text;
  end;

  if v_erro is null then
    -- A exceção exterior reverte integralmente o DO, incluindo o UPDATE.
    raise exception
      'TESTE FALHOU: o trigger permitiu concluir a subempreitada % sem avaliação.',
      v_subempreitada_id;
  end if;

  raise notice
    'TESTE PASSOU: a subempreitada % não foi concluída. Bloqueio devolvido: %',
    v_subempreitada_id,
    v_erro;
end
$$;

select
  tgname as trigger,
  case tgenabled
    when 'O' then 'ativo'
    when 'A' then 'sempre ativo'
    when 'R' then 'ativo em replica'
    when 'D' then 'desativado'
  end as estado
from pg_trigger
where tgrelid = 'public.subempreitadas'::regclass
  and tgname in (
    'trg_sincronizar_subempreitada_planeamento',
    'trg_bloquear_conclusao'
  )
  and not tgisinternal
order by tgname;
