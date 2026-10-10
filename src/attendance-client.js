export const FOLHA_RPCS = Object.freeze({ context:'fn_folha_contexto_v2', candidates:'fn_folha_pessoas_v2', operate:'fn_folha_operar_v2', history:'fn_folha_historico_v2' });
export function createSheetClient({ supabase, requestId=()=>crypto.randomUUID(), confirm }) {
  let pending=null, busy=false;
  async function rpc(name,body) {
    const r=await supabase(`rpc/${name}`,{method:'POST',body:JSON.stringify(body)});
    const j=await r.json().catch(()=>null);
    if(!r.ok) {
      const error=new Error(r.status===404?'A Folha de Ponto ainda não está disponível.':j?.message||'Não foi possível concluir a operação.');
      error.code=j?.code||String(r.status);throw error;
    }
    return j;
  }
  async function context(date,workId=null) {
    const j=await rpc(FOLHA_RPCS.context,{p_data:date,p_obra_id:workId});
    if(j?.version!==2 || !Array.isArray(j.works) || !Array.isArray(j.rows) || !Array.isArray(j.external_rows) || !j.permissions || ['write','external_write','allocation_write'].some(k=>typeof j.permissions[k]!=='boolean') || j.date!==date || (workId && j.work_id!==workId))throw new Error('Resposta da Folha inválida.');
    return j;
  }
  async function operate(action,data) {
    if(busy)throw new Error('Aguarde a operação em curso.');
    busy=true;
    const fingerprint=JSON.stringify({action,data});
    if(pending?.fingerprint!==fingerprint)pending={fingerprint,id:requestId()};
    const body={...data,version:2,request_id:pending.id};
    try {
      const endpoint=action.startsWith('team_')?'fn_equipa_operar_v2':FOLHA_RPCS.operate;
      const preview=await rpc(endpoint,{p_acao:action,p_dados:body,p_confirmar:false,p_versao:null});
      if(preview?.version!==2 || preview.committed!==false || typeof preview.versao!=='string' || !preview.versao)throw new Error('Pré-visualização inválida.');
      if(!await confirm(preview.summary || 'Confirmar esta alteração?')) {pending=null;return null;}
      const result=await rpc(endpoint,{p_acao:action,p_dados:body,p_confirmar:true,p_versao:preview.versao});
      const people=data.key?[data.key.person_id]:data.person_id?[data.person_id]:data.external_id?[data.external_id]:data.people?.map(x=>x.person_id)||data.items?.map(x=>x.key.person_id);
      const validKeys=Array.isArray(result?.changed_keys) && result.changed_keys.length>0 && result.changed_keys.every(k=>
        k && ['primeline','external'].includes(k.kind) && typeof k.person_id==='string' && k.person_id &&
        k.date===data.date && (k.work_id===data.work_id || data.source_work_id&&k.work_id===data.source_work_id) &&
        (!data.key || k.kind===data.key.kind) && (action!=='external_register' || k.kind==='external') &&
        (!people || people.includes(k.person_id))) &&
        (!people || people.every(id=>result.changed_keys.some(k=>k.person_id===id&&k.work_id===data.work_id)));
      if(result?.version!==2 || result.committed!==true || result.request_id!==body.request_id || !validKeys)throw new Error('Gravação não confirmada. Recarregue antes de repetir.');
      pending=null;return result;
    } catch(error) {
      if(['STALE_REVISION','40001','42501'].includes(error.code))pending=null;
      throw error;
    } finally {busy=false;}
  }
  return {context,operate,candidates:async(date,workId)=>{
    const j=await rpc(FOLHA_RPCS.candidates,{p_data:date,p_obra_id:workId});
    if(j?.version!==2 || !Array.isArray(j.people))throw new Error('Lista de pessoas inválida.');return j.people;
  },history:async(key)=>{
    const j=await rpc(FOLHA_RPCS.history,{p_chave:key});
    if(j?.version!==2 || !Array.isArray(j.events) || !Array.isArray(j.legacy) || j.legacy_interpretation!=='original')throw new Error('Histórico inválido.');return j;
  }};
}
export function createAttendanceManagementClient({supabase,confirm,requestId=()=>crypto.randomUUID()}) {
  let pending=null,busy=false;
  async function call(name,body){const r=await supabase(`rpc/${name}`,{method:'POST',body:JSON.stringify(body)});const j=await r.json().catch(()=>null);if(!r.ok){const e=new Error(r.status===404?'A gestão da Folha ainda não está disponível.':j?.message||'Operação recusada.');e.code=j?.code||String(r.status);throw e;}return j;}
  return {
    context:async({workId=null,personId=null,month=null}={})=>{const j=await call('fn_folha_gestao_contexto_v2',{p_obra_id:workId,p_colaborador_id:personId,p_competencia:month});if(j?.version!==2||!['tasks','task_reports','overtime','history'].every(k=>Array.isArray(j[k]))||(j.permissions?.admin && (!['people','vacations','entitlements','payroll'].every(k=>Array.isArray(j[k]))||!Number.isInteger(j.vacation_revision)))||!j.permissions||!['admin','he_review','task_report','task_review'].every(k=>typeof j.permissions[k]==='boolean'))throw new Error('Contexto administrativo inválido.');return j;},
    execute:async(action,data)=>{
      if(busy)throw new Error('Aguarde a operação em curso.');busy=true;
      const fingerprint=JSON.stringify({action,data});if(pending?.fingerprint!==fingerprint)pending={fingerprint,id:requestId()};
      const body={...data,version:2,request_id:pending.id};
      try{
        const p=await call('fn_folha_gestao_v2',{p_acao:action,p_dados:body,p_confirmar:false,p_versao:null});
        if(p?.version!==2||p.committed!==false||typeof p.versao!=='string'||!p.versao)throw new Error('Pré-visualização inválida.');
        const vacationPreview=p.preview?.dates;const consumption=p.preview?.calendar_pending?'Calendário por validar; consumo ainda não definitivo.':p.preview?.consumed_days!=null?`${p.preview.consumed_days} dias úteis consumidos.`:'';
        const message=action.startsWith('vacation_')&&Array.isArray(vacationPreview)?`Confirmar ${vacationPreview.length} dias úteis? ${consumption}${action==='vacation_replace'?' Os dias desmarcados deste período serão retirados.':''}`:action==='vacation_replace'?`Confirmar os ${data.dates.length} dias de férias selecionados? Os dias desmarcados deste período serão retirados.`:'Confirmar esta alteração?';
        if(!await confirm(message)){pending=null;return null;}
        const r=await call('fn_folha_gestao_v2',{p_acao:action,p_dados:body,p_confirmar:true,p_versao:p.versao});
        if(r?.version!==2||r.committed!==true||r.request_id!==body.request_id||r.revision!==data.expected_revision+1)throw new Error('Gravação não confirmada. Recarregue antes de repetir.');
        pending=null;return r;
      }catch(e){if(['40001','42501','STALE_REVISION'].includes(e.code))pending=null;throw e;}finally{busy=false;}
    }
  };
}
