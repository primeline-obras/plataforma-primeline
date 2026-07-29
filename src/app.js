import { clearSession, downloadInvoicePdf, getSession, isSupabaseConfigured, requestPasswordReset, signIn, signOut, supabase, uploadDeliveryNote, uploadInvoicePdf, uploadWorkflowPdf } from "./supabase-browser.js";
import { demoInvoices, demoSubcontracts, demoSuppliers, demoWorks } from "./demoData-browser.js?v=2";
import { createProductionDashboard } from "./production-dashboard.js?v=6";

const $ = (selector) => document.querySelector(selector);
const euro = new Intl.NumberFormat("pt-PT", { style: "currency", currency: "EUR" });
const prettyDate = new Intl.DateTimeFormat("pt-PT", { day: "2-digit", month: "short", year: "numeric" });
const UI_THEME_KEY = "primeline_theme";
const UI_TV_KEY = "primeline_tv_mode";
const UI_SIDEBAR_KEY = "primeline_sidebar_collapsed";
const savedTheme = localStorage.getItem(UI_THEME_KEY);
document.documentElement.dataset.theme = savedTheme === "dark" ? "dark" : "light";
document.documentElement.classList.toggle("tv-mode", localStorage.getItem(UI_TV_KEY) === "true");
document.documentElement.classList.toggle("sidebar-collapsed", localStorage.getItem(UI_SIDEBAR_KEY) === "true");
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

let works = [], suppliers = [], subcontracts = [], invoices = [], financeInvoices = [], invoiceGuides = [], collaborators = [];
const PRIMELINE_COMPANY_ID = "73fb13c8-d29f-4192-a506-4ca243343add";
let currentFilter = "all";
let session = getSession();
let selectedPdf = null;
let localPdfUrl = "";
let openedPdfUrl = "";
let activeView = "overview";
let selectedWorkId = "";
let workDetails = { contract: null, phases: [], measurements: [], payments: [], consultations: [], billings: [], billingLinks: [], documents: [], error: "", procurementError: "", billingError: "" };
let selectedWorkTab = "summary";
let selectedTeamWeek = mondayIso(new Date());
let teamData = { allocations: [], absences: [], contracts: [], overtime: [], responsibles: [], users: [], loadedWeek: "", error: "" };
let selectedTeamTab = "collaborators";
let workforceEditing = false;
let selectedWorkforcePersonId = "";
let selectedWorkforceSourceDate = "";
let selectedWorkforceSourcePeriod = "";
let selectedWorkforcePeriod = "dia_inteiro";

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
      <button class="sidebar-collapse" id="sidebar-collapse" type="button" aria-pressed="false" title="Recolher menu"><span>⟵</span><b>RECOLHER</b></button>
      <nav><p>GESTÃO</p>
        <button class="active" data-view="overview">▦ <span>Visão geral</span></button><button data-view="works">▥ <span>Obras</span></button>
        <button data-view="invoices">▤ <span>Faturas</span></button><button data-view="finance">€ <span>Financeiro</span></button><button data-view="documents">□ <span>Documentos</span></button><button data-view="workforce">▦ <span>Quadro de pessoal</span></button><button data-view="team">♙ <span>Equipa</span></button>
        <p>CONFIGURAÇÃO</p><button>⚙ <span>Definições</span></button>
      </nav>
      <div class="sidebar-user"><span id="user-initials">PL</span><div><strong id="user-name">UTILIZADOR</strong><small id="user-role">SESSÃO AUTENTICADA</small></div><button class="logout-button" id="logout" title="Terminar sessão">↗</button></div>
    </aside>
    <main>
      <header class="topbar"><button class="mobile-menu" id="menu">${icon("menu")}</button><div class="mobile-brand">${brand()}</div>
        <div class="top-actions">${!isSupabaseConfigured ? '<span class="demo-badge">MODO DEMONSTRAÇÃO</span>' : ""}<button class="display-toggle" id="tv-toggle" type="button" aria-pressed="false">MODO TV</button><button class="display-toggle" id="theme-toggle" type="button" aria-pressed="false">TEMA</button><button class="icon-button">${icon("bell")}<i>3</i></button></div>
      </header>
      <div class="page overview-view" id="overview-view"></div>
      <div class="page meeting-view" id="meeting-view" hidden></div>
      <div class="page" id="invoice-view" hidden>
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
              <label>CONDIÇÃO DE PAGAMENTO<div class="select-wrap"><select name="condicao_pagamento" required><option value="">Selecionar condição</option><option value="imediato">Imediato</option><option value="15_dias">15 dias</option><option value="30_dias">30 dias</option></select><b>⌄</b></div><em id="payment-condition-suggestion"></em></label>
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
      <div class="page finance-view" id="finance-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">TESOURARIA</p><h1>FINANCEIRO</h1><p>Faturas aprovadas a aguardar pagamento.</p></div>
          <div class="heading-stat"><span>POR PAGAR</span><strong id="finance-count">00</strong></div>
        </div>
        <section class="finance-board" id="finance-board"></section>
        <section class="panel paid-history">
          <div class="paid-history-head"><div><p class="eyebrow">ARQUIVO</p><h2>HISTÓRICO DE FATURAS PAGAS</h2></div><span id="paid-count">0 FATURAS</span></div>
          <div class="paid-list" id="paid-list"></div>
        </section>
      </div>
      <div class="page team-view" id="team-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">GESTÃO DE PESSOAS</p><h1>EQUIPA</h1><p>Colaboradores, ausências, contratos e horas extraordinárias.</p></div>
          <div class="heading-stat"><span>ATIVOS</span><strong id="team-active-count">00</strong></div>
        </div>
        <div class="team-toolbar directory-toolbar">
          <div class="search-box">${icon("search")}<input id="team-directory-search" placeholder="Pesquisar colaborador ou função…"></div>
        </div>
        <section class="team-kpis" id="team-kpis"></section>
        <section class="team-alert-summary" id="team-alert-summary"></section>
        <nav class="team-tabs">
          <button class="active" data-team-tab="collaborators">COLABORADORES</button>
          <button data-team-tab="absences">AUSÊNCIAS</button>
          <button data-team-tab="contracts">CONTRATOS</button>
          <button data-team-tab="overtime">HORAS EXTRA</button>
        </nav>
        <section class="panel team-tab-panel" data-team-panel="absences" hidden>
          <div class="team-section-head"><div><p class="eyebrow">DISPONIBILIDADE</p><h2>AUSÊNCIAS DA SEMANA</h2></div></div>
          <div id="team-absences"></div>
        </section>
        <section class="panel team-directory-panel team-tab-panel" data-team-panel="collaborators">
          <div class="team-section-head"><div><p class="eyebrow">ESTRUTURA</p><h2>COLABORADORES</h2></div><span id="team-result-count"></span></div>
          <div id="team-directory"></div>
        </section>
        <section class="panel team-tab-panel" data-team-panel="contracts" hidden>
          <div class="team-section-head"><div><p class="eyebrow">VÍNCULOS</p><h2>CONTRATOS</h2></div><span id="team-contract-count"></span></div>
          <div id="team-contracts"></div>
        </section>
        <section class="panel team-tab-panel" data-team-panel="overtime" hidden>
          <div class="team-section-head"><div><p class="eyebrow">PAGAMENTOS</p><h2>HORAS EXTRAORDINÁRIAS</h2></div><span id="team-overtime-count"></span></div>
          <div id="team-overtime"></div>
        </section>
      </div>
      <div class="page workforce-view" id="workforce-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">PLANEAMENTO SEMANAL</p><h1>QUADRO DE PESSOAL</h1><p>Distribuição das equipas operacionais pelas obras.</p></div>
          <div class="workforce-heading-actions"><div class="workforce-legend"><span><i class="foreman"></i>ENCARREGADO</span><span><i class="mason"></i>PEDREIRO</span><span><i class="helper"></i>SERVENTE</span></div><button class="outline-action" id="edit-workforce" type="button">EDITAR QUADRO</button></div>
        </div>
        <div class="workforce-edit-banner" id="workforce-edit-banner" hidden><strong>MODO DE EDIÇÃO</strong><span id="workforce-edit-message">Selecione um íman e depois clique no dia e obra de destino.</span><button id="remove-workforce-allocation" type="button" hidden>RETIRAR</button><button id="finish-workforce-edit" type="button">TERMINAR</button></div>
        <div class="workforce-roster" id="workforce-roster" hidden></div>
        <div class="team-toolbar">
          <div class="week-navigation">
            <button class="outline-action" id="team-previous-week" type="button" aria-label="Semana anterior">←</button>
            <label>SEMANA DE<input id="team-week" type="date"></label>
            <button class="outline-action" id="team-next-week" type="button" aria-label="Semana seguinte">→</button>
            <button class="outline-action" id="team-current-week" type="button">SEMANA ATUAL</button>
          </div>
          <div class="search-box">${icon("search")}<input id="team-search" placeholder="Pesquisar colaborador, função ou obra…"></div>
        </div>
        <section class="panel team-board-panel">
          <div class="team-section-head"><div><p class="eyebrow">SEMANA SELECIONADA</p><h2>DISTRIBUIÇÃO POR OBRA</h2></div><span id="team-week-label"></span></div>
          <div id="team-board"></div>
        </section>
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
    <div class="dialog-backdrop" id="workflow-dialog" hidden>
      <section class="work-dialog-card workflow-dialog-card" role="dialog" aria-modal="true">
        <div class="panel-title"><span id="workflow-dialog-title">REGISTO</span><button id="close-workflow-dialog" type="button" aria-label="Fechar">×</button></div>
        <div id="workflow-dialog-content"></div>
      </section>
    </div>
    <div class="pdf-modal" id="pdf-modal" hidden>
      <div class="pdf-modal-bar"><strong id="pdf-modal-title">DOCUMENTO</strong><button id="close-pdf" aria-label="Fechar">×</button></div>
      <div class="pdf-modal-body"><iframe id="pdf-frame" title="Pré-visualização do PDF"></iframe></div>
    </div>
  </div>`;

const form = $("#invoice-form");
form.data_fatura.value = new Date().toISOString().slice(0, 10);
const productionDashboard = createProductionDashboard({
  supabase,
  isSupabaseConfigured,
  getSession,
  getWorks: () => works,
  getPendingInvoices: () => invoices,
  getFinanceInvoices: () => financeInvoices,
  getSuppliers: () => suppliers,
  euro,
  prettyDate,
  toast,
  showView: view => switchView(view),
});
productionDashboard.bind();

function renderUser() {
  const email = session?.user?.email || "utilizador";
  const label = session?.user?.user_metadata?.full_name || email.split("@")[0];
  $("#user-name").textContent = label.toUpperCase();
  $("#user-initials").textContent = label.split(/[ ._-]+/).slice(0, 2).map(part => part[0]).join("").toUpperCase();
}

window.addEventListener("primeline:session-expired", () => {
  session = null;
  $("#auth-screen").hidden = false;
  $("#auth-error").textContent = "A sua sessão expirou. Inicie sessão novamente.";
});

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
    const guides = invoiceGuides.filter(guide => guide.fatura_id === invoice.id);
    const hasGuide = guides.length > 0;
    return `<article class="invoice-card" data-invoice-card="${invoice.id}">
      <div class="invoice-icon">${icon("invoice")}</div><div class="invoice-main">
        <div class="invoice-top"><div><strong>${supplier}</strong><span>${invoice.numero_doc}</span></div><strong class="invoice-value">${euro.format(Number(invoice.valor))}</strong></div>
        <div class="invoice-meta"><span>OBRA ${work?.numero || "—"}</span><span class="type-pill ${invoice.tipo_origem}">${typeLabels[invoice.tipo_origem]}</span><span>${prettyDate.format(new Date(`${invoice.data_fatura}T12:00:00`))}</span>${invoice.arquivo_url ? `<button class="document-link" data-pdf="${encodeURIComponent(invoice.arquivo_url)}">${icon("invoice")} VER PDF</button>` : ""}</div>
        <div class="approval-fields">
          <label class="guide-picker ${hasGuide ? "ready" : ""}">
            ${icon("upload")}<span>${hasGuide ? `${guides.length} GUIA(S) ANEXADA(S)` : "ANEXAR GUIAS"}</span>
            <input type="file" accept="application/pdf,image/jpeg,image/png,image/webp,.pdf,.jpg,.jpeg,.png,.webp" multiple data-guide-input="${invoice.id}">
          </label>
          <div class="attached-guides">${guides.map((guide, index) => `<button type="button" data-guide="${encodeURIComponent(guide.arquivo_url)}">GUIA ${index + 1}</button>`).join("")}</div>
        </div>
        <div class="card-actions"><button class="reject" data-action="recusado" data-id="${invoice.id}">${icon("x")} RECUSAR</button><button class="approve" data-action="aprovado" data-id="${invoice.id}" ${hasGuide ? "" : "disabled"} title="${hasGuide ? "Aprovar fatura" : "Anexe uma guia para aprovar"}">${icon("check")} APROVAR</button></div>
      </div></article>`;
  }).join("");
}

function invoiceSortDate(invoice) { return new Date(`${invoice.data_fatura || "1970-01-01"}T12:00:00`).getTime(); }

function financeCard(invoice) {
  const supplier = suppliers.find(item => item.id === invoice.fornecedor_id)?.nome || "Fornecedor";
  const work = works.find(item => item.id === invoice.obra_id);
  const guides = invoiceGuides.filter(guide => guide.fatura_id === invoice.id);
  const today = new Date().toISOString().slice(0, 10);
  return `<article class="finance-card">
    <div class="finance-card-top"><span>OBRA ${work?.numero || "—"}</span><strong>${euro.format(Number(invoice.valor))}</strong></div>
    <h3>${supplier}</h3><p>${invoice.numero_doc}</p>
    <div class="finance-date"><span>DATA DA FATURA</span><strong>${prettyDate.format(new Date(`${invoice.data_fatura}T12:00:00`))}</strong></div>
    <div class="finance-guides"><span>GUIAS</span><div>${guides.map((guide, index) => `<button type="button" data-guide="${encodeURIComponent(guide.arquivo_url)}">${icon("invoice")} GUIA ${index + 1}</button>`).join("") || "<small>Sem guia disponível</small>"}</div></div>
    <label class="payment-date">DATA DE PAGAMENTO<input type="date" value="${today}" data-payment-date="${invoice.id}"></label>
    <button class="mark-paid" data-mark-paid="${invoice.id}">${icon("check")} MARCAR COMO PAGA</button>
  </article>`;
}

function renderFinance() {
  const unpaid = financeInvoices.filter(invoice => invoice.estado_pagamento === "por_pagar");
  const paid = financeInvoices.filter(invoice => invoice.estado_pagamento === "pago").sort((a, b) => new Date(b.data_pagamento) - new Date(a.data_pagamento));
  const columns = [["imediato", "IMEDIATO"], ["15_dias", "15 DIAS"], ["30_dias", "30 DIAS"]];
  $("#finance-count").textContent = String(unpaid.length).padStart(2, "0");
  $("#finance-board").innerHTML = columns.map(([term, label]) => {
    const rows = unpaid.filter(invoice => invoice.condicao_pagamento === term).sort((a, b) => invoiceSortDate(b) - invoiceSortDate(a));
    return `<div class="finance-column"><div class="finance-column-head"><h2>${label}</h2><span>${rows.length}</span></div>
      <div class="finance-column-list">${rows.length ? rows.map(financeCard).join("") : `<div class="finance-empty">SEM FATURAS</div>`}</div>
    </div>`;
  }).join("");
  $("#paid-count").textContent = `${paid.length} ${paid.length === 1 ? "FATURA" : "FATURAS"}`;
  $("#paid-list").innerHTML = paid.length ? paid.map(invoice => {
    const supplier = suppliers.find(item => item.id === invoice.fornecedor_id)?.nome || "Fornecedor";
    const work = works.find(item => item.id === invoice.obra_id);
    return `<article><div><strong>${supplier}</strong><span>${invoice.numero_doc} · OBRA ${work?.numero || "—"}</span></div><strong>${euro.format(Number(invoice.valor))}</strong><time>PAGA EM ${prettyDate.format(new Date(invoice.data_pagamento))}</time></article>`;
  }).join("") : `<div class="finance-empty">AINDA NÃO EXISTEM FATURAS PAGAS</div>`;
}

async function loadData() {
  if (isSupabaseConfigured && !getSession()) return;
  if (!isSupabaseConfigured) {
    works = demoWorks; suppliers = demoSuppliers; subcontracts = demoSubcontracts;
    invoices = demoInvoices.filter(invoice => invoice.estado_aprovacao === "pendente");
    financeInvoices = demoInvoices.filter(invoice => invoice.estado_aprovacao === "aprovado")
      .map(invoice => ({ ...invoice, condicao_pagamento: invoice.condicao_pagamento || "imediato", estado_pagamento: invoice.estado_pagamento || (invoice.data_pagamento ? "pago" : "por_pagar") }));
    invoiceGuides = [];
  } else {
    const results = await Promise.all([
      supabase("obras?select=id,numero,nome,cliente,morada,tipo,modalidade,situacao,data_inicio,data_fim_prevista,diretor_obra_id&order=numero.desc"),
      supabase("fornecedores?select=id,nome&estado_confianca=neq.inativo&order=nome"),
      supabase("subempreitadas?select=id,obra_id,fornecedor_id,especialidade,valor_adjudicado,estado,tipo_pagamento,fase_id&order=especialidade"),
      supabase("faturas?select=*&estado_aprovacao=eq.pendente&order=criado_em.desc"),
      supabase("faturas?select=*&estado_aprovacao=eq.aprovado&order=data_aprovacao.desc"),
      supabase("faturas_guias?select=id,fatura_id,arquivo_url,nome_arquivo,mime_type,criado_em&order=criado_em.asc"),
    ]);
    const failed = results.find(result => !result.ok);
    if (failed) { toast(`Não foi possível carregar os dados: ${await failed.text()}`, "error"); return; }
    [works, suppliers, subcontracts, invoices, financeInvoices, invoiceGuides] = await Promise.all(results.map(result => result.json()));
    const collaboratorsResult = await supabase("colaboradores?select=id,nome,funcao,nivel&data_saida=is.null&order=nome");
    collaborators = collaboratorsResult.ok ? await collaboratorsResult.json() : [];
  }
  renderSelectors(); renderInvoices(); renderFinance();
  renderWorks();
  renderWorkDirectors();
  await productionDashboard.refreshOverview();
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
  const orderedWorks = [...filtered].sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true, sensitivity: "base" }));
  $("#works-list").innerHTML = orderedWorks.length ? orderedWorks.map(work => `
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

