export const podeConsultarFornecedores = identity => Boolean(identity?.authUserId && identity?.userId && identity?.companyId && roles.has(identity.role));
// Read-only V1 transport. Authorization remains enforced by the existing backend.
// Transport must be the existing session-bound application client; never owner SQL.
const roles=new Set(['administrativo','financeiro','diretor_obra','gestao_plataforma']);
const failure=code=>Object.assign(new Error(code),{code});
const identityKey=x=>JSON.stringify([x?.authUserId,x?.userId,x?.companyId,x?.role]);
export function prepararLeitor({api,getIdentity}) {
 let generation=0;
 return {
  reset(){generation++;},
  async load(){
   const seq=++generation,identity={...getIdentity()},key=identityKey(identity);
   if(!identity.authUserId||!identity.userId||!identity.companyId||!roles.has(identity.role))throw failure('CONSULTA_NAO_AUTORIZADA');
   const current=()=>seq===generation&&identityKey(getIdentity())===key;
   let response,data;
   try {
    response=await api('rpc/fn_faturas_fornecedores_contexto_v1',{method:'POST',body:'{}'});
    if(!current())throw failure('CONTEXTO_OBSOLETO');
    if(!response.ok)throw failure(response.status===403?'CONSULTA_NAO_AUTORIZADA':'CONSULTA_INDISPONIVEL');
    data=await response.json();
   } catch(error) {
    if(!current())throw failure('CONTEXTO_OBSOLETO');
    throw failure(['CONSULTA_NAO_AUTORIZADA','CONSULTA_INDISPONIVEL'].includes(error.code)?error.code:'CONSULTA_INDISPONIVEL');
   }
   if(!current())throw failure('CONTEXTO_OBSOLETO');
   if(data?.write_enabled!==false)throw failure('ESTADO_FECHADO_NAO_COMPROVADO');
   if(data.actor_id!==identity.userId||data.role!==identity.role)throw failure('IDENTIDADE_DIVERGENTE');
   for(const field of ['works','suppliers','people','subcontracts','invoices','payments','history']) {
    if(!Array.isArray(data[field]))throw failure('CONTRATO_INCOMPLETO');
   }
   const works=new Set(data.works.map(x=>x.id));
   if(data.invoices.some(x=>x.empresa_id!==identity.companyId||(x.obra_id!==null&&!works.has(x.obra_id))))throw failure('AMBITO_DIVERGENTE');
   const ids=new Set(data.invoices.map(x=>x.id));
   if(data.payments.some(x=>!ids.has(x.recepcao_id))||data.history.some(x=>!ids.has(x.recepcao_id)))throw failure('VINCULO_DIVERGENTE');
   return {state:'ready',writeEnabled:false,context:data};
  }
 };
}
