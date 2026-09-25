import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {pathToFileURL} from 'node:url';
import {loadSources,compare,norm} from './reconcile_supplier_directory.mjs';

export function makeSql(report,current,hash,apply=false){
  const proposals=report.filter(r=>['novo','existente'].includes(r.status)).map(r=>({key:r.key,nome:r.nome,acao:r.status,
    alvo:r.target?.id||null,alvo_nome:r.target?.nome||null,email:r.proposal.email,telefone:r.proposal.telefone,notas:r.proposal.notas,
    emails:r.emails,phones:r.phones}));
  const snapshot=current.map(r=>({id:r.cadastro.id,nome:r.cadastro.nome}));
  const payload=JSON.stringify(proposals,null,2),baseline=JSON.stringify(snapshot);
  if(payload.includes('$fornecedores_fonte$')||baseline.includes('$fornecedores_snapshot$'))throw Error('Delimitador SQL presente nos dados.');
  return `-- ${apply?'APLICAR':'PRÉ-VISUALIZAR SEM GRAVAR'} — Base de Dados de Subempreiteiros e Fornecedores.xlsx
-- Fonte SHA256: ${hash}
-- Só campos vazios; não renomeia, não funde, não altera NIF, avaliações, tipos ou zonas.
-- Novos: tipo por classificar (NULL), estado nao_avaliado. Não cria faturas/contratos.
begin;
do $permissao$
begin
  if current_user not in ('postgres','supabase_admin') or auth.uid() is not null then
    if not exists(select 1 from public.utilizadores u where u.id=public.fn_utilizador_atual_id()
      and coalesce(u.ativo,false) and u.funcao in ('gestao_plataforma','administrativo','gerencia')
      and u.empresa_id='73fb13c8-d29f-4192-a506-4ca243343add'::uuid) then
      raise exception 'Sem permissão para completar este diretório.';
    end if;
  end if;
end $permissao$;

create temp table _forn_opcao(aplicar boolean,fonte_hash text,empresa_id uuid) on commit drop;
insert into _forn_opcao values(${apply},'${hash}','73fb13c8-d29f-4192-a506-4ca243343add');
create temp table _forn_fonte on commit drop as
select * from jsonb_to_recordset($fornecedores_fonte$
${payload}
$fornecedores_fonte$::jsonb) as s(key text,nome text,acao text,alvo uuid,alvo_nome text,email text,telefone text,notas text,emails text[],phones text[]);
create temp table _forn_snapshot on commit drop as
select * from jsonb_to_recordset($fornecedores_snapshot$${baseline}$fornecedores_snapshot$::jsonb) as s(id uuid,nome text);
create temp table _forn_resultado(nome text,acao text,fornecedor_id uuid,campos text[],motivo text) on commit drop;

create or replace function pg_temp.forn_norm(v text) returns text language sql immutable as $norm$
 select regexp_replace(translate(lower(coalesce(v,'')),
 'áàãâäéèêëíìîïóòõôöúùûüçñ','aaaaaeeeeiiiiooooouuuucn'),'[^a-z0-9]','','g');
$norm$;

-- Impede alterações concorrentes durante a validação/gravação do lote.
lock table public.fornecedores in share row exclusive mode;
lock table public.fornecedores_aliases in share row exclusive mode;
do $importar$
declare
  o record; s record; v_atual public.fornecedores%rowtype; depois public.fornecedores%rowtype;
  campos text[]; chave uuid; marcador text; alterado boolean;
begin
  select * into o from _forn_opcao;
  marcador:='[Fonte Excel '||left(o.fonte_hash,16)||' — dados históricos a confirmar]';
  if not exists(select 1 from public.empresas where id=o.empresa_id) then raise exception 'Empresa não encontrada.'; end if;
  -- Deteta nomes removidos/mesclados/renomeados ou contactos novos desde a exportação.
  if exists(select 1 from _forn_snapshot b left join public.fornecedores f on f.id=b.id and f.empresa_id=o.empresa_id
    where f.id is null or f.nome is distinct from b.nome) then
    raise exception 'O diretório foi renomeado/mesclado desde a exportação. Exporte novamente; nada foi gravado.';
  end if;
  if exists(select 1 from public.fornecedores f where f.empresa_id=o.empresa_id
    and not exists(select 1 from _forn_snapshot b where b.id=f.id)
    and not exists(select 1 from _forn_fonte q where q.acao='novo' and q.key=pg_temp.forn_norm(f.nome)
      and position(marcador in coalesce(f.notas,''))>0)) then
    raise exception 'Existem novos cadastros desde a exportação. Exporte novamente para prevenir duplicados.';
  end if;

  if o.aplicar then
    create table if not exists public.fornecedores_excel_historico (
      id uuid primary key default gen_random_uuid(),
      empresa_id uuid not null, fornecedor_id uuid not null,
      fonte_hash text not null, nome_fonte text not null, operacao text not null,
      antes jsonb, depois jsonb, criado_em timestamptz not null default now(),
      utilizador_id uuid, sessao_sql text not null
    );
    alter table public.fornecedores_excel_historico enable row level security;
    revoke all on public.fornecedores_excel_historico from public,anon,authenticated;
  end if;

  for s in select * from _forn_fonte order by acao,nome loop
    campos:='{}'; chave:=null;
    if s.acao='existente' then
      select * into v_atual from public.fornecedores where id=s.alvo and empresa_id=o.empresa_id for update;
      if not found or v_atual.nome is distinct from s.alvo_nome then raise exception 'Cadastro mudou: %',s.nome; end if;
      if nullif(btrim(v_atual.email),'') is null and s.email is not null then campos:=array_append(campos,'email'); end if;
      if nullif(btrim(v_atual.telefone),'') is null and s.telefone is not null then campos:=array_append(campos,'telefone'); end if;
      if nullif(btrim(v_atual.notas),'') is null and s.notas is not null then campos:=array_append(campos,'notas'); end if;
      alterado:=cardinality(campos)>0;
      if o.aplicar and alterado then
        update public.fornecedores set
          email=case when 'email'=any(campos) then s.email else email end,
          telefone=case when 'telefone'=any(campos) then s.telefone else telefone end,
          notas=case when 'notas'=any(campos) then s.notas else notas end
        where id=v_atual.id and empresa_id=o.empresa_id returning * into depois;
        insert into public.fornecedores_excel_historico(empresa_id,fornecedor_id,fonte_hash,nome_fonte,operacao,antes,depois,utilizador_id,sessao_sql)
          values(o.empresa_id,v_atual.id,o.fonte_hash,s.nome,'preenchimento',to_jsonb(v_atual),to_jsonb(depois),public.fn_utilizador_atual_id(),session_user);
      end if;
      insert into _forn_resultado values(s.nome,case when alterado then case when o.aplicar then 'preenchido' else 'a_preencher' end else 'sem_alteracao' end,v_atual.id,campos,null);
    else
      -- Registos criados por este mesmo lote são reconhecidos na repetição.
      select f.id into chave from public.fornecedores f where f.empresa_id=o.empresa_id
        and pg_temp.forn_norm(f.nome)=s.key and position(marcador in coalesce(f.notas,''))>0;
      if chave is not null then
        insert into _forn_resultado values(s.nome,'ja_importado',chave,'{}',null); continue;
      end if;
      -- Revalida nomes, aliases e contactos ATUAIS; nunca associa automaticamente por telefone.
      if exists(select 1 from public.fornecedores f where f.empresa_id=o.empresa_id and (
        pg_temp.forn_norm(f.nome)=s.key
        or exists(select 1 from unnest(s.emails) e where position(e in lower(coalesce(f.email,'')))>0)
        or exists(select 1 from unnest(s.phones) p where position(p in regexp_replace(coalesce(f.telefone,'')||coalesce(f.contacto,''),'[^0-9]','','g'))>0)))
      or exists(select 1 from public.fornecedores_aliases a where a.empresa_id=o.empresa_id and (
        pg_temp.forn_norm(a.nome)=s.key or exists(select 1 from unnest(s.emails) e where position(e in lower(coalesce(a.email,'')))>0))) then
        insert into _forn_resultado values(s.nome,'ignorado_conflito',null,'{}','Nome, alias ou contacto já presente; rever manualmente'); continue;
      end if;
      if o.aplicar then
        insert into public.fornecedores(empresa_id,nome,email,telefone,notas,tipo_entidade,estado_confianca)
          values(o.empresa_id,s.nome,s.email,s.telefone,s.notas,null,'nao_avaliado') returning * into depois;
        chave:=depois.id;
        insert into public.fornecedores_excel_historico(empresa_id,fornecedor_id,fonte_hash,nome_fonte,operacao,antes,depois,utilizador_id,sessao_sql)
          values(o.empresa_id,chave,o.fonte_hash,s.nome,'insercao',null,to_jsonb(depois),public.fn_utilizador_atual_id(),session_user);
      end if;
      insert into _forn_resultado values(s.nome,case when o.aplicar then 'inserido' else 'a_inserir' end,chave,array['nome','email','telefone','notas'],null);
    end if;
  end loop;
end $importar$;

select (select aplicar from _forn_opcao) as aplicado,
  count(*) filter(where acao='a_inserir') as novos_previstos,
  count(*) filter(where acao='inserido') as novos_inseridos,
  count(*) filter(where acao='a_preencher') as cadastros_a_completar,
  count(*) filter(where acao='preenchido') as cadastros_completados,
  count(*) filter(where acao='sem_alteracao') as sem_alteracao,
  count(*) filter(where acao='ja_importado') as ja_importados,
  count(*) filter(where acao='ignorado_conflito') as conflitos_na_execucao,
  ${report.filter(r=>r.status==='revisao').length} as nomes_para_revisao,
  coalesce(jsonb_agg(jsonb_build_object('nome',nome,'motivo',motivo)) filter(where acao='ignorado_conflito'),'[]') as detalhes_conflitos
from _forn_resultado;
commit;
`;
}

