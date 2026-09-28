import { workforceRequest } from './workforce-policy.js';

const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const localDate = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`; };
const periodLabel = p => ({dia_inteiro:'Dia inteiro',manha:'Manhã',tarde:'Tarde'}[p] || p);
const normalize = s => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase();

export function createForemanTeam({root, supabase, getRole, toast, onAttendance, onHistory}) {
  let date = localDate(), workId = null, data = {obras:[],equipa:[],candidatos:[]};
  let loading = false, error = '', generation = 0, dialog = false, busy = false, selected = '', period = 'dia_inteiro', search = '', preview = null;
  const allowed = () => getRole() === 'encarregado';
  const work = () => data.obras.find(w => w.id === workId);
  function situation(c) {
    if (c.ausente) return 'Ausente nesta data · movimentação indisponível';
    if (!c.alocacoes?.length) return 'Sem obra nesta data';
    return `${c.alocacoes.map(a=>`Obra ${a.obra_numero || '—'} · ${periodLabel(a.periodo)}`).join(' / ')}${c.alocacoes.length > 1 ? ' · Múltiplas alocações · contactar ADM/Gestão' : ''}`;
  }
  function candidates() {
    const target = root.querySelector('[data-candidates]');
    if (!target) return;
    const list = data.candidatos.filter(c=>normalize(c.nome).includes(normalize(search)));
    target.innerHTML = list.map(c=>`<button type="button" data-candidate="${esc(c.colaborador_id)}" aria-pressed="${c.colaborador_id===selected}" ${c.ausente||busy?'disabled':''}><strong>${esc(c.nome)}</strong><span>${esc(c.funcao || 'Função não indicada')}</span><small>${esc(situation(c))}</small></button>`).join('') || '<p>Sem resultados.</p>';
  }
  function render() {
    if (!allowed()) { root.innerHTML = ''; return; }
    const people = [...new Map(data.equipa.map(c=>[c.colaborador_id,c])).values()];
    const count = name => people.filter(c=>name==='encarreg' ? /encarreg|^enc[.\s]/.test(normalize(c.funcao)) : normalize(c.funcao).includes(name)).length;
    root.innerHTML = `<section class="foreman-team"><h1>EQUIPA OBRA ${esc(work()?.numero || '—')}</h1><p>${esc(work()?.nome || '')}</p>
      <div class="foreman-toolbar"><label>DATA<input type="date" data-team-date value="${date}" ${busy?'disabled':''}></label>
      ${data.obras.length>1?`<label>OBRA<select data-team-work ${busy?'disabled':''}>${data.obras.map(w=>`<option value="${esc(w.id)}" ${w.id===workId?'selected':''}>${esc(w.numero)} · ${esc(w.nome)}</option>`).join('')}</select></label>`:''}
      <button type="button" data-team-refresh ${busy?'disabled':''}>ATUALIZAR</button><button type="button" data-team-attendance ${!work()||busy?'disabled':''}>FOLHA DE PONTO</button><button type="button" data-team-history ${busy?'disabled':''}>HISTÓRICO DE MOVIMENTAÇÕES</button></div>
      <p class="foreman-summary">${people.length} pessoas · ${count('encarreg')} Encarregados · ${count('pedreir')} Pedreiros · ${count('servente')} Serventes</p>
      ${loading?'<p role="status">A carregar equipa…</p>':error?`<p role="alert">${esc(error)}</p>`:!work()?'<p>Sem obra autorizada. Contacte ADM/Gestão.</p>':`<button type="button" class="foreman-add" data-team-add>＋ ADICIONAR COLABORADOR</button><div class="foreman-list">${people.map(c=>`<article><strong>${esc(c.nome)}</strong><span>${esc(c.funcao || 'Função não indicada')}</span><span>${esc([...new Set(data.equipa.filter(p=>p.colaborador_id===c.colaborador_id).map(p=>periodLabel(p.periodo)))].join(' + '))}</span></article>`).join('') || '<p>Sem colaboradores alocados nesta data.</p>'}</div>`}
      ${dialog?`<section class="foreman-add-panel" role="region" aria-label="Adicionar colaborador"><h2>ADICIONAR COLABORADOR</h2><p>Obra ${esc(work()?.numero)} · ${date}</p><label>PESQUISAR NOME<input type="search" data-team-search value="${esc(search)}" ${busy?'disabled':''}></label><div data-candidates></div><label>PERÍODO<select data-team-period ${busy?'disabled':''}>${['dia_inteiro','manha','tarde'].map(p=>`<option value="${p}" ${p===period?'selected':''}>${periodLabel(p)}</option>`).join('')}</select></label><p data-team-preview role="status"></p><p data-team-error role="alert"></p><button type="button" data-team-preview-button ${!selected||busy?'disabled':''}>${preview?'CONFIRMAR MOVIMENTAÇÃO':'PRÉ-VISUALIZAR'}</button><button type="button" data-team-cancel ${busy?'disabled':''}>CANCELAR</button></section>`:''}</section>`;
    candidates();
    if (preview) {
      const c = data.candidatos.find(c=>c.colaborador_id===selected);
      const origin = c?.alocacoes?.find(a=>a.obra_id===preview.obra_origem_id);
      root.querySelector('[data-team-preview]').textContent = preview.acao === 'mover'
        ? `${c.nome} atualmente na Obra ${origin?.obra_numero || preview.obra_origem_id}. Mover para a Obra ${work().numero}? ${date} · ${periodLabel(period)}.`
        : `${c.nome} não possui outra alocação neste período. Adicionar à Obra ${work().numero}? ${date} · ${periodLabel(period)}.`;
    }
  }
  async function load(context = {}) {
    if (!allowed()) return;
    if (busy) return;
    if (context.workId) workId = context.workId;
    if (context.date) date = context.date;
    const current = ++generation;
    dialog = false; preview = null; loading = true; error = ''; render();
    try {
      const response = await supabase('rpc/fn_equipa_obra_encarregado',{method:'POST',body:JSON.stringify({p_data:date,p_obra_id:workId})});
      const result = await response.json();
      if (current !== generation || !allowed()) return;
      if (!response.ok) throw new Error(result.message || 'Não foi possível carregar a equipa.');
      if (!Array.isArray(result.obras)||!Array.isArray(result.equipa)||!Array.isArray(result.candidatos) || (result.obra_id && !result.obras.some(w=>w.id===result.obra_id))) throw new Error('Resposta de equipa inválida. Contacte ADM/Gestão.');
      data = result; workId = result.obra_id;
    } catch(e) { if(current===generation) {error=e.message; data={obras:[],equipa:[],candidatos:[]}; workId=null;} }
    finally { if(current===generation) {loading=false;render();} }
  }
  root.addEventListener('input', e=> { if(e.target.matches('[data-team-search]')) {search=e.target.value;candidates();} });
  root.addEventListener('change', e=> {
    if (busy || !allowed()) return;
    if(e.target.matches('[data-team-date]') && e.target.value) {date=e.target.value;load();}
    if(e.target.matches('[data-team-work]') && data.obras.some(w=>w.id===e.target.value)) {workId=e.target.value;load();}
    if(e.target.matches('[data-team-period]')) {period=e.target.value;preview=null;render();}
  });
  root.addEventListener('click', async e=> {
    const button = e.target.closest('button');
    if (!button || button.disabled || busy || !allowed()) return;
    if(button.matches('[data-team-refresh]')) return load();
    if(button.matches('[data-team-attendance]')) return onAttendance({workId,date});
    if(button.matches('[data-team-history]')) return onHistory({workId,date});
    if(button.matches('[data-team-add]')) {dialog=true;selected='';search='';period='dia_inteiro';preview=null;render();root.querySelector('[data-team-search]').focus();return;}
    if(button.matches('[data-team-cancel]')) {dialog=false;preview=null;render();root.querySelector('[data-team-add]')?.focus();return;}
    if(button.matches('[data-candidate]')) {
      const c = data.candidatos.find(c=>c.colaborador_id===button.dataset.candidate);
      if(!c||c.ausente) return;
      selected=c.colaborador_id;preview=null;render();return;
    }
    if(!button.matches('[data-team-preview-button]')) return;
    const c = data.candidatos.find(c=>c.colaborador_id===selected);
    if(!c || c.ausente || !work()) return;
    const confirming = Boolean(preview);
    busy=true;render();
    try {
      const result = await workforceRequest(supabase,'minha_obra',{obra_id:workId,colaborador_id:selected,data:date,periodo:period},confirming,preview?.versao ?? null);
      if(!confirming) {
        if(!result.versao || !['adicionar','mover'].includes(result.acao)) throw new Error(result.message || 'Pré-visualização não confirmável.');
        preview=result;busy=false;render();root.querySelector('[data-team-preview-button]').focus();
      } else {busy=false;dialog=false;preview=null;toast('Movimentação concluída e registada.');await load();}
    } catch(e) {preview=null;busy=false;render();root.querySelector('[data-team-error]').textContent=`${e.message} Contacte ADM/Gestão.`;}
  });
  return {show:load};
}