function mondayIso(value) {
  const date = value instanceof Date ? new Date(value) : new Date(`${value}T12:00:00`);
  const day = date.getDay() || 7;
  date.setDate(date.getDate() - day + 1);
  return date.toISOString().slice(0, 10);
}

function addDaysIso(value, days) {
  const date = new Date(`${value}T12:00:00`);
  date.setDate(date.getDate() + days);
  return date.toISOString().slice(0, 10);
}

function personInitials(name = "") {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map(part => part[0]).join("").toUpperCase() || "—";
}

function shortPersonName(name = "") {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  return parts.length > 1 ? `${parts[0]} ${parts.at(-1)}` : (parts[0] || "Colaborador");
}

function compactWorkName(name = "") {
  return name
    .replace(/Quinta da Marinha/gi, "Qt. Marinha")
    .replace(/Av(?:enida)?\.?\s+Bombeiros Voluntários/gi, "Av. Bombeiros")
    .replace(/Tavira Primeline/gi, "Tavira")
    .replace(/Quinta Patino/gi, "Qt. Patino")
    .replace(/\s+/g, " ")
    .trim();
}

function workforceInitials(name = "") {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  const firstName = (parts[0] || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-PT");
  if (firstName === "regivaldo") return "RR";
  return parts.length > 1 ? `${parts[0][0]}${parts.at(-1)[0]}`.toUpperCase() : (parts[0]?.slice(0, 2).toUpperCase() || "—");
}

function workforceRoleClass(person) {
  const roster = {
    manuel: "foreman", paulo: "foreman", regivaldo: "foreman", vitor: "foreman", wanderson: "foreman", william: "foreman", alessandro: "foreman",
    adilson: "mason", bonifacio: "mason", fernando: "mason", helder: "mason", joao_afonso: "mason", mateus: "mason",
    gilson: "helper", joao_borges: "helper", clayton: "helper", genito: "helper", mauro: "helper",
  };
  const normalized = shortPersonName(person?.nome || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-PT");
  const [first, last] = normalized.split(/\s+/);
  const key = first === "joao" ? `joao_${last}` : first;
  return roster[key] || "";
}

function compareWorkforcePeople(a, b) {
  const order = { foreman: 0, mason: 1, helper: 2 };
  return (order[workforceRoleClass(a)] ?? 9) - (order[workforceRoleClass(b)] ?? 9)
    || String(a?.nome || "").localeCompare(String(b?.nome || ""), "pt-PT");
}

function fixedWorkTeam(work) {
  const userById = new Map(teamData.users.map(user => [user.id, user]));
  const fixed = [];
  const director = collaborators.find(person => person.id === work.diretor_obra_id);
  if (director) fixed.push({ label: "DIRETOR", name: director.nome });
  teamData.responsibles.filter(item => item.obra_id === work.id).forEach(item => {
    const role = String(item.papel || "").toLocaleLowerCase("pt-PT");
    const label = role.includes("adjunt") ? "ADJUNTO" : role.includes("prepar") ? "PREPARADOR" : role.includes("diretor") ? "DIRETOR" : "";
    const user = userById.get(item.utilizador_id);
    if (label && user?.nome && !fixed.some(person => person.label === label && person.name === user.nome)) fixed.push({ label, name: user.nome });
  });
  return fixed;
}

function renderWorkforceMagnet(person, allocation = null) {
  const period = allocation?.periodo || "";
  const periodLabel = period === "manha" ? "M" : period === "tarde" ? "T" : "";
  const samePerson = selectedWorkforcePersonId === person.id;
  const selected = samePerson
    && (!allocation || (selectedWorkforceSourceDate === allocation.data && selectedWorkforceSourcePeriod === period));
  return `<button type="button" class="workforce-magnet ${workforceRoleClass(person)} ${samePerson && allocation ? "selected-position" : ""} ${selected ? "selected" : ""}" data-workforce-person="${person.id}" data-source-date="${allocation?.data || ""}" data-source-period="${period}" title="${shortPersonName(person.nome)} · ${period ? period.replace("_", " ") : "Disponível"}"><b>${workforceInitials(person.nome)}</b>${periodLabel ? `<em>${periodLabel}</em>` : ""}</button>`;
}

function effectiveWorkforceForDate(events, date, personById) {
  const result = [];
  const dayEvents = events.filter(item => item.data === date);
  [...new Set(dayEvents.map(item => item.colaborador_id))].forEach(personId => {
    const person = personById.get(personId);
    if (!person || !workforceRoleClass(person)) return;
    const grouped = new Map();
    dayEvents.filter(item => item.colaborador_id === personId).forEach(event => {
      const eventSlots = event.periodo === "dia_inteiro" ? ["manha", "tarde"] : [event.periodo];
      eventSlots.forEach(slot => {
      const entry = grouped.get(event.obra_id) || { person, slots: [], sourceEvents: [] };
      entry.slots.push(slot);
      entry.sourceEvents.push(event);
      grouped.set(event.obra_id, entry);
      });
    });
    grouped.forEach((entry, obraId) => {
      const sameSource = entry.sourceEvents.length === 2 && entry.sourceEvents[0].id === entry.sourceEvents[1].id;
      result.push({
        obra_id: obraId,
        person: entry.person,
        slots: entry.slots,
        allocation: {
          data: sameSource || entry.sourceEvents.length === 1 ? entry.sourceEvents[0].data : "",
          periodo: entry.slots.length === 2 ? "dia_inteiro" : entry.slots[0],
        },
      });
    });
  });
  return result;
}

function workforceStateSignature(items) {
  return items.map(item => `${item.person.id}:${item.slots.slice().sort().join("+")}`).sort().join("|");
}

function isVacation(absence) {
  return String(absence?.tipo || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-PT").includes("ferias");
}

function renderTeam() {
  const workforceSearch = ($("#team-search")?.value || "").trim().toLocaleLowerCase("pt-PT");
  const directorySearch = ($("#team-directory-search")?.value || "").trim().toLocaleLowerCase("pt-PT");
  const workById = new Map(works.map(work => [work.id, work]));
  const personById = new Map(collaborators.map(person => [person.id, person]));
  const operationalPeople = collaborators.filter(person => workforceRoleClass(person)).sort(compareWorkforcePeople);
  const boardWeeks = [-7, 0, 7, 14].map(offset => addDaysIso(selectedTeamWeek, offset));
  const allocations = teamData.allocations.filter(item => personById.has(item.colaborador_id) && workforceRoleClass(personById.get(item.colaborador_id)));
  const currentAllocations = allocations.filter(item => item.data >= selectedTeamWeek && item.data <= addDaysIso(selectedTeamWeek, 6));
  const currentAllocatedIds = new Set(currentAllocations.map(item => item.colaborador_id));
  const currentAbsences = teamData.absences.filter(item => item.data >= selectedTeamWeek && item.data <= addDaysIso(selectedTeamWeek, 6));
  const absentIds = new Set(currentAbsences.map(item => item.colaborador_id));
  const activeWorks = works
    .filter(work => !["concluida", "concluído", "concluido", "cancelada"].includes((work.situacao || "").toLocaleLowerCase("pt-PT")))
    .sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true, sensitivity: "base" }));
  const unallocated = collaborators.filter(person => !currentAllocatedIds.has(person.id));
  const pendingHours = teamData.overtime.reduce((total, item) => total + Number(item.horas || 0), 0);

  $("#team-active-count").textContent = String(collaborators.length).padStart(2, "0");
  $("#team-week").value = selectedTeamWeek;
  $("#team-week-label").textContent = `SEMANA ATUAL · ${prettyDate.format(new Date(`${selectedTeamWeek}T12:00:00`))}`;
  $("#team-kpis").innerHTML = [
    ["COLABORADORES ATIVOS", collaborators.length],
    ["ALOCADOS", currentAllocatedIds.size],
    ["SEM ALOCAÇÃO", unallocated.length],
    ["AUSENTES NA SEMANA", absentIds.size],
  ].map(([label, value]) => `<article><span>${label}</span><strong>${String(value).padStart(2, "0")}</strong></article>`).join("");

  if (teamData.error) {
    $("#team-board").innerHTML = `<div class="work-warning"><strong>DADOS PARCIAIS</strong><span>${teamData.error}</span></div>`;
  } else {
    const weekLabels = ["SEMANA -1", "SEMANA ATUAL", "SEMANA +1", "SEMANA +2"];
    const weekdays = ["SEG", "TER", "QUA", "QUI", "SEX"];
    const boardHead = `<div class="workforce-grid workforce-grid-head"><div>OBRA E RESPONSÁVEIS</div>${boardWeeks.map((week, index) => {
      const vacationPeople = operationalPeople.filter(person => teamData.absences.some(absence => absence.colaborador_id === person.id && isVacation(absence) && absence.data >= week && absence.data <= addDaysIso(week, 4)));
      return `<div><strong>${weekLabels[index]}</strong><span>${prettyDate.format(new Date(`${week}T12:00:00`))} — ${prettyDate.format(new Date(`${addDaysIso(week, 4)}T12:00:00`))}</span><div class="workforce-vacation-box" data-vacation-week="${week}" title="Selecione um íman e clique aqui para marcar férias"><b>FÉRIAS</b><span>${vacationPeople.length ? vacationPeople.map(person => `<i title="${shortPersonName(person.nome)}">${workforceInitials(person.nome)}</i>`).join("") : "—"}</span></div><div class="workforce-day-labels">${weekdays.map((day, dayIndex) => `<b>${day}<small>${addDaysIso(week, dayIndex).slice(8)}</small></b>`).join("")}</div></div>`;
    }).join("")}</div>`;
    const rows = activeWorks.map(work => {
      const workAllocations = allocations.filter(item => item.obra_id === work.id);
      const matchesSearch = workAllocations.some(item => `${personById.get(item.colaborador_id)?.nome || ""}`.toLocaleLowerCase("pt-PT").includes(workforceSearch))
        || `${work.numero || ""} ${work.nome || ""}`.toLocaleLowerCase("pt-PT").includes(workforceSearch);
      if (workforceSearch && !matchesSearch) return "";
      const fixed = fixedWorkTeam(work);
      return `<article class="workforce-grid team-work-row">
        <div class="team-work-name"><span>OBRA ${work.numero || "—"}</span><strong title="${work.nome || "Sem designação"}">${compactWorkName(work.nome || "Sem designação")}</strong><div class="fixed-work-team">${fixed.length ? fixed.map(person => `<small><b>${person.label}</b>${shortPersonName(person.name)}</small>`).join("") : "<small>Responsáveis não definidos</small>"}</div></div>
        ${boardWeeks.map((week, weekIndex) => {
          let previousSignature = "";
          let previousEffective = [];
          return `<div class="workforce-week-cell ${weekIndex === 1 ? "current" : ""}">${weekdays.map((day, dayIndex) => {
            const date = addDaysIso(week, dayIndex);
            const allExact = effectiveWorkforceForDate(allocations, date, personById);
            const exact = allExact.filter(item => item.obra_id === work.id);
            const carried = previousEffective.map(previous => {
              const reassignedSlots = allExact.filter(item => item.person.id === previous.person.id && item.obra_id !== work.id).flatMap(item => item.slots);
              return { ...previous, slots: previous.slots.filter(slot => !reassignedSlots.includes(slot)) };
            }).filter(item => item.slots.length);
            const effective = exact.length ? exact : carried;
            const signature = workforceStateSignature(effective);
            const unchanged = dayIndex > 0 && !exact.length && signature && signature === previousSignature;
            previousSignature = signature;
            previousEffective = effective;
            const content = !effective.length
              ? '<span class="no-workforce" title="Sem equipa nesta obra"></span>'
              : unchanged
                ? '<span class="workforce-arrow" title="Equipa sem alterações">→</span>'
                : effective.sort((a, b) => compareWorkforcePeople(a.person, b.person)).map(item => renderWorkforceMagnet(item.person, item.allocation)).join("");
            return `<div class="workforce-day-cell ${!effective.length ? "empty-day" : unchanged ? "unchanged-day" : "changed-day"}" data-workforce-cell data-work-id="${work.id}" data-date="${date}">${content}</div>`;
          }).join("")}</div>`;
        }).join("")}
      </article>`;
    }).join("");
    $("#team-board").innerHTML = `${boardHead}${rows || `<div class="empty-state"><strong>SEM RESULTADOS</strong><span>Ajuste a pesquisa.</span></div>`}`;
    $("#workforce-roster").innerHTML = `<div class="roster-intro"><strong>ÍMANES DISPONÍVEIS</strong><span>Selecione uma pessoa e depois o dia/obra.</span></div><div class="roster-magnets">${operationalPeople.map(person => renderWorkforceMagnet(person)).join("")}</div><label class="roster-period">PERÍODO<select data-workforce-period><option value="dia_inteiro" ${selectedWorkforcePeriod === "dia_inteiro" ? "selected" : ""}>Dia inteiro</option><option value="manha" ${selectedWorkforcePeriod === "manha" ? "selected" : ""}>Manhã</option><option value="tarde" ${selectedWorkforcePeriod === "tarde" ? "selected" : ""}>Tarde</option></select></label>${selectedWorkforceSourceDate ? '<button class="roster-remove" type="button" data-remove-workforce>RETIRAR ALOCAÇÃO</button>' : ""}`;
  }

  const absences = [...currentAbsences].sort((a, b) => String(a.data).localeCompare(String(b.data)));
  $("#team-absences").innerHTML = absences.length ? absences.map(item => {
    const person = personById.get(item.colaborador_id);
    return `<article class="absence-card"><time>${formatOptionalDate(item.data)}</time><strong>${person?.nome || "Colaborador"}</strong><span>${String(item.tipo || "Ausência").replace(/_/g, " ")}</span></article>`;
  }).join("") : `<div class="empty-state"><strong>SEM AUSÊNCIAS</strong><span>Não existem ausências registadas nesta semana.</span></div>`;

  const contractByPerson = new Map(teamData.contracts.map(item => [item.colaborador_id, item]));
  const hoursByPerson = new Map();
  teamData.overtime.forEach(item => hoursByPerson.set(item.colaborador_id, (hoursByPerson.get(item.colaborador_id) || 0) + Number(item.horas || 0)));
  const visiblePeople = collaborators.filter(person => {
    const work = workById.get(currentAllocations.find(item => item.colaborador_id === person.id)?.obra_id);
    return !directorySearch || `${person.nome} ${person.funcao || ""} ${person.nivel || ""} ${work?.numero || ""} ${work?.nome || ""}`.toLocaleLowerCase("pt-PT").includes(directorySearch);
  });
  $("#team-result-count").textContent = `${visiblePeople.length} COLABORADOR${visiblePeople.length === 1 ? "" : "ES"} · ${pendingHours.toLocaleString("pt-PT")} H EXTRA POR PAGAR`;
  $("#team-directory").innerHTML = visiblePeople.length ? visiblePeople.map(person => {
    const allocation = currentAllocations.find(item => item.colaborador_id === person.id);
    const work = workById.get(allocation?.obra_id);
    const contract = contractByPerson.get(person.id);
    const absence = currentAbsences.find(item => item.colaborador_id === person.id);
    return `<article class="team-directory-row">
      <span class="team-avatar">${personInitials(person.nome)}</span>
      <div class="team-person-main"><strong>${person.nome}</strong><span>${person.funcao || "Função não definida"}${person.nivel ? ` · ${person.nivel}` : ""}</span></div>
      <div><span>SITUAÇÃO SEMANAL</span><strong class="${absence ? "text-alert" : ""}">${absence ? String(absence.tipo).replace(/_/g, " ") : work ? `Obra ${work.numero || "—"}` : "Sem alocação"}</strong></div>
      <div><span>CONTRATO</span><strong>${contract?.tipo_contrato ? String(contract.tipo_contrato).replace(/_/g, " ") : "Não registado"}</strong></div>
      <div><span>HORAS EXTRA</span><strong>${(hoursByPerson.get(person.id) || 0).toLocaleString("pt-PT")} h</strong></div>
    </article>`;
  }).join("") : `<div class="empty-state"><strong>SEM RESULTADOS</strong><span>Ajuste a pesquisa.</span></div>`;

  const endingContracts = teamData.contracts.filter(contract => contract.data_fim_prevista && contract.data_fim_prevista <= addDaysIso(new Date().toISOString().slice(0, 10), 30));
  const missingContracts = collaborators.filter(person => !contractByPerson.has(person.id));
  $("#team-alert-summary").innerHTML = [
    endingContracts.length ? `<article class="attention"><strong>${endingContracts.length}</strong><span>CONTRATO${endingContracts.length === 1 ? "" : "S"} A TERMINAR EM 30 DIAS</span></article>` : "",
    missingContracts.length ? `<article class="pending"><strong>${missingContracts.length}</strong><span>COLABORADOR${missingContracts.length === 1 ? "" : "ES"} SEM CONTRATO REGISTADO</span></article>` : "",
    absentIds.size ? `<article class="info"><strong>${absentIds.size}</strong><span>AUSENTE${absentIds.size === 1 ? "" : "S"} ESTA SEMANA</span></article>` : "",
    pendingHours ? `<article class="attention"><strong>${pendingHours.toLocaleString("pt-PT")} h</strong><span>HORAS EXTRA POR PAGAR</span></article>` : "",
  ].filter(Boolean).join("") || `<article class="ok"><strong>✓</strong><span>SEM ALERTAS DE EQUIPA</span></article>`;

  $("#team-contract-count").textContent = `${teamData.contracts.length} CONTRATOS ATIVOS`;
  $("#team-contracts").innerHTML = teamData.contracts.length ? teamData.contracts.map(contract => {
    const person = personById.get(contract.colaborador_id);
    return `<article class="team-detail-row"><div><strong>${person?.nome || "Colaborador"}</strong><span>${String(contract.tipo_contrato || "Tipo não definido").replace(/_/g, " ")}</span></div><div><span>INÍCIO</span><strong>${formatOptionalDate(contract.data_inicio)}</strong></div><div><span>FIM PREVISTO</span><strong>${formatOptionalDate(contract.data_fim_prevista)}</strong></div><em>${contract.estado || "ativo"}</em></article>`;
  }).join("") : `<div class="empty-state"><strong>SEM CONTRATOS</strong><span>Não existem contratos ativos registados.</span></div>`;

  $("#team-overtime-count").textContent = `${pendingHours.toLocaleString("pt-PT")} H POR PAGAR`;
  $("#team-overtime").innerHTML = teamData.overtime.length ? teamData.overtime.map(item => {
    const person = personById.get(item.colaborador_id);
    const work = workById.get(item.obra_id);
    return `<article class="team-detail-row"><div><strong>${person?.nome || "Colaborador"}</strong><span>${work ? `Obra ${work.numero} · ${work.nome}` : "Sem obra associada"}</span></div><div><span>DATA</span><strong>${formatOptionalDate(item.data)}</strong></div><div><span>HORAS</span><strong>${Number(item.horas || 0).toLocaleString("pt-PT")} h</strong></div><em>POR PAGAR</em></article>`;
  }).join("") : `<div class="empty-state"><strong>SEM HORAS PENDENTES</strong><span>Não existem horas extraordinárias por pagar.</span></div>`;
}

