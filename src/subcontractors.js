const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

const isoDate = value => value ? String(value).slice(0, 10) : "";
const paymentLabel = value => ({
  imediato: "Imediato",
  "15_dias": "15 dias",
  "30_dias": "30 dias",
})[value] || "Não definida";

export function createSubcontractorsModule({
  supabase,
  isSupabaseConfigured,
  getWorks,
  getSuppliers,
  euro,
  toast,
}) {
  const state = {
    workId: "",
    phases: [],
    consultations: [],
    consultationItems: [],
    candidates: [],
    candidateItems: [],
    budgetItems: [],
    subcontracts: [],
    evaluations: [],
    contractThreshold: null,
    canEdit: false,
    loaded: false,
    action: null,
  };
  const workSelect = document.querySelector("#subcontractors-work");
  const content = document.querySelector("#subcontractors-content");

  function supplierName(id) {
    return getSuppliers().find(item => item.id === id)?.nome || "Fornecedor";
  }

  function phaseLabel(id) {
    const phase = state.phases.find(item => item.id === id);
    return phase ? `${phase.codigo || ""} ${phase.descricao || ""}`.trim() : "Fase não definida";
  }

  function budgetDescription(id) {
    const item = state.budgetItems.find(row => row.id === id);
    return item?.descricao || item?.designacao || item?.artigo || item?.nome || "Artigo do orçamento";
  }

  function contractAlert(value) {
    if (!Number.isFinite(state.contractThreshold)) {
      return `<span class="subcontract-contract-na">LIMITE CONTRATUAL INDISPONÍVEL</span>`;
    }
    return Number(value || 0) >= state.contractThreshold
      ? `<span class="subcontract-contract-alert">CONTRATO OBRIGATÓRIO · ≥ ${euro.format(state.contractThreshold)}</span>`
      : `<span class="subcontract-contract-na">CONTRATO NÃO OBRIGATÓRIO</span>`;
  }

  function renderComparative(consultation) {
    const candidates = state.candidates.filter(
      item => item.consulta_subempreitada_id === consultation.id);
    const links = state.consultationItems.filter(
      item => item.consulta_subempreitada_id === consultation.id);
    return `<article class="comparison-card">
      <div class="comparison-head">
        <div><span>${escapeHtml(phaseLabel(consultation.fase_id))}</span>
          <h3>${escapeHtml(consultation.trabalho || "Consulta")}</h3></div>
        <strong class="comparison-status ${escapeHtml(consultation.estado)}">${escapeHtml(
          String(consultation.estado || "em_consulta").replaceAll("_", " ").toUpperCase())}</strong>
      </div>
      ${candidates.length ? `<div class="comparison-scroll"><table class="comparison-table">
        <thead><tr><th>ARTIGO</th>${candidates.map(candidate =>
          `<th>${escapeHtml(supplierName(candidate.fornecedor_id))}</th>`).join("")}</tr></thead>
        <tbody>
          ${links.map(link => `<tr><td>${escapeHtml(budgetDescription(link.item_orcamento_id))}</td>
            ${candidates.map(candidate => {
              const price = state.candidateItems.find(item =>
                item.candidato_id === candidate.id &&
                item.item_orcamento_id === link.item_orcamento_id);
              return `<td>${price ? euro.format(Number(price.preco_total || 0)) : "—"}</td>`;
            }).join("")}</tr>`).join("")}
          <tr class="comparison-total"><td>TOTAL</td>${candidates.map(candidate =>
            `<td>${euro.format(Number(candidate.valor_total || 0))}</td>`).join("")}</tr>
        </tbody>
      </table></div>
      <div class="comparison-candidates">${candidates.map(candidate => `
        <section class="${candidate.escolhido ? "chosen" : ""}">
          <div><strong>${escapeHtml(supplierName(candidate.fornecedor_id))}</strong>
            <span>${escapeHtml(candidate.contacto || candidate.telefone || "Contacto não indicado")}</span></div>
          <b>${euro.format(Number(candidate.valor_total || 0))}</b>
          ${contractAlert(candidate.valor_total)}
          ${candidate.escolhido
            ? `<em>✓ ADJUDICADO</em>`
            : state.canEdit
              ? `<button type="button" data-award-candidate="${candidate.id}">ADJUDICAR</button>`
              : `<em class="read-only">CONSULTA · SÓ LEITURA</em>`}
        </section>`).join("")}</div>`
        : `<div class="subcontract-empty">AINDA NÃO EXISTEM CANDIDATOS NESTA CONSULTA</div>`}
    </article>`;
  }

  function renderSubcontract(subcontract) {
    const evaluation = state.evaluations.find(
      item => item.subempreitada_id === subcontract.id);
    return `<article class="subcontract-directory-card">
      <div><span>${escapeHtml(phaseLabel(subcontract.fase_id))}</span>
        <h3>${escapeHtml(subcontract.especialidade || "Subempreitada")}</h3>
        <p>${escapeHtml(supplierName(subcontract.fornecedor_id))}</p></div>
      <div class="subcontract-directory-value"><strong>${euro.format(
        Number(subcontract.valor_adjudicado || 0))}</strong>${contractAlert(
          subcontract.valor_adjudicado)}</div>
      <dl>
        <div><dt>INÍCIO PREVISTO</dt><dd>${isoDate(subcontract.data_inicio_prevista) || "—"}</dd></div>
        <div><dt>FIM PREVISTO</dt><dd>${isoDate(subcontract.data_fim_prevista) || "—"}</dd></div>
        <div><dt>PAGAMENTO</dt><dd>${paymentLabel(subcontract.condicao_pagamento)}</dd></div>
      </dl>
      <div class="subcontract-directory-state">
        <span class="${escapeHtml(subcontract.estado)}">${escapeHtml(
          String(subcontract.estado || "").replaceAll("_", " ").toUpperCase())}</span>
        ${evaluation ? `<small>AVALIAÇÃO REGISTADA</small>` : ""}
        ${subcontract.estado === "concluido" || !state.canEdit
          ? ""
          : `<button type="button" data-complete-subcontract="${subcontract.id}">CONCLUIR E AVALIAR</button>`}
      </div>
    </article>`;
  }

  function renderAction() {
    if (!state.action) return "";
    if (state.action.type === "award") {
      const candidate = state.candidates.find(item => item.id === state.action.id);
      return `<div class="dialog-backdrop subcontract-action-dialog">
        <section class="work-dialog-card" role="dialog" aria-modal="true">
          <div class="panel-title"><span>ADJUDICAR · ${escapeHtml(
            supplierName(candidate?.fornecedor_id))}</span>
            <button type="button" data-close-subcontract-action>×</button></div>
          <form data-award-form>
            <div class="form-row">
              <label>INÍCIO PREVISTO<input name="data_inicio_prevista" type="date" required></label>
              <label>FIM PREVISTO<input name="data_fim_prevista" type="date" required></label>
            </div>
            <label>CONDIÇÃO DE PAGAMENTO<div class="select-wrap">
              <select name="condicao_pagamento" required>
                <option value="">Selecionar</option><option value="imediato">Imediato</option>
                <option value="15_dias">15 dias</option><option value="30_dias">30 dias</option>
              </select><b>⌄</b></div></label>
            ${contractAlert(candidate?.valor_total)}
            <p class="form-error" data-subcontract-error></p>
            <div class="dialog-actions"><button class="outline-action" type="button" data-close-subcontract-action>CANCELAR</button>
              <button class="primary-button" type="submit">CONFIRMAR ADJUDICAÇÃO →</button></div>
          </form>
        </section></div>`;
    }
    return `<div class="dialog-backdrop subcontract-action-dialog">
      <section class="work-dialog-card" role="dialog" aria-modal="true">
        <div class="panel-title"><span>CONCLUIR E AVALIAR</span>
          <button type="button" data-close-subcontract-action>×</button></div>
        <form data-evaluation-form>
          <p class="subcontract-evaluation-note">A conclusão só será gravada depois de todos os critérios serem avaliados.</p>
          <div class="evaluation-grid">
            ${[
              ["qualidade", "QUALIDADE"],
              ["cumprimento_prazo", "CUMPRIMENTO DO PRAZO"],
              ["seguranca", "SEGURANÇA"],
              ["comunicacao", "COMUNICAÇÃO"],
            ].map(([name, label]) => `<label>${label}<div class="select-wrap"><select name="${name}" required>
              <option value="">1–5</option>${[1, 2, 3, 4, 5].map(value =>
                `<option value="${value}">${value}</option>`).join("")}</select><b>⌄</b></div></label>`).join("")}
          </div>
          <label>OBSERVAÇÕES<textarea name="observacoes" rows="4" placeholder="Notas sobre o trabalho executado"></textarea></label>
          <p class="form-error" data-subcontract-error></p>
          <div class="dialog-actions"><button class="outline-action" type="button" data-close-subcontract-action>CANCELAR</button>
            <button class="primary-button" type="submit">CONCLUIR SUBEMPREITADA →</button></div>
        </form>
      </section></div>`;
  }

  function render() {
    if (!state.loaded) {
      content.innerHTML = `<div class="empty-state"><strong>A CARREGAR SUBEMPREITEIROS…</strong></div>`;
      return;
    }
    content.innerHTML = `
      <section class="subcontractors-kpis">
        <article><span>EM CONSULTA</span><strong>${state.consultations.filter(
          item => item.estado === "em_consulta").length}</strong></article>
        <article><span>EM EXECUÇÃO</span><strong>${state.subcontracts.filter(
          item => item.estado === "em_execucao").length}</strong></article>
        <article><span>CONCLUÍDAS</span><strong>${state.subcontracts.filter(
          item => item.estado === "concluido").length}</strong></article>
        <article><span>CONTRATO OBRIGATÓRIO</span><strong>${state.subcontracts.filter(
          item => Number.isFinite(state.contractThreshold) &&
            Number(item.valor_adjudicado || 0) >= state.contractThreshold).length}</strong></article>
      </section>
      <section class="subcontractors-section">
        <div class="subcontractors-section-head"><div><p class="eyebrow">PROCUREMENT</p>
          <h2>MAPAS COMPARATIVOS</h2></div><span>${state.consultations.length} CONSULTAS</span></div>
        <div class="comparison-list">${state.consultations.length
          ? state.consultations.map(renderComparative).join("")
          : `<div class="subcontract-empty">NÃO EXISTEM CONSULTAS NESTA OBRA</div>`}</div>
      </section>
      <section class="subcontractors-section">
        <div class="subcontractors-section-head"><div><p class="eyebrow">EXECUÇÃO</p>
          <h2>SUBEMPREITADAS REGISTADAS</h2></div><span>${state.subcontracts.length} REGISTOS</span></div>
        <div class="subcontract-directory-list">${state.subcontracts.length
          ? state.subcontracts.map(renderSubcontract).join("")
          : `<div class="subcontract-empty">NÃO EXISTEM SUBEMPREITADAS NESTA OBRA</div>`}</div>
      </section>
      ${renderAction()}`;
  }

  function setWorkOptions() {
    const works = getWorks().slice().sort((a, b) =>
      String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true }));
    workSelect.innerHTML = works.map(work =>
      `<option value="${work.id}">OBRA ${escapeHtml(work.numero)} · ${escapeHtml(work.nome)}</option>`
    ).join("");
    if (!state.workId && works[0]) state.workId = works[0].id;
    workSelect.value = state.workId;
  }

  async function query(path) {
    const response = await supabase(path);
    if (!response.ok) throw new Error(await response.text());
    return response.json();
  }

  async function load(workId = state.workId) {
    setWorkOptions();
    state.workId = workId || workSelect.value;
    workSelect.value = state.workId;
    state.loaded = false;
    render();
    if (!isSupabaseConfigured || !state.workId) {
      state.loaded = true;
      render();
      return;
    }
    try {
      const encoded = encodeURIComponent(state.workId);
      const thresholdRequest = supabase("rpc/fn_limite_contrato_subempreitada", {
        method: "POST",
        body: JSON.stringify({}),
      });
      const permissionRequest = supabase("rpc/fn_pode_editar_obra", {
        method: "POST",
        body: JSON.stringify({ p_obra_id: state.workId }),
      });
      const [phases, consultations, subcontracts, thresholdResponse, permissionResponse] = await Promise.all([
        query(`fases?select=id,codigo,descricao,obra_id&obra_id=eq.${encoded}&order=codigo`),
        query(`consultas_subempreitada?select=*&obra_id=eq.${encoded}&order=criado_em.desc`),
        query(`subempreitadas?select=*&obra_id=eq.${encoded}&order=criado_em.desc`),
        thresholdRequest,
        permissionRequest,
      ]);
      state.phases = phases;
      state.consultations = consultations;
      state.subcontracts = subcontracts;
      if (thresholdResponse.ok) {
        const configuredThreshold = Number(await thresholdResponse.json());
        if (Number.isFinite(configuredThreshold) && configuredThreshold >= 0) {
          state.contractThreshold = configuredThreshold;
        }
      }
      state.canEdit = permissionResponse.ok && Boolean(await permissionResponse.json());
      const consultationIds = state.consultations.map(item => item.id);
      const subcontractIds = state.subcontracts.map(item => item.id);
      if (consultationIds.length) {
        const filter = consultationIds.map(encodeURIComponent).join(",");
        [state.consultationItems, state.candidates] = await Promise.all([
          query(`consultas_subempreitada_itens?select=*&consulta_subempreitada_id=in.(${filter})&order=criado_em`),
          query(`consultas_subempreitada_candidatos?select=*&consulta_subempreitada_id=in.(${filter})&order=criado_em`),
        ]);
      } else {
        state.consultationItems = [];
        state.candidates = [];
      }
      const candidateIds = state.candidates.map(item => item.id);
      state.candidateItems = candidateIds.length
        ? await query(`consultas_subempreitada_candidatos_itens?select=*&candidato_id=in.(${candidateIds.map(
          encodeURIComponent).join(",")})&order=criado_em`)
        : [];
      const budgetIds = [...new Set(state.consultationItems.map(
        item => item.item_orcamento_id).filter(Boolean))];
      state.budgetItems = budgetIds.length
        ? await query(`itens_orcamento?select=*&id=in.(${budgetIds.map(encodeURIComponent).join(",")})`)
        : [];
      state.evaluations = subcontractIds.length
        ? await query(`avaliacoes_subempreiteiro?select=*&subempreitada_id=in.(${subcontractIds.map(
          encodeURIComponent).join(",")})&order=criado_em.desc`)
        : [];
    } catch (error) {
      toast(`Não foi possível carregar o módulo: ${error.message}`, "error");
      state.phases = [];
      state.consultations = [];
      state.subcontracts = [];
      state.canEdit = false;
    }
    state.loaded = true;
    render();
  }

  content.addEventListener("click", event => {
    const close = event.target.closest("[data-close-subcontract-action]");
    if (close) {
      state.action = null;
      render();
      return;
    }
    const award = event.target.closest("[data-award-candidate]");
    if (award) {
      state.action = { type: "award", id: award.dataset.awardCandidate };
      render();
      return;
    }
    const complete = event.target.closest("[data-complete-subcontract]");
    if (complete) {
      state.action = { type: "complete", id: complete.dataset.completeSubcontract };
      render();
    }
  });

  content.addEventListener("submit", async event => {
    event.preventDefault();
    const form = event.target;
    const errorNode = form.querySelector("[data-subcontract-error]");
    const button = form.querySelector('[type="submit"]');
    button.disabled = true;
    try {
      const values = Object.fromEntries(new FormData(form));
      if (form.matches("[data-award-form]")) {
        const response = await supabase("rpc/fn_adjudicar_candidato_subempreitada", {
          method: "POST",
          body: JSON.stringify({
            p_candidato_id: state.action.id,
            p_data_inicio_prevista: values.data_inicio_prevista,
            p_data_fim_prevista: values.data_fim_prevista,
            p_condicao_pagamento: values.condicao_pagamento,
          }),
        });
        if (!response.ok) throw new Error(await response.text());
        toast("Candidato adjudicado e planeamento atualizado.");
      } else {
        const response = await supabase("rpc/fn_concluir_subempreitada_com_avaliacao", {
          method: "POST",
          body: JSON.stringify({
            p_subempreitada_id: state.action.id,
            p_qualidade: Number(values.qualidade),
            p_cumprimento_prazo: Number(values.cumprimento_prazo),
            p_seguranca: Number(values.seguranca),
            p_comunicacao: Number(values.comunicacao),
            p_observacoes: values.observacoes || null,
          }),
        });
        if (!response.ok) throw new Error(await response.text());
        toast("Avaliação registada e subempreitada concluída.");
      }
      state.action = null;
      await load(state.workId);
    } catch (error) {
      errorNode.textContent = error.message || "Não foi possível concluir a operação.";
      button.disabled = false;
    }
  });

  workSelect.addEventListener("change", () => {
    state.action = null;
    load(workSelect.value);
  });

  return {
    show() {
      setWorkOptions();
      load(state.workId || workSelect.value);
    },
    refresh: load,
  };
}
