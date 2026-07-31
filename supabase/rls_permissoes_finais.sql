-- PRIMELINE | Matriz final de permissões
-- Executar integralmente no SQL Editor com uma conta owner.
-- Esta migração substitui as políticas permissivas antigas das tabelas usadas pela aplicação.

begin;

-- As funções existentes continuam a ser a única fonte de verdade dos papéis.
create or replace function public.fn_e_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.administradores_plataforma
    where utilizador_id = public.fn_utilizador_atual_id()
  )
  or exists (
    select 1
    from public.utilizadores
    where id = public.fn_utilizador_atual_id()
      and funcao = 'gerencia'
      and coalesce(ativo, true)
  );
$$;

create or replace function public.fn_e_administrativo()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_admin()
    or exists (
      select 1 from public.utilizadores
      where id = public.fn_utilizador_atual_id()
        and funcao = 'administrativo'
        and coalesce(ativo, true)
    );
$$;

create or replace function public.fn_e_financeiro()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_admin()
    or exists (
      select 1 from public.utilizadores
      where id = public.fn_utilizador_atual_id()
        and funcao = 'financeiro'
        and coalesce(ativo, true)
    );
$$;

create or replace function public.fn_pode_ver_obra(p_obra_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_administrativo()
    or exists (
      select 1
      from public.obra_responsaveis r
      join public.utilizadores u on u.id = r.utilizador_id
      where r.obra_id = p_obra_id
        and r.utilizador_id = public.fn_utilizador_atual_id()
        and u.funcao in ('diretor_obra', 'preparador')
        and coalesce(u.ativo, true)
    );
$$;

create or replace function public.fn_pode_editar_obra(p_obra_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.fn_e_admin()
    or exists (
      select 1
      from public.obra_responsaveis r
      join public.utilizadores u on u.id = r.utilizador_id
      where r.obra_id = p_obra_id
        and r.utilizador_id = public.fn_utilizador_atual_id()
        and u.funcao in ('diretor_obra', 'preparador')
        and coalesce(u.ativo, true)
    );
$$;

revoke all on function public.fn_e_admin() from public, anon;
revoke all on function public.fn_e_administrativo() from public, anon;
revoke all on function public.fn_e_financeiro() from public, anon;
revoke all on function public.fn_pode_ver_obra(uuid) from public, anon;
revoke all on function public.fn_pode_editar_obra(uuid) from public, anon;
grant execute on function public.fn_e_admin() to authenticated;
grant execute on function public.fn_e_administrativo() to authenticated;
grant execute on function public.fn_e_financeiro() to authenticated;
grant execute on function public.fn_pode_ver_obra(uuid) to authenticated;
grant execute on function public.fn_pode_editar_obra(uuid) to authenticated;

-- Remove políticas antigas, incluindo as políticas "using (true)" que eram somadas por OR.
do $$
declare
  r record;
  v_tables text[] := array[
    'administradores_plataforma', 'utilizadores', 'obra_responsaveis',
    'obras', 'fornecedores', 'contratos', 'fases', 'autos_medicao',
    'alteracoes_tee', 'itens_orcamento', 'planeamento_fases_resumo',
    'planeamento_itens', 'planeamento_itens_dependencias',
    'consultas_subempreitada', 'consultas_subempreitada_itens',
    'consultas_subempreitada_candidatos', 'consultas_subempreitada_candidatos_itens',
    'subempreitadas', 'avaliacoes_subempreiteiro', 'pagamentos_subempreitada',
    'faturas', 'faturas_guias', 'faturacao', 'faturacao_autos_medicao',
    'documentos', 'documentos_obra', 'alertas', 'lancamentos_mao_obra',
    'despesas_estaleiro', 'colaboradores', 'medicina_trabalho', 'viaturas',
    'ausencias', 'colaboradores_contratos', 'horas_extraordinarias',
    'quadro_pessoal_alocacao', 'seguranca_incidentes', 'seguranca_inspecoes',
    'epis', 'desenhos', 'rfis', 'faturas_itens'
  ];
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public' and tablename = any(v_tables)
  loop
    execute format('drop policy if exists %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;

  for r in
    select c.relname as tablename
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and c.relname = any(v_tables)
  loop
    execute format('alter table public.%I enable row level security', r.tablename);
    execute format('revoke all on table public.%I from anon', r.tablename);
    execute format('grant select, insert, update, delete on table public.%I to authenticated', r.tablename);
    execute format(
      'create policy pl_admin_total on public.%I for all to authenticated using (public.fn_e_admin()) with check (public.fn_e_admin())',
      r.tablename
    );
  end loop;
end
$$;

-- Perfil e estrutura de responsabilidades.
create policy pl_utilizadores_proprio_ou_rh
on public.utilizadores for select to authenticated
using (
  id = public.fn_utilizador_atual_id()
  or public.fn_e_administrativo()
);

create policy pl_responsabilidades_select
on public.obra_responsaveis for select to authenticated
using (
  utilizador_id = public.fn_utilizador_atual_id()
  or public.fn_e_administrativo()
);

create policy pl_administradores_select
on public.administradores_plataforma for select to authenticated
using (public.fn_e_admin());

-- Obras: financeiro vê apenas a lista/resumo; o detalhe usa fn_pode_ver_obra.
create policy pl_obras_select
on public.obras for select to authenticated
using (public.fn_pode_ver_obra(id) or public.fn_e_financeiro());

-- Diretório geral de fornecedores/subempreiteiros: leitura para todos os autenticados.
create policy pl_fornecedores_select
on public.fornecedores for select to authenticated
using (auth.uid() is not null);

create policy pl_subempreitadas_diretorio_select
on public.subempreitadas for select to authenticated
using (auth.uid() is not null);

create policy pl_avaliacoes_diretorio_select
on public.avaliacoes_subempreiteiro for select to authenticated
using (auth.uid() is not null);

create policy pl_subempreitadas_insert
on public.subempreitadas for insert to authenticated
with check (public.fn_pode_editar_obra(obra_id));

create policy pl_subempreitadas_update
on public.subempreitadas for update to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));

create policy pl_avaliacoes_insert
on public.avaliacoes_subempreiteiro for insert to authenticated
with check (
  public.fn_pode_editar_obra(obra_id)
  and avaliado_por = public.fn_utilizador_atual_id()
  and qualidade between 1 and 5
  and cumprimento_prazo between 1 and 5
  and seguranca between 1 and 5
  and comunicacao between 1 and 5
  and exists (
    select 1
    from public.subempreitadas s
    where s.id = subempreitada_id
      and s.obra_id = avaliacoes_subempreiteiro.obra_id
      and s.fornecedor_id = avaliacoes_subempreiteiro.fornecedor_id
  )
);

create policy pl_avaliacoes_update
on public.avaliacoes_subempreiteiro for update to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (
  public.fn_pode_editar_obra(obra_id)
  and avaliado_por = public.fn_utilizador_atual_id()
  and qualidade between 1 and 5
  and cumprimento_prazo between 1 and 5
  and seguranca between 1 and 5
  and comunicacao between 1 and 5
  and exists (
    select 1
    from public.subempreitadas s
    where s.id = subempreitada_id
      and s.obra_id = avaliacoes_subempreiteiro.obra_id
      and s.fornecedor_id = avaliacoes_subempreiteiro.fornecedor_id
  )
);

-- Leitura direta por obra.
create policy pl_contratos_select on public.contratos
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());
create policy pl_fases_select on public.fases
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());
create policy pl_autos_select on public.autos_medicao
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());
create policy pl_tees_select on public.alteracoes_tee
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());
create policy pl_consultas_select on public.consultas_subempreitada
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());
create policy pl_faturacao_select on public.faturacao
for select to authenticated using (public.fn_pode_ver_obra(obra_id));
create policy pl_documentos_obra_select on public.documentos_obra
for select to authenticated using (public.fn_pode_ver_obra(obra_id));
create policy pl_mao_obra_select on public.lancamentos_mao_obra
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());
create policy pl_estaleiro_select on public.despesas_estaleiro
for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());
create policy pl_seguranca_incidentes_select on public.seguranca_incidentes
for select to authenticated using (public.fn_pode_ver_obra(obra_id));
create policy pl_seguranca_inspecoes_select on public.seguranca_inspecoes
for select to authenticated using (public.fn_pode_ver_obra(obra_id));
create policy pl_desenhos_select on public.desenhos
for select to authenticated using (public.fn_pode_ver_obra(obra_id));
create policy pl_rfis_select on public.rfis
for select to authenticated using (public.fn_pode_ver_obra(obra_id));
create policy pl_faturas_itens_select on public.faturas_itens
for select to authenticated using (exists (
  select 1 from public.faturas f
  where f.id = fatura_id
    and (
      public.fn_pode_ver_obra(f.obra_id)
      or public.fn_e_administrativo()
      or public.fn_e_financeiro()
    )
));

