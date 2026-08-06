import { generateRncPdf } from "./rnc-pdf.js?v=2";

const esc = value => String(value ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[c]);
const today = () => new Date().toISOString().slice(0, 10);
const labels = { aberto: "Aberto", em_correcao: "Em correção", verificado: "Verificado", fechado: "Fechado", critica: "Crítica", maior: "Maior", menor: "Menor", execucao_propria: "Execução própria", subempreiteiro: "Subempreiteiro", material: "Material", projeto_especificacao: "Projeto / Especificação", outro: "Outro" };
export const rncCode = (work, numero) => `RNC-${String(work?.numero || "OBRA").trim()}-${String(numero).padStart(3, "0")}`;

export function createRncModule({ root, supabase, isConfigured, getWorks, getRole, uploadWorkDocument, downloadWorkDocument, toast }) {
  const state = { workId: "", rows: [], annexes: [], phases: [], subcontracts: [], users: [], canEdit: false, loading: false, openForm: false };
  const api = async (path, options = {}) => {
    const response = await supabase(path, options);
    if (!response.ok) { const payload = await response.json().catch(() => ({})); throw new Error(payload.message || payload.details || "Não foi possível concluir a operação."); }
    if (response.status === 204) return null;
    return response.json();
  };
  const work = () => getWorks().find(item => item.id === state.workId);
  const phase = id => state.phases.find(item => item.id === id);
  const subcontract = id => state.subcontracts.find(item => item.id === id);
  const user = id => state.users.find(item => item.id === id)?.nome || "—";
  const annexesFor = id => state.annexes.filter(item => item.rnc_id === id);
  const canCreate = () => ["gerencia", "diretor_obra", "preparador", "encarregado"].includes(getRole());

  function newForm() {
    if (!state.openForm || !canCreate()) return "";
    return `<form class="rnc-form" data-rnc-create>
      <div class="rnc-form-grid"><label>CÓDIGO DA RNC<input value="RNC-${esc(work()?.numero || "OBRA")}-[automático]" disabled></label><label>DATA DE DETEÇÃO<input type="date" name="data_deteccao" value="${today()}" required></label>
      <label>FASE<select name="fase_id"><option value="">Sem fase</option>${state.phases.map(item => `<option value="${item.id}">${esc(item.codigo || "")} · ${esc(item.descricao)}</option>`).join("")}</select></label><label>LOCAL DA OCORRÊNCIA<input name="local_ocorrencia" maxlength="240"></label>
      <label>ORIGEM<select name="origem" required>${["execucao_propria", "subempreiteiro", "material", "projeto_especificacao", "outro"].map(value => `<option value="${value}">${labels[value]}</option>`).join("")}</select></label>
      <label>GRAVIDADE<select name="gravidade" required><option value="critica">Crítica</option><option value="maior">Maior</option><option value="menor">Menor</option></select></label>
      <label class="rnc-subcontract" hidden>SUBEMPREITADA<select name="subempreitada_id"><option value="">Selecionar</option>${state.subcontracts.map(item => `<option value="${item.id}">${esc(item.especialidade || "Subempreitada")}</option>`).join("")}</select></label>
      <label class="wide">DESCRIÇÃO<textarea name="descricao" rows="4" required></textarea></label>
      <label class="wide rnc-file-picker">FOTOS / EVIDÊNCIAS (OPCIONAL)<input type="file" name="anexos" multiple accept="application/pdf,image/jpeg,image/png,image/webp,.pdf,.jpg,.jpeg,.png,.webp"></label></div>
      <p class="form-error"></p><button class="primary-button" type="submit">REGISTAR RNC <span>→</span></button></form>`;
  }

  function actions(row) {
    if (!state.canEdit) return `<div class="readonly-note">CONSULTA · O ENCARREGADO NÃO ALTERA O ESTADO</div>`;
    if (row.estado === "aberto") return `<form class="rnc-inline-form" data-rnc-correction="${row.id}"><label>AÇÃO CORRETIVA<textarea name="acao" required></textarea></label><label>RESPONSÁVEL<input name="responsavel" required></label><label>PRAZO<input type="date" name="prazo" required></label><button type="submit">DEFINIR AÇÃO CORRETIVA</button></form>`;
    if (row.estado === "em_correcao") return `<form class="rnc-inline-form rnc-verification" data-rnc-verify="${row.id}"><p><strong>PROVA DE VERIFICAÇÃO OBRIGATÓRIA</strong><br>Preencha a observação abaixo ou anexe pelo menos uma fotografia/documento antes de verificar.</p><label>OBSERVAÇÃO DA VERIFICAÇÃO<textarea name="observacao_verificacao"></textarea></label><label>PROVA / ANEXO<input type="file" name="prova" multiple accept="application/pdf,image/jpeg,image/png,image/webp"></label><button type="submit">VERIFICAR</button></form>`;
    if (row.estado === "verificado") return `<button class="rnc-close" data-rnc-close="${row.id}">FECHAR RNC</button>`;
    if (row.estado === "fechado" && row.subempreitada_id) return `<button class="rnc-evaluate" data-rnc-evaluate="${row.id}">AVALIAR FORNECEDOR</button>`;
    return "";
  }

  function card(row) {
    const evidence = annexesFor(row.id);
    const sub = subcontract(row.subempreitada_id);
    return `<article class="rnc-card severity-${row.gravidade}"><header><div><span>${esc(rncCode(work(), row.numero))}</span><h3>${esc(row.local_ocorrencia || "Não conformidade")}</h3></div><span class="rnc-severity ${row.gravidade}">${labels[row.gravidade]}</span></header>
      <p>${esc(row.descricao)}</p><dl><div><dt>Deteção</dt><dd>${esc(row.data_deteccao)}</dd></div><div><dt>Fase</dt><dd>${esc(phase(row.fase_id)?.descricao || "—")}</dd></div><div><dt>Origem</dt><dd>${labels[row.origem] || esc(row.origem)}</dd></div>${sub ? `<div><dt>Subempreitada</dt><dd>${esc(sub.especialidade)}</dd></div>` : ""}</dl>
      ${row.acao_corretiva ? `<div class="rnc-correction"><strong>AÇÃO CORRETIVA</strong><p>${esc(row.acao_corretiva)}</p><small>${esc(row.responsavel_correcao)} · prazo ${esc(row.prazo_correcao)}</small></div>` : ""}
      ${row.observacao_verificacao ? `<div class="rnc-verification-note"><strong>VERIFICAÇÃO</strong><p>${esc(row.observacao_verificacao)}</p></div>` : ""}
      <div class="rnc-annexes">${evidence.map(item => `<button data-rnc-annex="${encodeURIComponent(item.arquivo_url)}">${esc(item.nome_arquivo)}</button>`).join("") || "<small>Sem anexos</small>"}</div>
      <footer><button data-rnc-pdf="${row.id}">GERAR RNC PDF</button>${actions(row)}</footer></article>`;
  }

  function render() {
    if (!root) return;
    const groups = ["aberto", "em_correcao", "verificado", "fechado"];
    root.innerHTML = `<div class="page-heading"><div><p class="eyebrow">QUALIDADE EM OBRA</p><h1>RNC</h1><p>Relatórios de não conformidade, evidências e ações corretivas.</p></div><label>OBRA<select data-rnc-work>${getWorks().map(item => `<option value="${item.id}" ${item.id === state.workId ? "selected" : ""}>Obra ${esc(item.numero)} · ${esc(item.nome)}</option>`).join("")}</select></label></div>
      <section class="panel rnc-panel"><div class="rnc-toolbar"><div><strong>${esc(work()?.nome || "Selecione uma obra")}</strong><span>${state.rows.length} relatório(s)</span></div>${canCreate() ? `<button data-rnc-toggle>${state.openForm ? "FECHAR" : "+ NOVA RNC"}</button>` : ""}</div>${newForm()}
      ${state.loading ? `<div class="empty-state">A CARREGAR RNCs…</div>` : `<div class="rnc-board">${groups.map(status => { const rows = state.rows.filter(item => item.estado === status); return `<section class="rnc-column"><header><h2>${labels[status]}</h2><b>${rows.length}</b></header><div>${rows.length ? rows.map(card).join("") : `<div class="rnc-empty">SEM REGISTOS</div>`}</div></section>`; }).join("")}</div>`}</section>`;
  }

  async function load(force = false) {
    if (!state.workId) state.workId = getWorks()[0]?.id || "";
    if (!state.workId) return render();
    state.loading = true; render();
    try {
      if (!isConfigured) { state.rows = []; state.annexes = []; state.phases = []; state.subcontracts = []; state.canEdit = true; }
      else {
        const [rows, phases, subs, permission] = await Promise.all([
          api(`rnc?select=*&obra_id=eq.${encodeURIComponent(state.workId)}&order=numero.desc`), api(`fases?select=id,codigo,descricao&obra_id=eq.${encodeURIComponent(state.workId)}&order=codigo`),
          api(`subempreitadas?select=id,obra_id,fornecedor_id,especialidade&obra_id=eq.${encodeURIComponent(state.workId)}&order=especialidade`), api("rpc/fn_pode_editar_obra", { method: "POST", body: JSON.stringify({ p_obra_id: state.workId }) }),
        ]);
        state.rows = rows; state.phases = phases; state.subcontracts = subs; state.canEdit = Boolean(permission);
        const usersResponse = await supabase("utilizadores?select=id,nome");
        state.users = usersResponse.ok ? await usersResponse.json() : [];
        state.annexes = rows.length ? await api(`rnc_anexos?select=*&rnc_id=in.(${rows.map(item => encodeURIComponent(item.id)).join(",")})&order=criado_em`) : [];
      }
    } catch (error) { toast(error.message, "error"); }
    finally { state.loading = false; render(); }
  }

  async function uploadAnnexes(rncId, files) {
    for (const file of files) {
      const path = await uploadWorkDocument(file, state.workId, "rnc");
      const inserted = await api("rnc_anexos?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ rnc_id: rncId, arquivo_url: path, nome_arquivo: file.name }) });
      state.annexes.push(inserted[0]);
    }
  }

  async function create(form) {
    const fields = Object.fromEntries(new FormData(form).entries());
    const payload = { p_obra_id: state.workId, p_data_deteccao: fields.data_deteccao, p_fase_id: fields.fase_id || null, p_local_ocorrencia: fields.local_ocorrencia || null, p_descricao: fields.descricao, p_origem: fields.origem, p_subempreitada_id: fields.origem === "subempreiteiro" ? fields.subempreitada_id || null : null, p_gravidade: fields.gravidade };
    const row = isConfigured ? await api("rpc/fn_criar_rnc", { method: "POST", body: JSON.stringify(payload) }) : { id: crypto.randomUUID(), numero: state.rows.length + 1, obra_id: state.workId, estado: "aberto", ...Object.fromEntries(Object.entries(payload).map(([key, value]) => [key.replace(/^p_/, ""), value])) };
    const files = [...form.elements.anexos.files]; if (isConfigured && files.length) await uploadAnnexes(row.id, files);
    state.openForm = false; toast(`${rncCode(work(), row.numero)} registada.`); await load(true);
  }

  async function evaluate(row) {
    const sub = subcontract(row.subempreitada_id); if (!sub) return;
    const panel = document.createElement("form"); panel.className = "rnc-evaluation-dialog";
    panel.innerHTML = `<div><h3>AVALIAR FORNECEDOR</h3><p>${esc(sub.especialidade)}</p>${["qualidade", "cumprimento_prazo", "seguranca", "comunicacao"].map(name => `<label>${name.replaceAll("_", " ").toUpperCase()}<input type="number" name="${name}" min="1" max="5" value="5" required></label>`).join("")}<label>OBSERVAÇÕES<textarea name="observacoes"></textarea></label><label>ANEXOS (OPCIONAL)<input type="file" name="anexos" multiple></label><button type="submit">GUARDAR AVALIAÇÃO</button><button type="button" data-cancel>Cancelar</button></div>`;
    document.body.append(panel); panel.querySelector("[data-cancel]").onclick = () => panel.remove();
    panel.onsubmit = async event => { event.preventDefault(); const data = Object.fromEntries(new FormData(panel).entries());
      try { const inserted = await api("avaliacoes_subempreiteiro?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ obra_id: state.workId, subempreitada_id: sub.id, fornecedor_id: sub.fornecedor_id, qualidade: Number(data.qualidade), cumprimento_prazo: Number(data.cumprimento_prazo), seguranca: Number(data.seguranca), comunicacao: Number(data.comunicacao), observacoes: data.observacoes || null }) });
        for (const file of [...panel.elements.anexos.files]) { const path = await uploadWorkDocument(file, state.workId, "avaliacoes-subempreiteiro"); await api("avaliacoes_subempreiteiro_anexos", { method: "POST", body: JSON.stringify({ avaliacao_id: inserted[0].id, arquivo_url: path, nome_arquivo: file.name }) }); }
        panel.remove(); toast("Avaliação e anexos guardados.");
      } catch (error) { toast(error.message, "error"); }
    };
  }

  root.addEventListener("change", event => {
    if (event.target.matches("[data-rnc-work]")) { state.workId = event.target.value; state.openForm = false; load(true); }
    if (event.target.matches('[name="origem"]')) { const field = event.target.form.querySelector(".rnc-subcontract"); field.hidden = event.target.value !== "subempreiteiro"; field.querySelector("select").required = !field.hidden; }
  });
  root.addEventListener("submit", event => { event.preventDefault(); const form = event.target; const button = form.querySelector('[type="submit"]'); button.disabled = true;
    (async () => { if (form.matches("[data-rnc-create]")) return create(form);
      if (form.matches("[data-rnc-correction]")) await api("rpc/fn_definir_acao_rnc", { method: "POST", body: JSON.stringify({ p_rnc_id: form.dataset.rncCorrection, p_acao_corretiva: form.elements.acao.value, p_responsavel_correcao: form.elements.responsavel.value, p_prazo_correcao: form.elements.prazo.value }) });
      if (form.matches("[data-rnc-verify]")) { const files = [...form.elements.prova.files], observation = form.elements.observacao_verificacao.value.trim(); if (!observation && !files.length) throw new Error("Escreva uma observação de verificação ou anexe uma prova antes de verificar."); if (files.length) await uploadAnnexes(form.dataset.rncVerify, files); await api("rpc/fn_verificar_rnc", { method: "POST", body: JSON.stringify({ p_rnc_id: form.dataset.rncVerify, p_observacao_verificacao: observation || null }) }); }
      toast("RNC atualizada."); await load(true);
    })().catch(error => toast(error.message, "error")).finally(() => { button.disabled = false; });
  });
  root.addEventListener("click", event => { const toggle = event.target.closest("[data-rnc-toggle]"); if (toggle) { state.openForm = !state.openForm; return render(); }
    const close = event.target.closest("[data-rnc-close]"); if (close) return api("rpc/fn_fechar_rnc", { method: "POST", body: JSON.stringify({ p_rnc_id: close.dataset.rncClose }) }).then(() => load(true)).catch(error => toast(error.message, "error"));
    const annex = event.target.closest("[data-rnc-annex]"); if (annex) return downloadWorkDocument(decodeURIComponent(annex.dataset.rncAnnex)).then(blob => window.open(URL.createObjectURL(blob), "_blank")).catch(error => toast(error.message, "error"));
    const pdf = event.target.closest("[data-rnc-pdf]"); if (pdf) { const row = state.rows.find(item => item.id === pdf.dataset.rncPdf); return generateRncPdf({ rnc: row, work: work(), phase: phase(row.fase_id), subcontract: subcontract(row.subempreitada_id), reporter: user(row.reportado_por), verifier: user(row.verificado_por), annexes: annexesFor(row.id), download: downloadWorkDocument }).catch(error => toast(error.message, "error")); }
    const evaluation = event.target.closest("[data-rnc-evaluate]"); if (evaluation) return evaluate(state.rows.find(item => item.id === evaluation.dataset.rncEvaluate));
  });
  return { show: workId => { if (workId) state.workId = workId; return load(true); }, refresh: () => load(true) };
}
