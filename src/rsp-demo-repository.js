import {canUseRspDemo} from './rsp-demo.js?v=b46105965f37';
const canonical=value=>JSON.stringify(value,(_,v)=>v&&typeof v==='object'&&!Array.isArray(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);

// Shared application transport: no new client, session, key or credential store.
export function createRspDemoRepository({supabase,getIdentity,createId=()=>crypto.randomUUID()}) {
  const identity=()=>{const i=getIdentity();if(!canUseRspDemo(i))throw Error('RSP_IDENTITY_DENIED');return JSON.stringify(i);};
  async function request(path,options={}) {
    const before=identity();
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),30000);
    let response,body;
    try{response=await supabase(path,{...options,signal:controller.signal});
      if(identity()!==before)throw Error('RSP_SESSION_CHANGED');
      body=await response.json();
    }finally{clearTimeout(timer);}
    if(identity()!==before)throw Error('RSP_SESSION_CHANGED');
    if(identity()!==before)throw Error('RSP_SESSION_CHANGED');
    if(!response.ok){const e=Error('RSP_SERVER_STOP');e.code=body?.message==='RSP_REVISION_CONFLICT'?'RSP_REVISION_CONFLICT':'RSP_SERVER_STOP';throw e;}
    return body;
  }
  return {
    async load(){
      const row=await request('rpc/fn_rsp_demo_load_v1');
      if(row.document?.version!==3||!Array.isArray(row.document.works)||!Number.isSafeInteger(row.revision)||row.revision<0)throw Error('RSP_RESPONSE_FORMAT');
      return row;
    },
    async save(document,expectedRevision){
      const requestId=createId();
      const result=await request('rpc/fn_rsp_demo_save_v1',{method:'POST',body:JSON.stringify({p_document:document,p_expected_revision:expectedRevision,p_request_id:requestId})});
      if(result?.revision!==expectedRevision+1||result?.last_request_id!==requestId||canonical(result.document)!==canonical(document))throw Error('RSP_ACK_INVALID');
      return result;
    }
  };
}
