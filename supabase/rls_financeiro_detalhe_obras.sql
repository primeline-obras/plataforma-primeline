-- Primeline | Financeiro: detalhe operacional em modo exclusivamente de leitura.
-- Executar depois de rls_permissoes_finais.sql quando a base já estiver configurada.
-- As políticas de escrita não são alteradas: continuam dependentes de
-- fn_pode_editar_obra() e, por isso, o papel financeiro não ganha ações.

drop policy if exists pl_fases_select on public.fases;
create policy pl_fases_select on public.fases for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());

drop policy if exists pl_tees_select on public.alteracoes_tee;
create policy pl_tees_select on public.alteracoes_tee for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());

drop policy if exists pl_consultas_select on public.consultas_subempreitada;
create policy pl_consultas_select on public.consultas_subempreitada for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());

drop policy if exists pl_mao_obra_select on public.lancamentos_mao_obra;
create policy pl_mao_obra_select on public.lancamentos_mao_obra for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());

drop policy if exists pl_estaleiro_select on public.despesas_estaleiro;
create policy pl_estaleiro_select on public.despesas_estaleiro for select to authenticated
using (public.fn_pode_ver_obra(obra_id) or public.fn_e_financeiro());

drop policy if exists pl_itens_orcamento_select on public.itens_orcamento;
create policy pl_itens_orcamento_select on public.itens_orcamento for select to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

drop policy if exists pl_planeamento_fases_select on public.planeamento_fases_resumo;
create policy pl_planeamento_fases_select on public.planeamento_fases_resumo for select to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

drop policy if exists pl_planeamento_itens_select on public.planeamento_itens;
create policy pl_planeamento_itens_select on public.planeamento_itens for select to authenticated
using (exists (
  select 1 from public.fases f
  where f.id = fase_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

drop policy if exists pl_planeamento_dependencias_select on public.planeamento_itens_dependencias;
create policy pl_planeamento_dependencias_select
on public.planeamento_itens_dependencias for select to authenticated
using (exists (
  select 1
  from public.planeamento_itens i
  join public.fases f on f.id = i.fase_id
  where i.id = item_id
    and (public.fn_pode_ver_obra(f.obra_id) or public.fn_e_financeiro())
));

drop policy if exists pl_consulta_itens_select on public.consultas_subempreitada_itens;
create policy pl_consulta_itens_select
on public.consultas_subempreitada_itens for select to authenticated
using (exists (
  select 1 from public.consultas_subempreitada c
  where c.id = consulta_subempreitada_id
    and (public.fn_pode_ver_obra(c.obra_id) or public.fn_e_financeiro())
));

drop policy if exists pl_candidatos_select on public.consultas_subempreitada_candidatos;
create policy pl_candidatos_select
on public.consultas_subempreitada_candidatos for select to authenticated
using (exists (
  select 1 from public.consultas_subempreitada c
  where c.id = consulta_subempreitada_id
    and (public.fn_pode_ver_obra(c.obra_id) or public.fn_e_financeiro())
));

drop policy if exists pl_candidato_itens_select on public.consultas_subempreitada_candidatos_itens;
create policy pl_candidato_itens_select
on public.consultas_subempreitada_candidatos_itens for select to authenticated
using (exists (
  select 1
  from public.consultas_subempreitada_candidatos cc
  join public.consultas_subempreitada c on c.id = cc.consulta_subempreitada_id
  where cc.id = candidato_id
    and (public.fn_pode_ver_obra(c.obra_id) or public.fn_e_financeiro())
));

drop policy if exists pl_pagamentos_subempreitada_select on public.pagamentos_subempreitada;
create policy pl_pagamentos_subempreitada_select
on public.pagamentos_subempreitada for select to authenticated
using (exists (
  select 1 from public.subempreitadas s
  where s.id = subempreitada_id
    and (public.fn_pode_ver_obra(s.obra_id) or public.fn_e_financeiro())
));
