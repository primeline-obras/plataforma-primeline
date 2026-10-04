import {readFile} from 'node:fs/promises';
const read=async p=>(await readFile(new URL(p,import.meta.url),'utf8')).replaceAll('\r','');
const captured=JSON.parse(await read('./fixtures/encarregado-catalogo-real-20261004.json'));
const migration=await read('../supabase/encarregado_escopo_migration.sql');
const economicTables=new Set(['faturas','faturacao','subempreitadas','consultas_subempreitada','consultas_subempreitada_candidatos','consultas_subempreitada_candidatos_itens','consultas_subempreitada_itens','subempreitada_aditamentos','avaliacoes_subempreiteiro','planeamento_custos_componentes','orcamento_fases','itens_orcamento','contratos','alteracoes_tee','alteracoes_tee_itens','alteracoes_tee_revisoes','tee_importacoes_revisoes','mapa_financeiro_ajustes','debitos_diretos','debitos_diretos_lancamentos','financeiro_estados_mensais','financeiro_estados_mensais_historico','mapas_comparativos','comparativo_propostas','comparativo_itens','comparativo_itens_precos','comparativo_ajustes','gestao_obras_lancamentos','previsao_financeira_mensal','lancamentos_materiais','mao_obra_registos','fornecedores']);
// Same focused class as the preceding review. No dynamic payloads or general audit.
export const focusedInventory=[];
for(const [signature,raw] of Object.entries(captured.details.definitions)){
 let definition=raw.replaceAll('\r','');const name=signature.split('(')[0];
 const matches=[...migration.matchAll(new RegExp('CREATE OR REPLACE FUNCTION public\\.'+name+'\\(','g'))];
 if(matches.length){
  const arity=signature.slice(signature.indexOf('(')+1,-1).split(',').filter(Boolean).length;
  const selected=matches.find(m=>migration.slice(m.index).split(')')[0].slice(migration.slice(m.index).indexOf('(')+1).split(',').filter(Boolean).length===arity);
  if(!selected)throw new Error('Ambiguous SQL overload in focused scan: '+signature);
  const rest=migration.slice(selected.index),tag=rest.match(/AS (\$[^$]*\$)/)?.[1];if(tag)definition=rest.slice(0,rest.indexOf(tag,rest.indexOf(tag)+tag.length)+tag.length);
 }
 if(!/SECURITY DEFINER/.test(definition)||!/fn_(e_admin|pode_editar_obra|e_diretor_obra|pode_editar_mapa_gestao_obras)\(/.test(definition))continue;
 const writes=[...definition.matchAll(/\b(?:insert\s+into|update|delete\s+from)\s+public\.([a-z_]\w*)/gi)].map(m=>m[1]);
 if(!writes.some(t=>economicTables.has(t))&&!(writes.includes('planeamento_itens')&&/valor|custo|compromisso/i.test(definition)))continue;
 let external=true;
 const last=migration.lastIndexOf('REVOKE ALL ON FUNCTION public.'+signature+' FROM PUBLIC,anon,authenticated,service_role;');
 if(last>=0)external=migration.slice(last,last+450).includes('GRANT EXECUTE ON FUNCTION public.'+signature+' TO authenticated;');
 // Legacy supplier/MGO functions are reviewed individually: tenant comes from the actor,
 // and their target selection is constrained to that company. A substring alone is not proof.
 const scopedLegacy=new Set(['fn_importar_mapa_gestao','fn_mesclar_fornecedor','fn_eliminar_fornecedor_duplicado','fn_definir_zonas_fornecedor','fn_criar_especialidade_fornecedor','fn_editar_fornecedor_diretorio','fn_guardar_cadastro_fornecedor']);
 const guard=/fn_financeiro_autorizar_obra\(/.test(definition)?'central_tenant_guard':scopedLegacy.has(name)?'reviewed_actor_company_target_selection':null;
 focusedInventory.push({signature,writes:[...new Set(writes)],external,guard,status:!external?'INTERNAL_ONLY':guard?'SCOPED':'MISSING_TENANT'});
}
export const focusedResidual=focusedInventory.filter(f=>f.status==='MISSING_TENANT');
