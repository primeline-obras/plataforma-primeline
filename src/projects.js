const number = value => Number(value || 0);

export function createProjectsModule({ root, api, isConfigured, euro, escapeHtml, getWorks, canManage, openWork, companyId, toast }) {
  let projects = [];
  let contracts = [];
  let investments = [];
  let selectedId = "";
  let loaded = false;

  const currentByWork = (rows, field) => {
    const result = new Map();
    rows.forEach(row => {
      const previous = result.get(row.obra_id);
      if (!previous || number(row[field]) >= number(previous[field])) result.set(row.obra_id, row);
    });
    return result;
  };

  function stageFinancial(work, contractByWork, investmentByWork) {
    if (work.modalidade === "investimento_proprio") {
      const investment = investmentByWork.get(work.id) || {};
      const budget = number(investment.orcamento_revisto_sem_iva || investment.orcamento_inicial_sem_iva);
      const cost = number(investment.custo_realizado_sem_iva || investment.custo_realizado);
      return { investment: true, sale: budget, cost, margin: budget - cost };
    }
    const contract = contractByWork.get(work.id) || {};
    const sale = number(contract.venda_contratual_efetiva || contract.venda_contratual_inicial);
    const cost = number(contract.custo_direto_efetivo || contract.custo_direto_inicial);
    return { investment: false, sale, cost, margin: sale - cost };
  }

  async function load(force = false) {
    if (loaded && !force) return render();
    if (!isConfigured) {
      projects = [];
      contracts = [];
      investments = [];
      loaded = true;
      return render();
    }
    root.innerHTML = `<div class="empty-state">A CARREGAR PROJETOS…</div>`;
    const [projectsResponse, contractsResponse, investmentsResponse] = await Promise.all([
      api("projetos?select=id,empresa_id,nome,cliente,morada,criado_em&order=nome"),
      api("contratos?select=id,obra_id,venda_contratual_inicial,venda_contratual_efetiva,custo_direto_inicial,custo_direto_efetivo"),
      api("investimentos?select=*"),
    ]);
    const failed = [projectsResponse, contractsResponse, investmentsResponse].find(response => !response.ok);
    if (failed) {
      root.innerHTML = `<div class="work-warning"><strong>PROJETOS INDISPONÍVEIS</strong><span>${escapeHtml(await failed.text())}</span></div>`;
      return;
    }
    [projects, contracts, investments] = await Promise.all([projectsResponse.json(), contractsResponse.json(), investmentsResponse.json()]);
    selectedId = projects.some(project => project.id === selectedId) ? selectedId : (projects[0]?.id || "");
    loaded = true;
    render();
  }

  function render() {
    const works = getWorks();
    const project = projects.find(item => item.id === selectedId);
    const stages = works.filter(work => work.projeto_id === selectedId)
      .sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true }));
    const contractByWork = currentByWork(contracts, "venda_contratual_efetiva");
    const investmentByWork = currentByWork(investments, "orcamento_revisto_sem_iva");
    const rows = stages.map(work => ({ work, ...stageFinancial(work, contractByWork, investmentByWork) }));
    const clientRows = rows.filter(row => !row.investment);
    const investmentRows = rows.filter(row => row.investment);
    const totals = clientRows.reduce((sum, row) => ({ sale: sum.sale + row.sale, cost: sum.cost + row.cost, margin: sum.margin + row.margin }), { sale: 0, cost: 0, margin: 0 });
    const investmentTotals = investmentRows.reduce((sum, row) => ({ budget: sum.budget + row.sale, cost: sum.cost + row.cost, deviation: sum.deviation + row.margin }), { budget: 0, cost: 0, deviation: 0 });

    root.innerHTML = `<div class="page-heading"><div><p class="eyebrow">GESTÃO INTEGRADA</p><h1>PROJETOS</h1><p>Agrupamento de etapas independentes de um mesmo projeto.</p></div>${canManage() ? `<button class="outline-action" data-new-project>＋ NOVO PROJETO</button>` : ""}</div>
      <div class="projects-layout">
        <section class="panel projects-list-panel"><div class="works-list-head"><span>PROJETOS</span><small>${projects.length}</small></div>
          <div class="projects-list">${projects.length ? projects.map(item => {
            const count = works.filter(work => work.projeto_id === item.id).length;
            return `<button type="button" class="project-list-item ${item.id === selectedId ? "selected" : ""}" data-project-id="${item.id}"><strong>${escapeHtml(item.nome)}</strong><small>${count} ${count === 1 ? "ETAPA" : "ETAPAS"}</small></button>`;
          }).join("") : `<div class="empty-state"><strong>SEM PROJETOS</strong><span>As obras continuam disponíveis normalmente.</span></div>`}</div>
        </section>
        <section class="panel project-detail">${project ? `<header><div><p class="eyebrow">PROJETO</p><h2>${escapeHtml(project.nome)}</h2><span>${escapeHtml(project.cliente || "Cliente não indicado")}</span></div><p>${escapeHtml(project.morada || "Morada não indicada")}</p></header>
          <div class="project-summary"><div><span>VENDA ATUAL</span><strong>${euro.format(totals.sale)}</strong></div><div><span>CUSTO DIRETO</span><strong>${euro.format(totals.cost)}</strong></div><div><span>MARGEM PREVISTA</span><strong class="${totals.margin < 0 ? "negative" : "positive"}">${euro.format(totals.margin)}</strong></div></div>
          ${investmentRows.length ? `<div class="project-investment-summary"><strong>INVESTIMENTO PRÓPRIO</strong><span>Orçamento revisto ${euro.format(investmentTotals.budget)}</span><span>Custo realizado ${euro.format(investmentTotals.cost)}</span><span>Desvio ${euro.format(investmentTotals.deviation)}</span></div>` : ""}
          <div class="project-stage-head"><div><p class="eyebrow">ETAPAS</p><h3>OBRAS DO PROJETO</h3></div><span>${stages.length}</span></div>
          <div class="project-stages">${rows.length ? rows.map(row => `<button type="button" class="project-stage" data-project-work="${row.work.id}"><div><span>OBRA ${escapeHtml(row.work.numero)}</span><strong>${escapeHtml(row.work.nome)}</strong><small>${escapeHtml(row.work.situacao || "Situação não definida")}</small></div><dl>${row.investment ? `<div><dt>ORÇAMENTO</dt><dd>${euro.format(row.sale)}</dd></div><div><dt>CUSTO REALIZADO</dt><dd>${euro.format(row.cost)}</dd></div><div><dt>DESVIO</dt><dd>${euro.format(row.margin)}</dd></div>` : `<div><dt>VENDA</dt><dd>${euro.format(row.sale)}</dd></div><div><dt>CUSTO</dt><dd>${euro.format(row.cost)}</dd></div><div><dt>MARGEM</dt><dd>${euro.format(row.margin)}</dd></div>`}</dl><b>→</b></button>`).join("") : `<div class="empty-state"><strong>AINDA SEM ETAPAS</strong><span>Associe uma obra a este projeto no formulário de criação da obra.</span></div>`}</div>` : `<div class="empty-state"><strong>SELECIONE UM PROJETO</strong></div>`}</section>
      </div>`;
  }

  function openNewProject() {
    root.querySelector("[data-project-dialog]")?.remove();
    root.insertAdjacentHTML("beforeend", `<div class="dialog-backdrop" data-project-dialog><section class="work-dialog-card"><div class="panel-title"><span>＋ NOVO PROJETO</span><button type="button" data-close-project>×</button></div><form data-project-form><label>NOME<input name="nome" required maxlength="160"></label><label>CLIENTE<input name="cliente" maxlength="160"></label><label>MORADA<input name="morada" maxlength="240"></label><p class="form-error"></p><div class="dialog-actions"><button class="outline-action" type="button" data-close-project>CANCELAR</button><button class="primary-button" type="submit">CRIAR PROJETO <span>→</span></button></div></form></section></div>`);
    root.querySelector('[name="nome"]').focus();
  }

  root.addEventListener("click", event => {
    const projectButton = event.target.closest("[data-project-id]");
    if (projectButton) { selectedId = projectButton.dataset.projectId; render(); return; }
    const workButton = event.target.closest("[data-project-work]");
    if (workButton) { openWork(workButton.dataset.projectWork); return; }
    if (event.target.closest("[data-new-project]")) { openNewProject(); return; }
    if (event.target.closest("[data-close-project]")) root.querySelector("[data-project-dialog]")?.remove();
  });

  root.addEventListener("submit", async event => {
    const form = event.target.closest("[data-project-form]");
    if (!form) return;
    event.preventDefault();
    const fields = Object.fromEntries(new FormData(form));
    const button = form.querySelector('[type="submit"]');
    button.disabled = true;
    const response = await api("projetos?select=id,empresa_id,nome,cliente,morada,criado_em", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ empresa_id: companyId, nome: fields.nome.trim(), cliente: fields.cliente.trim() || null, morada: fields.morada.trim() || null }) });
    if (!response.ok) {
      const detail = await response.json().catch(() => ({}));
      form.querySelector(".form-error").textContent = detail.message || "Não foi possível criar o projeto.";
      button.disabled = false;
      return;
    }
    const [created] = await response.json();
    projects.push(created);
    selectedId = created.id;
    root.querySelector("[data-project-dialog]")?.remove();
    toast("Projeto criado com sucesso.");
    render();
  });

  return { show: () => load(), refresh: () => load(true), options: () => projects };
}
