import {loadDocumentCatalog, tokens, buildDocumentName} from './document-nomenclature.js?v=2';
import {platformConfirm} from './platform-dialogs.js?v=2';
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const labels = {'Nº':'Número já atribuído pelo módulo',XX:'Revisão',ASSUNTO:'Assunto',MATERIAL:'Material',EMPRESA:'Empresa / entidade', 'Nº_FATURA':'Número oficial da fatura', 'Nº_GUIA':'Número oficial da guia'};
const errors={SOURCE_NUMBER_ALREADY_NAMED:'Este número já tem uma emissão nesta obra. Para rever a mesma série, selecione a revisão anterior.',FORBIDDEN:'Sem autorização para confirmar nomes. Mantêm-se as permissões do índice.',STALE_REVISION:'A referência mudou. Atualize a ficha e reveja a emissão.',EXPLICIT_CONTRACT_OR_TEE_LINK_REQUIRED:'Falta a associação comprovada ao contrato de subempreitada ou ao TEE. Este caso fica pendente.',EXPLICIT_SOURCE_NUMBER_REQUIRED:'Indique e confirme o número factual já atribuído pelo módulo.',DUPLICATE_DOCUMENT_NAME:'Já existe este nome nesta obra. Reveja o tipo, o número e a revisão.',REASON_REQUIRED:'Indique um motivo com pelo menos três caracteres.',DOCUMENT_ALREADY_NAMED:'Este ficheiro já tem um nome de emissão. Para nova revisão, selecione o novo ficheiro.',PRESERVE_ORIGINAL_NAME:'Este tipo exige preservar o nome original.',INVALID_NAME_COMPONENT:'Preencha os campos sem caracteres de caminho ou caracteres inválidos.',SERIES_NUMBER_CHANGED:'Uma revisão deve preservar o número factual da série.',REVISION_NOT_DEFINED_BY_CATALOG:'O índice não define revisões para este tipo.'};

Object.assign(errors,{
  ATA_ONLY:'Este circuito permite apenas atas de reunião de obra.',
  ATA_DOCUMENT_TYPE_REQUIRED:'Selecione uma ata já registada no Centro Documental.',
  ATA_NUMBER_UNCONFIRMED:'O número da ata não está comprovado no registo original. Corrija o cadastro documental antes de emitir.',
  ATA_REVISION_UNCONFIRMED:'A revisão da ata não está comprovada no registo original. Não é atribuída uma revisão automaticamente.',
  ATA_NUMBER_MISMATCH:'O número registado na ata mudou. Atualize a ficha e volte a pré-visualizar.',
  ATA_PREDECESSOR_REQUIRED:'Já existe uma emissão desta ata. Selecione a revisão anterior comprovada; não é criada outra série.',
  SOURCE_CONTRACT_UNAVAILABLE:'O contrato selecionado não está disponível nesta obra e empresa.',
  SOURCE_TEE_UNAVAILABLE:'O TEE selecionado não está disponível nesta obra e empresa.',
  SOURCE_TEE_NUMBER_UNCONFIRMED:'O número histórico do TEE não é canónico. Confirme a referência antes de normalizar o nome.',
  SOURCE_TEE_NUMBER_MISMATCH:'O número indicado não corresponde ao TEE selecionado.',
  PERIOD_WITHOUT_DATE_REQUIRED:'Identifique o período por semana ou quinzena, sem data no nome.'
  ,SOURCE_REVISION_UNCONFIRMED:'A revisão histórica não é numérica. Preserve a referência original; não é convertida para REV00.'
  ,SOURCE_REVISION_MISMATCH:'A revisão documental não corresponde à revisão seguinte desta série. Preserve a referência e reveja a ligação.'
  ,FIRST_ISSUE_CONFIRMATION_REQUIRED:'Confirme uma primeira emissão formal nova. Uma revisão histórica desconhecida deve manter o nome original.'
  ,PREVIEW_NAME_CHANGED:'O nome ou a revisão mudou desde a pré-visualização. Reveja antes de confirmar.'
});