function applyText(file,text){
  const exists=fs.existsSync(file),old=exists?fs.readFileSync(file,'utf8'):'';
  let patch='*** Begin Patch\n'+(exists?'*** Update File: ':'*** Add File: ')+file+'\n';
  if(exists)patch+='@@\n'+old.trimEnd().split('\n').map(x=>'-'+x).join('\n')+'\n';
  patch+=text.trimEnd().split('\n').map(x=>'+'+x).join('\n')+'\n*** End Patch\n';
  if(exists)throw Error('O ficheiro já existe: '+file);
  let chunk=[],size=0,last=null;
  function flush(){if(!chunk.length)return;const p='*** Begin Patch\n'+(last===null?'*** Add File: ':'*** Update File: ')+file+'\n'+(last===null?'':'@@\n '+last+'\n')+chunk.map(l=>'+'+l).join('\n')+'\n'+(last===null?'':'*** End of File\n')+'*** End Patch';const sh="apply_patch <<'PATCH_FORN'\n"+p+"\nPATCH_FORN";const r=spawnSync('/bin/bash',['-c',sh],{encoding:'utf8',timeout:20000});if(r.error||r.status)throw Error(r.error?.message||r.stderr||r.stdout);last=chunk.at(-1);chunk=[];size=0;}
  for(const line of text.trimEnd().split('\n')){if(size+line.length>18000)flush();chunk.push(line);size+=line.length+1;}flush();
}

