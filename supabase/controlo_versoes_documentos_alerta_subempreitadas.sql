-- Controlo auditável de revisões e alerta de execução sem aprovação da Gerência.
-- Executar integralmente no SQL Editor com uma conta owner.
begin;

alter table public.documentos_obra
  add column if not exists destinatarios text,
  add column if not exists enviado_em timestamptz;

update public.documentos_obra set enviado_em = criado_em where enviado_em is null;

comment on column public.documentos_obra.destinatarios is
  'Destinatários a quem esta revisão foi enviada.';
comment on column public.documentos_obra.enviado_em is
  'Data e hora efetivas do envio desta revisão; não é a data do ficheiro.';

create index if not exists idx_documentos_obra_historico_revisoes
  on public.documentos_obra (obra_id, tipo, numero_documento, enviado_em desc, criado_em desc);

create or replace function public.fn_alertar_subempreitada_execucao_sem_aprovacao()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_empresa_id uuid;
  v_obra text;
begin
  if new.estado = 'em_execucao'
     and coalesce(new.estado_aprovacao_gerencia, '') <> 'aprovado' then
    select o.empresa_id, coalesce(to_jsonb(o)->>'numero', to_jsonb(o)->>'nome', '—')
      into v_empresa_id, v_obra from public.obras o where o.id = new.obra_id;

    insert into public.alertas (
      empresa_id, obra_id, tipo, entidade_tipo, entidade_id, titulo, descricao,
      data_evento_referencia, antecedencia_dias, data_gatilho,
      destinatario_role, estado
    )
    select v_empresa_id, new.obra_id,
      'subempreitada_execucao_sem_aprovacao', 'subempreitadas', new.id,
      'Subempreitada em execução sem aprovação',
      coalesce(new.especialidade, 'Subempreitada') || ' · Obra ' || v_obra ||
        ' · aprovação: ' || coalesce(new.estado_aprovacao_gerencia, 'não definida'),
      current_date, 0, current_date, 'gerencia', 'pendente'
    where not exists (
      select 1 from public.alertas a
      where a.tipo = 'subempreitada_execucao_sem_aprovacao'
        and a.entidade_tipo = 'subempreitadas'
        and a.entidade_id = new.id and a.estado = 'pendente'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_alertar_subempreitada_execucao_sem_aprovacao on public.subempreitadas;
create trigger trg_alertar_subempreitada_execucao_sem_aprovacao
after insert or update of estado, estado_aprovacao_gerencia on public.subempreitadas
for each row execute function public.fn_alertar_subempreitada_execucao_sem_aprovacao();

-- Cria o alerta também para situações já existentes, sem bloquear nem alterar o estado.
update public.subempreitadas set estado = estado
where estado = 'em_execucao'
  and coalesce(estado_aprovacao_gerencia, '') <> 'aprovado';

commit;
