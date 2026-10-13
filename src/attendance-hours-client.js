// Prepared controller. Deliberately not mounted by app.js before visual approval.
export function createHoursPreparationClient({supabase,confirm,requestId=()=>crypto.randomUUID()}){
 let busy=false,pending=null,epoch=0;
 const current=g=>{if(g!==epoch)throw Error("Sessão alterada. Reabra o contexto antes de continuar.");};
 async function call(name,body){const generation=epoch;const r=await supabase('rpc/'+name,{method:'POST',body:JSON.stringify(body)});const j=await r.json().catch(()=>null);current(generation);if(!r.ok){const e=new Error(r.status===404?'O contrato de Gestão de Horas ainda não está instalado.':j?.message||'Operação recusada.');e.code=j?.code||String(r.status);throw e;}return j;}
 return {
  reset:()=>{epoch++;pending=null;},
  context:async(date,workId)=>{const c=await call('fn_folha_horas_contexto_v3',{p_data:date,p_obra_id:workId});if(c?.version!==3||c.date!==date||c.work_id!==workId||!Array.isArray(c.rows)||!Array.isArray(c.external_rows)||c.reference_edit_capability!==false||!c.operational_write_capabilities)throw Error('Contexto de horas inválido.');return c;},
  report:async({workId,from,to,kind=null,providerId=null})=>{const r=await call('fn_folha_relatorio_horas_v3',{p_obra_id:workId,p_inicio:from,p_fim:to,p_kind:kind,p_fornecedor_id:providerId});if(r?.version!==3||r.work_id!==workId||r.from!==from||r.to!==to||!['records','daily','weekly','monthly','legacy'].every(k=>Array.isArray(r[k]))||r.classification_included!==false||r.financial_effect!==false)throw Error('Relatório factual inválido.');if(kind&&r.records.some(x=>x.kind!==kind)||providerId&&r.records.some(x=>x.provider_id!==providerId))throw Error('Relatório fora do âmbito.');return r;},
  monthly:async(personId,month)=>{const r=await call('fn_folha_conferencia_contexto_v3',{p_colaborador_id:personId,p_competencia:month});if(r?.version!==3||r.person_id!==personId||r.month!==month||!r.snapshot||!Array.isArray(r.snapshot.pending)||!Array.isArray(r.history)||typeof r.conference_write_capability!=='boolean'||r.he_policy!=='HR-27'||r.financial_effect!==false)throw Error('Competência fora do contrato.');return r;},
  reportFaltou:async({personId,date,workId,reason=null})=>{
   if(busy)throw Error('Aguarde a operação em curso.');busy=true;const generation=epoch;
   const facts={version:2,date,work_id:workId,key:{kind:'primeline',person_id:personId,date,work_id:workId},reason},fingerprint=JSON.stringify(facts);
   if(pending?.fingerprint!==fingerprint)pending={fingerprint,id:requestId()};const body={...facts,request_id:pending.id};
   try{const p=await call('fn_folha_faltou_v2',{p_acao:'absence_report',p_dados:body,p_confirmar:false,p_versao:null});current(generation);if(p?.version!==2||p.committed!==false||!p.versao)throw Error('Preview de Faltou inválido.');if(!await confirm('Confirmar FALTOU? A classificação será feita pelo Administrativo. A equipa e as horas permanecem intactas.')){pending=null;return null;}
    current(generation);const r=await call('fn_folha_faltou_v2',{p_acao:'absence_report',p_dados:body,p_confirmar:true,p_versao:p.versao});current(generation);if(r?.version!==2||r.committed!==true||r.request_id!==body.request_id||r.absence?.colaborador_id!==personId||r.absence?.data!==date||r.absence?.tipo!=='falta_reportada_pendente'||r.absence?.estado!=='ausente_pendente'||!Array.isArray(r.changed_keys)||r.changed_keys.length!==1||r.changed_keys[0].person_id!==personId||r.changed_keys[0].date!==date||r.changed_keys[0].work_id!==workId||r.changed_keys[0].kind!=='primeline')throw Error('Gravação não confirmada. Recarregue antes de repetir.');pending=null;return r;
   }catch(e){if(['40001','42501','STALE_REVISION'].includes(e.code))pending=null;throw e;}finally{busy=false;}
  },
  executeMonthly:async({action,personId,month,expectedRevision,reason=null,records=[]})=>{
   if(!['conferir','devolver','validar'].includes(action)||!Number.isInteger(expectedRevision)||expectedRevision<0)throw Error('Operação mensal inválida.');
   if(busy)throw Error('Aguarde a operação em curso.');busy=true;const generation=epoch;
   const facts={version:3,person_id:personId,month,expected_revision:expectedRevision,reason,records},fingerprint=JSON.stringify({action,...facts});
   if(pending?.fingerprint!==fingerprint)pending={fingerprint,id:requestId()};const body={...facts,request_id:pending.id};
   try{const p=await call('fn_folha_conferencia_v3',{p_acao:action,p_dados:body,p_confirmar:false,p_versao:null});current(generation);if(p?.version!==3||p.committed!==false||!p.versao)throw Error('Preview mensal inválido.');if(!await confirm('Confirmar a operação sobre esta competência mensal?')){pending=null;return null;}
    current(generation);const r=await call('fn_folha_conferencia_v3',{p_acao:action,p_dados:body,p_confirmar:true,p_versao:p.versao});current(generation);
    if(r?.version!==3||r.committed!==true||r.request_id!==body.request_id||r.financial_effect!==false||r.conference?.colaborador_id!==personId||r.conference?.competencia!==month||r.revision!==r.conference?.revision)throw Error('Conferência não confirmada. Recarregue antes de repetir.');pending=null;return r;
   }catch(e){if(['40001','42501','STALE_REVISION'].includes(e.code))pending=null;throw e;}finally{busy=false;}
  },
  requireMonthlyWriter:context=>{if(context.conference_write_capability!==true)throw Error('Validação mensal ainda não implementada; não usar payroll_validate como substituto.');},
  requireDestinationWriter:context=>{if(context.operational_write_capabilities?.free_destinations!==true)throw Error('Garantia/Outra com referência livre exige o contrato de destinos; não usar Escritório como alternativa.');},
  requireExternalExcelConfirmation:confirmation=>{if(confirmation?.server_authorized!==true||confirmation.export_format!=='xlsx'||confirmation.confirmed_by_role!=='diretor_obra'||!confirmation.facts_fingerprint||!confirmation.confirmation_id)throw Error('Exportação Excel requer confirmação do Diretor de Obra sobre a revisão atual.');}
 };
}