export function mountDocumentNomenclature({root, supabase, work, documents, identity, confirm = platformConfirm,
  catalogLoader=loadDocumentCatalog, ataOnly=false}) {
  if(ataOnly)documents=documents.filter(d=>d.tipo==='atas_reuniao');
  let dead = false, busy = false, catalog, context, draft = null, pending = null;
  const actor = JSON.stringify(identity());
  const current = () => !dead && root.isConnected && actor === JSON.stringify(identity());
  const rpc = async (name, body) => {
    const r = await supabase('rpc/' + name, {method:'POST',body:JSON.stringify(body)});
    const j = await r.json();
    if (!r.ok) throw Error(errors[j.message] || j.message || 'Nomenclatura indisponível.');
    if (j.version !== 1 || j.work_id !== work.id) throw Error('Resposta fora da obra.');
    return j;
  };
  const message = text => {if(current()) root.querySelector('[role=alert]').textContent = text;};
  const item = () => catalog.itens.find(i => i.linha_excel === Number(root.querySelector('[name=linha]').value));
  function syncOrigin(){
    const preserve=root.querySelector('[name=origem]').value==='externo'||item().padrao_nome==='Manter nomenclatura original';
    root.querySelectorAll('[data-name-token]').forEach(n=>{n.required=!preserve&&n.dataset.nameToken!=='FASE';n.disabled=preserve;});
    root.querySelector('[name=anterior]').disabled=preserve||!tokens(item()).includes('XX');
    root.querySelector('[name=numero_confirmado]').disabled=preserve;
    root.querySelector('[name=primeira_emissao_confirmada]').disabled=preserve;
    root.querySelector('[name=escopo]').disabled=preserve;
    root.querySelector('[name=escopo]').required=!preserve&&[24,25,39,40].includes(item().linha_excel);
  }
  function revisionOptions(){
    const i=item(),scope=root.querySelector('[name=escopo]').value||null;
    const rows=context.entries.filter(e=>e.linha===i.linha_excel&&(e.escopo_id||null)===scope&&!context.entries.some(n=>n.anterior_id===e.id));
    root.querySelector('[name=anterior]').innerHTML='<option value="">Sem revisão anterior nesta série</option>'+rows.map(e=>`<option value="${esc(e.id)}">${esc(e.nome)}</option>`).join('');
  }
  function renderFields() {
    draft = null;
    const i = item();
    root.querySelector('[data-name-rule]').textContent = `${i.documento} · ${i.padrao_nome} · ${i.observacoes || ''}`;
    root.querySelector('[data-name-fields]').innerHTML = tokens(i).filter(t => !['OBRA','XX'].includes(t)).concat(i.linha_excel===35?['FASE']:[]).map(t => `<label>${esc(t==='FASE'?'Código da fase · apenas para MQT por fase':labels[t] || t.replaceAll('_',' '))}<input data-name-token="${esc(t)}" ${t==='Nº'?'inputmode="numeric"':''} ${t==='FASE'?'':'required'}></label>`).join('');
    root.querySelector('[data-name-number]').hidden = !tokens(i).includes('Nº');
    root.querySelector('[data-name-first]').hidden = !tokens(i).includes('XX');
    root.querySelector('[data-name-scope]').hidden=![24,25,39,40].includes(i.linha_excel);
    root.querySelector('[name=escopo]').innerHTML='<option value="">Selecionar relação comprovada</option>'+([24,25].includes(i.linha_excel)?context.subempreitadas||[]:context.tees||[]).map(s=>`<option value="${esc(s.id)}">${esc([39,40].includes(i.linha_excel)?'TEE '+(s.numero||'Número por confirmar')+' · '+(s.nome||''):s.nome)}</option>`).join('');
    revisionOptions();
    root.querySelector('[data-name-confirm]').hidden = true;
    root.querySelector('[data-name-preview]').textContent = '';
    syncOrigin();
    if(ataOnly){
      root.querySelector('[data-name-first]').hidden=true;
      const doc=documents.find(d=>d.id===root.querySelector('[name=documento]').value);
      const number=root.querySelector('[data-name-token="Nº"]');
      number.value=doc?.numero_documento||'';number.readOnly=true;
      root.querySelector('[data-name-rule]').textContent+=doc?` · Número registado: ${doc.numero_documento||'em falta'} · Revisão registada: ${doc.revisao||'em falta'}`:'';
    }
    message('');
  }
  function render() {
    if (!current()) return;
    const wasOpen=root.querySelector('.nomenclature-panel')?.open || false;
    root.innerHTML = `<details class="document-upload-panel nomenclature-panel" ${wasOpen?'open':''}><summary>NOMENCLATURA DOCUMENTAL · ÍNDICE APROVADO</summary>
      <p>O nome de emissão é separado do ficheiro original. Não altera UUIDs, o Storage, aprovações ou referências históricas.</p>
      <p>Requisições de materiais e notas de encomenda: formato oficial pendente. Não é atribuída uma sigla.</p>
      <form data-name-form class="work-document-upload">
        <label>TIPO DOCUMENTAL<select name="linha">${catalog.itens.map(i => `<option value="${i.linha_excel}">${esc(i.documento)}</option>`).join('')}</select></label>
        <p data-name-rule></p>
        <label>FICHEIRO EXISTENTE<select name="documento" required><option value="">Selecionar ficheiro original</option>${documents.map(d=>`<option value="${esc(d.id)}">${esc(d.nome_arquivo)}</option>`).join('')}</select></label>
        <label>ORIGEM<select name="origem"><option value="externo">Externo, assinado ou histórico · preservar nome</option><option value="interno">Nova emissão interna · nome normalizado separado</option></select></label>
        <div data-name-fields class="nomenclature-fields"></div>
        <label data-name-scope hidden>CONTRATO DE SUBEMPREITADA / TEE DA MESMA OBRA<select name="escopo"></select></label>
        <label data-name-number hidden><input type="checkbox" name="numero_confirmado">Confirmo o número factual já atribuído pelo módulo. Este painel não cria sequências de PDE, TEE ou Autos.</label>
        <label data-name-first hidden><input type="checkbox" name="primeira_emissao_confirmada">Quando não existe revisão documental registada, confirmo que é uma nova primeira emissão formal (REV00). Não converte revisões históricas desconhecidas.</label>
        <label>REVISÃO ANTERIOR<select name="anterior"><option value="">Sem revisão anterior nesta série</option>${context.entries.filter(e=>!context.entries.some(n=>n.anterior_id===e.id)).map(e=>`<option value="${esc(e.id)}">${esc(e.nome)}</option>`).join('')}</select></label>
        <label>MOTIVO<input name="motivo" minlength="3" maxlength="1000"></label>
        <button type="submit">PRÉ-VISUALIZAR NOME</button><output data-name-preview aria-live="polite"></output>
        <button type="button" data-name-confirm hidden>CONFIRMAR NOME DE EMISSÃO</button>
        <p role="alert"></p>
      </form>
      <h4>NOMES E REVISÕES REGISTADOS</h4>${context.entries.map(e=>`<article><strong>${esc(e.nome)}</strong><p>${esc(catalog.itens.find(i=>i.linha_excel===e.linha)?.documento)}</p><p>Original: ${esc(e.nome_original)} · ${esc(e.autor_nome||e.autor_id)} · ${esc(new Intl.DateTimeFormat('pt-PT',{dateStyle:'short',timeStyle:'short',timeZone:'Europe/Lisbon'}).format(new Date(e.criado_em)))}</p><p>${esc(e.motivo)}</p>${documents.some(d=>d.id===e.documento_id)?`<button type="button" data-name-download="${esc(e.id)}">DESCARREGAR CÓPIA COM ESTE NOME</button>`:'<p>Ficheiro indisponível; histórico preservado.</p>'}</article>`).join('') || '<p>Sem nomes de emissão registados. Os nomes anteriores permanecem intactos.</p>'}
      <p>A confirmação utiliza as permissões do índice existente. Pré-visualizar não regista alterações.</p></details>`;
    root.querySelector('[data-name-confirm]').disabled = !context.can_write;
    renderFields();
  }
  async function load() {
    try {
      [catalog,context] = await Promise.all([catalogLoader(),rpc('fn_documentos_nomes_contexto_v1',{p_obra:work.id})]);
      if (!current()) return;
      if (context.catalog_sha256 !== catalog.sha256_fonte || typeof context.can_write!=='boolean' || !Array.isArray(context.entries) || context.entries.some(e=>e.obra_id!==work.id || e.empresa_id!==context.empresa_id)) throw Error('Catálogo ou âmbito divergente.');
      if(ataOnly){catalog={...catalog,itens:catalog.itens.filter(i=>i.linha_excel===13)};context={...context,entries:context.entries.filter(e=>e.linha===13)};if(catalog.itens.length!==1)throw Error('Tipo de ata indisponível.');}
      render();
    } catch(e) {if(current()) root.textContent = 'Nomenclatura indisponível: ' + e.message;}
  }
  function body() {
    const f = root.querySelector('form'), doc = documents.find(d=>d.id===f.elements.documento.value);
    if (!doc) throw Error('Selecione o ficheiro original.');
    if(ataOnly){
      if(!/^[0-9]{1,9}$/.test(doc.numero_documento||'')||Number(doc.numero_documento)<1)throw Error('Número da ata em falta ou não comprovado no registo original.');
      if(!/^(REV)?[0-9]{1,9}$/.test(doc.revisao||''))throw Error('Revisão da ata em falta ou não comprovada no registo original.');
    }
    const prev = context.entries.find(e=>e.id===f.elements.anterior.value);
    return {documento_id:doc.id,nome_original_esperado:doc.nome_arquivo,arquivo_url_esperado:doc.arquivo_url,origem:f.elements.origem.value,
      linha_excel:item().linha_excel,campos:Object.fromEntries([...root.querySelectorAll('[data-name-token]')].map(n=>[n.dataset.nameToken,n.value])),
      numero_confirmado:f.elements.numero_confirmado.checked,primeira_emissao_confirmada:f.elements.primeira_emissao_confirmada.checked,escopo_id:f.elements.escopo.value||null,anterior_id:prev?.id || null,revisao_esperada:prev?.revisao ?? null,motivo:f.elements.motivo.value.trim()};
  }
  const change = e => {if(busy)return;draft=null;root.querySelector('[data-name-confirm]').hidden=true;message('');if(e.target.name==='linha'||(ataOnly&&e.target.name==='documento'))renderFields();if(e.target.name==='origem')syncOrigin();if(e.target.name==='escopo')revisionOptions();};
  const submit = async e => {
    if(!e.target.matches('[data-name-form]'))return;
    e.preventDefault();if(busy||!current())return;
    busy=true; e.target.inert=true;
    try {
      const b=body(),doc=documents.find(d=>d.id===b.documento_id);
      if(b.origem==='externo'||item().padrao_nome==='Manter nomenclatura original') {
        root.querySelector('[data-name-preview]').textContent=buildDocumentName(item(),{}, {external:true,originalName:doc.nome_arquivo});
        return;
      }
      const key=JSON.stringify(b);if(pending?.key!==key)pending={key,id:crypto.randomUUID()};
      const r=await rpc('fn_documentos_nome_operar_v1',{p_obra:work.id,p_dados:b,p_request:pending.id,p_confirmar:false});
      if(!current())return;
      if(r.request_id!==pending.id||r.committed!==false)throw Error('Pré-visualização não confirmada.');
      draft={body:b,name:r.nome,request:pending.id};
      root.querySelector('[data-name-preview]').textContent=r.nome;
      root.querySelector('[data-name-confirm]').hidden=!context.can_write;
    } catch(e){message(e.message);} finally {busy=false;if(current())e.target.inert=false;}
  };
  const click = async e => {
    const download=e.target.closest('[data-name-download]');
    if(download){
      const n=context.entries.find(n=>n.id===download.dataset.nameDownload),d=documents.find(d=>d.id===n?.documento_id);
      if(!current()||!d||d.arquivo_url!==n.arquivo_url_original){message('A referência do ficheiro mudou ou está indisponível. Atualize a ficha.');return;}
      root.dispatchEvent(new CustomEvent('document-named-copy',{bubbles:true,detail:{path:d.arquivo_url,name:n.nome}}));return;
    }
    if(!e.target.closest('[data-name-confirm]')||!draft||busy||!current())return;
    busy=true;const f=root.querySelector('form');f.inert=true;
    try {
      if(JSON.stringify(body())!==JSON.stringify(draft.body))throw Error('Os campos mudaram. Pré-visualize novamente.');
      if(draft.body.motivo.length<3)throw Error(errors.REASON_REQUIRED);
      if(!await confirm(`Confirmar o nome de emissão?\n${draft.name}\nO nome e o ficheiro originais permanecem intactos.`))return;
      if(!current())return;
      const r=await rpc('fn_documentos_nome_operar_v1',{p_obra:work.id,p_dados:{...draft.body,nome_esperado:draft.name},p_request:draft.request,p_confirmar:true});
      if(!current())return;
      if(r.committed!==true||r.request_id!==draft.request||r.nome!==draft.name)throw Error('Nome não confirmado. Atualize antes de repetir.');
      pending=null;draft=null;await load();
    }catch(e){message(e.message);}finally{busy=false;if(current())f.inert=false;}
  };
  root.addEventListener('change',change);root.addEventListener('input',change);root.addEventListener('submit',submit);root.addEventListener('click',click);
  return {ready:load(),destroy(){dead=true;for(const [n,f]of[['change',change],['input',change],['submit',submit],['click',click]])root.removeEventListener(n,f);root.innerHTML='';}};
}