-- Escrita operacional apenas por quem gere a obra.
create policy pl_autos_write on public.autos_medicao
for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));
create policy pl_tees_write on public.alteracoes_tee
for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));
create policy pl_consultas_write on public.consultas_subempreitada
for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));
create policy pl_faturacao_write on public.faturacao
for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));
create policy pl_seguranca_incidentes_write on public.seguranca_incidentes
for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));
create policy pl_seguranca_inspecoes_write on public.seguranca_inspecoes
for all to authenticated
using (public.fn_pode_editar_obra(obra_id))
with check (public.fn_pode_editar_obra(obra_id));
create policy pl_faturas_itens_insert on public.faturas_itens
for insert to authenticated
with check (exists (
  select 1 from public.faturas f
  where f.id = fatura_id
    and f.tipo_origem = 'material'
    and public.fn_e_administrativo()
));

-- Dados dependentes de fase.
create policy pl_itens_orcamento_select
on public.itens_orcamento for select to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

create policy pl_planeamento_fases_select
on public.planeamento_fases_resumo for select to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

create policy pl_planeamento_itens_select
on public.planeamento_itens for select to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

create policy pl_planeamento_itens_write
on public.planeamento_itens for all to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id and public.fn_pode_editar_obra(f.obra_id)
))
with check (exists (
  select 1 from public.fases f
  where f.id = fase_id and public.fn_pode_editar_obra(f.obra_id)
));