function setWorkforceEditing(enabled) {
  workforceEditing = enabled;
  selectedWorkforcePersonId = "";
  selectedWorkforceSourceDate = "";
  selectedWorkforceSourcePeriod = "";
  $("#workforce-edit-banner").hidden = !enabled;
  $("#workforce-roster").hidden = !enabled;
  $("#remove-workforce-allocation").hidden = true;
  $("#edit-workforce").textContent = enabled ? "A EDITAR…" : "EDITAR QUADRO";
  $("#edit-workforce").classList.toggle("active", enabled);
  $("#workforce-view").classList.toggle("editing", enabled);
  $("#workforce-edit-message").textContent = "Selecione um íman e depois clique no dia e obra de destino.";
  renderTeam();
}

async function saveWorkforceAllocation(personId, date, workId) {
  const person = collaborators.find(item => item.id === personId);
  if (!person) return;
  const period = selectedWorkforcePeriod;
  const vacation = teamData.absences.find(item => item.colaborador_id === personId && item.data === date && isVacation(item));
  if (vacation) {
    toast(`${shortPersonName(person.nome)} está de férias em ${formatOptionalDate(date)} e não pode ser colocado no quadro.`, "error");
    return;
  }
  const dayAllocations = teamData.allocations.filter(item => item.colaborador_id === personId && item.data === date);
  const conflicting = dayAllocations.filter(item => period === "dia_inteiro" || item.periodo === "dia_inteiro" || item.periodo === period);
  const alreadyThere = conflicting.length === 1 && conflicting[0].obra_id === workId && conflicting[0].periodo === period;
  if (alreadyThere) {
    toast("O colaborador já se encontra nessa posição.");
    return;
  }
  if (period !== "dia_inteiro" && dayAllocations.some(item => item.periodo === "dia_inteiro")) {
    toast("Retire primeiro a alocação de dia inteiro antes de dividir o dia.", "error");
    return;
  }
  const currentUser = teamData.users.find(user => user.auth_user_id === session?.user?.id);
  $("#workforce-edit-message").textContent = `A guardar ${shortPersonName(person.nome)}…`;
  let response = null;
  if (period === "dia_inteiro" && dayAllocations.length) {
    response = await supabase(`quadro_pessoal_alocacao?colaborador_id=eq.${encodeURIComponent(personId)}&data=eq.${date}`, { method: "DELETE" });
    if (!response.ok) {
      toast(`Não foi possível alterar o quadro: ${await response.text()}`, "error");
      return;
    }
  } else if (conflicting.length) {
    response = await supabase(`quadro_pessoal_alocacao?colaborador_id=eq.${encodeURIComponent(personId)}&data=eq.${date}&periodo=eq.${period}`, {
      method: "PATCH",
      body: JSON.stringify({ obra_id: workId, criado_por: currentUser?.id || null }),
    });
    if (response.ok) {
      selectedWorkforceSourceDate = "";
      selectedWorkforceSourcePeriod = "";
      await loadTeamData(true);
      $("#remove-workforce-allocation").hidden = true;
      $("#workforce-edit-message").textContent = `${shortPersonName(person.nome)} continua selecionado. Clique nos próximos dias/obras.`;
      toast("Alocação adicionada. O íman continua selecionado.");
      return;
    }
  }
  if (!response || response.ok) {
    response = await supabase("quadro_pessoal_alocacao", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify({ colaborador_id: personId, obra_id: workId, semana_inicio: mondayIso(date), data: date, periodo: period, criado_por: currentUser?.id || null }),
    });
  }
  if (!response.ok) {
    toast(`Não foi possível alterar o quadro: ${await response.text()}`, "error");
    $("#workforce-edit-message").textContent = "A alteração falhou. Confirme as permissões e tente novamente.";
    return;
  }
  selectedWorkforceSourceDate = "";
  selectedWorkforceSourcePeriod = "";
  await loadTeamData(true);
  $("#remove-workforce-allocation").hidden = true;
  $("#workforce-edit-message").textContent = `${shortPersonName(person.nome)} continua selecionado. Clique nos próximos dias/obras.`;
  toast("Alocação adicionada. O íman continua selecionado.");
}

