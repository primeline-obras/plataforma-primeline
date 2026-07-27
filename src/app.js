import { clearSession, downloadInvoicePdf, getSession, isSupabaseConfigured, requestPasswordReset, signIn, signOut, supabase, uploadInvoicePdf } from "./supabase-browser.js";
import { demoInvoices, demoSubcontracts, demoSuppliers, demoWorks } from "./demoData-browser.js";

const $ = (selector) => document.querySelector(selector);
const euro = new Intl.NumberFormat("pt-PT", { style: "currency", currency: "EUR" });
const prettyDate = new Intl.DateTimeFormat("pt-PT", { day: "2-digit", month: "short", year: "numeric" });
const icon = (name) => {
  const paths = {
    menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
    bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M13.7 21a2 2 0 0 1-3.4 0"/>',
    invoice: '<path d="M6 2h9l4 4v16H6zM14 2v5h5M9 12h7M9 16h7"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    x: '<path d="m6 6 12 12M18 6 6 18"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
    upload: '<path d="M12 16V4m0 0L7 9m5-5 5 5M5 20h14"/>',
  };
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${paths[name] || paths.invoice}</svg>`;
};

let works = [], suppliers = [], subcontracts = [], invoices = [], collaborators = [];
const PRIMELINE_COMPANY_ID = "73fb13c8-d29f-4192-a506-4ca243343add";
let currentFilter = "all";
let session = getSession();
let selectedPdf = null;
let localPdfUrl = "";
let openedPdfUrl = "";
let activeView = "invoices";
let selectedWorkId = "";
let workDetails = { contract: null, phases: [], measurements: [], payments: [], consultations: [], error: "", procurementError: "" };
let selectedWorkTab = "summary";

function brand() {
  return `<div class="brand"><div class="brand-mark"><span></span><span></span><span></span></div><div><strong>PRIMELINE</strong><small>ENGENHARIA E CONSTRUÇÃO</small></div></div>`;
}

document.querySelector("#root").innerHTML = `
  <div class="app-shell">
    <section class="auth-screen" id="auth-screen" ${session || !isSupabaseConfigured ? "hidden" : ""}>
      <div class="auth-brand">${brand()}</div>
      <div class="auth-card">
        <p class="eyebrow">ACESSO RESERVADO</p>
        <h1>ENTRAR</h1>
        <p>Utilize as credenciais da sua conta PRIMELINE.</p>
        <form id="login-form">
          <label>EMAIL<input name="email" type="text" inputmode="email" autocomplete="email" placeholder="nome@primeline.pt" required></label>
          <label>PALAVRA-PASSE<input name="password" type="password" autocomplete="current-password" placeholder="••••••••" required></label>
          <p class="auth-error" id="auth-error"></p>
          <button class="primary-button login-button" type="submit">INICIAR SESSÃO <span>→</span></button>
          <button class="forgot-link" id="show-recovery" type="button">ESQUECI-ME DA PALAVRA-PASSE</button>
        </form>
        <form id="recovery-form" hidden>
          <button class="back-link" id="hide-recovery" type="button">← VOLTAR AO LOGIN</button>
          <p class="recovery-copy">Indique o email da sua conta. Enviaremos uma ligação segura para definir uma nova palavra-passe.</p>
          <label>EMAIL<input name="recovery_email" type="text" inputmode="email" autocomplete="email" placeholder="nome@primeline.pt" required></label>
          <p class="auth-error" id="recovery-error"></p>
          <p class="auth-success" id="recovery-success"></p>
          <button class="primary-button login-button" type="submit">ENVIAR LIGAÇÃO <span>→</span></button>
        </form>
        <small>PRIMELINE · ENGENHARIA E CONSTRUÇÃO</small>
      </div>
    </section>
    <button class="scrim" id="scrim" aria-label="Fechar menu"></button>
    <aside class="sidebar">${brand()}
      <nav><p>GESTÃO</p>
        <button data-view="overview">▦ <span>Visão geral</span></button><button data-view="works">▥ <span>Obras</span></button>
        <button class="active" data-view="invoices">▤ <span>Faturas</span></button><button data-view="documents">□ <span>Documentos</span></button><button data-view="team">♙ <span>Equipa</span></button>
        <p>CONFIGURAÇÃO</p><button>⚙ <span>Definições</span></button>
      </nav>
      <div class="sidebar-user"><span id="user-initials">PL</span><div><strong id="user-name">UTILIZADOR</strong><small id="user-role">SESSÃO AUTENTICADA</small></div><button class="logout-button" id="logout" title="Terminar sessão">↗</button></div>
    </aside>
    <main>
      <header class="topbar"><button class="mobile-menu" id="menu">${icon("menu")}</button><div class="mobile-brand">${brand()}</div>
        <div class="top-actions">${!isSupabaseConfigured ? '<span class="demo-badge">MODO DEMONSTRAÇÃO</span>' : ""}<button class="icon-button">${icon("bell")}<i>3</i></button></div>
      </header>
      <div class="page" id="invoice-view">
        <div class="page-heading"><div><p class="eyebrow">GESTÃO FINANCEIRA</p><h1>FATURAS</h1><p>Registo e aprovação de despesas das obras.</p></div><div class="heading-stat"><span>PENDENTES</span><strong id="count">00</strong></div></div>
        <section class="invoice-grid">
          <div class="panel new-invoice">
            <div class="panel-title"><span>＋ NOVA FATURA</span><small>INSERÇÃO MANUAL</small></div>
            <form id="invoice-form">
              <label>OBRA<div class="select-wrap"><select name="obra_id" required></select><b>⌄</b></div></label>
              <label>TIPO DE DESPESA<div class="segmented">
                <button type="button" data-type="subempreitada" class="selected">SUBEMPREITADA</button><button type="button" data-type="material">MATERIAL</button><button type="button" data-type="estaleiro">ESTALEIRO</button>
              </div></label>
              <input type="hidden" name="tipo_origem" value="subempreitada">
              <label>FORNECEDOR<div class="select-wrap"><select name="fornecedor_id" required></select><b>⌄</b></div></label>
              <label class="conditional" id="subcontract-field">SUBEMPREITADA<div class="select-wrap"><select name="subempreitada_id" required></select><b>⌄</b></div><em id="subcontract-hint"></em></label>
              <div class="form-row"><label>N.º DOCUMENTO<input name="numero_doc" placeholder="Ex. FT 2026/001" required></label><label>DATA<input name="data_fatura" type="date" required></label></div>
              <label>VALOR (EUR)<div class="money-input"><input name="valor" type="number" min="0.01" step="0.01" placeholder="0,00" required><span>€</span></div></label>
              <input id="pdf-input" type="file" accept="application/pdf,.pdf" hidden>
              <div class="pdf-attachment" id="pdf-attachment" hidden>
                <div class="pdf-attachment-head">
                  <span>${icon("invoice")}<strong id="pdf-name"></strong><small id="pdf-size"></small></span>
                  <div><button type="button" id="preview-pdf">PRÉ-VISUALIZAR</button><button type="button" id="remove-pdf" aria-label="Remover PDF">×</button></div>
                </div>
              </div>
              <div class="extraction-panel" id="extraction-panel" hidden>
                <div class="extraction-title"><span>LEITURA AUTOMÁTICA</span><small id="extraction-status">A ANALISAR…</small></div>
                <div id="extraction-results"></div>
                <p id="extraction-note"></p>
              </div>
              <div class="form-actions"><button type="button" class="upload-button" id="choose-pdf">${icon("upload")} ANEXAR PDF</button><button class="primary-button" type="submit">REGISTAR FATURA <span>→</span></button></div>
            </form>
          </div>
          <div class="panel pending-panel">
            <div class="pending-head"><div><p class="eyebrow">POR VALIDAR</p><h2>FATURAS PENDENTES</h2></div><div class="select-wrap"><select id="work-filter"></select><b>⌄</b></div></div>
            <div class="search-box">${icon("search")}<input id="search" placeholder="Pesquisar fornecedor ou documento…"></div>
            <div class="invoice-list" id="invoice-list"><div class="empty-state">A CARREGAR FATURAS…</div></div>
          </div>
        </section>
      </div>
      <div class="page works-view" id="works-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">GESTÃO DE OBRA</p><h1>OBRAS</h1><p>Acompanhamento operacional e financeiro.</p></div>
          <div class="heading-stat"><span>ATIVAS</span><strong id="active-works-count">00</strong></div>
        </div>
        <div class="works-toolbar">
          <div class="search-box">${icon("search")}<input id="work-search" placeholder="Pesquisar número, nome ou cliente…"></div>
          <div class="select-wrap"><select id="work-status-filter"><option value="all">Todas as situações</option></select><b>⌄</b></div>
          <button class="outline-action" id="new-work" type="button">＋ NOVA OBRA</button>
        </div>
        <div class="works-layout">
          <section class="works-list-panel panel">
            <div class="works-list-head"><span>PORTFÓLIO</span><small id="works-result-count">0 OBRAS</small></div>
            <div id="works-list" class="works-list"></div>
          </section>
          <section class="work-detail panel" id="work-detail">
            <div class="empty-state"><strong>SELECIONE UMA OBRA</strong><span>Consulte os principais dados e indicadores.</span></div>
          </section>
        </div>
      </div>
      <div class="page placeholder-view" id="placeholder-view" hidden>
        <div class="empty-state"><strong id="placeholder-title">MÓDULO EM PREPARAÇÃO</strong><span>Esta área será desenvolvida numa próxima etapa.</span></div>
      </div>
    </main>
    <div id="toast"></div>
    <div class="dialog-backdrop" id="work-dialog" hidden>
      <section class="work-dialog-card" role="dialog" aria-modal="true" aria-labelledby="work-dialog-title">
        <div class="panel-title"><span id="work-dialog-title">＋ NOVA OBRA</span><button id="close-work-dialog" type="button" aria-label="Fechar">×</button></div>
        <form id="work-form">
          <div class="form-row"><label>N.º DA OBRA<input name="numero" required maxlength="30" placeholder="Ex. 121"></label><label>SITUAÇÃO<div class="select-wrap"><select name="situacao"><option value="em_curso">Em curso</option><option value="planeamento">Planeamento</option><option value="suspensa">Suspensa</option></select><b>⌄</b></div></label></div>
          <label>DESIGNAÇÃO<input name="nome" required maxlength="160" placeholder="Ex. Moradia Unifamiliar — Cascais"></label>
          <div class="form-row"><label>CLIENTE<input name="cliente" maxlength="160"></label><label>DIRETOR DE OBRA<div class="select-wrap"><select name="diretor_obra_id"><option value="">Não definido</option></select><b>⌄</b></div></label></div>
          <label>MORADA<input name="morada" maxlength="240"></label>
          <div class="form-row"><label>TIPO<input name="tipo" maxlength="80" placeholder="Ex. Construção nova"></label><label>MODALIDADE<input name="modalidade" maxlength="80" placeholder="Ex. Empreitada geral"></label></div>
          <div class="form-row"><label>DATA DE INÍCIO<input name="data_inicio" type="date"></label><label>FIM PREVISTO<input name="data_fim_prevista" type="date"></label></div>
          <p class="form-error" id="work-form-error"></p>
          <div class="dialog-actions"><button class="outline-action" id="cancel-work" type="button">CANCELAR</button><button class="primary-button" type="submit">CRIAR OBRA <span>→</span></button></div>
        </form>
      </section>
    </div>
    <div class="pdf-modal" id="pdf-modal" hidden>
      <div class="pdf-modal-bar"><strong id="pdf-modal-title">DOCUMENTO</strong><button id="close-pdf" aria-label="Fechar">×</button></div>
      <div class="pdf-modal-body"><iframe id="pdf-frame" title="Pré-visualização do PDF"></iframe></div>
    </div>
  </div>`;

const form = $("#invoice-form");
form.data_fatura.value = new Date().toISOString().slice(0, 10);

function renderUser() {
  const email = session?.user?.email || "utilizador";
  const label = session?.user?.user_metadata?.full_name || email.split("@")[0];
  $("#user-name").textContent = label.toUpperCase();
  $("#user-initials").textContent = label.split(/[ ._-]+/).slice(0, 2).map(part => part[0]).join("").toUpperCase();
}

function toast(message, kind = "success") {
  $("#toast").innerHTML = `<div class="toast ${kind}"><span>${icon(kind === "error" ? "x" : "check")}</span>${message}</div>`;
  setTimeout(() => { $("#toast").innerHTML = ""; }, 4200);
}

function optionList(items, label, emptyLabel) {
  return `<option value="">${emptyLabel}</option>${items.map((item) => `<option value="${item.id}">${label(item)}</option>`).join("")}`;
}

function renderSelectors() {
  form.obra_id.innerHTML = optionList(works, w => `Obra ${w.numero} — ${w.nome}`, "Selecionar obra");
  form.fornecedor_id.innerHTML = optionList(suppliers, s => s.nome, "Selecionar fornecedor");
  $("#work-filter").innerHTML = `<option value="all">Todas as obras</option>${works.map(w => `<option value="${w.id}">Obra ${w.numero}</option>`).join("")}`;
  if (works[0]) form.obra_id.value = works[0].id;
  renderSubcontracts();
}

function renderSubcontracts() {
  const eligible = subcontracts.filter(s => s.obra_id === form.obra_id.value && (!form.fornecedor_id.value || s.fornecedor_id === form.fornecedor_id.value));
  form.subempreitada_id.innerHTML = optionList(eligible, s => s.especialidade, "Selecionar especialidade");
  $("#subcontract-hint").textContent = form.fornecedor_id.value && !eligible.length ? "Sem subempreitadas compatíveis nesta obra." : "";
}

function renderInvoices() {
  const needle = $("#search").value.toLowerCase();
  const visible = invoices.filter(invoice => {
    const supplier = suppliers.find(s => s.id === invoice.fornecedor_id)?.nome || "";
    return (currentFilter === "all" || invoice.obra_id === currentFilter) && (!needle || invoice.numero_doc?.toLowerCase().includes(needle) || supplier.toLowerCase().includes(needle));
  });
  $("#count").textContent = String(invoices.length).padStart(2, "0");
  if (!visible.length) {
    $("#invoice-list").innerHTML = `<div class="empty-state">${icon("check")}<strong>TUDO VALIDADO</strong><span>Não há faturas pendentes neste filtro.</span></div>`;
    return;
  }
  const typeLabels = { subempreitada: "Subempreitada", material: "Material", estaleiro: "Estaleiro" };
  $("#invoice-list").innerHTML = visible.map(invoice => {
    const supplier = suppliers.find(s => s.id === invoice.fornecedor_id)?.nome || "Fornecedor";
    const work = works.find(w => w.id === invoice.obra_id);
    return `<article class="invoice-card">
      <div class="invoice-icon">${icon("invoice")}</div><div class="invoice-main">
        <div class="invoice-top"><div><strong>${supplier}</strong><span>${invoice.numero_doc}</span></div><strong class="invoice-value">${euro.format(Number(invoice.valor))}</strong></div>
        <div class="invoice-meta"><span>OBRA ${work?.numero || "—"}</span><span class="type-pill ${invoice.tipo_origem}">${typeLabels[invoice.tipo_origem]}</span><span>${prettyDate.format(new Date(`${invoice.data_fatura}T12:00:00`))}</span>${invoice.arquivo_url ? `<button class="document-link" data-pdf="${encodeURIComponent(invoice.arquivo_url)}">${icon("invoice")} VER PDF</button>` : ""}</div>
        <div class="card-actions"><button class="reject" data-action="recusado" data-id="${invoice.id}">${icon("x")} RECUSAR</button><button class="approve" data-action="aprovado" data-id="${invoice.id}">${icon("check")} APROVAR</button></div>
      </div></article>`;
  }).join("");
}

async function loadData() {
  if (isSupabaseConfigured && !getSession()) return;
  if (!isSupabaseConfigured) {
    [works, suppliers, subcontracts, invoices] = [demoWorks, demoSuppliers, demoSubcontracts, demoInvoices];
  } else {
    const results = await Promise.all([
      supabase("obras?select=id,numero,nome,cliente,morada,tipo,modalidade,situacao,data_inicio,data_fim_prevista,diretor_obra_id&order=numero.desc"),
      supabase("fornecedores?select=id,nome&estado_confianca=neq.inativo&order=nome"),
      supabase("subempreitadas?select=id,obra_id,fornecedor_id,especialidade,valor_adjudicado,estado,tipo_pagamento,fase_id&order=especialidade"),
      supabase("faturas?select=*&estado_aprovacao=eq.pendente&order=criado_em.desc"),
    ]);
    const failed = results.find(result => !result.ok);
    if (failed) { toast(`Não foi possível carregar os dados: ${await failed.text()}`, "error"); return; }
    [works, suppliers, subcontracts, invoices] = await Promise.all(results.map(result => result.json()));
    const collaboratorsResult = await supabase("colaboradores?select=id,nome,funcao,nivel&data_saida=is.null&order=nome");
    collaborators = collaboratorsResult.ok ? await collaboratorsResult.json() : [];
  }
  renderSelectors(); renderInvoices();
  renderWorks();
  renderWorkDirectors();
}

function renderWorkDirectors() {
  const select = $("#work-form")?.diretor_obra_id;
  if (!select) return;
  select.innerHTML = `<option value="">Não definido</option>${collaborators.map(person => `<option value="${person.id}">${person.nome}${person.funcao ? ` — ${person.funcao}` : ""}</option>`).join("")}`;
}

function workSituationLabel(value) {
  if (!value) return "Não definida";
  return value.replace(/_/g, " ").replace(/\b\w/g, letter => letter.toUpperCase());
}

function renderWorks() {
  const search = ($("#work-search")?.value || "").toLocaleLowerCase("pt-PT");
  const status = $("#work-status-filter")?.value || "all";
  const situations = [...new Set(works.map(work => work.situacao).filter(Boolean))].sort();
  const statusSelect = $("#work-status-filter");
  if (statusSelect && statusSelect.options.length === 1) {
    statusSelect.innerHTML += situations.map(item => `<option value="${item}">${workSituationLabel(item)}</option>`).join("");
  }
  const filtered = works.filter(work => {
    const haystack = `${work.numero || ""} ${work.nome || ""} ${work.cliente || ""}`.toLocaleLowerCase("pt-PT");
    return (!search || haystack.includes(search)) && (status === "all" || work.situacao === status);
  });
  const active = works.filter(work => !["concluida", "concluído", "concluido", "cancelada"].includes((work.situacao || "").toLocaleLowerCase("pt-PT")));
  if ($("#active-works-count")) $("#active-works-count").textContent = String(active.length).padStart(2, "0");
  if ($("#works-result-count")) $("#works-result-count").textContent = `${filtered.length} ${filtered.length === 1 ? "OBRA" : "OBRAS"}`;
  if (!$("#works-list")) return;
  $("#works-list").innerHTML = filtered.length ? filtered.map(work => `
    <button class="work-list-item ${work.id === selectedWorkId ? "selected" : ""}" data-work-id="${work.id}">
      <span class="work-number">${String(work.numero || "—").padStart(3, "0")}</span>
      <span class="work-list-copy"><strong>${work.nome || "Obra sem designação"}</strong><small>${work.cliente || "Cliente não indicado"}</small></span>
      <span class="work-status ${work.situacao || "indefinida"}">${workSituationLabel(work.situacao)}</span>
      <span class="work-arrow">→</span>
    </button>`).join("") : `<div class="empty-state"><strong>SEM RESULTADOS</strong><span>Ajuste a pesquisa ou os filtros.</span></div>`;
}

function formatOptionalDate(value) {
  return value ? prettyDate.format(new Date(`${value}T12:00:00`)) : "—";
}

function workProgress(work) {
  if (!work.data_inicio || !work.data_fim_prevista) return null;
  const start = new Date(`${work.data_inicio}T12:00:00`).getTime();
  const end = new Date(`${work.data_fim_prevista}T12:00:00`).getTime();
  if (end <= start) return null;
  return Math.max(0, Math.min(100, Math.round(((Date.now() - start) / (end - start)) * 100)));
}

async function loadWorkDetails(workId) {
  selectedWorkId = workId;
  selectedWorkTab = "summary";
  workDetails = { contract: null, phases: [], measurements: [], payments: [], consultations: [], error: "", procurementError: "" };
  renderWorks();
  const work = works.find(item => item.id === workId);
  $("#work-detail").innerHTML = `<div class="empty-state">A CARREGAR DADOS DA OBRA…</div>`;
  if (!isSupabaseConfigured) {
    workDetails = {
      contract: { venda_inicial: 553619.19, venda_efetiva: 472179.26, valor_adiantamento: 110723.84, data_assinatura: "2026-02-11" },
      phases: Array.from({ length: 10 }, (_, index) => ({ id: `f-${index}`, codigo: `F${String(index + 1).padStart(2, "0")}`, nome: `Fase ${index + 1}` })),
      measurements: [],
      payments: [
        { subempreitada_id: "sub-elec", valor: 8500 },
        { subempreitada_id: "sub-ac", valor: 1350 },
      ],
      consultations: [
        { id: "c-caix", obra_id: work.id, especialidade: "Caixilharia", estado: "em_consulta", fornecedor_id: null },
        { id: "c-gas", obra_id: work.id, especialidade: "Gás", estado: "em_consulta", fornecedor_id: null },
      ],
      error: "",
      procurementError: "",
    };
    renderWorkDetail(work);
    return;
  }
  const [contractResult, phasesResult, measurementsResult] = await Promise.all([
    supabase(`contratos?select=*&obra_id=eq.${encodeURIComponent(workId)}&limit=1`),
    supabase(`fases?select=*&obra_id=eq.${encodeURIComponent(workId)}`),
    supabase(`autos_medicao?select=*&obra_id=eq.${encodeURIComponent(workId)}&order=mes_referencia.desc`),
  ]);
  const results = [contractResult, phasesResult, measurementsResult];
  const failed = results.find(result => !result.ok);
  if (failed) {
    const detail = await failed.json().catch(() => ({}));
    workDetails.error = detail.message || "Não foi possível consultar os detalhes desta obra.";
  } else {
    const [contracts, phases, measurements] = await Promise.all(results.map(result => result.json()));
    workDetails.contract = contracts[0] || null;
    workDetails.phases = phases;
    workDetails.measurements = measurements;
  }
  const subcontractIds = subcontracts.filter(item => item.obra_id === workId).map(item => item.id);
  const [consultationsResult, paymentsResult] = await Promise.all([
    supabase(`consultas_subempreitada?select=*&obra_id=eq.${encodeURIComponent(workId)}`),
    subcontractIds.length
      ? supabase(`pagamentos_subempreitada?select=subempreitada_id,valor,estado_aprovacao&subempreitada_id=in.(${subcontractIds.map(encodeURIComponent).join(",")})`)
      : Promise.resolve(new Response(JSON.stringify([]), { status: 200, headers: { "Content-Type": "application/json" } })),
  ]);
  if (!consultationsResult.ok || !paymentsResult.ok) {
    const failedProcurement = !consultationsResult.ok ? consultationsResult : paymentsResult;
    const detail = await failedProcurement.json().catch(() => ({}));
    workDetails.procurementError = detail.message || "Não foi possível consultar pagamentos e consultas.";
  } else {
    workDetails.consultations = await consultationsResult.json();
    workDetails.payments = await paymentsResult.json();
  }
  renderWorkDetail(work);
}

function renderWorkSummary(work) {
  const contract = workDetails.contract;
  const subcontractRows = subcontracts.filter(item => item.obra_id === work.id);
  const subcontractTotal = subcontractRows.reduce((sum, item) => sum + Number(item.valor_adjudicado || 0), 0);
  const measuredTotal = workDetails.measurements.reduce((sum, item) => sum + Number(item.valor_a_faturar || 0), 0);
  const progress = workProgress(work);
  const sale = Number(contract?.venda_efetiva || contract?.venda_inicial || 0);
  return `
    <div class="work-kpis">
      <div><span>VENDA CONTRATADA</span><strong>${sale ? euro.format(sale) : "—"}</strong></div>
      <div><span>AUTOS A FATURAR</span><strong>${measuredTotal ? euro.format(measuredTotal) : euro.format(0)}</strong></div>
      <div><span>SUBEMPREITADAS</span><strong>${euro.format(subcontractTotal)}</strong><small>${subcontractRows.length} adjudicadas</small></div>
    </div>
    <div class="work-timeline">
      <div><span>INÍCIO</span><strong>${formatOptionalDate(work.data_inicio)}</strong></div>
      <div class="timeline-progress"><span>PRAZO DECORRIDO</span><div><i style="width:${progress ?? 0}%"></i></div><strong>${progress === null ? "—" : `${progress}%`}</strong></div>
      <div><span>FIM PREVISTO</span><strong>${formatOptionalDate(work.data_fim_prevista)}</strong></div>
    </div>
    <div class="work-detail-grid">
      <section><div class="detail-section-title"><span>CONTRATO</span></div>
        <dl>
          <div><dt>Venda inicial</dt><dd>${contract?.venda_inicial != null ? euro.format(Number(contract.venda_inicial)) : "—"}</dd></div>
          <div><dt>Venda efetiva</dt><dd>${contract?.venda_efetiva != null ? euro.format(Number(contract.venda_efetiva)) : "—"}</dd></div>
          <div><dt>Adiantamento</dt><dd>${contract?.valor_adiantamento != null ? euro.format(Number(contract.valor_adiantamento)) : "—"}</dd></div>
          <div><dt>Assinatura</dt><dd>${formatOptionalDate(contract?.data_assinatura)}</dd></div>
        </dl>
      </section>
      <section><div class="detail-section-title"><span>FASES</span><small>${workDetails.phases.length}</small></div>
        <div class="phase-tags">${workDetails.phases.length ? workDetails.phases.map(phase => `<span>${phase.codigo || phase.numero || "—"}<small>${phase.nome || phase.designacao || ""}</small></span>`).join("") : "<em>Sem fases disponíveis</em>"}</div>
      </section>
    </div>`;
}

function supplierName(id) {
  return suppliers.find(item => item.id === id)?.nome || "Fornecedor não identificado";
}

function renderSubcontractsTab(work) {
  const rows = subcontracts.filter(item => item.obra_id === work.id);
  const paidBySubcontract = new Map();
  workDetails.payments.forEach(payment => {
    paidBySubcontract.set(payment.subempreitada_id, (paidBySubcontract.get(payment.subempreitada_id) || 0) + Number(payment.valor || 0));
  });
  const openConsultations = workDetails.consultations.filter(item => !item.fornecedor_id && (item.estado === "em_consulta" || !item.estado));
  const adjudicatedTotal = rows.reduce((sum, item) => sum + Number(item.valor_adjudicado || 0), 0);
  const paidTotal = rows.reduce((sum, item) => sum + (paidBySubcontract.get(item.id) || 0), 0);
  const overallPercent = adjudicatedTotal > 0 ? Math.min(100, Math.round((paidTotal / adjudicatedTotal) * 100)) : 0;
  return `
    ${workDetails.procurementError ? `<div class="work-warning"><strong>DADOS PARCIAIS</strong><span>${workDetails.procurementError} Execute o script RLS do separador Subempreitadas.</span></div>` : ""}
    <div class="procurement-summary">
      <div><span>ADJUDICADO</span><strong>${euro.format(adjudicatedTotal)}</strong></div>
      <div><span>PAGO</span><strong>${euro.format(paidTotal)}</strong></div>
      <div><span>EXECUÇÃO FINANCEIRA</span><strong>${overallPercent}%</strong><div class="mini-progress"><i style="width:${overallPercent}%"></i></div></div>
      <div><span>POR ADJUDICAR</span><strong>${openConsultations.length}</strong></div>
    </div>
    <div class="subcontracts-list">
      ${rows.length ? rows.map(row => {
        const adjudicated = Number(row.valor_adjudicado || 0);
        const paid = paidBySubcontract.get(row.id) || 0;
        const percent = adjudicated > 0 ? Math.min(100, Math.round((paid / adjudicated) * 100)) : 0;
        const approval = row.estado_aprovacao_gerencia || (row.aprovado_por_gerencia ? "aprovado" : "pendente");
        return `<article class="subcontract-card">
          <div class="subcontract-main"><span class="subcontract-specialty">${row.especialidade || "Sem especialidade"}</span><strong>${supplierName(row.fornecedor_id)}</strong><small>${workSituationLabel(row.estado)}</small></div>
          <div class="subcontract-value"><span>ADJUDICADO</span><strong>${euro.format(adjudicated)}</strong></div>
          <div class="subcontract-paid"><div><span>PAGO</span><strong>${euro.format(paid)}</strong><em>${percent}%</em></div><div class="payment-progress"><i style="width:${percent}%"></i></div></div>
          <span class="approval-badge ${approval}">${workSituationLabel(approval)}</span>
        </article>`;
      }).join("") : `<div class="empty-state"><strong>SEM SUBEMPREITADAS</strong><span>Ainda não existem adjudicações nesta obra.</span></div>`}
    </div>
    <section class="open-consultations">
      <div class="detail-section-title"><span>POR ADJUDICAR</span><small>${openConsultations.length}</small></div>
      ${openConsultations.length ? `<div class="consultation-grid">${openConsultations.map(item => `<div><span>${item.especialidade || item.designacao || "Especialidade não indicada"}</span><strong>EM CONSULTA</strong><small>Fornecedor por definir</small></div>`).join("")}</div>` : `<p>Não existem especialidades em consulta sem fornecedor definido.</p>`}
    </section>`;
}

function renderWorkTab(work) {
  if (selectedWorkTab === "subcontracts") return renderSubcontractsTab(work);
  if (selectedWorkTab === "measurements") return `<div class="empty-state"><strong>AUTOS DE MEDIÇÃO</strong><span>Este separador será desenvolvido na próxima etapa.</span></div>`;
  if (selectedWorkTab === "phases") return `<div class="empty-state"><strong>FASES</strong><span>Este separador será desenvolvido numa próxima etapa.</span></div>`;
  return renderWorkSummary(work);
}

function renderWorkDetail(work) {
  if (!work) return;
  $("#work-detail").innerHTML = `
    <div class="work-detail-head">
      <div><p class="eyebrow">OBRA ${work.numero || "—"}</p><h2>${work.nome || "Sem designação"}</h2><span>${work.cliente || "Cliente não indicado"}</span></div>
      <span class="work-status ${work.situacao || "indefinida"}">${workSituationLabel(work.situacao)}</span>
    </div>
    <div class="work-location">${work.morada || "Morada não indicada"}</div>
    ${workDetails.error ? `<div class="work-warning"><strong>DADOS PARCIAIS</strong><span>${workDetails.error} Execute as políticas RLS adicionais incluídas no projeto.</span></div>` : ""}
    <nav class="work-tabs">
      <button data-work-tab="summary" class="${selectedWorkTab === "summary" ? "active" : ""}">RESUMO</button>
      <button data-work-tab="subcontracts" class="${selectedWorkTab === "subcontracts" ? "active" : ""}">SUBEMPREITADAS</button>
      <button data-work-tab="measurements" class="${selectedWorkTab === "measurements" ? "active" : ""}">AUTOS DE MEDIÇÃO</button>
      <button data-work-tab="phases" class="${selectedWorkTab === "phases" ? "active" : ""}">FASES</button>
    </nav>
    <div class="work-tab-content">${renderWorkTab(work)}</div>`;
}

function switchView(view) {
  activeView = view;
  document.querySelectorAll(".sidebar nav [data-view]").forEach(button => button.classList.toggle("active", button.dataset.view === view));
  $("#invoice-view").hidden = view !== "invoices";
  $("#works-view").hidden = view !== "works";
  $("#placeholder-view").hidden = ["invoices", "works"].includes(view);
  if (!["invoices", "works"].includes(view)) {
    const labels = { overview: "VISÃO GERAL", documents: "DOCUMENTOS", team: "EQUIPA" };
    $("#placeholder-title").textContent = labels[view] || "MÓDULO EM PREPARAÇÃO";
  }
  if (view === "works") {
    renderWorks();
    if (!selectedWorkId && works[0]) loadWorkDetails(works[0].id);
  }
  $(".sidebar").classList.remove("open");
}

document.querySelectorAll("[data-type]").forEach(button => button.addEventListener("click", () => {
  document.querySelectorAll("[data-type]").forEach(item => item.classList.remove("selected"));
  button.classList.add("selected"); form.tipo_origem.value = button.dataset.type;
  const isSubcontract = button.dataset.type === "subempreitada";
  $("#subcontract-field").hidden = !isSubcontract; form.subempreitada_id.required = isSubcontract;
}));
form.obra_id.addEventListener("change", renderSubcontracts);
form.fornecedor_id.addEventListener("change", renderSubcontracts);
$("#search").addEventListener("input", renderInvoices);
$("#work-filter").addEventListener("change", e => { currentFilter = e.target.value; renderInvoices(); });
document.querySelectorAll(".sidebar nav [data-view]").forEach(button => button.addEventListener("click", () => switchView(button.dataset.view)));
$("#work-search").addEventListener("input", renderWorks);
$("#work-status-filter").addEventListener("change", renderWorks);
function closeWorkDialog() {
  $("#work-dialog").hidden = true;
  $("#work-form-error").textContent = "";
}
$("#new-work").addEventListener("click", () => {
  renderWorkDirectors();
  $("#work-dialog").hidden = false;
  $("#work-form").numero.focus();
});
$("#close-work-dialog").addEventListener("click", closeWorkDialog);
$("#cancel-work").addEventListener("click", closeWorkDialog);
$("#work-dialog").addEventListener("click", event => {
  if (event.target === $("#work-dialog")) closeWorkDialog();
});
$("#work-form").addEventListener("submit", async event => {
  event.preventDefault();
  const workForm = event.currentTarget;
  const button = workForm.querySelector('button[type="submit"]');
  const fields = Object.fromEntries(new FormData(workForm));
  $("#work-form-error").textContent = "";
  if (fields.data_inicio && fields.data_fim_prevista && fields.data_fim_prevista < fields.data_inicio) {
    $("#work-form-error").textContent = "A data de fim prevista não pode ser anterior à data de início.";
    return;
  }
  const duplicate = works.some(work => String(work.numero).trim().toLocaleLowerCase("pt-PT") === fields.numero.trim().toLocaleLowerCase("pt-PT"));
  if (duplicate) {
    $("#work-form-error").textContent = "Já existe uma obra com este número.";
    return;
  }
  const payload = {
    empresa_id: PRIMELINE_COMPANY_ID,
    numero: fields.numero.trim(),
    nome: fields.nome.trim(),
    cliente: fields.cliente.trim() || null,
    morada: fields.morada.trim() || null,
    tipo: fields.tipo.trim() || null,
    modalidade: fields.modalidade.trim() || null,
    diretor_obra_id: fields.diretor_obra_id || null,
    situacao: fields.situacao || "em_curso",
    data_inicio: fields.data_inicio || null,
    data_fim_prevista: fields.data_fim_prevista || null,
  };
  button.disabled = true;
  try {
    if (!isSupabaseConfigured) {
      payload.id = crypto.randomUUID();
    } else {
      const response = await supabase("obras?select=id,numero,nome,cliente,morada,tipo,modalidade,situacao,data_inicio,data_fim_prevista,diretor_obra_id", {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        const detail = await response.json().catch(() => ({}));
        throw new Error(detail.message || detail.details || "Não foi possível criar a obra.");
      }
      Object.assign(payload, (await response.json())[0]);
    }
    works.unshift(payload);
    renderSelectors();
    renderWorks();
    workForm.reset();
    closeWorkDialog();
    toast(`Obra ${payload.numero} criada com sucesso.`);
    await loadWorkDetails(payload.id);
  } catch (error) {
    $("#work-form-error").textContent = error.message || "Não foi possível criar a obra.";
  } finally {
    button.disabled = false;
  }
});
$("#works-list").addEventListener("click", event => {
  const item = event.target.closest("[data-work-id]");
  if (item) loadWorkDetails(item.dataset.workId);
});
$("#work-detail").addEventListener("click", event => {
  const tabButton = event.target.closest("[data-work-tab]");
  if (!tabButton) return;
  selectedWorkTab = tabButton.dataset.workTab;
  renderWorkDetail(works.find(item => item.id === selectedWorkId));
});
$("#menu").addEventListener("click", () => $(".sidebar").classList.add("open"));
$("#scrim").addEventListener("click", () => $(".sidebar").classList.remove("open"));
$("#choose-pdf").addEventListener("click", () => $("#pdf-input").click());

function normalizeExactName(value) {
  return value.toLocaleLowerCase("pt-PT").replace(/\s+/g, " ").trim();
}

function parsePortugueseMoney(value) {
  const clean = value.replace(/[€\s]/g, "");
  if (!clean) return null;
  let normalized = clean;
  if (clean.includes(",")) normalized = clean.replace(/\./g, "").replace(",", ".");
  else if ((clean.match(/\./g) || []).length > 1) normalized = clean.replace(/\./g, "");
  const number = Number(normalized);
  return Number.isFinite(number) && number > 0 ? number : null;
}

function toIsoDate(value) {
  const parts = value.match(/^(\d{1,2})[./-](\d{1,2})[./-](\d{4})$/);
  if (parts) return `${parts[3]}-${parts[2].padStart(2, "0")}-${parts[1].padStart(2, "0")}`;
  const iso = value.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  return iso ? iso[0] : null;
}

function extractionRow(label, value, confidence) {
  const labels = { alta: "ALTA", provavel: "PROVÁVEL", manual: "MANUAL" };
  return `<div class="extraction-row"><span>${label}</span><strong>${value || "Não identificado"}</strong><em class="${confidence}">${labels[confidence]}</em></div>`;
}

async function extractPdfData(file) {
  $("#extraction-panel").hidden = false;
  $("#extraction-status").textContent = "A ANALISAR…";
  $("#extraction-results").innerHTML = "";
  $("#extraction-note").textContent = "Os dados encontrados continuam editáveis e devem ser confirmados.";
  try {
    const pdfjs = await import("https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.min.mjs");
    pdfjs.GlobalWorkerOptions.workerSrc = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/pdf.worker.min.mjs";
    const bytes = new Uint8Array(await file.arrayBuffer());
    const pdf = await pdfjs.getDocument({ data: bytes }).promise;
    const lines = [];
    for (let pageNumber = 1; pageNumber <= Math.min(pdf.numPages, 12); pageNumber += 1) {
      const page = await pdf.getPage(pageNumber);
      const content = await page.getTextContent();
      let line = "";
      for (const item of content.items) {
        line += `${item.str || ""} `;
        if (item.hasEOL) {
          if (line.trim()) lines.push(line.replace(/\s+/g, " ").trim());
          line = "";
        }
      }
      if (line.trim()) lines.push(line.replace(/\s+/g, " ").trim());
    }
    const meaningfulLines = lines.filter(Boolean);
    const fullText = meaningfulLines.join("\n");
    if (fullText.replace(/\s/g, "").length < 20) {
      $("#extraction-status").textContent = "SEM TEXTO";
      $("#extraction-note").textContent = "Este PDF parece ser uma digitalização sem texto pesquisável. Preencha os campos manualmente; será necessário OCR para automatizar este documento.";
      $("#extraction-results").innerHTML = extractionRow("Documento", "", "manual") + extractionRow("Fornecedor", "", "manual") + extractionRow("Data", "", "manual") + extractionRow("Valor", "", "manual");
      return;
    }

    const documentPatterns = [
      /(?:^|\b)(FT|FS|FR|FATURA|INVOICE)\s*(?:N[.ºO]*\s*)?[:#-]?\s*([A-Z0-9][A-Z0-9/._-]{2,})/im,
      /(?:DOCUMENTO|DOC\.?)\s*(?:N[.ºO]*\s*)?[:#-]?\s*([A-Z0-9][A-Z0-9/._-]{2,})/im,
    ];
    let documentNumber = "";
    for (const pattern of documentPatterns) {
      const match = fullText.match(pattern);
      if (match) {
        documentNumber = match[2] ? `${match[1].toUpperCase()} ${match[2]}` : match[1];
        break;
      }
    }

    let invoiceDate = "";
    const dateLine = meaningfulLines.find(line => /\b(data|date|emiss[aã]o)\b/i.test(line) && /\d{1,4}[./-]\d{1,2}[./-]\d{2,4}/.test(line));
    const dateMatch = (dateLine || fullText).match(/\b(?:\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{4}-\d{2}-\d{2})\b/);
    if (dateMatch) invoiceDate = toIsoDate(dateMatch[0]) || "";

    const totalLabels = [
      /total\s+(?:a\s+)?pagar/i,
      /total\s+(?:do\s+)?documento/i,
      /valor\s+total/i,
      /\btotal\b/i,
    ];
    let invoiceValue = null;
    for (const label of totalLabels) {
      const candidates = meaningfulLines.filter(line => label.test(line) && !/subtotal|iva/i.test(line));
      for (const candidate of candidates.reverse()) {
        const values = candidate.match(/\d{1,3}(?:[.\s]\d{3})*(?:,\d{2})|\d+(?:[.,]\d{2})/g);
        if (values?.length) {
          invoiceValue = parsePortugueseMoney(values.at(-1));
          if (invoiceValue) break;
        }
      }
      if (invoiceValue) break;
    }

    const normalizedLines = new Set(meaningfulLines.map(normalizeExactName));
    const exactSupplier = suppliers.find(supplier => normalizedLines.has(normalizeExactName(supplier.nome)));

    if (documentNumber) form.numero_doc.value = documentNumber;
    if (invoiceDate) form.data_fatura.value = invoiceDate;
    if (invoiceValue) form.valor.value = invoiceValue.toFixed(2);
    if (exactSupplier) {
      form.fornecedor_id.value = exactSupplier.id;
      renderSubcontracts();
      form.subempreitada_id.value = "";
    } else {
      form.fornecedor_id.value = "";
      renderSubcontracts();
    }

    $("#extraction-status").textContent = "CONCLUÍDA";
    $("#extraction-results").innerHTML =
      extractionRow("Documento", documentNumber, documentNumber ? "alta" : "manual") +
      extractionRow("Fornecedor", exactSupplier?.nome, exactSupplier ? "alta" : "manual") +
      extractionRow("Data", invoiceDate ? prettyDate.format(new Date(`${invoiceDate}T12:00:00`)) : "", invoiceDate ? "provavel" : "manual") +
      extractionRow("Valor", invoiceValue ? euro.format(invoiceValue) : "", invoiceValue ? "provavel" : "manual");
    $("#extraction-note").textContent = exactSupplier
      ? "Fornecedor encontrado por correspondência exata. Confirme os restantes campos e escolha manualmente a subempreitada, quando aplicável."
      : "O fornecedor não corresponde exatamente a nenhum registo existente. Selecione-o manualmente na lista; nenhum fornecedor foi criado.";
  } catch (error) {
    $("#extraction-status").textContent = "FALHOU";
    $("#extraction-results").innerHTML = "";
    $("#extraction-note").textContent = `Não foi possível ler este PDF: ${error.message || "erro desconhecido"}. Preencha os campos manualmente.`;
  }
}

$("#pdf-input").addEventListener("change", event => {
  const file = event.target.files?.[0];
  if (!file) return;
  if (file.type !== "application/pdf" && !file.name.toLowerCase().endsWith(".pdf")) {
    toast("Apenas são aceites ficheiros PDF.", "error");
    event.target.value = "";
    return;
  }
  if (file.size > 10 * 1024 * 1024) {
    toast("O PDF excede o limite de 10 MB.", "error");
    event.target.value = "";
    return;
  }
  if (localPdfUrl) URL.revokeObjectURL(localPdfUrl);
  selectedPdf = file;
  localPdfUrl = URL.createObjectURL(file);
  $("#pdf-name").textContent = file.name;
  $("#pdf-size").textContent = `${(file.size / 1024 / 1024).toFixed(2)} MB`;
  $("#pdf-attachment").hidden = false;
  $("#choose-pdf").innerHTML = `${icon("upload")} SUBSTITUIR PDF`;
  extractPdfData(file);
});

function openPdfModal(url, title) {
  $("#pdf-frame").src = url;
  $("#pdf-modal-title").textContent = title || "DOCUMENTO";
  $("#pdf-modal").hidden = false;
}

function closePdfModal() {
  $("#pdf-modal").hidden = true;
  $("#pdf-frame").src = "about:blank";
  if (openedPdfUrl) {
    URL.revokeObjectURL(openedPdfUrl);
    openedPdfUrl = "";
  }
}

$("#preview-pdf").addEventListener("click", () => {
  if (localPdfUrl) openPdfModal(localPdfUrl, selectedPdf?.name);
});
$("#remove-pdf").addEventListener("click", () => {
  if (localPdfUrl) URL.revokeObjectURL(localPdfUrl);
  selectedPdf = null;
  localPdfUrl = "";
  $("#pdf-input").value = "";
  $("#pdf-attachment").hidden = true;
  $("#extraction-panel").hidden = true;
  $("#extraction-results").innerHTML = "";
  $("#choose-pdf").innerHTML = `${icon("upload")} ANEXAR PDF`;
});
$("#close-pdf").addEventListener("click", closePdfModal);
$("#pdf-modal").addEventListener("click", event => {
  if (event.target === $("#pdf-modal")) closePdfModal();
});
document.addEventListener("keydown", event => {
  if (event.key === "Escape" && !$("#pdf-modal").hidden) closePdfModal();
});
$("#logout").addEventListener("click", async () => {
  await signOut(); session = null;
  $("#auth-screen").hidden = false;
  works = []; suppliers = []; subcontracts = []; invoices = [];
  renderInvoices();
});

$("#login-form").addEventListener("submit", async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector("button");
  const fields = Object.fromEntries(new FormData(event.currentTarget));
  button.disabled = true; button.firstChild.textContent = "A AUTENTICAR… ";
  $("#auth-error").textContent = "";
  try {
    session = await signIn(fields.email, fields.password);
    $("#auth-screen").hidden = true;
    renderUser();
    await loadData();
  } catch (error) {
    clearSession();
    $("#auth-error").textContent = error.message;
  } finally {
    button.disabled = false; button.firstChild.textContent = "INICIAR SESSÃO ";
  }
});

$("#show-recovery").addEventListener("click", () => {
  $("#login-form").hidden = true;
  $("#recovery-form").hidden = false;
  $("#auth-error").textContent = "";
  $(".auth-card h1").textContent = "RECUPERAR ACESSO";
  $(".auth-card > p:not(.eyebrow)").textContent = "Receba uma ligação segura no seu email.";
});

$("#hide-recovery").addEventListener("click", () => {
  $("#recovery-form").hidden = true;
  $("#login-form").hidden = false;
  $("#recovery-error").textContent = "";
  $("#recovery-success").textContent = "";
  $(".auth-card h1").textContent = "ENTRAR";
  $(".auth-card > p:not(.eyebrow)").textContent = "Utilize as credenciais da sua conta PRIMELINE.";
});

$("#recovery-form").addEventListener("submit", async event => {
  event.preventDefault();
  const button = event.currentTarget.querySelector(".primary-button");
  const email = event.currentTarget.recovery_email.value.trim();
  button.disabled = true;
  button.firstChild.textContent = "A ENVIAR… ";
  $("#recovery-error").textContent = "";
  $("#recovery-success").textContent = "";
  try {
    await requestPasswordReset(email);
    $("#recovery-success").textContent = "Email enviado. Consulte também a pasta de spam. A ligação é válida por tempo limitado.";
    event.currentTarget.recovery_email.value = "";
  } catch (error) {
    const messages = {
      over_email_send_rate_limit: "Foram pedidos demasiados emails. Aguarde alguns minutos e tente novamente.",
      email_address_invalid: "O endereço de email não é válido.",
    };
    $("#recovery-error").textContent = messages[error.code] || error.message || "Não foi possível enviar o email de recuperação.";
  } finally {
    button.disabled = false;
    button.firstChild.textContent = "ENVIAR LIGAÇÃO ";
  }
});

form.addEventListener("submit", async event => {
  event.preventDefault();
  const payload = Object.fromEntries(new FormData(form));
  payload.valor = Number(payload.valor); payload.subempreitada_id ||= null;
  const submit = form.querySelector(".primary-button"); submit.disabled = true; submit.firstChild.textContent = "A GUARDAR… ";
  if (!isSupabaseConfigured) {
    invoices.unshift({ ...payload, id: `demo-${Date.now()}`, estado_aprovacao: "pendente", criado_em: new Date().toISOString() });
    toast("Fatura adicionada em modo de demonstração.");
  } else {
    if (selectedPdf) {
      submit.firstChild.textContent = "A ENVIAR PDF… ";
      try {
        payload.arquivo_url = await uploadInvoicePdf(selectedPdf, payload.obra_id);
      } catch (error) {
        toast(error.message || "Não foi possível enviar o PDF.", "error");
        submit.disabled = false;
        submit.firstChild.textContent = "REGISTAR FATURA ";
        return;
      }
    }
    submit.firstChild.textContent = "A REGISTAR… ";
    const result = await supabase("faturas", { method: "POST", body: JSON.stringify(payload), headers: { Prefer: "return=representation" } });
    if (!result.ok) {
      const detail = await result.text();
      toast(
        payload.arquivo_url
          ? `O PDF foi enviado, mas a fatura não foi registada. Contacte o administrador para remover o ficheiro órfão. ${detail}`
          : `Erro ao registar: ${detail}`,
        "error",
      );
    }
    else { const [inserted] = await result.json(); invoices.unshift(inserted); toast("Fatura registada e enviada para aprovação."); }
  }
  const keepWork = form.obra_id.value, keepType = form.tipo_origem.value;
  form.reset(); form.obra_id.value = keepWork; form.tipo_origem.value = keepType; form.data_fatura.value = new Date().toISOString().slice(0, 10);
  if (localPdfUrl) URL.revokeObjectURL(localPdfUrl);
  selectedPdf = null; localPdfUrl = "";
  $("#pdf-attachment").hidden = true;
  $("#extraction-panel").hidden = true;
  $("#extraction-results").innerHTML = "";
  $("#choose-pdf").innerHTML = `${icon("upload")} ANEXAR PDF`;
  renderSubcontracts(); renderInvoices(); submit.disabled = false; submit.firstChild.textContent = "REGISTAR FATURA ";
});

$("#invoice-list").addEventListener("click", async event => {
  const pdfButton = event.target.closest("[data-pdf]");
  if (pdfButton) {
    pdfButton.disabled = true;
    try {
      const objectPath = decodeURIComponent(pdfButton.dataset.pdf);
      const blob = await downloadInvoicePdf(objectPath);
      openedPdfUrl = URL.createObjectURL(blob);
      openPdfModal(openedPdfUrl, "FATURA");
    } catch (error) {
      toast(error.message || "Não foi possível abrir o PDF.", "error");
    } finally {
      pdfButton.disabled = false;
    }
    return;
  }
  const button = event.target.closest("[data-action]"); if (!button) return;
  const invoice = invoices.find(item => String(item.id) === button.dataset.id); if (!invoice) return;
  const decision = button.dataset.action;
  if (isSupabaseConfigured) {
    const result = await supabase(`faturas?id=eq.${invoice.id}&estado_aprovacao=eq.pendente`, {
      method: "PATCH", body: JSON.stringify({ estado_aprovacao: decision, data_aprovacao: new Date().toISOString() }),
    });
    if (!result.ok) { toast(`Não foi possível concluir: ${await result.text()}`, "error"); return; }
  }
  invoices = invoices.filter(item => item.id !== invoice.id); renderInvoices();
  toast(`Fatura ${decision === "aprovado" ? "aprovada" : "recusada"}${isSupabaseConfigured ? "" : " em modo de demonstração"}.`);
});

renderUser();
loadData();
