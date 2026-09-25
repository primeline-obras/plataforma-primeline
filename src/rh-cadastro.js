const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const RH_FIELDS = [
  ['nome','Nome'],['funcao','Função'],['nivel','Nível'],['valor_hora','Valor/hora','number'],
  ['nif','NIF'],['email','Email','email'],['contacto','Contacto','tel'],['morada','Morada'],
  ['data_admissao','Admissão','date'],['data_nascimento','Nascimento','date'],['codigo_rh','Código RH'],
  ['observacoes','Observações'],['seguranca_social_ok','Inscrição na Segurança Social confirmada','boolean'],
  ['seguro_ok','Seguro confirmado','boolean'],['registo_trabalhador_ok','Registo do trabalhador confirmado','boolean'],
  ['niss','NISS'],['tipo_contrato','Tipo de contrato'],['data_inicio','Início do contrato','date'],['data_fim_prevista','Fim previsto do contrato','date']
];
export function parseRhValue(value, type) {
  if (value == null || String(value).trim() === '') return undefined;
  if (type === 'boolean') {
    const text=String(value).trim().toLowerCase();
    if (['sim','true','1'].includes(text)) return true;
    if (['não','nao','false','0'].includes(text)) return false;
    throw new Error('Use Sim ou Não.');
  }
  if (type === 'number') {
    const text=String(value).trim().replace(/\s/g,'');
    if (!/^(\d+|\d{1,3}(\.\d{3})+)(,\d+)?$/.test(text) && !/^\d+(\.\d+)?$/.test(text)) throw new Error('Valor numérico inválido.');
    const result=Number(text.includes(',') ? text.replace(/\./g,'').replace(',','.') : text);
    if (!Number.isFinite(result) || result<0) throw new Error('Valor/hora inválido.');
    return result;
  }
  if (type === 'date') {
    let text=String(value).trim();
    const pt=/^(\d{2})\/(\d{2})\/(\d{4})$/.exec(text);
    if(pt) text=`${pt[3]}-${pt[2]}-${pt[1]}`;
    if(!/^\d{4}-\d{2}-\d{2}$/.test(text) || Number.isNaN(Date.parse(text)) || new Date(text).toISOString().slice(0,10)!==text) throw new Error('Use AAAA-MM-DD ou DD/MM/AAAA; confirme a data.');
    return text;
  }
  return String(value).trim();
}
function flattened(record) {
  const active=record.contratos.filter(c=>c.estado==='ativo');
  if(active.length>1) throw new Error(`${record.colaborador.nome}: existem vários contratos ativos. Rever primeiro.`);
  return {...record.colaborador,niss:record.niss,...Object.fromEntries(['tipo_contrato','data_inicio','data_fim_prevista'].map(k=>[k,active[0]?.[k]??null]))};
}
export const contractTypeLabel = type => ({a_prazo:'Contrato de Trabalho a Termo Certo',tempo_indeterminado:'Contrato de Trabalho por Tempo Indeterminado'}[type] || 'Tipo por confirmar');
export function prepareRhRows(rows, records) {
  const byId=new Map(records.map(r=>[r.colaborador.id,r])); const seen=new Set();
  return rows.map((row,index)=>{
    const record=byId.get(String(row.id||'').trim()); const errors=[]; const changes=[];
    const payload={id:String(row.id||'').trim(),versao:String(row.versao||''),campos:{}};
    if(!record) errors.push('ID não encontrado. Use o modelo exportado.');
    if(seen.has(payload.id)) errors.push('ID repetido no ficheiro.');
    seen.add(payload.id);
    if(!payload.versao) errors.push('Versão ausente; volte a exportar o modelo.');
    let before={}; try { if(record) before=flattened(record); } catch(e) { errors.push(e.message); }
    for(const [key,label,type] of RH_FIELDS) {
      try {
        const value=parseRhValue(row[key],type); if(value===undefined) continue;
        if(key==='niss') payload.niss=value;
        else if(['tipo_contrato','data_inicio','data_fim_prevista'].includes(key)) (payload.contrato??={})[key]=value;
        else payload.campos[key]=value;
        if(String(value)!==String(before[key]??'')) changes.push({label,antes:before[key],depois:value});
      } catch(e) { errors.push(`${label}: ${e.message}`); }
    }
    return {linha:index+2,nome:record?.colaborador.nome||row.nome||'',payload,changes,errors};
  });
}
export function createRhCadastro({api,canManage,isManagement,works,refresh,toast,configured}) {
  const $=s=>document.querySelector(s);
  const rpc=async(name,body)=>{
    if(!configured()) throw new Error('Esta operação exige ligação à plataforma.');
    const response=await api(`rpc/${name}`,{method:'POST',body:JSON.stringify(body)});
    const data=await response.json(); if(!response.ok) throw new Error(data.message||'Não foi possível concluir.'); return data;
  };
  const show=(title,html)=>{ $('#workflow-dialog-title').textContent=title; $('#workflow-dialog-content').innerHTML=html; $('#workflow-dialog').hidden=false; };
  function field(key,label,type,value,required=false) {
    if(key==='observacoes') return `<label>${esc(label)}<textarea name="observacoes" rows="3">${esc(value)}</textarea></label>`;
    if(type==='boolean') return `<label>${esc(label)}<select name="${key}"><option value="">Não confirmado</option><option value="true" ${value===true?'selected':''}>Sim</option><option value="false" ${value===false?'selected':''}>Não</option></select></label>`;
    return `<label>${esc(label)}<input name="${key}" type="${type||'text'}" value="${esc(value)}" ${required?'required':''} ${type==='number'?'min="0" step="0.01"':''} ${['nif','niss'].includes(key)?`inputmode="numeric" maxlength="${key==='nif'?9:11}"`:''}></label>`;
  }
  async function open(person=null) {
    if(!canManage()) return;
    try {
      const record=person?(await rpc('fn_rh_consultar',{p_id:person.id}))[0]:null;
      if(person&&!record) throw new Error('Colaborador não disponível para edição.');
      const values=record?flattened(record):{};
      const general=RH_FIELDS.filter(([k])=>!['tipo_contrato','data_inicio','data_fim_prevista'].includes(k));
      show(person?`EDITAR · ${person.nome}`:'NOVO COLABORADOR',`<form id="rh-form">
        <p>Nome, função e admissão são obrigatórios. Na edição individual, apagar um campo opcional limpa esse valor.</p>
        <fieldset class="work-template-fieldset"><legend>IDENTIFICAÇÃO E CONTACTOS</legend><div class="rh-field-grid">${general.filter(([k,,t])=>t!=='boolean'&&k!=='observacoes').map(([k,l,t])=>field(k,l,t,values[k],['nome','funcao','data_admissao'].includes(k))).join('')}</div></fieldset>
        <fieldset class="work-template-fieldset"><legend>CONTRATO ATIVO</legend>
          <label>Tipo<select name="tipo_contrato"><option value="">Ainda não registado</option><option value="a_prazo" ${values.tipo_contrato==='a_prazo'?'selected':''}>Contrato de Trabalho a Termo Certo</option><option value="tempo_indeterminado" ${values.tipo_contrato==='tempo_indeterminado'?'selected':''}>Contrato de Trabalho por Tempo Indeterminado</option></select></label>
          <div class="form-row">${field('data_inicio','Início','date',values.data_inicio)}${field('data_fim_prevista','Fim previsto','date',values.data_fim_prevista)}</div>
          <small>Corrige os dados do contrato ativo; não regista uma renovação. Os contratos anteriores são preservados. Anexe o PDF em Documentos do colaborador.</small>
          ${record?`<details><summary>Histórico: ${record.contratos.length} contrato(s)</summary>${record.contratos.map(c=>`<p>${esc(contractTypeLabel(c.tipo_contrato))} · ${esc(c.data_inicio)} — ${esc(c.data_fim_prevista||(c.tipo_contrato==='tempo_indeterminado'?'Sem termo':'Fim não informado'))} · ${esc(c.estado)}</p>`).join('')}</details>`:''}
        </fieldset>
        <fieldset class="work-template-fieldset"><legend>CONFORMIDADE E NOTAS</legend><div class="rh-field-grid">${general.filter(([,,t])=>t==='boolean').map(([k,l,t])=>field(k,l,t,values[k])).join('')}</div>${field('observacoes','Observações','text',values.observacoes)}</fieldset>
        ${person?field('data_saida','Data de saída (inativa sem apagar histórico)','date',values.data_saida):`<fieldset class="work-template-fieldset"><legend>ALOCAÇÃO INICIAL</legend><div class="form-row"><label>Local<select name="alocacao_tipo"><option value="obra">Obra</option><option value="escritorio">Escritório</option></select></label><label data-rh-work>Obra<select name="obra_id" required><option value="">Selecionar</option>${works().filter(w=>['preparacao','em_curso'].includes(w.situacao)).map(w=>`<option value="${esc(w.id)}">${esc(w.numero)} · ${esc(w.nome)}</option>`).join('')}</select></label></div><div class="form-row">${field('epi_data','Entrega inicial de EPI','date','')}${field('medicina_data','Consulta inicial de medicina do trabalho','date','')}</div></fieldset>`}
        <p class="form-error" role="alert"></p><div class="dialog-actions"><button type="button" class="outline-action" data-close-workflow>CANCELAR</button><button type="submit" class="primary-button">GUARDAR</button></div></form>`);
      const form=$('#rh-form');
      form.elements.nome.focus({preventScroll:true});
      const updateContract=()=>{const type=form.elements.tipo_contrato.value;form.elements.data_inicio.required=!!type;form.elements.data_fim_prevista.required=type==='a_prazo';form.elements.data_fim_prevista.disabled=type==='tempo_indeterminado';};
      form.elements.tipo_contrato.onchange=updateContract;updateContract();
      if(!person){const updateWork=()=>{const enabled=form.elements.alocacao_tipo.value==='obra';form.elements.obra_id.required=enabled;form.elements.obra_id.disabled=!enabled;form.querySelector('[data-rh-work]').hidden=!enabled;};form.elements.alocacao_tipo.onchange=updateWork;updateWork();}
      form.onsubmit=async event=>{
        event.preventDefault();const button=form.querySelector('[type=submit]');button.disabled=true;
        try {
          const values=Object.fromEntries(new FormData(form));const payload={id:person?.id||null,versao:record?.versao,campos:{}};
          for(const [k,,t] of general) {const value=parseRhValue(values[k],t)??null;if(k==='niss')payload.niss=value;else payload.campos[k]=value;}
          if(person) payload.campos.data_saida=values.data_saida||null;
          else Object.assign(payload,{alocacao_tipo:values.alocacao_tipo,obra_id:values.obra_id||null,epi_data:values.epi_data||null,medicina_data:values.medicina_data||null});
          if(values.tipo_contrato)payload.contrato={tipo_contrato:values.tipo_contrato,data_inicio:values.data_inicio||null,data_fim_prevista:values.tipo_contrato==='tempo_indeterminado'?null:values.data_fim_prevista||null};
          else if(record?.contratos.some(c=>c.estado==='ativo'&&c.tipo_contrato)) throw new Error('Não pode apagar o contrato ativo retirando o tipo.');
          else {
            const pending=record?.contratos.find(c=>c.estado==='ativo'&&!c.tipo_contrato);
            if((values.data_inicio||'')!==(pending?.data_inicio||'')||(values.data_fim_prevista||'')!==(pending?.data_fim_prevista||'')) throw new Error('Selecione o tipo de contrato para alterar os dados contratuais neste formulário.');
          }
          await rpc('fn_rh_guardar',{p_dados:payload});$('#workflow-dialog').hidden=true;$('#workflow-dialog-content').innerHTML='';
          try { await refresh();toast('Cadastro e contrato guardados.'); } catch {toast('Guardado, mas a lista não atualizou. Atualize a página.','error');}
        }catch(e){form.querySelector('.form-error').textContent=e.message;}finally{button.disabled=false;}
      };
    }catch(e){toast(e.message,'error');}
  }
  async function openImport(){
    if(!isManagement()) return;
    try {
      if(!globalThis.XLSX)throw new Error('O leitor Excel não carregou. Atualize a página.');
      let prepared=[];
      show('COMPLETAR CADASTROS · EXCEL',`<section id="rh-import"><p>Atualiza colaboradores existentes pelo ID. Não cria pessoas, não altera alocações nem inativa colaboradores. Células vazias preservam os dados. O modelo contém dados pessoais: guarde-o num local restrito.</p><button type="button" class="outline-action" data-rh-template>DESCARREGAR MODELO PREENCHIDO</button><label>Ficheiro Excel<input type="file" accept=".xlsx" data-rh-file></label><p class="form-error" role="alert"></p><div data-rh-preview></div><button type="button" class="primary-button" data-rh-confirm disabled>CONFIRMAR ATUALIZAÇÃO</button></section>`);
      const root=$('#rh-import'),error=root.querySelector('.form-error'),confirm=root.querySelector('[data-rh-confirm]'),input=root.querySelector('[data-rh-file]');
      root.querySelector('[data-rh-template]').onclick=async()=>{
        try {
          const records=await rpc('fn_rh_consultar',{});
          const data=records.map(record=>{const flat=flattened(record);return [record.colaborador.id,record.versao,...RH_FIELDS.map(([k,,t])=>flat[k]==null?'':t==='boolean'?(flat[k]?'Sim':'Não'):flat[k])];});
          const book=XLSX.utils.book_new();const sheet=XLSX.utils.aoa_to_sheet([['id','versao',...RH_FIELDS.map(([k])=>k)],...data]);
          sheet['!cols']=[{wch:38},{wch:34},...RH_FIELDS.map(()=>({wch:24}))];
          XLSX.utils.book_append_sheet(book,sheet,'Colaboradores');
          XLSX.utils.book_append_sheet(book,XLSX.utils.aoa_to_sheet([
            ['Instruções'],['Não altere ID ou versão. Não adicione colaboradores neste ficheiro.'],['Vazios mantêm dados. Para limpar um campo use a edição individual.'],
            ['Datas: AAAA-MM-DD ou DD/MM/AAAA. Tipos: a_prazo / tempo_indeterminado.'],['Seguro/registo/SS: Sim ou Não. NIF e NISS devem ser texto, preservando zeros.'],
            ['Início confirmado pode ser importado sem tipo. Campos vazios preservam os dados existentes.'],
            ['Contrato incompleto: consulte os avisos; os restantes dados podem ser atualizados. Para limpar um fim previsto, use o formulário individual.'],
            ...RH_FIELDS.map(([k,l])=>[k,l])]),'Instruções');
          XLSX.writeFile(book,'cadastro-rh.xlsx');
        }catch(e){error.textContent=e.message;}
      };
      input.onchange=async()=>{
        confirm.disabled=true;prepared=[];error.textContent='';root.querySelector('[data-rh-preview]').innerHTML='';input.disabled=true;
        try {
          const file=input.files[0];if(!file)return;if(file.size>10*1024*1024)throw new Error('Máximo 10 MB por ficheiro.');
          const book=XLSX.read(await file.arrayBuffer(),{type:'array',cellDates:false});const sheet=book.Sheets.Colaboradores;
          if(!sheet)throw new Error('Folha Colaboradores não encontrada.');
          const matrix=XLSX.utils.sheet_to_json(sheet,{header:1,raw:true,defval:''});
          const headers=matrix[0]||[],allowed=['id','versao',...RH_FIELDS.map(([k])=>k)];
          if(headers.length!==allowed.length||new Set(headers).size!==headers.length||allowed.some(k=>!headers.includes(k)))throw new Error('Cabeçalhos diferentes do modelo. Exporte novamente.');
          if(matrix.length>1001)throw new Error('Máximo 1000 colaboradores por ficheiro.');
          const rows=matrix.slice(1).filter(row=>row.some(v=>v!=='')).map(row=>Object.fromEntries(headers.map((k,i)=>{
            let value=row[i];if(typeof value==='number'&&RH_FIELDS.find(f=>f[0]===k)?.[2]==='date'){const d=XLSX.SSF.parse_date_code(value);if(!d)throw new Error('Data Excel inválida.');value=`${d.y}-${String(d.m).padStart(2,'0')}-${String(d.d).padStart(2,'0')}`;}return [k,value];
          })));
          if(!rows.length)throw new Error('Sem linhas para validar.');
          prepared=prepareRhRows(rows,await rpc('fn_rh_consultar',{}));
          if(!prepared.some(r=>r.errors.length)){
            const result=await rpc('fn_rh_importar',{p_linhas:prepared.map(r=>r.payload),p_confirmar:false});
            result.linhas.forEach((r,i)=>{if(!r.ok)prepared[i].errors.push(r.erro);else {prepared[i].alterado=r.alterado;prepared[i].avisos=r.avisos||[];}});
          }
          const errors=prepared.filter(r=>r.errors.length).length,changed=prepared.filter(r=>r.alterado).length;
          root.querySelector('[data-rh-preview]').innerHTML=`<p>${prepared.length} linhas · ${changed} a atualizar · ${errors} com erro · ${prepared.filter(r=>r.avisos?.length).length} com avisos</p>${prepared.map(r=>`<details><summary>Linha ${r.linha} · ${esc(r.nome)} · ${r.errors.length?'ERRO':r.alterado?'Alterações':'Sem alterações'}${r.avisos?.length?' · AVISO':''}</summary>${r.errors.map(e=>`<p>${esc(e)}</p>`).join('')}${(r.avisos||[]).map(a=>`<p><strong>Aviso:</strong> ${esc(a)}</p>`).join('')}${r.changes.map(c=>`<p><strong>${esc(c.label)}</strong>: ${esc(c.antes??'Vazio')} → ${esc(c.depois)}</p>`).join('')}</details>`).join('')}`;
          confirm.disabled=!!errors||!changed;
        }catch(e){error.textContent=e.message;}finally{input.disabled=false;}
      };
      confirm.onclick=async()=>{
        confirm.disabled=true;input.disabled=true;error.textContent='';
        try {
          const result=await rpc('fn_rh_importar',{p_linhas:prepared.map(r=>r.payload),p_confirmar:true});
          prepared=[];root.querySelector('[data-rh-preview]').textContent=`Guardado: ${result.linhas.filter(r=>r.alterado).length} cadastros atualizados. ${result.linhas.flatMap(r=>r.avisos||[]).length} aviso(s). ${[...new Set(result.linhas.flatMap(r=>r.avisos||[]))].join(' ')} Para verificar a reimportação, selecione novamente o mesmo ficheiro.`;
          input.value='';try{await refresh();}catch{toast('Dados guardados. Atualize a página para renovar a lista.','error');}
        }catch(e){error.textContent=e.message+' Volte a selecionar o ficheiro para validar antes de tentar novamente.';}finally{input.disabled=false;}
      };
    }catch(e){toast(e.message,'error');}
  }
  return {open,openImport};
}