if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href){
  const [lib,xlsx,csv]=process.argv.slice(2),X=createRequire(import.meta.url)(path.resolve(lib));
  const data=loadSources(X,xlsx,csv),report=compare(data.extracted,data.current,data.hash);
  const base='supabase/fornecedores_excel_20260923';
  applyText(base+'_previsualizar.sql',makeSql(report,data.current,data.hash,false));
  applyText(base+'_aplicar.sql',makeSql(report,data.current,data.hash,true));
  const workbook=X.utils.book_new();
  const counts=report.reduce((o,r)=>(o[r.status]=(o[r.status]||0)+1,o),{});
  const summary=[['Indicador','Total'],['Cadastros na plataforma',data.current.length],['Linhas de fornecedores no Excel',data.extracted.rows.length],['Designações normalizadas',report.length],['Correspondências seguras',counts.existente||0],['Cadastros com campos vazios a completar',report.filter(r=>r.status==='existente'&&r.fields.length).length],['Novos candidatos seguros',counts.novo||0],['Nomes para revisão',counts.revisao||0],['Linhas sem nome excluídas',data.extracted.orphans.length],['Fonte SHA256',data.hash],['Estado','Preparado; não executado em produção'],['Critérios','Só vazios; sem fusão, sem renomear, sem deduzir NIF, tipo, avaliação ou zona operacional.'],['Notas','Contacto secundário/localidade/atividade/observações preservados nas notas dos novos registos. Notas existentes não são substituídas.'],['Limite','O Excel não contém NIF; ausência de coincidência não prova identidade jurídica. Casos semelhantes ficam retidos.']];
  X.utils.book_append_sheet(workbook,X.utils.aoa_to_sheet(summary),'Resumo');
  const headers=['Nome no Excel','Ação','Nome na plataforma','ID','Critério','Campos vazios a completar','Divergências preservadas','Possíveis cadastros existentes','Possíveis repetições no Excel','Email proposto','Telefone proposto','Notas da fonte'];
  for(const [status,title] of [['existente','Existentes'],['novo','Novos'],['revisao','Revisao']]){
    const rows=report.filter(r=>r.status===status).map(r=>[r.nome,r.status,r.target?.nome||'',r.target?.id||'',r.reason,r.fields.join(', '),r.conflicts.join(', '),r.candidates.join(' | '),r.siblings.join(' | '),r.proposal.email||'',r.proposal.telefone||'',r.proposal.notas]);
    const sheet=X.utils.aoa_to_sheet([headers,...rows]);sheet['!autofilter']={ref:X.utils.encode_range({s:{r:0,c:0},e:{r:rows.length,c:headers.length-1}})};sheet['!cols']=headers.map((_,i)=>({wch:i===11?90:35}));X.utils.book_append_sheet(workbook,sheet,title);
  }
  X.utils.book_append_sheet(workbook,X.utils.json_to_sheet(data.extracted.orphans),'Sem nome');
  fs.writeFileSync('docs/fornecedores-comparacao-20260923.xlsx',X.write(workbook,{type:'buffer',bookType:'xlsx'}));
  applyText('docs/fornecedores-comparacao-20260923.md',`# Comparação do diretório — 23/09/2026\n\n${summary.map(([k,v])=>`- ${k}: ${v}`).join('\n')}\n\nOs nomes para revisão não constam do SQL de gravação. O relatório XLSX inclui os candidatos e a folha/linha de origem.\n\n1. Executar primeiro o SQL terminado em _previsualizar.sql (não grava cadastros).\n2. Conferir os totais e conflitos.\n3. Executar _aplicar.sql para gravar o lote seguro numa transação única.\n4. Repetir a pré-visualização: novos_previstos e cadastros_a_completar devem ficar a zero.\n\nAlterações ficam em public.fornecedores_excel_historico (acesso administrativo SQL; sem leitura direta para utilizadores da app). Não altera faturas, subempreitadas, aliases ou ligações existentes. Novos parceiros sem tipo são apresentados como Tipo por classificar.\n`);
  console.log(JSON.stringify({snapshot:data.current.length,sourceRows:data.extracted.rows.length,counts,updates:report.filter(r=>r.status==='existente'&&r.fields.length).length,orphans:data.extracted.orphans.length,hash:data.hash},null,2));
}