async function removeWorkforceAllocation() {
  if (!selectedWorkforcePersonId || !selectedWorkforceSourceDate || !selectedWorkforceSourcePeriod) return;
  const response = await supabase(`quadro_pessoal_alocacao?colaborador_id=eq.${encodeURIComponent(selectedWorkforcePersonId)}&data=eq.${selectedWorkforceSourceDate}&periodo=eq.${selectedWorkforceSourcePeriod}`, { method: "DELETE" });
  if (!response.ok) {
    toast(`Não foi possível retirar a alocação: ${await response.text()}`, "error");
  } else {
    selectedWorkforceSourceDate = "";
    selectedWorkforceSourcePeriod = "";
    $("#remove-workforce-allocation").hidden = true;
    await loadTeamData(true);
    toast("Alocação retirada.");
  }
}

async function saveVacationWeek(personId, week) {
  const person = collaborators.find(item => item.id === personId);
  if (!person) return;
  const dates = Array.from({ length: 5 }, (_, index) => addDaysIso(week, index));
  const existing = new Set(teamData.absences.filter(item => item.colaborador_id === personId && isVacation(item)).map(item => item.data));
  const missing = dates.filter(date => !existing.has(date));
  if (!missing.length) {
    toast(`${shortPersonName(person.nome)} já está de férias nessa semana.`);
    return;
  }
  const response = await supabase("ausencias", {
    method: "POST",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify(missing.map(data => ({ colaborador_id: personId, data, tipo: "ferias" }))),
  });
  if (!response.ok) {
    toast(`Não foi possível marcar as férias: ${await response.text()}`, "error");
    return;
  }
  await loadTeamData(true);
  $("#workforce-edit-message").textContent = `${shortPersonName(person.nome)} marcado de férias. O íman continua selecionado.`;
  toast("Férias registadas de segunda a sexta-feira.");
}

async function loadTeamData(force = false) {
  if (!force && teamData.loadedWeek === selectedTeamWeek) return renderTeam();
  teamData = { allocations: [], absences: [], contracts: [], overtime: [], responsibles: [], users: [], loadedWeek: selectedTeamWeek, error: "" };
  $("#team-board").innerHTML = `<div class="empty-state">A CARREGAR O QUADRO…</div>`;
  if (!isSupabaseConfigured) return renderTeam();
  const boardStart = addDaysIso(selectedTeamWeek, -7);
  const boardEnd = addDaysIso(selectedTeamWeek, 20);
  const results = await Promise.all([
    supabase(`quadro_pessoal_alocacao?select=id,colaborador_id,obra_id,semana_inicio,data,periodo&semana_inicio=gte.${boardStart}&semana_inicio=lte.${addDaysIso(selectedTeamWeek, 14)}&order=data`),
    supabase(`ausencias?select=id,colaborador_id,data,tipo&data=gte.${boardStart}&data=lte.${boardEnd}&order=data`),
    supabase("colaboradores_contratos?select=id,colaborador_id,tipo_contrato,data_inicio,data_fim_prevista,estado&estado=eq.ativo"),
    supabase("horas_extraordinarias?select=id,colaborador_id,obra_id,data,horas,estado_pagamento&estado_pagamento=eq.por_pagar"),
    supabase("obra_responsaveis?select=obra_id,utilizador_id,papel"),
    supabase("utilizadores?select=id,nome,funcao,auth_user_id"),
  ]);
  const names = ["alocações", "ausências", "contratos", "horas extraordinárias", "responsáveis de obra", "utilizadores"];
  const payloads = await Promise.all(results.map(async (result, index) => result.ok ? result.json() : { failed: names[index], detail: await result.text() }));
  const failures = payloads.filter(payload => payload?.failed);
  [teamData.allocations, teamData.absences, teamData.contracts, teamData.overtime, teamData.responsibles, teamData.users] = payloads.map(payload => Array.isArray(payload) ? payload : []);
  const essentialFailures = failures.filter(item => ["alocações", "ausências"].includes(item.failed));
  if (essentialFailures.length) teamData.error = `Não foi possível ler ${essentialFailures.map(item => item.failed).join(", ")}. Confirme as políticas RLS do módulo Equipa.`;
  renderTeam();
}

