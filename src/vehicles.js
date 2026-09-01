import { platformConfirm, platformPrompt } from "./platform-dialogs.js?v=1";

const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

const today = () => new Date().toISOString().slice(0, 10);
const EVENT_LABELS = {
  revisao: "Revisão", inspecao: "Inspeção", pneus: "Pneus",
  bateria: "Bateria", reparacao: "Reparação", outro: "Outro",
};
const CLAIM_LABELS = { aberto: "Aberto", em_seguradora: "Em seguradora", fechado: "Fechado" };

function daysUntil(value) {
  if (!value) return null;
  return Math.ceil((new Date(`${value}T12:00:00`) - new Date(`${today()}T12:00:00`)) / 86400000);
}

function deadlineState(value, threshold = 30) {
  const days = daysUntil(value);
  if (days === null) return { className: "neutral", label: "Sem data" };
  if (days < 0) return { className: "expired", label: `Vencido há ${Math.abs(days)} dias` };
  if (days <= threshold) return { className: "warning", label: days === 0 ? "Vence hoje" : `Vence em ${days} dias` };
  return { className: "valid", label: "Dentro da validade" };
}

export function createVehiclesModule({
  root, supabase, isConfigured, getCollaborators, getSuppliers,
  uploadEntityDocument, downloadWorkDocument, deleteWorkDocument, euro, prettyDate, toast,
}) {
  const state = {
    loaded: false, loading: false, query: "", selectedVehicleId: "",
    vehicles: [], events: [], claims: [], claimFiles: [], fines: [], fineFiles: [], error: "",
  };

  async function api(path, options) {
    const response = await supabase(path, options);
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      throw new Error(payload.message || payload.details || `Não foi possível consultar ${path.split("?")[0]}.`);
    }
    return response.status === 204 ? [] : response.json();
  }

  const collaborators = () => getCollaborators().slice().sort((a, b) =>
    String(a.nome || "").localeCompare(String(b.nome || ""), "pt-PT"));
  const suppliers = () => getSuppliers().slice().sort((a, b) =>
    String(a.nome || "").localeCompare(String(b.nome || ""), "pt-PT"));
  const vehicle = () => state.vehicles.find(item => item.id === state.selectedVehicleId) || state.vehicles[0] || null;
  const personName = id => collaborators().find(item => item.id === id)?.nome || "Não identificado";
  const supplierName = id => suppliers().find(item => item.id === id)?.nome || "Não indicado";
  const vehicleName = item => `${item?.marca_modelo || "Viatura"}${item?.matricula ? ` · ${item.matricula}` : ""}`;
  const formatDate = value => value ? prettyDate.format(new Date(`${value}T12:00:00`)) : "—";

  async function load(force = false) {
    if (state.loading || (state.loaded && !force)) return render();
    state.loading = true;
    state.error = "";
    render();
    try {
      if (!isConfigured) {
        state.vehicles = [];
        state.loaded = true;
        return render();
      }
      const [vehicles, events, claims, claimFiles, fines, fineFiles] = await Promise.all([
        api("viaturas?select=*&order=numero_interno.asc.nullslast,matricula.asc"),
        api("viaturas_eventos?select=*&order=data.desc,criado_em.desc"),
        api("viaturas_sinistros?select=*&order=data.desc,criado_em.desc"),
        api("viaturas_sinistros_anexos?select=*&order=criado_em.desc"),
        api("multas?select=*&order=data.desc,criado_em.desc"),
        api("multas_anexos?select=*&order=criado_em.desc"),
      ]);
      Object.assign(state, { vehicles, events, claims, claimFiles, fines, fineFiles, loaded: true });
      if (!state.selectedVehicleId || !vehicles.some(item => item.id === state.selectedVehicleId)) {
        state.selectedVehicleId = vehicles[0]?.id || "";
      }
    } catch (error) {
      state.error = `${error.message} Confirme se executou supabase/bloco_06_viaturas.sql.`;
    } finally {
      state.loading = false;
      render();
    }
  }

  function deadline(label, value, threshold = 30) {
    const status = deadlineState(value, threshold);
    return `<article class="fleet-deadline ${status.className}"><span>${label}</span><strong>${formatDate(value)}</strong><small>${status.label}</small></article>`;
  }

  function renderVehicleList() {
    const query = state.query.trim().toLocaleLowerCase("pt-PT");
    const people = new Map(collaborators().map(item => [item.id, item.nome]));
    const rows = state.vehicles.filter(item => !query || `${item.marca_modelo || ""} ${item.matricula || ""} ${item.numero_interno || ""} ${people.get(item.colaborador_atribuido_id) || ""}`.toLocaleLowerCase("pt-PT").includes(query));
    return `<aside class="fleet-directory">
      <div class="fleet-search"><input data-fleet-search value="${esc(state.query)}" placeholder="Pesquisar viatura, matrícula ou colaborador…"></div>
      <div class="fleet-directory-count">${rows.length} VIATURA${rows.length === 1 ? "" : "S"}</div>
      <div class="fleet-directory-list">${rows.length ? rows.map(item => {
        const insurance = deadlineState(item.seguro_data, 15);
        const inspection = deadlineState(item.data_inspecao_proxima, 15);
        return `<button type="button" class="fleet-directory-row ${item.id === vehicle()?.id ? "active" : ""}" data-fleet-vehicle="${item.id}">
          <span>${esc(item.numero_interno ? `VIATURA ${item.numero_interno}` : "VIATURA")}</span>
          <strong>${esc(item.marca_modelo || "Sem modelo")}</strong><small>${esc(item.matricula || "Sem matrícula")}</small>
          <em>${esc(people.get(item.colaborador_atribuido_id) || "Sem atribuição")}</em>
          <i class="${insurance.className}" title="Seguro: ${insurance.label}"></i><i class="${inspection.className}" title="Inspeção: ${inspection.label}"></i>
        </button>`;
      }).join("") : `<div class="fleet-empty">SEM RESULTADOS</div>`}</div>
    </aside>`;
  }

  function renderEventForm(item) {
    return `<details class="fleet-form-card"><summary>＋ REGISTAR EVENTO</summary>
      <form data-fleet-event-form data-vehicle-id="${item.id}">
        <div class="fleet-form-grid">
          <label>TIPO<select name="tipo" required>${Object.entries(EVENT_LABELS).map(([value, label]) => `<option value="${value}">${label}</option>`).join("")}</select></label>
          <label>DATA<input name="data" type="date" required value="${today()}"></label>
          <label>CUSTO (€)<input name="custo" type="number" min="0" step="0.01"></label>
          <label>FORNECEDOR<select name="fornecedor_id"><option value="">Não indicado</option>${suppliers().map(row => `<option value="${row.id}">${esc(row.nome)}</option>`).join("")}</select></label>
        </div>
        <label>DESCRIÇÃO<textarea name="descricao" rows="2"></textarea></label>
        <label class="fleet-next-date-toggle"><input name="atualizar_data" type="checkbox"> Atualizar a próxima data da viatura</label>
        <label data-fleet-next-date>NOVA DATA PREVISTA<input name="nova_data" type="date" disabled></label>
        <p class="fleet-form-help">Disponível para Revisão e Inspeção. O evento fica sempre guardado no histórico.</p>
        <button class="primary-button" type="submit">GUARDAR EVENTO <span>→</span></button><p class="form-error"></p>
      </form>
    </details>`;
  }

  function renderClaimForm(item) {
    return `<details class="fleet-form-card"><summary>＋ REGISTAR SINISTRO</summary>
      <form data-fleet-claim-form data-vehicle-id="${item.id}">
        <div class="fleet-form-grid">
          <label>DATA<input name="data" type="date" required value="${today()}"></label>
          <label>CONDUTOR / COLABORADOR<select name="colaborador_id"><option value="">Não indicado</option>${collaborators().map(row => `<option value="${row.id}">${esc(row.nome)}</option>`).join("")}</select></label>
          <label>ESTADO<select name="estado"><option value="aberto">Aberto</option><option value="em_seguradora">Em seguradora</option><option value="fechado">Fechado</option></select></label>
        </div>
        <label>DESCRIÇÃO<textarea name="descricao" rows="3" required></textarea></label>
        <label>ANEXOS (OPCIONAL)<input name="anexos" type="file" multiple accept="application/pdf,image/*,.doc,.docx,.xls,.xlsx,.csv"></label>
        <button class="primary-button" type="submit">GUARDAR SINISTRO <span>→</span></button><p class="form-error"></p>
      </form>
    </details>`;
  }

  function renderTimeline(item) {
    const rows = state.events.filter(row => row.viatura_id === item.id);
    return `<section class="fleet-section"><header><div><p class="eyebrow">HISTÓRICO ÚNICO</p><h3>EVENTOS DA VIATURA</h3></div><span>${rows.length}</span></header>
      <div class="fleet-timeline">${rows.length ? rows.map(row => `<article>
        <time>${formatDate(row.data)}</time><i class="${row.tipo}"></i><div><strong>${esc(EVENT_LABELS[row.tipo] || row.tipo)}</strong><p>${esc(row.descricao || "Sem descrição")}</p><small>${esc(supplierName(row.fornecedor_id))}</small></div><b>${row.custo == null ? "—" : euro.format(Number(row.custo))}</b><div><button type="button" data-fleet-edit-event="${row.id}">EDITAR</button><button type="button" class="danger-action" data-fleet-delete-event="${row.id}">APAGAR</button></div>
      </article>`).join("") : `<div class="fleet-empty">AINDA SEM EVENTOS</div>`}</div>
    </section>`;
  }

  function attachmentButtons(rows, kind) {
    return rows.map(file => `<span><button type="button" data-fleet-download="${encodeURIComponent(file.arquivo_url)}" data-file-name="${esc(file.nome_arquivo)}">${esc(file.nome_arquivo)}</button><button type="button" class="danger-action" data-fleet-delete-file="${file.id}" data-file-kind="${kind}" data-file-path="${encodeURIComponent(file.arquivo_url)}">APAGAR</button></span>`).join("");
  }

  function renderClaims(item) {
    const rows = state.claims.filter(row => row.viatura_id === item.id);
    return `<section class="fleet-section"><header><div><p class="eyebrow">OCORRÊNCIAS</p><h3>SINISTROS</h3></div><span>${rows.length}</span></header>
      <div class="fleet-record-list">${rows.length ? rows.map(row => {
        const files = state.claimFiles.filter(file => file.sinistro_id === row.id);
        return `<article><div><time>${formatDate(row.data)}</time><strong>${esc(personName(row.colaborador_id))}</strong><p>${esc(row.descricao)}</p>${files.length ? `<div class="fleet-attachments">${attachmentButtons(files, "sinistro")}</div>` : ""}</div><label>ESTADO<select data-fleet-claim-status="${row.id}">${Object.entries(CLAIM_LABELS).map(([value,label]) => `<option value="${value}" ${value === row.estado ? "selected" : ""}>${label}</option>`).join("")}</select></label><div><button type="button" data-fleet-edit-claim="${row.id}">EDITAR</button><button type="button" class="danger-action" data-fleet-delete-claim="${row.id}">APAGAR</button></div></article>`;
      }).join("") : `<div class="fleet-empty">SEM SINISTROS REGISTADOS</div>`}</div>
    </section>`;
  }

  function renderVehicleDetail() {
    const item = vehicle();
    if (!item) return `<section class="fleet-detail"><div class="fleet-empty large">NÃO EXISTEM VIATURAS REGISTADAS</div></section>`;
    const assigned = collaborators().find(person => person.id === item.colaborador_atribuido_id);
    return `<section class="fleet-detail">
      <header class="fleet-detail-head"><div><p class="eyebrow">FICHA DA VIATURA</p><h2>${esc(item.marca_modelo || "Sem modelo")}</h2><span>${esc(item.matricula || "Sem matrícula")} · ${esc(item.numero_interno ? `N.º interno ${item.numero_interno}` : "Sem número interno")}</span></div><div><span>ATRIBUÍDA A</span><strong>${esc(assigned?.nome || "Sem atribuição")}</strong></div></header>
      <div class="fleet-deadlines">${deadline("SEGURO", item.seguro_data, 15)}${deadline("INSPEÇÃO", item.data_inspecao_proxima, 15)}${deadline("PRÓXIMA REVISÃO", item.data_proxima_revisao, 30)}</div>
      <div class="fleet-form-actions">${renderEventForm(item)}${renderClaimForm(item)}</div>
      ${renderTimeline(item)}${renderClaims(item)}
    </section>`;
  }

  function renderFineForm() {
    const selected = vehicle();
    return `<details class="fleet-form-card fleet-fine-form"><summary>＋ REGISTAR MULTA</summary>
      <form data-fleet-fine-form>
        <div class="fleet-form-grid">
          <label>COLABORADOR RESPONSÁVEL<select name="colaborador_id" required><option value="">Selecionar colaborador</option>${collaborators().map(row => `<option value="${row.id}">${esc(row.nome)}</option>`).join("")}</select></label>
          <label>VIATURA (OPCIONAL)<select name="viatura_id"><option value="">Sem viatura associada</option>${state.vehicles.map(row => `<option value="${row.id}" ${row.id === selected?.id ? "selected" : ""}>${esc(vehicleName(row))}</option>`).join("")}</select></label>
          <label>DATA<input name="data" type="date" required value="${today()}"></label>
          <label>VALOR (€)<input name="valor" type="number" min="0" step="0.01"></label>
        </div>
        <label>DESCRIÇÃO<textarea name="descricao" rows="2"></textarea></label>
        <label>ANEXOS (OPCIONAL)<input name="anexos" type="file" multiple accept="application/pdf,image/*,.doc,.docx"></label>
        <button class="primary-button" type="submit">GUARDAR MULTA <span>→</span></button><p class="form-error"></p>
      </form>
    </details>`;
  }

  function renderFines() {
    const totals = new Map();
    state.fines.forEach(row => totals.set(row.colaborador_id, (totals.get(row.colaborador_id) || 0) + 1));
    return `<section class="panel fleet-fines"><header><div><p class="eyebrow">RESPONSABILIDADE INDIVIDUAL</p><h2>MULTAS POR COLABORADOR</h2></div><span>${state.fines.length} REGISTOS</span></header>
      ${renderFineForm()}
      <div class="fleet-record-list">${state.fines.length ? state.fines.map(row => {
        const files = state.fineFiles.filter(file => file.multa_id === row.id);
        const linkedVehicle = state.vehicles.find(item => item.id === row.viatura_id);
        return `<article><div><time>${formatDate(row.data)}</time><strong>${esc(personName(row.colaborador_id))} <i>${totals.get(row.colaborador_id)} no histórico</i></strong><p>${esc(row.descricao || "Sem descrição")}</p><small>${esc(linkedVehicle ? vehicleName(linkedVehicle) : "Sem viatura associada")}</small>${files.length ? `<div class="fleet-attachments">${attachmentButtons(files, "multa")}</div>` : ""}</div><b>${row.valor == null ? "—" : euro.format(Number(row.valor))}</b><div><button type="button" data-fleet-edit-fine="${row.id}">EDITAR</button><button type="button" class="danger-action" data-fleet-delete-fine="${row.id}">APAGAR</button></div></article>`;
      }).join("") : `<div class="fleet-empty">SEM MULTAS REGISTADAS</div>`}</div>
    </section>`;
  }

  function render() {
    root.innerHTML = `<div class="page-heading"><div><p class="eyebrow">GESTÃO DE FROTA</p><h1>VIATURAS</h1><p>Validades, histórico de manutenção, sinistros e multas.</p></div><div class="heading-stat"><span>FROTA</span><strong>${String(state.vehicles.length).padStart(2, "0")}</strong></div></div>
      ${state.error ? `<div class="work-warning"><strong>DADOS INDISPONÍVEIS</strong><span>${esc(state.error)}</span></div>` : ""}
      ${state.loading ? `<div class="fleet-loading">A CARREGAR A FROTA…</div>` : `<div class="fleet-layout">${renderVehicleList()}${renderVehicleDetail()}</div>${renderFines()}`}`;
  }

  async function saveFiles(files, entityType, entityId, documentType, table, foreignKey, parentId) {
    for (const file of [...files]) {
      const path = await uploadEntityDocument(file, entityType, entityId, `${documentType}_${parentId}`);
      const [saved] = await api(`${table}?select=*`, {
        method: "POST", headers: { Prefer: "return=representation" },
        body: JSON.stringify({ [foreignKey]: parentId, arquivo_url: path, nome_arquivo: file.name }),
      });
      if (table === "viaturas_sinistros_anexos") state.claimFiles.unshift(saved);
      else state.fineFiles.unshift(saved);
    }
  }

  root.addEventListener("input", event => {
    if (!event.target.matches("[data-fleet-search]")) return;
    state.query = event.target.value;
    const selectionStart = event.target.selectionStart;
    render();
    const input = root.querySelector("[data-fleet-search]");
    input?.focus(); input?.setSelectionRange(selectionStart, selectionStart);
  });

  root.addEventListener("click", async event => {
    const selectButton = event.target.closest("[data-fleet-vehicle]");
    if (selectButton) { state.selectedVehicleId = selectButton.dataset.fleetVehicle; render(); return; }
    const mutationButton = event.target.closest("[data-fleet-edit-event],[data-fleet-delete-event],[data-fleet-edit-claim],[data-fleet-delete-claim],[data-fleet-edit-fine],[data-fleet-delete-fine]");
    if (mutationButton) {
      const entries = [["fleetEditEvent","viaturas_eventos","editar"],["fleetDeleteEvent","viaturas_eventos","apagar"],["fleetEditClaim","viaturas_sinistros","editar"],["fleetDeleteClaim","viaturas_sinistros","apagar"],["fleetEditFine","multas","editar"],["fleetDeleteFine","multas","apagar"]];
      const match = entries.find(([key]) => mutationButton.dataset[key]);
      const [key, table, action] = match; const id = mutationButton.dataset[key];
      let dados = {};
      if (action === "apagar" && !await platformConfirm("Apagar este registo e os anexos associados? A ação fica registada na auditoria.", { title: "Apagar registo", danger: true, confirmLabel: "APAGAR" })) return;
      if (action === "editar") { const collection = table === "viaturas_eventos" ? state.events : table === "viaturas_sinistros" ? state.claims : state.fines; const row = collection.find(item => item.id === id); const description = await platformPrompt("Edite a descrição do registo.", row?.descricao || "", { title: "Editar registo", label: "DESCRIÇÃO" }); if (description === null) return; dados = { descricao: description.trim() || null }; }
      try { await api("rpc/fn_gerir_registo_frota", { method: "POST", body: JSON.stringify({ p_tabela: table, p_registo_id: id, p_acao: action, p_dados: dados }) }); await load(true); toast(action === "apagar" ? "Registo apagado." : "Registo atualizado."); } catch (error) { toast(error.message, "error"); }
      return;
    }
    const deleteFile = event.target.closest("[data-fleet-delete-file]");
    if (deleteFile) { if (!await platformConfirm("Apagar este anexo?", { title: "Apagar anexo", danger: true, confirmLabel: "APAGAR" })) return; try { const table = deleteFile.dataset.fileKind === "sinistro" ? "viaturas_sinistros_anexos" : "multas_anexos"; await api("rpc/fn_gerir_registo_frota", { method: "POST", body: JSON.stringify({ p_tabela: table, p_registo_id: deleteFile.dataset.fleetDeleteFile, p_acao: "apagar", p_dados: {} }) }); await deleteWorkDocument(decodeURIComponent(deleteFile.dataset.filePath)).catch(() => {}); await load(true); toast("Anexo apagado."); } catch (error) { toast(error.message, "error"); } return; }
    const download = event.target.closest("[data-fleet-download]");
    if (!download) return;
    download.disabled = true;
    try {
      const blob = await downloadWorkDocument(decodeURIComponent(download.dataset.fleetDownload));
      const url = URL.createObjectURL(blob); const link = document.createElement("a");
      link.href = url; link.download = download.dataset.fileName || "anexo"; link.click();
      setTimeout(() => URL.revokeObjectURL(url), 60000);
    } catch (error) { toast(error.message || "Não foi possível descarregar o anexo.", "error"); }
    finally { download.disabled = false; }
  });

  root.addEventListener("change", event => {
    const status = event.target.closest("[data-fleet-claim-status]");
    if (status) { status.disabled = true; api("rpc/fn_gerir_registo_frota", { method: "POST", body: JSON.stringify({ p_tabela: "viaturas_sinistros", p_registo_id: status.dataset.fleetClaimStatus, p_acao: "editar", p_dados: { estado: status.value } }) }).then(() => { const row = state.claims.find(item => item.id === status.dataset.fleetClaimStatus); if (row) row.estado = status.value; toast("Estado do sinistro atualizado."); render(); }).catch(error => { toast(error.message, "error"); status.disabled = false; }); return; }
    const form = event.target.closest("[data-fleet-event-form]");
    if (!form) return;
    const eligible = ["revisao", "inspecao"].includes(form.elements.tipo.value);
    form.elements.atualizar_data.disabled = !eligible;
    if (!eligible) form.elements.atualizar_data.checked = false;
    form.elements.nova_data.disabled = !eligible || !form.elements.atualizar_data.checked;
    form.elements.nova_data.required = eligible && form.elements.atualizar_data.checked;
  });

  root.addEventListener("submit", async event => {
    const eventForm = event.target.closest("[data-fleet-event-form]");
    const claimForm = event.target.closest("[data-fleet-claim-form]");
    const fineForm = event.target.closest("[data-fleet-fine-form]");
    if (!eventForm && !claimForm && !fineForm) return;
    event.preventDefault();
    const form = eventForm || claimForm || fineForm;
    const button = form.querySelector('button[type="submit"]'); const errorNode = form.querySelector(".form-error");
    button.disabled = true; errorNode.textContent = "";
    try {
      if (eventForm) {
        const fields = Object.fromEntries(new FormData(form));
        const payload = { viatura_id: form.dataset.vehicleId, tipo: fields.tipo, data: fields.data, descricao: fields.descricao?.trim() || null, custo: fields.custo ? Number(fields.custo) : null, fornecedor_id: fields.fornecedor_id || null };
        let saved = { id: crypto.randomUUID(), criado_em: new Date().toISOString(), ...payload };
        if (isConfigured) [saved] = await api("viaturas_eventos?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        state.events.unshift(saved);
        if (fields.atualizar_data === "on" && fields.nova_data) {
          const column = fields.tipo === "revisao" ? "data_proxima_revisao" : "data_inspecao_proxima";
          if (isConfigured) await api(`viaturas?id=eq.${encodeURIComponent(payload.viatura_id)}&select=*`, { method: "PATCH", headers: { Prefer: "return=representation" }, body: JSON.stringify({ [column]: fields.nova_data }) });
          Object.assign(state.vehicles.find(row => row.id === payload.viatura_id), { [column]: fields.nova_data });
        }
        toast("Evento adicionado ao histórico da viatura.");
      } else if (claimForm) {
        const data = new FormData(form);
        const payload = { viatura_id: form.dataset.vehicleId, colaborador_id: data.get("colaborador_id") || null, data: data.get("data"), descricao: String(data.get("descricao") || "").trim(), estado: data.get("estado") };
        let saved = { id: crypto.randomUUID(), criado_em: new Date().toISOString(), ...payload };
        if (isConfigured) [saved] = await api("viaturas_sinistros?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        state.claims.unshift(saved);
        if (isConfigured && form.elements.anexos.files.length) await saveFiles(form.elements.anexos.files, "viatura", payload.viatura_id, "sinistro", "viaturas_sinistros_anexos", "sinistro_id", saved.id);
        toast("Sinistro registado.");
      } else {
        const data = new FormData(form);
        const payload = { colaborador_id: data.get("colaborador_id"), viatura_id: data.get("viatura_id") || null, data: data.get("data"), descricao: String(data.get("descricao") || "").trim() || null, valor: data.get("valor") ? Number(data.get("valor")) : null };
        let saved = { id: crypto.randomUUID(), criado_em: new Date().toISOString(), ...payload };
        if (isConfigured) [saved] = await api("multas?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        state.fines.unshift(saved);
        if (isConfigured && form.elements.anexos.files.length) await saveFiles(form.elements.anexos.files, "colaborador", payload.colaborador_id, "multa", "multas_anexos", "multa_id", saved.id);
        toast("Multa associada ao colaborador.");
      }
      render();
    } catch (error) { errorNode.textContent = error.message || "Não foi possível guardar o registo."; button.disabled = false; }
  });

  return { show: () => load(), refresh: () => load(true) };
}
