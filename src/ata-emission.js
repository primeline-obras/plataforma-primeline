import {mountDocumentNomenclature} from './document-nomenclature-panel.js?v=ata-20261022';
export async function mountAtaEmission({root,supabase,work,documents,identity,downloadWorkDocument,confirm}){
 let live=true,panel;const actor=JSON.stringify(identity());
 const current=()=>live&&root.isConnected&&actor===JSON.stringify(identity());
 try {
  const response=await fetch(new URL('./ata-emission-config.json?v=20261022',import.meta.url),{cache:'no-store'});
  const config=response.ok?await response.json():null;
  if(!current()||config?.version!==1||config.enabled!==true)return {destroy(){live=false;}};
 }catch{return {destroy(){live=false;}};}
 if(!document.querySelector('link[data-ata-emission-style]')){
  const link=document.createElement('link');link.rel='stylesheet';link.href=new URL('./ata-emission.css?v=20261022',import.meta.url).href;
  link.dataset.ataEmissionStyle='';document.head.append(link);
 }
 const download=async event=>{
  if(!current()||!event.detail)return;event.stopPropagation();
  const {path,name}=event.detail;
  const button=event.target.querySelector('[data-name-download]:focus');if(button)button.disabled=true;
  root.querySelector('[role=alert]').textContent='';
  try{
   if(!documents.some(d=>d.tipo==='atas_reuniao'&&d.arquivo_url===path))throw Error('Ficheiro indisponível. Atualize a ficha.');
   const blob=await downloadWorkDocument(path);if(!current())return;
   if(!(blob instanceof Blob))throw Error('Não foi possível obter a cópia.');
   const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  }catch(e){if(current())root.querySelector('[role=alert]').textContent=e.message||'Não foi possível descarregar. Tente novamente.';}
  finally{if(current()&&button)button.disabled=false;}
 };
 root.addEventListener('document-named-copy',download);
 const catalogLoader=async()=>{
  const r=await fetch(new URL('./ata-emission-catalog.json?v=20261022',import.meta.url));if(!r.ok)throw Error('Catálogo de atas indisponível.');
  const c=await r.json();if(c.itens?.length!==1||c.itens[0].linha_excel!==13||c.itens[0].padrao_nome!=='[OBRA]_ATA_[Nº]_Reuniao_Obra_REV[XX]')throw Error('Catálogo de atas divergente.');return c;
 };
 panel=mountDocumentNomenclature({root,supabase,work,documents,identity,catalogLoader,ataOnly:true,...(confirm?{confirm}:{})});
 await panel.ready;
 return {destroy(){live=false;panel.destroy();root.removeEventListener('document-named-copy',download);}};
}