function selectCurrentContract(contracts = []) {
  return [...contracts].sort((a, b) => {
    const completeness = contract => ["venda_contratual_inicial", "venda_contratual_efetiva", "valor_adiantamento"]
      .reduce((score, field) => score + (contract?.[field] != null ? 1 : 0), 0);
    return completeness(b) - completeness(a)
      || Number(b.venda_contratual_inicial || 0) - Number(a.venda_contratual_inicial || 0)
      || Number(b.venda_contratual_efetiva || 0) - Number(a.venda_contratual_efetiva || 0);
  })[0] || null;
}

function measurementBilledValue(measurement) {
  return Number(measurement?.valor_a_faturar || 0);
}

function totalClientBilling(contract, measurements = []) {
  return Number(contract?.valor_adiantamento || 0)
    + measurements.reduce((total, measurement) => total + measurementBilledValue(measurement), 0);
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
  workDetails = { contract: null, phases: [], measurements: [], payments: [], consultations: [], billings: [], billingLinks: [], documents: [], error: "", procurementError: "", billingError: "" };
  renderWorks();
  const work = works.find(item => item.id === workId);
  $("#work-detail").innerHTML = `<div class="empty-state">A CARREGAR DADOS DA OBRA…</div>`;
  if (!isSupabaseConfigured) {
    workDetails = {
      contract: { venda_contratual_inicial: 553619.19, venda_contratual_efetiva: 472179.26, custo_direto_efetivo: 355023.64, valor_adiantamento: 110723.84, data_assinatura: "2026-02-11" },
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
      billings: [],
      billingLinks: [],
      documents: [],
      error: "",
      procurementError: "",
      billingError: "",
    };
    renderWorkDetail(work);
    return;
  }
  const [contractResult, phasesResult, measurementsResult] = await Promise.all([
    supabase(`contratos?select=id,obra_id,venda_contratual_inicial,custo_direto_inicial,venda_contratual_efetiva,custo_direto_efetivo,valor_adiantamento,percentual_retencao_garantia,data_assinatura,atualizado_em&obra_id=eq.${encodeURIComponent(workId)}`),
    supabase(`fases?select=*&obra_id=eq.${encodeURIComponent(workId)}`),
    supabase(`autos_medicao?select=id,obra_id,mes_referencia,numero_auto,tipo,data_medicao,estado,valor_bruto_medido,valor_retencao_garantia,valor_deduzido_adiantamento,valor_a_faturar&obra_id=eq.${encodeURIComponent(workId)}&order=mes_referencia.desc`),
  ]);
  const detailErrors = [];
  if (contractResult.ok) workDetails.contract = selectCurrentContract(await contractResult.json());
  else detailErrors.push((await contractResult.json().catch(() => ({}))).message || "Contrato indisponível");
  if (phasesResult.ok) workDetails.phases = await phasesResult.json();
  else detailErrors.push((await phasesResult.json().catch(() => ({}))).message || "Fases indisponíveis");
  if (measurementsResult.ok) workDetails.measurements = await measurementsResult.json();
  else detailErrors.push((await measurementsResult.json().catch(() => ({}))).message || "Autos de medição indisponíveis");
  workDetails.error = detailErrors.join(" · ");
  if (workDetails.measurements.length) {
    const measurementIds = workDetails.measurements.map(item => item.id);
    const billingsResult = await supabase(`faturacao?select=*&obra_id=eq.${encodeURIComponent(workId)}&order=data_emissao_fatura.desc`);
    if (billingsResult.ok) {
      workDetails.billings = await billingsResult.json();
      const billingIds = workDetails.billings.map(item => item.id);
      const [linksResult, documentsResult] = await Promise.all([
        supabase(`faturacao_autos_medicao?select=*&auto_medicao_id=in.(${measurementIds.map(encodeURIComponent).join(",")})`),
        supabase(`documentos?select=*&entidade_id=in.(${[...measurementIds, ...billingIds].map(encodeURIComponent).join(",")})`),
      ]);
      if (linksResult.ok) workDetails.billingLinks = await linksResult.json();
      else workDetails.billingError = "A relação entre autos e faturas ainda não está disponível.";
      if (documentsResult.ok) workDetails.documents = await documentsResult.json();
      else workDetails.billingError ||= "Não foi possível consultar os PDFs dos autos e faturas.";
    } else {
      workDetails.billingError = "Não foi possível consultar a faturação desta obra.";
    }
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
  const measuredTotal = totalClientBilling(contract, workDetails.measurements);
  const progress = workProgress(work);
  const sale = Number(contract?.venda_contratual_efetiva || contract?.venda_contratual_inicial || 0);
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
          <div><dt>Venda inicial</dt><dd>${contract?.venda_contratual_inicial != null ? euro.format(Number(contract.venda_contratual_inicial)) : "—"}</dd></div>
          <div><dt>Venda efetiva</dt><dd>${contract?.venda_contratual_efetiva != null ? euro.format(Number(contract.venda_contratual_efetiva)) : "—"}</dd></div>
          <div><dt>Adiantamento</dt><dd>${contract?.valor_adiantamento != null ? euro.format(Number(contract.valor_adiantamento)) : "—"}</dd></div>
          <div><dt>Assinatura</dt><dd>${formatOptionalDate(contract?.data_assinatura)}</dd></div>
        </dl>
      </section>
      <section><div class="detail-section-title"><span>FASES</span><small>${workDetails.phases.length}</small></div>
        <div class="phase-tags">${workDetails.phases.length ? workDetails.phases.map(phase => `<span>${phase.codigo || phase.numero || "—"}<small>${phase.descricao || ""}</small></span>`).join("") : "<em>Sem fases disponíveis</em>"}</div>
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

function measurementStatusLabel(status) {
  return {
    rascunho: "Rascunho",
    enviado_cliente: "Auto enviado",
    aprovado_cliente: "Auto aprovado",
    recusado_cliente: "Auto recusado",
  }[status] || workSituationLabel(status);
}

function documentFor(entityId, type) {
  return workDetails.documents.find(document => document.entidade_id === entityId && document.tipo_documento === type);
}

function billingForMeasurement(measurementId) {
  const link = workDetails.billingLinks.find(item => item.auto_medicao_id === measurementId);
  return link ? workDetails.billings.find(item => item.id === link.faturacao_id) : null;
}

function renderMeasurementsTab(work) {
  const rows = workDetails.measurements;
  const measured = totalClientBilling(workDetails.contract, rows);
  const invoiced = workDetails.billings.reduce((sum, item) => sum + Number(item.valor || 0), 0);
  const received = workDetails.billings.reduce((sum, item) => sum + Number(item.valor_recebido || 0), 0);
  return `
    ${workDetails.billingError ? `<div class="work-warning"><strong>DADOS PARCIAIS</strong><span>${workDetails.billingError} Execute a migração do fluxo de autos e faturação.</span></div>` : ""}
    <div class="measurement-toolbar">
      <div class="measurement-kpis">
        <div><span>FATURADO ACUMULADO</span><strong>${euro.format(measured)}</strong></div>
        <div><span>FATURADO</span><strong>${euro.format(invoiced)}</strong></div>
        <div><span>RECEBIDO</span><strong>${euro.format(received)}</strong></div>
      </div>
      <button class="outline-action" data-new-measurement type="button">＋ NOVO AUTO</button>
    </div>
    <div class="measurements-list">
      ${rows.length ? rows.map(item => {
        const billing = billingForMeasurement(item.id);
        const autoPdf = documentFor(item.id, "auto_medicao_pdf");
        const invoicePdf = billing && documentFor(billing.id, "fatura_cliente_pdf");
        const paid = billing && Number(billing.valor_recebido || 0) >= Number(billing.valor || 0);
        return `<article class="measurement-card">
          <div class="measurement-head">
            <div><span>${item.tipo || "contratual"}</span><strong>Auto ${item.numero_auto || "sem número"}</strong><small>${prettyDate.format(new Date(`${item.mes_referencia}T12:00:00`))}</small></div>
            <span class="measurement-state ${item.estado}">${measurementStatusLabel(item.estado)}</span>
          </div>
          <div class="measurement-values">
            <div><span>BRUTO</span><strong>${euro.format(Number(item.valor_bruto_medido || 0))}</strong></div>
            <div><span>RETENÇÃO</span><strong>${euro.format(Number(item.valor_retencao_garantia || 0))}</strong></div>
            <div><span>ADIANTAMENTO</span><strong>${euro.format(Number(item.valor_deduzido_adiantamento || 0))}</strong></div>
            <div><span>A FATURAR</span><strong>${euro.format(Number(item.valor_a_faturar || 0))}</strong></div>
          </div>
          <div class="workflow-line">
            <span class="${item.estado !== "rascunho" ? "done" : ""}">AUTO ENVIADO</span>
            <i></i><span class="${["aprovado_cliente"].includes(item.estado) ? "done" : ""}">AUTO APROVADO</span>
            <i></i><span class="${billing ? "done" : ""}">FATURA EMITIDA</span>
            <i></i><span class="${paid ? "done" : ""}">PAGO</span>
          </div>
          ${billing ? `<div class="billing-summary"><span>FATURA ${billing.numero_fatura}</span><strong>${euro.format(Number(billing.valor))}</strong><small>${paid ? `Recebida em ${formatOptionalDate(billing.data_recebimento)}` : "Pagamento pendente"}</small></div>` : ""}
          <div class="measurement-actions">
            ${autoPdf ? `<button data-workflow-pdf="${encodeURIComponent(autoPdf.url_arquivo)}">VER AUTO PDF</button>` : ""}
            ${invoicePdf ? `<button data-workflow-pdf="${encodeURIComponent(invoicePdf.url_arquivo)}">VER FATURA PDF</button>` : ""}
            ${item.estado === "rascunho" ? `<button data-measure-action="enviado_cliente" data-id="${item.id}">MARCAR ENVIADO</button>` : ""}
            ${item.estado === "enviado_cliente" ? `<button data-measure-action="recusado_cliente" data-id="${item.id}">RECUSAR</button><button data-measure-action="aprovado_cliente" data-id="${item.id}">APROVAR</button>` : ""}
            ${item.estado === "aprovado_cliente" && !billing ? `<button class="dark" data-new-billing="${item.id}">EMITIR FATURA</button>` : ""}
            ${billing && !paid ? `<button class="dark" data-mark-paid="${billing.id}">MARCAR PAGO</button>` : ""}
          </div>
        </article>`;
      }).join("") : `<div class="empty-state"><strong>SEM AUTOS DE MEDIÇÃO</strong><span>Crie o primeiro auto desta obra.</span></div>`}
    </div>`;
}

function renderWorkTab(work) {
  if (selectedWorkTab === "subcontracts") return renderSubcontractsTab(work);
  if (selectedWorkTab === "measurements") return renderMeasurementsTab(work);
  if (selectedWorkTab === "phases") return `<div class="empty-state"><strong>FASES</strong><span>Este separador será desenvolvido numa próxima etapa.</span></div>`;
  return renderWorkSummary(work);
}

function renderWorkDetail(work) {
  if (!work) return;
  $("#work-detail").innerHTML = `
    <div class="work-detail-head">
      <div><p class="eyebrow">OBRA ${work.numero || "—"}</p><h2>${work.nome || "Sem designação"}</h2><span>${work.cliente || "Cliente não indicado"}</span></div>
      <div class="work-detail-actions"><button type="button" data-open-meeting="${work.id}">REUNIÃO SEMANAL →</button><span class="work-status ${work.situacao || "indefinida"}">${workSituationLabel(work.situacao)}</span></div>
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
  $("#overview-view").hidden = view !== "overview";
  $("#meeting-view").hidden = view !== "meeting";
  $("#invoice-view").hidden = view !== "invoices";
  $("#works-view").hidden = view !== "works";
  $("#finance-view").hidden = view !== "finance";
  $("#team-view").hidden = view !== "team";
  $("#workforce-view").hidden = view !== "workforce";
  $("#placeholder-view").hidden = ["overview", "meeting", "invoices", "works", "finance", "team", "workforce"].includes(view);
  if (!["overview", "meeting", "invoices", "works", "finance", "team", "workforce"].includes(view)) {
    const labels = { documents: "DOCUMENTOS" };
    $("#placeholder-title").textContent = labels[view] || "MÓDULO EM PREPARAÇÃO";
  }
  if (view === "works") {
    renderWorks();
    if (!selectedWorkId && works[0]) loadWorkDetails(works[0].id);
  }
  if (view === "finance") renderFinance();
  if (view === "team" || view === "workforce") loadTeamData();
  if (view === "overview") productionDashboard.refreshOverview();
  closeSidebar();
}

function openSidebar() {
  $(".sidebar").classList.add("open");
  $("#scrim").classList.add("open");
}

function closeSidebar() {
  $(".sidebar").classList.remove("open");
  $("#scrim").classList.remove("open");
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
$("#team-search").addEventListener("input", renderTeam);
$("#team-directory-search").addEventListener("input", renderTeam);
$("#edit-workforce").addEventListener("click", () => setWorkforceEditing(!workforceEditing));
$("#finish-workforce-edit").addEventListener("click", () => setWorkforceEditing(false));
$("#remove-workforce-allocation").addEventListener("click", removeWorkforceAllocation);
$("#team-board").addEventListener("click", async event => {
  if (!workforceEditing) return;
  const vacationBox = event.target.closest("[data-vacation-week]");
  if (vacationBox) {
    if (!selectedWorkforcePersonId) {
      toast("Selecione primeiro um íman.", "error");
      return;
    }
    await saveVacationWeek(selectedWorkforcePersonId, vacationBox.dataset.vacationWeek);
    return;
  }
  const magnet = event.target.closest("[data-workforce-person]");
  if (magnet) {
    selectedWorkforcePersonId = magnet.dataset.workforcePerson;
    selectedWorkforceSourceDate = magnet.dataset.sourceDate || "";
    selectedWorkforceSourcePeriod = magnet.dataset.sourcePeriod || "";
    $("#remove-workforce-allocation").hidden = !selectedWorkforceSourceDate;
    const person = collaborators.find(item => item.id === selectedWorkforcePersonId);
    $("#workforce-edit-message").textContent = `${shortPersonName(person?.nome || "")} selecionado. Clique no dia e obra de destino.`;
    renderTeam();
    return;
  }
  const cell = event.target.closest("[data-workforce-cell]");
  if (!cell || !selectedWorkforcePersonId) {
    if (cell) toast("Selecione primeiro um íman.", "error");
    return;
  }
  cell.classList.add("saving");
  await saveWorkforceAllocation(selectedWorkforcePersonId, cell.dataset.date, cell.dataset.workId);
});
$("#workforce-roster").addEventListener("click", event => {
  if (!workforceEditing) return;
  if (event.target.closest("[data-remove-workforce]")) {
    removeWorkforceAllocation();
    return;
  }
  const magnet = event.target.closest("[data-workforce-person]");
  if (!magnet) return;
  selectedWorkforcePersonId = magnet.dataset.workforcePerson;
  selectedWorkforceSourceDate = "";
  selectedWorkforceSourcePeriod = "";
  $("#remove-workforce-allocation").hidden = true;
  const person = collaborators.find(item => item.id === selectedWorkforcePersonId);
  $("#workforce-edit-message").textContent = `${shortPersonName(person?.nome || "")} selecionado. Escolha o período e clique no dia/obra.`;
  renderTeam();
});
$("#workforce-roster").addEventListener("change", event => {
  const select = event.target.closest("[data-workforce-period]");
  if (select) selectedWorkforcePeriod = select.value;
});
document.querySelectorAll("[data-team-tab]").forEach(button => button.addEventListener("click", () => {
  selectedTeamTab = button.dataset.teamTab;
  document.querySelectorAll("[data-team-tab]").forEach(item => item.classList.toggle("active", item.dataset.teamTab === selectedTeamTab));
  document.querySelectorAll("[data-team-panel]").forEach(panel => { panel.hidden = panel.dataset.teamPanel !== selectedTeamTab; });
}));
$("#team-week").addEventListener("change", event => {
  selectedTeamWeek = mondayIso(event.target.value);
  loadTeamData(true);
});
$("#team-previous-week").addEventListener("click", () => {
  selectedTeamWeek = addDaysIso(selectedTeamWeek, -7);
  loadTeamData(true);
});
$("#team-next-week").addEventListener("click", () => {
  selectedTeamWeek = addDaysIso(selectedTeamWeek, 7);
  loadTeamData(true);
});
$("#team-current-week").addEventListener("click", () => {
  selectedTeamWeek = mondayIso(new Date());
  loadTeamData(true);
});
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
function closeWorkflowDialog() {
  $("#workflow-dialog").hidden = true;
  $("#workflow-dialog-content").innerHTML = "";
}

function openNewMeasurementDialog() {
  $("#workflow-dialog-title").textContent = "NOVO AUTO DE MEDIÇÃO";
  $("#workflow-dialog-content").innerHTML = `<form id="measurement-form">
    <div class="form-row"><label>N.º DO AUTO<input name="numero_auto" required></label><label>MÊS DE REFERÊNCIA<input name="mes_referencia" type="date" required></label></div>
    <label>TIPO<div class="select-wrap"><select name="tipo"><option value="contratual">Contratual</option><option value="adicional">Adicional</option></select><b>⌄</b></div></label>
    <div class="form-row"><label>DATA DE MEDIÇÃO<input name="data_medicao" type="date"></label><label>VALOR BRUTO<input name="valor_bruto_medido" type="number" min="0" step="0.01" required></label></div>
    <div class="form-row"><label>RETENÇÃO DE GARANTIA<input name="valor_retencao_garantia" type="number" min="0" step="0.01" value="0"></label><label>DEDUÇÃO DO ADIANTAMENTO<input name="valor_deduzido_adiantamento" type="number" min="0" step="0.01" value="0"></label></div>
    <label>PDF DO AUTO (OPCIONAL)<input name="pdf" type="file" accept="application/pdf,.pdf"></label>
    <p class="form-error"></p><div class="dialog-actions"><button class="outline-action" type="button" data-close-workflow>CANCELAR</button><button class="primary-button" type="submit">CRIAR AUTO <span>→</span></button></div>
  </form>`;
  $("#workflow-dialog").hidden = false;
  $("#measurement-form").addEventListener("submit", submitMeasurement);
}

async function submitMeasurement(event) {
  event.preventDefault();
  const formElement = event.currentTarget;
  const fields = Object.fromEntries(new FormData(formElement));
  const errorElement = formElement.querySelector(".form-error");
  const button = formElement.querySelector('button[type="submit"]');
  const advance = Number(fields.valor_deduzido_adiantamento || 0);
  if (fields.tipo === "adicional" && advance > 0) {
    errorElement.textContent = "A dedução do adiantamento só pode ser aplicada a autos contratuais.";
    return;
  }
  const payload = {
    obra_id: selectedWorkId, mes_referencia: fields.mes_referencia,
    numero_auto: fields.numero_auto.trim(), tipo: fields.tipo,
    data_medicao: fields.data_medicao || null, estado: "rascunho",
    valor_bruto_medido: Number(fields.valor_bruto_medido),
    valor_retencao_garantia: Number(fields.valor_retencao_garantia || 0),
    valor_deduzido_adiantamento: advance,
  };
  button.disabled = true;
  try {
    let inserted = { ...payload, id: crypto.randomUUID(), valor_a_faturar: payload.valor_bruto_medido - payload.valor_retencao_garantia - advance };
    if (isSupabaseConfigured) {
      const response = await supabase("autos_medicao?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
      if (!response.ok) throw new Error((await response.json().catch(() => ({}))).message || "Não foi possível criar o auto.");
      inserted = (await response.json())[0];
      if (fields.pdf?.size) {
        const path = await uploadWorkflowPdf(fields.pdf, selectedWorkId, "autos-medicao");
        const documentResponse = await supabase("documentos", {
          method: "POST", body: JSON.stringify({ empresa_id: PRIMELINE_COMPANY_ID, entidade_tipo: "auto_medicao", entidade_id: inserted.id, tipo_documento: "auto_medicao_pdf", nome_arquivo: fields.pdf.name, url_arquivo: path, data_emissao: fields.data_medicao || null }),
        });
        if (!documentResponse.ok) throw new Error("O auto foi criado, mas não foi possível associar o PDF.");
      }
    }
    workDetails.measurements.unshift(inserted);
    closeWorkflowDialog(); renderWorkDetail(works.find(item => item.id === selectedWorkId));
    toast("Auto de medição criado em rascunho.");
  } catch (error) { errorElement.textContent = error.message; }
  finally { button.disabled = false; }
}

function openBillingDialog(measurementId) {
  const eligible = workDetails.measurements.filter(item => item.estado === "aprovado_cliente" && !billingForMeasurement(item.id));
  $("#workflow-dialog-title").textContent = "EMITIR FATURA";
  $("#workflow-dialog-content").innerHTML = `<form id="billing-form">
    <div class="form-row"><label>N.º DA FATURA<input name="numero_fatura" required></label><label>DATA DE EMISSÃO<input name="data_emissao_fatura" type="date" required value="${new Date().toISOString().slice(0, 10)}"></label></div>
    <fieldset class="measurement-picker"><legend>AUTOS INCLUÍDOS</legend>${eligible.map(item => `<label><input type="checkbox" name="autos" value="${item.id}" ${item.id === measurementId ? "checked" : ""}><span>${item.numero_auto || "Sem número"} · ${item.tipo} · ${euro.format(Number(item.valor_a_faturar || 0))}</span></label>`).join("")}</fieldset>
    <label>VALOR DA FATURA<input name="valor" type="number" min="0.01" step="0.01" required value="${Number(eligible.find(item => item.id === measurementId)?.valor_a_faturar || 0).toFixed(2)}"></label>
    <label>PDF DA FATURA (OPCIONAL)<input name="pdf" type="file" accept="application/pdf,.pdf"></label>
    <p class="form-error"></p><div class="dialog-actions"><button class="outline-action" type="button" data-close-workflow>CANCELAR</button><button class="primary-button" type="submit">REGISTAR FATURA <span>→</span></button></div>
  </form>`;
  $("#workflow-dialog").hidden = false;
  $("#billing-form").addEventListener("submit", submitBilling);
}

async function submitBilling(event) {
  event.preventDefault();
  const formElement = event.currentTarget;
  const data = new FormData(formElement);
  const autoIds = data.getAll("autos");
  const errorElement = formElement.querySelector(".form-error");
  const button = formElement.querySelector('button[type="submit"]');
  if (!autoIds.length) { errorElement.textContent = "Selecione pelo menos um auto aprovado."; return; }
  const selected = workDetails.measurements.filter(item => autoIds.includes(item.id));
  const payload = {
    obra_id: selectedWorkId, contrato_id: workDetails.contract?.id || null,
    numero_fatura: String(data.get("numero_fatura")).trim(),
    descricao_auto: selected.map(item => item.numero_auto).filter(Boolean).join(" + "),
    data_emissao_auto: selected.map(item => item.data_medicao).filter(Boolean).sort().at(-1) || null,
    data_emissao_fatura: data.get("data_emissao_fatura"), valor: Number(data.get("valor")), estado: "emitida",
  };
  button.disabled = true;
  try {
    let billing = { ...payload, id: crypto.randomUUID(), valor_recebido: null };
    if (isSupabaseConfigured) {
      const response = await supabase("faturacao?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
      if (!response.ok) throw new Error((await response.json().catch(() => ({}))).message || "Não foi possível registar a fatura.");
      billing = (await response.json())[0];
      const linksResponse = await supabase("faturacao_autos_medicao", { method: "POST", body: JSON.stringify(autoIds.map(autoId => ({ faturacao_id: billing.id, auto_medicao_id: autoId }))) });
      if (!linksResponse.ok) throw new Error("A fatura foi criada, mas não foi possível associar os autos.");
      const pdf = data.get("pdf");
      if (pdf?.size) {
        const path = await uploadWorkflowPdf(pdf, selectedWorkId, "faturacao-clientes");
        const documentResponse = await supabase("documentos", { method: "POST", body: JSON.stringify({ empresa_id: PRIMELINE_COMPANY_ID, entidade_tipo: "faturacao", entidade_id: billing.id, tipo_documento: "fatura_cliente_pdf", nome_arquivo: pdf.name, url_arquivo: path, data_emissao: payload.data_emissao_fatura }) });
        if (!documentResponse.ok) throw new Error("A fatura foi criada, mas não foi possível associar o PDF.");
      }
    }
    workDetails.billings.unshift(billing);
    workDetails.billingLinks.push(...autoIds.map(autoId => ({ faturacao_id: billing.id, auto_medicao_id: autoId })));
    closeWorkflowDialog(); renderWorkDetail(works.find(item => item.id === selectedWorkId));
    toast("Fatura emitida e associada aos autos.");
  } catch (error) { errorElement.textContent = error.message; }
  finally { button.disabled = false; }
}

function openPaymentDialog(billingId) {
  const billing = workDetails.billings.find(item => item.id === billingId);
  $("#workflow-dialog-title").textContent = "REGISTAR PAGAMENTO";
  $("#workflow-dialog-content").innerHTML = `<form id="payment-form">
    <p class="dialog-copy">Fatura <strong>${billing.numero_fatura}</strong> · ${euro.format(Number(billing.valor))}</p>
    <div class="form-row"><label>DATA DE RECEBIMENTO<input name="data_recebimento" type="date" required value="${new Date().toISOString().slice(0, 10)}"></label><label>VALOR RECEBIDO<input name="valor_recebido" type="number" min="0.01" step="0.01" required value="${Number(billing.valor).toFixed(2)}"></label></div>
    <p class="form-error"></p><div class="dialog-actions"><button class="outline-action" type="button" data-close-workflow>CANCELAR</button><button class="primary-button" type="submit">CONFIRMAR PAGAMENTO <span>→</span></button></div>
  </form>`;
  $("#workflow-dialog").hidden = false;
  $("#payment-form").addEventListener("submit", async event => {
    event.preventDefault();
    const formElement = event.currentTarget;
    const data = Object.fromEntries(new FormData(formElement));
    const button = formElement.querySelector('button[type="submit"]');
    button.disabled = true;
    try {
      if (isSupabaseConfigured) {
        const response = await supabase(`faturacao?id=eq.${billingId}`, { method: "PATCH", body: JSON.stringify({ data_recebimento: data.data_recebimento, valor_recebido: Number(data.valor_recebido) }) });
        if (!response.ok) throw new Error((await response.json().catch(() => ({}))).message || "Não foi possível registar o pagamento.");
      }
      billing.data_recebimento = data.data_recebimento; billing.valor_recebido = Number(data.valor_recebido);
      closeWorkflowDialog(); renderWorkDetail(works.find(item => item.id === selectedWorkId)); toast("Pagamento registado.");
    } catch (error) { formElement.querySelector(".form-error").textContent = error.message; }
    finally { button.disabled = false; }
  });
}

$("#close-workflow-dialog").addEventListener("click", closeWorkflowDialog);
$("#workflow-dialog").addEventListener("click", event => { if (event.target === $("#workflow-dialog") || event.target.closest("[data-close-workflow]")) closeWorkflowDialog(); });
$("#work-detail").addEventListener("click", async event => {
  const meetingButton = event.target.closest("[data-open-meeting]");
  if (meetingButton) return productionDashboard.openMeeting(meetingButton.dataset.openMeeting, "works");
  const tabButton = event.target.closest("[data-work-tab]");
  if (tabButton) {
    selectedWorkTab = tabButton.dataset.workTab;
    renderWorkDetail(works.find(item => item.id === selectedWorkId));
    return;
  }
  if (event.target.closest("[data-new-measurement]")) return openNewMeasurementDialog();
  const billingButton = event.target.closest("[data-new-billing]");
  if (billingButton) return openBillingDialog(billingButton.dataset.newBilling);
  const paidButton = event.target.closest("[data-mark-paid]");
  if (paidButton) return openPaymentDialog(paidButton.dataset.markPaid);
  const pdfButton = event.target.closest("[data-workflow-pdf]");
  if (pdfButton) {
    try {
      const blob = await downloadInvoicePdf(decodeURIComponent(pdfButton.dataset.workflowPdf));
      openedPdfUrl = URL.createObjectURL(blob); openPdfModal(openedPdfUrl, "DOCUMENTO");
    } catch (error) { toast(error.message, "error"); }
    return;
  }
  const actionButton = event.target.closest("[data-measure-action]");
  if (actionButton) {
    const measurement = workDetails.measurements.find(item => item.id === actionButton.dataset.id);
    const state = actionButton.dataset.measureAction;
    const today = new Date().toISOString().slice(0, 10);
    const update = { estado: state };
    if (state === "enviado_cliente") update.data_envio_cliente = today;
    if (state === "aprovado_cliente") update.data_aprovacao_cliente = today;
    if (isSupabaseConfigured) {
      const response = await supabase(`autos_medicao?id=eq.${measurement.id}`, { method: "PATCH", body: JSON.stringify(update) });
      if (!response.ok) return toast(`Não foi possível atualizar o auto: ${await response.text()}`, "error");
    }
    Object.assign(measurement, update); renderWorkDetail(works.find(item => item.id === selectedWorkId));
    toast(`Estado atualizado para ${measurementStatusLabel(state)}.`);
  }
});
$("#menu").addEventListener("click", openSidebar);
$("#scrim").addEventListener("click", closeSidebar);
function syncDisplayToggles() {
  const dark = document.documentElement.dataset.theme === "dark";
  const tv = document.documentElement.classList.contains("tv-mode");
  const sidebarCollapsed = document.documentElement.classList.contains("sidebar-collapsed");
  $("#theme-toggle").textContent = dark ? "☀ CLARO" : "☾ ESCURO";
  $("#theme-toggle").setAttribute("aria-pressed", String(dark));
  $("#theme-toggle").title = dark ? "Ativar tema claro" : "Ativar tema escuro";
  $("#tv-toggle").textContent = tv ? "TV ATIVO" : "MODO TV";
  $("#tv-toggle").setAttribute("aria-pressed", String(tv));
  $("#tv-toggle").title = tv ? "Desativar modo de apresentação" : "Ativar modo de apresentação";
  $("#sidebar-collapse").setAttribute("aria-pressed", String(sidebarCollapsed));
  $("#sidebar-collapse").querySelector("span").textContent = sidebarCollapsed ? "⟶" : "⟵";
  $("#sidebar-collapse").querySelector("b").textContent = sidebarCollapsed ? "EXPANDIR" : "RECOLHER";
  $("#sidebar-collapse").title = sidebarCollapsed ? "Expandir menu" : "Recolher menu";
}
$("#theme-toggle").addEventListener("click", () => {
  const theme = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = theme;
  localStorage.setItem(UI_THEME_KEY, theme);
  syncDisplayToggles();
});
$("#tv-toggle").addEventListener("click", () => {
  const enabled = !document.documentElement.classList.contains("tv-mode");
  document.documentElement.classList.toggle("tv-mode", enabled);
  localStorage.setItem(UI_TV_KEY, String(enabled));
  syncDisplayToggles();
});
$("#sidebar-collapse").addEventListener("click", () => {
  const collapsed = !document.documentElement.classList.contains("sidebar-collapsed");
  document.documentElement.classList.toggle("sidebar-collapsed", collapsed);
  localStorage.setItem(UI_SIDEBAR_KEY, String(collapsed));
  syncDisplayToggles();
});
syncDisplayToggles();
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

function pdfRows(items, pageNumber) {
  const positioned = items.filter(item => String(item.str || "").trim()).map(item => ({ text: String(item.str).replace(/\s+/g, " ").trim(), x: Number(item.transform?.[4] || 0), y: Number(item.transform?.[5] || 0), width: Number(item.width || 0) })).sort((a, b) => Math.abs(b.y - a.y) > 2 ? b.y - a.y : a.x - b.x);
  const rows = [];
  for (const item of positioned) { let row = rows.find(candidate => Math.abs(candidate.y - item.y) <= 2); if (!row) { row = { pageNumber, y: item.y, items: [] }; rows.push(row); } row.items.push(item); }
  return rows.map(row => { row.items.sort((a, b) => a.x - b.x); row.text = row.items.map(item => item.text).join(" ").replace(/\s+/g, " ").trim(); return row; }).sort((a, b) => b.y - a.y);
}
function moneyTokens(row) {
  const tokens = [], pattern = /(?:€\s*)?\d{1,3}(?:[.\s]\d{3})*(?:,\d{2})|(?:€\s*)?\d+(?:[.,]\d{2})/g;
  for (const item of row.items) for (const match of item.text.matchAll(pattern)) { const value = parsePortugueseMoney(match[0]); if (value) tokens.push({ value, x: item.x }); }
  return tokens;
}
function labelPosition(row, label) {
  for (let span = 1; span <= row.items.length; span += 1) {
    for (let start = 0; start + span <= row.items.length; start += 1) {
      const end = start + span - 1;
      const text = row.items.slice(start, end + 1).map(item => item.text).join(" ");
      if (label.test(text)) {
        const first = row.items[start], last = row.items[end];
        return { startX: first.x, endX: last.x + last.width, centerX: (first.x + last.x + last.width) / 2 };
      }
    }
  }
  return null;
}
function findFinalTotal(rows) {
  const labels = [/total\s+do\s+documento/i, /total\s+a\s+pagar/i, /total\s+geral/i, /valor\s+a\s+pagar/i];
  for (const label of labels) for (let index = rows.length - 1; index >= 0; index -= 1) {
    const row = rows[index], position = labelPosition(row, label); if (!position) continue;
    const sameRow = moneyTokens(row).filter(token => token.x >= position.endX - 2); if (sameRow.length) return sameRow[0].value;
    const below = rows.filter(candidate => candidate.pageNumber === row.pageNumber && candidate.y < row.y && row.y - candidate.y <= 45).sort((a, b) => b.y - a.y);
    for (const candidate of below) { const aligned = moneyTokens(candidate).map(token => ({ ...token, distance: Math.abs(token.x - position.centerX) })).filter(token => token.distance <= 55).sort((a, b) => a.distance - b.distance); if (aligned.length) return aligned[0].value; }
  }
  return null;
}
function findDocumentNumber(rows) {
  for (const row of rows) { if (!/(fatura|invoice|nota|recibo)/i.test(row.text)) continue; const match = row.text.match(/\bN(?:\.?\s*[ºo°])?\.?\s*(?:[:#-]\s*)?(.+?)\s*$/i); if (match?.[1]) return match[1].trim(); }
  return "";
}
function findSupplierCandidate(firstPageRows) {
  const clientIndex = firstPageRows.findIndex(row => /\bcliente\b/i.test(row.text));
  const headerRows = firstPageRows.slice(0, clientIndex >= 0 ? clientIndex : Math.min(firstPageRows.length, 12));
  const addressPattern = /\b(rua|avenida|av\.?|estrada|travessa|largo|praça|praceta|c[oó]digo\s+postal|\d{4}-\d{3}|nif|nipc|telefone|tel\.?|email|www\.)\b/i;
  const documentPattern = /\b(fatura|invoice|recibo|nota\s+de|original|duplicado|data|p[áa]gina)\b/i;
  return headerRows.find(row => { const text = row.text.trim(); return text.length >= 2 && /[A-Za-zÀ-ÿ]/.test(text) && !addressPattern.test(text) && !documentPattern.test(text); })?.text || "";
}
function findPaymentConditionSuggestion(rows) {
  const row = rows.find(item => /\b(cond(?:ição|\.)?\s*(?:de\s*)?pagamento|payment\s*terms?|termos?\s+de\s+pagamento)\b/i.test(item.text));
  if (!row) return "";
  const match = row.text.match(/\b(?:cond(?:ição|\.)?\s*(?:de\s*)?pagamento|payment\s*terms?|termos?\s+de\s+pagamento)\b\s*[:.-]?\s*(.*)$/i);
  return (match?.[1] || row.text).replace(/^[.: -]+/, "").trim();
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
    const rows = [];
    for (let pageNumber = 1; pageNumber <= Math.min(pdf.numPages, 12); pageNumber += 1) {
      const page = await pdf.getPage(pageNumber);
      const content = await page.getTextContent();
      rows.push(...pdfRows(content.items, pageNumber));
    }
    const meaningfulLines = rows.map(row => row.text).filter(Boolean);
    const fullText = meaningfulLines.join("\n");
    if (fullText.replace(/\s/g, "").length < 20) {
      $("#extraction-status").textContent = "SEM TEXTO";
      $("#extraction-note").textContent = "Este PDF parece ser uma digitalização sem texto pesquisável. Preencha os campos manualmente; será necessário OCR para automatizar este documento.";
      $("#extraction-results").innerHTML = extractionRow("Documento", "", "manual") + extractionRow("Fornecedor", "", "manual") + extractionRow("Data", "", "manual") + extractionRow("Valor", "", "manual");
      return;
    }

    const documentNumber = findDocumentNumber(rows);

    let invoiceDate = "";
    const dateLine = meaningfulLines.find(line => /\b(data|date|emiss[aã]o)\b/i.test(line) && /\d{1,4}[./-]\d{1,2}[./-]\d{2,4}/.test(line));
    const dateMatch = (dateLine || fullText).match(/\b(?:\d{1,2}[./-]\d{1,2}[./-]\d{4}|\d{4}-\d{2}-\d{2})\b/);
    if (dateMatch) invoiceDate = toIsoDate(dateMatch[0]) || "";

    const invoiceValue = findFinalTotal(rows);
    const paymentConditionSuggestion = findPaymentConditionSuggestion(rows);

    const supplierCandidate = findSupplierCandidate(rows.filter(row => row.pageNumber === 1));
    const exactSupplier = suppliers.find(supplier => normalizeExactName(supplier.nome) === normalizeExactName(supplierCandidate));

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
      extractionRow("Fornecedor", supplierCandidate, exactSupplier ? "alta" : supplierCandidate ? "provavel" : "manual") +
      extractionRow("Data", invoiceDate ? prettyDate.format(new Date(`${invoiceDate}T12:00:00`)) : "", invoiceDate ? "provavel" : "manual") +
      extractionRow("Valor", invoiceValue ? euro.format(invoiceValue) : "", invoiceValue ? "provavel" : "manual") +
      extractionRow("Cond. pagamento (sugestão)", paymentConditionSuggestion, "manual");
    $("#payment-condition-suggestion").textContent = paymentConditionSuggestion
      ? `Sugestão lida no PDF: ${paymentConditionSuggestion}. Confirme manualmente uma das opções.`
      : "Selecione manualmente; este campo nunca é preenchido automaticamente.";
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
  $("#payment-condition-suggestion").textContent = "";
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
  $("#payment-condition-suggestion").textContent = "";
  $("#choose-pdf").innerHTML = `${icon("upload")} ANEXAR PDF`;
  renderSubcontracts(); renderInvoices(); submit.disabled = false; submit.firstChild.textContent = "REGISTAR FATURA ";
});

$("#invoice-list").addEventListener("click", async event => {
  const pdfButton = event.target.closest("[data-pdf], [data-guide]");
  if (pdfButton) {
    pdfButton.disabled = true;
    try {
      const objectPath = decodeURIComponent(pdfButton.dataset.pdf || pdfButton.dataset.guide);
      const blob = await downloadInvoicePdf(objectPath);
      openedPdfUrl = URL.createObjectURL(blob);
      openPdfModal(openedPdfUrl, pdfButton.dataset.guide ? "GUIA DE REMESSA" : "FATURA");
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
  const card = button.closest("[data-invoice-card]");
  const guideInput = card?.querySelector("[data-guide-input]");
  const existingGuides = invoiceGuides.filter(guide => guide.fatura_id === invoice.id);
  const selectedGuides = [...(guideInput?.files || [])];
  if (decision === "aprovado" && !existingGuides.length && !selectedGuides.length) {
    toast("Anexe pelo menos uma guia antes de aprovar a fatura.", "error");
    return;
  }
  button.disabled = true;
  const createdGuides = [];
  if (decision === "aprovado" && selectedGuides.length && isSupabaseConfigured) {
    try {
      button.innerHTML = `${icon("upload")} A ENVIAR GUIAS…`;
      for (const file of selectedGuides) {
        const arquivoUrl = await uploadDeliveryNote(file, invoice.obra_id, invoice.id);
        const response = await supabase("faturas_guias?select=*", {
          method: "POST",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify({ fatura_id: invoice.id, arquivo_url: arquivoUrl, nome_arquivo: file.name, mime_type: file.type }),
        });
        if (!response.ok) throw new Error(await response.text());
        createdGuides.push((await response.json())[0]);
      }
    } catch (error) {
      toast(error.message || "Não foi possível enviar as guias.", "error");
      button.disabled = false;
      button.innerHTML = `${icon("check")} APROVAR`;
      return;
    }
  }
  if (isSupabaseConfigured) {
    const result = await supabase(`faturas?id=eq.${invoice.id}&estado_aprovacao=eq.pendente`, {
      method: "PATCH", body: JSON.stringify({
        estado_aprovacao: decision,
        aprovado_por: session?.user?.id || null,
        data_aprovacao: new Date().toISOString(),
      }),
    });
    if (!result.ok) { toast(`Não foi possível concluir: ${await result.text()}`, "error"); button.disabled = false; return; }
  }
  if (decision === "aprovado") {
    if (isSupabaseConfigured) invoiceGuides.push(...createdGuides);
    else if (!existingGuides.length) invoiceGuides.push(...selectedGuides.map((file, index) => ({ id: `demo-guide-${Date.now()}-${index}`, fatura_id: invoice.id, arquivo_url: URL.createObjectURL(file), nome_arquivo: file.name, mime_type: file.type })));
    financeInvoices.unshift({ ...invoice, estado_aprovacao: "aprovado", estado_pagamento: "por_pagar", data_aprovacao: new Date().toISOString() });
    renderFinance();
  }
  invoices = invoices.filter(item => item.id !== invoice.id); renderInvoices();
  toast(`Fatura ${decision === "aprovado" ? "aprovada" : "recusada"}${isSupabaseConfigured ? "" : " em modo de demonstração"}.`);
});

$("#invoice-list").addEventListener("change", event => {
  const input = event.target.closest("[data-guide-input]");
  if (!input) return;
  const files = [...(input.files || [])];
  const picker = input.closest(".guide-picker");
  const approve = input.closest("[data-invoice-card]")?.querySelector('[data-action="aprovado"]');
  if (!files.length) {
    picker.classList.remove("ready");
    picker.querySelector("span").textContent = "ANEXAR GUIAS";
    approve.disabled = !invoiceGuides.some(guide => guide.fatura_id === input.dataset.guideInput);
    return;
  }
  const allowedTypes = ["application/pdf", "image/jpeg", "image/png", "image/webp"];
  const invalid = files.find(file => !allowedTypes.includes(file.type) || file.size > 10 * 1024 * 1024);
  if (invalid) {
    input.value = "";
    toast(!allowedTypes.includes(invalid.type) ? "As guias devem ser PDF, JPG, PNG ou WEBP." : `${invalid.name} excede o limite de 10 MB.`, "error");
    return;
  }
  picker.classList.add("ready");
  picker.querySelector("span").textContent = `${files.length} GUIA(S) SELECIONADA(S)`;
  approve.disabled = false;
  approve.title = "Aprovar fatura";
});

$("#finance-board").addEventListener("click", async event => {
  const guideButton = event.target.closest("[data-guide]");
  if (guideButton) {
    try {
      const path = decodeURIComponent(guideButton.dataset.guide);
      if (path.startsWith("blob:")) return openPdfModal(path, "GUIA DE REMESSA");
      const blob = await downloadInvoicePdf(path);
      openedPdfUrl = URL.createObjectURL(blob);
      openPdfModal(openedPdfUrl, "GUIA DE REMESSA");
    } catch (error) { toast(error.message || "Não foi possível abrir a guia.", "error"); }
    return;
  }
  const button = event.target.closest("[data-mark-paid]");
  if (!button) return;
  const invoice = financeInvoices.find(item => String(item.id) === button.dataset.markPaid);
  if (!invoice) return;
  button.disabled = true;
  const paymentDate = button.closest(".finance-card")?.querySelector("[data-payment-date]")?.value || new Date().toISOString().slice(0, 10);
  const paidAt = `${paymentDate}T12:00:00`;
  if (isSupabaseConfigured) {
    const result = await supabase(`faturas?id=eq.${invoice.id}&estado_aprovacao=eq.aprovado`, {
      method: "PATCH",
      body: JSON.stringify({ estado_pagamento: "pago", pago_por: session?.user?.id || null, data_pagamento: paymentDate }),
    });
    if (!result.ok) {
      toast(`Não foi possível marcar a fatura como paga: ${await result.text()}`, "error");
      button.disabled = false;
      return;
    }
  }
  invoice.data_pagamento = paidAt;
  invoice.estado_pagamento = "pago";
  invoice.pago_por = session?.user?.id || null;
  renderFinance();
  toast(`Fatura marcada como paga${isSupabaseConfigured ? "" : " em modo de demonstração"}.`);
});

renderUser();
loadData();