create policy pl_planeamento_dependencias_select
on public.planeamento_itens_dependencias for select to authenticated
using (exists (
  select 1
  from public.planeamento_itens i
  join public.fases f on f.id = i.fase_id
  where i.id = item_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

create policy pl_planeamento_dependencias_write
on public.planeamento_itens_dependencias for all to authenticated
using (exists (
  select 1
  from public.planeamento_itens i
  join public.fases f on f.id = i.fase_id
  where i.id = item_id and public.fn_pode_editar_obra(f.obra_id)
))
with check (
  exists (
    select 1
    from public.planeamento_itens i
    join public.fases f on f.id = i.fase_id
    where i.id = item_id and public.fn_pode_editar_obra(f.obra_id)
  )
  and exists (
    select 1
    from public.planeamento_itens i
    join public.fases f on f.id = i.fase_id
    where i.id = depende_de_item_id and public.fn_pode_editar_obra(f.obra_id)
  )
);

-- Filhos dos mapas comparativos.
create policy pl_consulta_itens_select
on public.consultas_subempreitada_itens for select to authenticated
using (exists (
  select 1 from public.consultas_subempreitada c
  where c.id = consulta_subempreitada_id
    and (public.fn_pode_ver_obra(c.obra_id) or public.fn_e_financeiro())
));
create policy pl_consulta_itens_write
on public.consultas_subempreitada_itens for all to authenticated
using (exists (
  select 1 from public.consultas_subempreitada c
  where c.id = consulta_subempreitada_id and public.fn_pode_editar_obra(c.obra_id)
))
with check (exists (
  select 1 from public.consultas_subempreitada c
  where c.id = consulta_subempreitada_id and public.fn_pode_editar_obra(c.obra_id)
));

create policy pl_candidatos_select
on public.consultas_subempreitada_candidatos for select to authenticated
using (exists (
  select 1 from public.consultas_subempreitada c
  where c.id = consulta_subempreitada_id
    and (public.fn_pode_ver_obra(c.obra_id) or public.fn_e_financeiro())
));
create policy pl_candidatos_write
on public.consultas_subempreitada_candidatos for all to authenticated
using (exists (
  select 1 from public.consultas_subempreitada c
  where c.id = consulta_subempreitada_id and public.fn_pode_editar_obra(c.obra_id)
))
with check (exists (
  select 1 from public.consultas_subempreitada c
  where c.id = consulta_subempreitada_id and public.fn_pode_editar_obra(c.obra_id)
));

create policy pl_candidato_itens_select
on public.consultas_subempreitada_candidatos_itens for select to authenticated
using (exists (
  select 1
  from public.consultas_subempreitada_candidatos cc
  join public.consultas_subempreitada c on c.id = cc.consulta_subempreitada_id
  where cc.id = candidato_id
    and (public.fn_pode_ver_obra(c.obra_id) or public.fn_e_financeiro())
));
create policy pl_candidato_itens_write
on public.consultas_subempreitada_candidatos_itens for all to authenticated
using (exists (
  select 1
  from public.consultas_subempreitada_candidatos cc
  join public.consultas_subempreitada c on c.id = cc.consulta_subempreitada_id
  where cc.id = candidato_id and public.fn_pode_editar_obra(c.obra_id)
))
with check (exists (
    select 1
    from public.consultas_subempreitada_candidatos cc
    join public.consultas_subempreitada c on c.id = cc.consulta_subempreitada_id
  where cc.id = candidato_id and public.fn_pode_editar_obra(c.obra_id)
));

create policy pl_pagamentos_subempreitada_select
on public.pagamentos_subempreitada for select to authenticated
using (exists (
  select 1 from public.subempreitadas s
  where s.id = subempreitada_id
    and (public.fn_pode_ver_obra(s.obra_id) or public.fn_e_financeiro())
));
create policy pl_pagamentos_subempreitada_insert
on public.pagamentos_subempreitada for insert to authenticated
with check (exists (
  select 1 from public.subempreitadas s
  where s.id = subempreitada_id and public.fn_pode_editar_obra(s.obra_id)
));

-- Faturas: Administrativo lança; gestão da obra decide; Financeiro paga.
create policy pl_faturas_select
on public.faturas for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());

create policy pl_faturas_insert
on public.faturas for insert to authenticated
with check (
  public.fn_e_administrativo()
  and estado_aprovacao = 'pendente'
  and estado_pagamento = 'por_pagar'
  and (
    (tipo_origem = 'subempreitada' and subempreitada_id is not null)
    or (tipo_origem in ('material', 'estaleiro') and subempreitada_id is null)
  )
);

create policy pl_faturas_guias_select
on public.faturas_guias for select to authenticated
using (exists (
  select 1 from public.faturas f
  where f.id = fatura_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));
create policy pl_faturas_guias_insert
on public.faturas_guias for insert to authenticated
with check (exists (
  select 1 from public.faturas f
  where f.id = fatura_id and public.fn_pode_editar_obra(f.obra_id)
));

-- Retira UPDATE direto: as duas operações abaixo alteram apenas os campos do respetivo fluxo.
revoke update on table public.faturas from authenticated;

create or replace function public.fn_decidir_fatura(p_fatura_id uuid, p_decisao text)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fatura public.faturas;
begin
  if p_decisao not in ('aprovado', 'recusado') then
    raise exception 'Decisão inválida.';
  end if;

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found or v_fatura.estado_aprovacao <> 'pendente' then
    raise exception 'A fatura já não está pendente.';
  end if;
  if not public.fn_pode_editar_obra(v_fatura.obra_id) then
    raise exception 'Sem permissão para decidir esta fatura.';
  end if;
  if p_decisao = 'aprovado' and not exists (
    select 1 from public.faturas_guias where fatura_id = p_fatura_id
  ) then
    raise exception 'É obrigatório anexar pelo menos uma guia antes da aprovação.';
  end if;

  update public.faturas
  set estado_aprovacao = p_decisao,
      aprovado_por = null,
      data_aprovacao = now()
  where id = p_fatura_id
  returning * into v_fatura;
  return v_fatura;
end;
$$;

create or replace function public.fn_marcar_fatura_paga(
  p_fatura_id uuid,
  p_data_pagamento date default current_date
)
returns public.faturas
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fatura public.faturas;
begin
  if not public.fn_e_financeiro() then
    raise exception 'O pagamento está reservado ao papel Financeiro.';
  end if;

  select * into v_fatura
  from public.faturas
  where id = p_fatura_id
  for update;

  if not found
     or v_fatura.estado_aprovacao <> 'aprovado'
     or v_fatura.estado_pagamento <> 'por_pagar' then
    raise exception 'A fatura não está disponível para pagamento.';
  end if;

  update public.faturas
  set estado_pagamento = 'pago',
      pago_por = public.fn_utilizador_atual_id(),
      data_pagamento = coalesce(p_data_pagamento, current_date)
  where id = p_fatura_id
  returning * into v_fatura;
  return v_fatura;
end;
$$;

revoke all on function public.fn_decidir_fatura(uuid, text) from public, anon;
revoke all on function public.fn_marcar_fatura_paga(uuid, date) from public, anon;
grant execute on function public.fn_decidir_fatura(uuid, text) to authenticated;
grant execute on function public.fn_marcar_fatura_paga(uuid, date) to authenticated;

-- Autos/faturação ao cliente e documentos associados.
create policy pl_faturacao_autos_select
on public.faturacao_autos_medicao for select to authenticated
using (exists (
  select 1 from public.autos_medicao a
  where a.id = auto_medicao_id and public.fn_pode_ver_obra(a.obra_id)
));
create policy pl_faturacao_autos_write
on public.faturacao_autos_medicao for all to authenticated
using (exists (
  select 1 from public.autos_medicao a
  where a.id = auto_medicao_id and public.fn_pode_editar_obra(a.obra_id)
))
with check (exists (
  select 1 from public.autos_medicao a
  where a.id = auto_medicao_id and public.fn_pode_editar_obra(a.obra_id)
));

create policy pl_documentos_workflow_select
on public.documentos for select to authenticated
using (
  (entidade_tipo in ('autos_medicao', 'auto_medicao') and exists (
    select 1 from public.autos_medicao a
    where a.id = entidade_id and public.fn_pode_ver_obra(a.obra_id)
  ))
  or (entidade_tipo = 'faturacao' and exists (
    select 1 from public.faturacao f
    where f.id = entidade_id and public.fn_pode_ver_obra(f.obra_id)
  ))
);
create policy pl_documentos_workflow_insert
on public.documentos for insert to authenticated
with check (
  (entidade_tipo in ('autos_medicao', 'auto_medicao') and exists (
    select 1 from public.autos_medicao a
    where a.id = entidade_id and public.fn_pode_editar_obra(a.obra_id)
  ))
  or (entidade_tipo = 'faturacao' and exists (
    select 1 from public.faturacao f
    where f.id = entidade_id and public.fn_pode_editar_obra(f.obra_id)
  ))
);

-- Documentos por obra: Administrativo também pode enviar, mas não ganha edição operacional.
create policy pl_documentos_obra_insert
on public.documentos_obra for insert to authenticated
with check (
  (public.fn_pode_editar_obra(obra_id) or public.fn_e_administrativo())
  and enviado_por = public.fn_utilizador_atual_id()
);

create or replace function public.fn_pode_editar_documentos_obra(p_obra_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select public.fn_pode_editar_obra(p_obra_id) or public.fn_e_administrativo();
$$;
revoke all on function public.fn_pode_editar_documentos_obra(uuid) from public, anon;
grant execute on function public.fn_pode_editar_documentos_obra(uuid) to authenticated;

-- Alertas: cada responsável vê os da sua obra; Administrativo/Financeiro veem os globais.
create policy pl_alertas_select
on public.alertas for select to authenticated
using (
  public.fn_e_administrativo()
  or public.fn_e_financeiro()
  or (obra_id is not null and public.fn_pode_ver_obra(obra_id))
);

-- Equipa e Quadro: exclusivamente Gerência/Administração e Administrativo.
create policy pl_colaboradores_rh on public.colaboradores
for all to authenticated using (public.fn_e_administrativo()) with check (public.fn_e_administrativo());
create policy pl_colaboradores_seguranca_select on public.colaboradores
for select to authenticated
using (
  data_saida is null
  and (
    public.fn_e_administrativo()
    or exists (
      select 1 from public.obra_responsaveis r
      where r.utilizador_id = public.fn_utilizador_atual_id()
    )
  )
);
create policy pl_epis_rh on public.epis
for all to authenticated using (public.fn_e_administrativo()) with check (public.fn_e_administrativo());
create policy pl_medicina_rh on public.medicina_trabalho
for all to authenticated using (public.fn_e_administrativo()) with check (public.fn_e_administrativo());
create policy pl_viaturas_rh on public.viaturas
for all to authenticated using (public.fn_e_administrativo()) with check (public.fn_e_administrativo());
create policy pl_ausencias_rh on public.ausencias
for all to authenticated using (public.fn_e_administrativo()) with check (public.fn_e_administrativo());
create policy pl_contratos_rh on public.colaboradores_contratos
for all to authenticated using (public.fn_e_administrativo()) with check (public.fn_e_administrativo());
create policy pl_horas_extra_rh on public.horas_extraordinarias
for all to authenticated using (public.fn_e_administrativo()) with check (public.fn_e_administrativo());
create policy pl_quadro_rh on public.quadro_pessoal_alocacao
for all to authenticated using (public.fn_e_administrativo()) with check (public.fn_e_administrativo());

-- Storage privado: o primeiro segmento do caminho é sempre obra_id.
drop policy if exists faturas_read_authenticated on storage.objects;
drop policy if exists faturas_upload_authenticated on storage.objects;
drop policy if exists documentos_storage_select on storage.objects;
drop policy if exists documentos_storage_insert on storage.objects;

create policy faturas_read_authenticated
on storage.objects for select to authenticated
using (
  bucket_id = 'faturas'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (
    public.fn_pode_ver_obra(((storage.foldername(name))[1])::uuid)
    or public.fn_e_financeiro()
  )
);

create policy faturas_upload_authenticated
on storage.objects for insert to authenticated
with check (
  bucket_id = 'faturas'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (
    (
      (storage.foldername(name))[2] = 'guias-remessa'
      and public.fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)
    )
    or (
      (storage.foldername(name))[2] <> 'guias-remessa'
      and public.fn_e_administrativo()
    )
  )
);

create policy documentos_storage_select
on storage.objects for select to authenticated
using (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and public.fn_pode_ver_obra(((storage.foldername(name))[1])::uuid)
);

create policy documentos_storage_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'documentos'
  and (storage.foldername(name))[1] ~* '^[0-9a-f-]{36}$'
  and (
    public.fn_pode_editar_obra(((storage.foldername(name))[1])::uuid)
    or public.fn_e_administrativo()
  )
);

commit;
