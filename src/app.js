import { clearSession, downloadInvoicePdf, downloadWorkDocument, getSession, isSupabaseConfigured, requestPasswordReset, signIn, signOut, supabase, uploadDeliveryNote, uploadEntityDocument, uploadInvoiceAttachment, uploadInvoicePdf, uploadWorkDocument, uploadWorkflowPdf } from "./supabase-browser.js?v=3";
import { demoInvoices, demoSubcontracts, demoSuppliers, demoWorks } from "./demoData-browser.js?v=2";
import { createProductionDashboard } from "./production-dashboard.js?v=13";
import { createPlanningModule } from "./planning.js?v=7";
import { createSubcontractorsModule } from "./subcontractors.js?v=3";
import { accessFor, effectiveAccessRole } from "./access-control.js?v=8";
import { DIRECT_DEBIT_CATEGORY_LABELS, DIRECT_DEBIT_RECURRENCE_LABELS, directDebitOccurrences } from "./direct-debits.js?v=1";
import { createSettingsModule } from "./settings.js?v=3";
import { createProcurementModule } from "./procurement.js?v=1";
import { createActionPlanModule } from "./action-plan.js?v=2";
import { createDocumentsModule } from "./documents.js?v=1";
import { createRncModule } from "./rnc.js?v=2";
import { createConsolidatedView } from "./consolidated-view.js?v=1";

const $ = (selector) => document.querySelector(selector);
const euro = new Intl.NumberFormat("pt-PT", { style: "currency", currency: "EUR" });
const prettyDate = new Intl.DateTimeFormat("pt-PT", { day: "2-digit", month: "short", year: "numeric" });
const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
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

let works = [], suppliers = [], subcontracts = [], invoices = [], financeInvoices = [], invoiceGuides = [], invoiceAttachments = [], collaborators = [];
let directDebits = [], directDebitEntries = [];
const PRIMELINE_COMPANY_ID = "73fb13c8-d29f-4192-a506-4ca243343add";
let accessContext = { role: isSupabaseConfigured ? "" : "gerencia", isAdmin: !isSupabaseConfigured, profile: null };
let currentFilter = "all";
let session = getSession();
let selectedPdf = null;
let localPdfUrl = "";
let extractedMaterialItems = [];
let extractedMaterialItemsApplied = false;
let openedPdfUrl = "";
let activeView = "overview";
let selectedFinanceTab = "invoices";
let expandedDirectDebitId = "";
let selectedWorkId = "";
let workDetails = {
  contract: null, investment: null, impacts: [], phases: [], measurements: [], payments: [], consultations: [],
  labor: [], siteExpenses: [], directDebits: [], directDebitEntries: [],
  billings: [], billingLinks: [], documents: [], workDocuments: [], documentUsers: {},
  drawings: [], rfis: [], safetyIncidents: [], safetyInspections: [], epis: [],
  safetyCollaborators: [], canEditDocuments: false, canEditSafety: false,
  error: "", procurementError: "", billingError: "", workDocumentsError: "",
  documentIndexesError: "", safetyError: "",
};
const localWorkDocumentFiles = new Map();
let selectedWorkTab = "summary";
let selectedTeamWeek = mondayIso(new Date());
let teamData = { allocations: [], absences: [], absenceAttachments: [], contracts: [], overtime: [], responsibles: [], users: [], vehicles: [], medicine: [], entityDocuments: [], loadedWeek: "", error: "" };
let selectedTeamTab = "collaborators";
let teamQuickFilter = "";
let selectedTeamEntity = null;
let selectedVehicleEditId = "";
const localEntityDocumentFiles = new Map();
let workforceEditing = false;
let selectedWorkforcePersonId = "";
let selectedWorkforceSourceDate = "";
let selectedWorkforceSourcePeriod = "";
let selectedWorkforceSourceRowKey = "";
let selectedWorkforceSourceIds = [];
let selectedWorkforcePeriod = "dia_inteiro";
let pendingWorkforceRows = [];
let settingsModule = null;
let procurementModule = null;

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
        <button data-view="action-plan">✓ <span>Plano de Ação</span></button><button data-view="consolidated">◆ <span>Visão consolidada</span></button><button class="active" data-view="overview">▦ <span>Visão geral</span></button><button data-view="works">▥ <span>Obras</span></button>
        <button data-view="invoices">▤ <span>Faturas</span></button><button data-view="finance">€ <span>Financeiro</span></button><button data-view="subcontractors">◇ <span>Subempreiteiros</span></button><button data-view="planning">▤ <span>Planeamento</span></button><button data-view="documents">□ <span>Documentos</span></button><button data-view="rnc">! <span>RNC</span></button><button data-view="workforce">▦ <span>Quadro de pessoal</span></button><button data-view="team">♙ <span>Equipa</span></button>
        <p>CONFIGURAÇÃO</p><button data-view="settings">⚙ <span>Definições</span></button>
      </nav>
      <div class="sidebar-user"><span id="user-initials">PL</span><div><strong id="user-name">UTILIZADOR</strong><small id="user-role">SESSÃO AUTENTICADA</small></div><button class="logout-button" id="logout" title="Terminar sessão">↗</button></div>
    </aside>
    <main>
      <header class="topbar"><button class="mobile-menu" id="menu">${icon("menu")}</button><div class="mobile-brand">${brand()}</div>
        <div class="top-actions">${!isSupabaseConfigured ? '<span class="demo-badge">MODO DEMONSTRAÇÃO</span>' : ""}<button class="display-toggle" id="tv-toggle" type="button" aria-pressed="false">MODO TV</button><button class="display-toggle" id="theme-toggle" type="button" aria-pressed="false">TEMA</button><button class="icon-button" id="notification-button" type="button" aria-label="Ver alertas pendentes">${icon("bell")}<i>0</i></button></div>
      </header>
      <div class="page overview-view" id="overview-view"></div>
      <div class="page consolidated-view" id="consolidated-view" hidden></div>
      <div class="page action-plan-view" id="action-plan-view" hidden></div>
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
              <section class="material-items-editor" id="material-items-editor" hidden>
                <div class="material-items-head"><div><span>DETALHE DA FATURA</span><strong>ARTIGOS / MATERIAIS</strong></div><button type="button" id="add-material-item">＋ ARTIGO</button></div>
                <div class="material-items-columns"><span>DESIGNAÇÃO</span><span>UNIDADE</span><span>QUANTIDADE</span><span>PREÇO BRUTO</span><span>DESC. %</span><span>DESC. €</span><span>TOTAL LÍQUIDO</span><span></span></div>
                <div id="material-items-list"></div>
                <p>O valor total da fatura continua a ser o valor final com IVA incluído.</p>
              </section>
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
      <div class="page planning-view" id="planning-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">PROGRAMAÇÃO DE OBRA</p><h1>PLANEAMENTO</h1><p>Tarefas, dependências e prazos detalhados por fase.</p></div>
          <div class="planning-work-picker"><label>OBRA</label><div class="select-wrap"><select id="planning-work"></select><b>⌄</b></div></div>
        </div>
        <section class="panel planning-panel">
          <div id="planning-content"></div>
        </section>
      </div>
      <div class="page subcontractors-view" id="subcontractors-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">BASE DE PARCEIROS</p><h1>SUBEMPREITEIROS</h1><p>Diretório geral, experiência em obra e avaliação histórica.</p></div>
        </div>
        <div id="subcontractors-content"></div>
      </div>
      <div class="page finance-view" id="finance-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">TESOURARIA</p><h1>FINANCEIRO</h1><p>Pagamentos, compromissos recorrentes e histórico financeiro.</p></div>
          <div class="heading-stat"><span>POR PAGAR</span><strong id="finance-count">00</strong></div>
        </div>
        <nav class="finance-tabs" aria-label="Secções financeiras">
          <button type="button" class="active" data-finance-tab="invoices">FATURAS E PAGAMENTOS</button>
          <button type="button" data-finance-tab="direct-debits">DÉBITOS DIRETOS</button>
        </nav>
        <div data-finance-panel="invoices">
          <section class="finance-board" id="finance-board"></section>
          <section class="panel paid-history">
            <div class="paid-history-head"><div><p class="eyebrow">ARQUIVO</p><h2>HISTÓRICO DE FATURAS PAGAS</h2></div><span id="paid-count">0 FATURAS</span></div>
            <div class="paid-list" id="paid-list"></div>
          </section>
        </div>
        <div data-finance-panel="direct-debits" hidden>
          <section class="panel direct-debit-create">
            <div class="direct-debit-section-head"><div><p class="eyebrow">COMPROMISSOS RECORRENTES</p><h2>NOVO DÉBITO DIRETO</h2></div><small>Os valores previstos alimentam automaticamente a previsão da obra.</small></div>
            <form id="direct-debit-form" class="direct-debit-form">
              <label>DESCRIÇÃO<input name="descricao" required maxlength="160" placeholder="Ex.: Seguro mensal da obra"></label>
              <label>CATEGORIA<select name="categoria"><option value="renda">Renda</option><option value="seguro">Seguro</option><option value="software">Software</option><option value="emprestimo">Empréstimo</option><option value="servico_publico">Serviço público</option><option value="outro">Outro</option></select></label>
              <label>VALOR PREVISTO (€)<input name="valor_previsto" type="number" min="0.01" step="0.01" required></label>
              <label>OBRA<select name="obra_id" id="direct-debit-work"><option value="">Geral da empresa</option></select></label>
              <label>RECORRÊNCIA<select name="recorrencia"><option value="">Sem recorrência</option><option value="mensal">Mensal</option><option value="trimestral">Trimestral</option><option value="anual">Anual</option></select></label>
              <label>DIA DO MÊS<input name="dia_mes" type="number" min="1" max="31" placeholder="Ex.: 8"></label>
              <label>DATA DE INÍCIO<input name="data_inicio" type="date" required></label>
              <label>DATA DE FIM<input name="data_fim" type="date"></label>
              <label class="direct-debit-active"><input name="ativo" type="checkbox" checked> DÉBITO ATIVO</label>
              <button type="submit" class="primary-button">GUARDAR DÉBITO DIRETO <span>→</span></button>
              <p class="form-error" id="direct-debit-form-error"></p>
            </form>
          </section>
          <section class="panel direct-debit-directory">
            <div class="direct-debit-section-head"><div><p class="eyebrow">CALENDÁRIO DE PAGAMENTOS</p><h2>DÉBITOS DIRETOS</h2></div><span id="direct-debit-count">0 REGISTOS</span></div>
            <div id="direct-debit-list"></div>
          </section>
        </div>
      </div>
      <div class="page team-view" id="team-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">GESTÃO DE PESSOAS</p><h1>EQUIPA</h1><p>Colaboradores, frota, documentos, ausências e contratos.</p></div>
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
          <button data-team-tab="medicine">MEDICINA DO TRABALHO</button>
          <button data-team-tab="vehicles">VIATURAS</button>
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
        <section class="panel team-tab-panel" data-team-panel="medicine" hidden>
          <div class="team-section-head"><div><p class="eyebrow">SAÚDE OCUPACIONAL</p><h2>MEDICINA DO TRABALHO</h2></div><span id="team-medicine-count"></span></div>
          <div id="team-medicine"></div>
        </section>
        <section class="panel team-tab-panel" data-team-panel="vehicles" hidden>
          <div class="team-section-head"><div><p class="eyebrow">FROTA</p><h2>VIATURAS</h2></div><span id="team-vehicle-count"></span></div>
          <div id="team-vehicles"></div>
        </section>
      </div>
      <div class="page workforce-view" id="workforce-view" hidden>
        <div class="page-heading">
          <div><p class="eyebrow">PLANEAMENTO SEMANAL</p><h1>QUADRO DE PESSOAL</h1><p>Distribuição das equipas operacionais pelas obras.</p></div>
          <div class="workforce-heading-actions"><div class="workforce-legend"><span><i class="foreman"></i>ENCARREGADO</span><span><i class="mason"></i>PEDREIRO</span><span><i class="helper"></i>SERVENTE</span></div><button class="outline-action" id="edit-workforce" type="button">EDITAR QUADRO</button></div>
        </div>
        <div class="workforce-edit-banner" id="workforce-edit-banner" hidden><strong>MODO DE EDIÇÃO</strong><span id="workforce-edit-message">Selecione um íman e depois clique no dia e obra de destino.</span><button id="add-workforce-line" type="button">＋ NOVA LINHA</button><button id="remove-workforce-allocation" type="button" hidden>RETIRAR</button><button id="finish-workforce-edit" type="button">TERMINAR</button></div>
        <form class="workforce-new-line" id="workforce-new-line" hidden>
          <div><span>TIPO DE LINHA</span><select id="workforce-line-type"><option value="obra">Obra existente</option><option value="garantia">Garantia</option><option value="pontual">Pontual</option></select></div>
          <div data-workforce-existing><span>OBRA</span><select id="workforce-line-work"></select></div>
          <div data-workforce-free hidden><span>NOME DA LINHA</span><input id="workforce-line-description" maxlength="120" placeholder="Ex.: Garantia Casa R"></div>
          <button type="submit">ADICIONAR LINHA</button><button type="button" data-cancel-workforce-line>CANCELAR</button>
        </form>
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
      <div class="page settings-view" id="settings-view" hidden></div>
      <div class="page documents-view" id="documents-view" hidden></div>
      <div class="page rnc-view" id="rnc-view" hidden></div>
      <div class="page placeholder-view" id="placeholder-view" hidden>
        <div class="empty-state"><strong id="placeholder-title">MÓDULO EM PREPARAÇÃO</strong><span>Esta área será desenvolvida numa próxima etapa.</span></div>
      </div>
    </main>
    <button class="notification-scrim" id="notification-scrim" type="button" aria-label="Fechar alertas" hidden></button>
    <aside class="notification-drawer" id="notification-drawer" aria-hidden="true" aria-labelledby="notification-drawer-title">
      <header><div><p>NOTIFICAÇÕES</p><h2 id="notification-drawer-title">ALERTAS PENDENTES</h2></div><button type="button" id="notification-close" aria-label="Fechar alertas">×</button></header>
      <div class="notification-drawer-list" id="notification-drawer-list"></div>
    </aside>
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
          <fieldset class="work-template-fieldset"><legend>MODELO DE ESTRUTURA</legend>
            <label>BASEAR NESTA OBRA<div class="select-wrap"><select name="modelo_obra_id"><option value="">Começar sem modelo</option></select><b>⌄</b></div></label>
            <label class="work-template-check"><input name="copiar_orcamento" type="checkbox" checked><span><strong>COPIAR CATEGORIAS DO ORÇAMENTO</strong><small>Replica designações e unidades, sempre sem quantidades, custos ou preços.</small></span></label>
            <p>O modelo copia fases e categorias comuns. Não copia cliente, responsáveis, contratos, documentos, fornecedores, tarefas, valores realizados ou movimentos financeiros.</p>
          </fieldset>
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

function materialItemRow(item = {}) {
  const id = item.id || crypto.randomUUID();
  return `<div class="material-item-row" data-material-item="${id}">
    <input data-item-field="designacao" value="${safeText(item.designacao || "")}" required placeholder="Ex.: Cimento cola" aria-label="Designação">
    <input data-item-field="unidade" value="${safeText(item.unidade || "")}" required placeholder="un., kg, m²" aria-label="Unidade">
    <input data-item-field="quantidade" type="number" min="0.001" step="0.001" value="${item.quantidade ?? ""}" required placeholder="Quantidade" aria-label="Quantidade">
    <input data-item-field="preco_unitario" type="number" min="0" step="0.0001" value="${item.preco_unitario ?? ""}" required placeholder="Preço bruto" aria-label="Preço unitário bruto">
    <input data-item-field="desconto_percentual" type="number" min="0" max="100" step="0.01" value="${item.desconto_percentual ?? ""}" placeholder="Desc. %" aria-label="Desconto percentual">
    <input data-item-field="valor_desconto" type="number" min="0" step="0.01" value="${item.valor_desconto ?? ""}" placeholder="Desc. €" aria-label="Valor do desconto">
    <output data-item-total aria-label="Total líquido">${euro.format(Number(item.preco_total || 0))}</output>
    <button type="button" data-remove-material-item aria-label="Remover artigo">×</button>
  </div>`;
}

function addMaterialItem(item = {}) {
  $("#material-items-list").insertAdjacentHTML("beforeend", materialItemRow(item));
}

function resetMaterialItems() {
  $("#material-items-list").innerHTML = "";
  addMaterialItem();
}

function showExtractedMaterialItems(items) {
  if (items !== extractedMaterialItems) {
    extractedMaterialItems = items.map(item => ({ ...item }));
    extractedMaterialItemsApplied = false;
    if (form.tipo_origem.value === "material") $("#material-items-list").innerHTML = "";
  }
  if (form.tipo_origem.value !== "material" || extractedMaterialItemsApplied) return;
  if (!extractedMaterialItems.length) {
    if (!$("#material-items-list").children.length) addMaterialItem();
    return;
  }
  $("#material-items-list").innerHTML = "";
  extractedMaterialItems.forEach(addMaterialItem);
  extractedMaterialItemsApplied = true;
}

function updateMaterialItemTotal(row, changedField = "") {
  const quantity = Number(row.querySelector('[data-item-field="quantidade"]').value || 0);
  const unitPrice = Number(row.querySelector('[data-item-field="preco_unitario"]').value || 0);
  const percentInput = row.querySelector('[data-item-field="desconto_percentual"]');
  const discountInput = row.querySelector('[data-item-field="valor_desconto"]');
  const gross = quantity * unitPrice;
  let percent = Number(percentInput.value || 0);
  let discount = Number(discountInput.value || 0);
  if (changedField === "valor_desconto") {
    discount = Math.min(gross, Math.max(0, discount));
    percent = gross ? discount / gross * 100 : 0;
    percentInput.value = percent ? percent.toFixed(2) : "";
  } else if (changedField === "desconto_percentual" || percentInput.value !== "") {
    discount = gross * percent / 100;
    discountInput.value = discount ? discount.toFixed(2) : "";
  } else if (discountInput.value !== "") {
    discount = Math.min(gross, Math.max(0, discount));
    percent = gross ? discount / gross * 100 : 0;
    percentInput.value = percent ? percent.toFixed(2) : "";
  }
  discount = Math.min(gross, Math.max(0, discount));
  row.querySelector("[data-item-total]").textContent = euro.format(Math.max(0, gross - discount));
}

function collectMaterialItems() {
  return [...document.querySelectorAll("[data-material-item]")].map(row => {
    const value = field => row.querySelector(`[data-item-field="${field}"]`).value;
    const quantity = Number(value("quantidade"));
    const unitPrice = Number(value("preco_unitario"));
    const discountPercent = value("desconto_percentual") === "" ? null : Number(value("desconto_percentual"));
    const discountValue = value("valor_desconto") === "" ? null : Number(value("valor_desconto"));
    const gross = quantity * unitPrice;
    const effectiveDiscount = discountValue ?? (discountPercent == null ? 0 : gross * discountPercent / 100);
    return {
      designacao: value("designacao").trim(),
      unidade: value("unidade").trim(),
      quantidade: quantity,
      preco_unitario: unitPrice,
      desconto_percentual: discountPercent,
      valor_desconto: discountValue,
      preco_total: Math.max(0, gross - effectiveDiscount),
    };
  }).filter(item => item.designacao || item.unidade || item.quantidade || item.preco_unitario);
}

resetMaterialItems();
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
  getAccessContext: () => accessContext,
  showView: (view, context) => switchView(view, context),
});
productionDashboard.bind();
const planningModule = createPlanningModule({
  supabase,
  isSupabaseConfigured,
  getWorks: () => works,
  toast,
});
const actionPlanModule = createActionPlanModule({
  root: $("#action-plan-view"),
  supabase,
  isConfigured: isSupabaseConfigured,
  getWorks: () => works,
  getRole: effectiveRole,
  toast,
  onPlanningChanged: () => planningModule.refresh(),
});
const documentsModule = createDocumentsModule({
  root: $("#documents-view"),
  supabase,
  isConfigured: isSupabaseConfigured,
  getWorks: () => works,
  getProfile: () => accessContext.profile,
  getRole: effectiveRole,
  uploadWorkDocument,
  downloadWorkDocument,
  prettyDate,
  toast,
  previewBlob: (blob, name) => {
    if (openedPdfUrl) URL.revokeObjectURL(openedPdfUrl);
    openedPdfUrl = URL.createObjectURL(blob);
    openPdfModal(openedPdfUrl, name);
  },
});
const rncModule = createRncModule({
  root: $("#rnc-view"), supabase, isConfigured: isSupabaseConfigured,
  getWorks: () => works, getRole: effectiveRole, uploadWorkDocument, downloadWorkDocument, toast,
});
const consolidatedView = createConsolidatedView({
  root: $("#consolidated-view"), supabase, isConfigured: isSupabaseConfigured,
  getWorks: () => works, getInvoices: () => financeInvoices.length ? financeInvoices : invoices,
  euro, toast,
});
const subcontractorsModule = createSubcontractorsModule({
  supabase,
  isSupabaseConfigured,
  getWorks: () => works,
  getSuppliers: () => suppliers,
  getSubcontracts: () => subcontracts,
  euro,
  toast,
});

function renderUser() {
  const email = session?.user?.email || "utilizador";
  const label = accessContext.profile?.nome || session?.user?.user_metadata?.full_name || email.split("@")[0];
  $("#user-name").textContent = label.toUpperCase();
  $("#user-initials").textContent = label.split(/[ ._-]+/).slice(0, 2).map(part => part[0]).join("").toUpperCase();
  $("#user-role").textContent = effectiveRole().replaceAll("_", " ").toUpperCase() || "SESSÃO AUTENTICADA";
}

function effectiveRole() {
  return effectiveAccessRole(accessContext);
}

function hasFullAccess() {
  return effectiveRole() === "gerencia";
}

function isAdministrative() {
  return effectiveRole() === "administrativo";
}

function canManageTeam() {
  return hasFullAccess() || isAdministrative();
}

function isFinancial() {
  return effectiveRole() === "financeiro";
}

function canManageDirectDebits() {
  return hasFullAccess() || isAdministrative() || isFinancial();
}

function canApproveInvoices() {
  return accessFor(accessContext).approveInvoices;
}

function canInsertInvoices() {
  return accessFor(accessContext).insertInvoices;
}

function canPayInvoices() {
  return accessFor(accessContext).payInvoices;
}

function canEditWork() {
  return accessFor(accessContext).editWork;
}

function allowedViews() {
  return new Set(accessFor(accessContext).views);
}

function defaultViewForCurrentUser() {
  const permitted = accessFor(accessContext).views;
  if (permitted.includes("action-plan")) return "action-plan";
  if (permitted.includes("overview")) return "overview";
  return permitted[0] || "settings";
}

function applyAccessVisibility() {
  const permitted = allowedViews();
  document.querySelectorAll(".sidebar nav [data-view]").forEach(button => {
    button.hidden = !permitted.has(button.dataset.view);
  });
  $(".new-invoice").hidden = !canInsertInvoices();
  $("#new-work").hidden = !hasFullAccess();
  document.querySelectorAll("[data-team-tab]").forEach(button => {
    button.hidden = !canManageTeam() && button.dataset.teamTab !== "absences";
  });
  if (!canManageTeam()) {
    selectedTeamTab = "absences";
    $("#team-directory-search").closest(".team-toolbar").hidden = true;
  } else {
    $("#team-directory-search").closest(".team-toolbar").hidden = false;
  }
  document.body.dataset.userRole = effectiveRole() || "sem_perfil";
  if (!permitted.has(activeView)) switchView(defaultViewForCurrentUser());
  renderUser();
}

async function loadAccessContext() {
  if (!isSupabaseConfigured) {
    accessContext = { role: "gerencia", isAdmin: true, profile: { nome: "Utilizador de demonstração", funcao: "gerencia" } };
    applyAccessVisibility();
    return;
  }
  const authId = getSession()?.user?.id;
  if (!authId) return;
  const [profileResult, adminResult] = await Promise.all([
    supabase(`utilizadores?select=id,empresa_id,nome,email,funcao,ativo,auth_user_id&auth_user_id=eq.${encodeURIComponent(authId)}&limit=1`),
    supabase("rpc/fn_e_admin", { method: "POST", body: "{}" }),
  ]);
  const profiles = profileResult.ok ? await profileResult.json() : [];
  const profile = profiles[0] || null;
  accessContext = {
    role: profile?.ativo === false ? "" : profile?.funcao || "",
    isAdmin: profile?.ativo === false ? false : adminResult.ok ? Boolean(await adminResult.json()) : profile?.funcao === "gerencia",
    profile,
  };
  applyAccessVisibility();
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

async function friendlyApiError(response, fallback) {
  const payload = await response.json().catch(async () => ({ message: await response.text().catch(() => "") }));
  const detail = payload.message || payload.details || payload.hint || fallback;
  if (/férias|ferias|ausente|ausência|ausencia/i.test(detail)) {
    return "Este colaborador está de férias/ausente nesta data.";
  }
  return detail || fallback;
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
    const attachments = invoiceAttachments.filter(item => item.fatura_id === invoice.id);
    const hasGuide = guides.length > 0;
    const actionable = canApproveInvoices();
    return `<article class="invoice-card" data-invoice-card="${invoice.id}">
      <div class="invoice-icon">${icon("invoice")}</div><div class="invoice-main">
        <div class="invoice-top"><div><strong>${supplier}</strong><span>${invoice.numero_doc}</span></div><strong class="invoice-value">${euro.format(Number(invoice.valor))}</strong></div>
        <div class="invoice-meta"><span>OBRA ${work?.numero || "—"}</span><span class="type-pill ${invoice.tipo_origem}">${typeLabels[invoice.tipo_origem]}</span><span>${prettyDate.format(new Date(`${invoice.data_fatura}T12:00:00`))}</span>${invoice.arquivo_url ? `<button class="document-link" data-pdf="${encodeURIComponent(invoice.arquivo_url)}">${icon("invoice")} VER PDF</button>` : ""}</div>
        <div class="approval-fields ${actionable ? "" : "readonly"}">
          <label class="guide-picker ${hasGuide ? "ready" : ""}">
            ${icon("upload")}<span>${hasGuide ? `${guides.length} GUIA(S) ANEXADA(S)` : "ANEXAR GUIAS"}</span>
            ${actionable ? `<input type="file" accept="application/pdf,image/jpeg,image/png,image/webp,.pdf,.jpg,.jpeg,.png,.webp" multiple data-guide-input="${invoice.id}">` : ""}
          </label>
          <div class="attached-guides">${guides.map((guide, index) => `<button type="button" data-guide="${encodeURIComponent(guide.arquivo_url)}">GUIA ${index + 1}</button>`).join("")}</div>
        </div>
        <div class="invoice-extra-attachments"><div><strong>ANEXOS ADICIONAIS</strong><small>OPCIONAL · não substitui a guia de remessa obrigatória</small></div>
          ${actionable ? `<label class="extra-attachment-picker">${icon("upload")} ADICIONAR ANEXOS<input type="file" multiple accept="application/pdf,image/jpeg,image/png,image/webp" data-invoice-attachment-input="${invoice.id}"></label>` : ""}
          <div>${attachments.map((item, index) => `<button type="button" data-invoice-attachment="${encodeURIComponent(item.arquivo_url)}">ANEXO ${index + 1}</button>`).join("") || "<small>Sem anexos adicionais</small>"}</div>
        </div>
        ${actionable ? `<div class="card-actions"><button class="reject" data-action="recusado" data-id="${invoice.id}">${icon("x")} RECUSAR</button><button class="approve" data-action="aprovado" data-id="${invoice.id}" ${hasGuide ? "" : "disabled"} title="${hasGuide ? "Aprovar fatura" : "Anexe uma guia para aprovar"}">${icon("check")} APROVAR</button></div>` : `<div class="readonly-note">CONSULTA · SEM PERMISSÃO PARA APROVAR OU RECUSAR</div>`}
      </div></article>`;
  }).join("");
}

function invoiceSortDate(invoice) { return new Date(`${invoice.data_fatura || "1970-01-01"}T12:00:00`).getTime(); }

function financeCard(invoice) {
  const supplier = suppliers.find(item => item.id === invoice.fornecedor_id)?.nome || "Fornecedor";
  const work = works.find(item => item.id === invoice.obra_id);
  const guides = invoiceGuides.filter(guide => guide.fatura_id === invoice.id);
  const attachments = invoiceAttachments.filter(item => item.fatura_id === invoice.id);
  const today = new Date().toISOString().slice(0, 10);
  return `<article class="finance-card">
    <div class="finance-card-top"><span>OBRA ${work?.numero || "—"}</span><strong>${euro.format(Number(invoice.valor))}</strong></div>
    <h3>${supplier}</h3><p>${invoice.numero_doc}</p>
    <div class="finance-date"><span>DATA DA FATURA</span><strong>${prettyDate.format(new Date(`${invoice.data_fatura}T12:00:00`))}</strong></div>
    <div class="finance-guides"><span>GUIAS</span><div>${guides.map((guide, index) => `<button type="button" data-guide="${encodeURIComponent(guide.arquivo_url)}">${icon("invoice")} GUIA ${index + 1}</button>`).join("") || "<small>Sem guia disponível</small>"}</div></div>
    <div class="finance-guides"><span>ANEXOS OPCIONAIS</span><div>${attachments.map((item, index) => `<button type="button" data-invoice-attachment="${encodeURIComponent(item.arquivo_url)}">${icon("invoice")} ANEXO ${index + 1}</button>`).join("") || "<small>Sem anexos adicionais</small>"}</div></div>
    ${canPayInvoices() ? `<label class="payment-date">DATA DE PAGAMENTO<input type="date" value="${today}" data-payment-date="${invoice.id}"></label>
    <button class="mark-paid" data-mark-paid="${invoice.id}">${icon("check")} MARCAR COMO PAGA</button>` : `<div class="readonly-note">CONSULTA · PAGAMENTO RESERVADO AO FINANCEIRO</div>`}
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
  renderDirectDebits();
  renderFinanceTabs();
}

function renderFinanceTabs() {
  document.querySelectorAll("[data-finance-tab]").forEach(button => {
    button.classList.toggle("active", button.dataset.financeTab === selectedFinanceTab);
  });
  document.querySelectorAll("[data-finance-panel]").forEach(panel => {
    panel.hidden = panel.dataset.financePanel !== selectedFinanceTab;
  });
}

function nextDirectDebitOccurrence(debit) {
  const today = new Date().toISOString().slice(0, 10);
  const horizon = new Date();
  horizon.setFullYear(horizon.getFullYear() + 3);
  return directDebitOccurrences(debit, today, horizon.toISOString().slice(0, 10))[0] || null;
}

function renderDirectDebits() {
  const list = $("#direct-debit-list");
  if (!list) return;
  $("#direct-debit-count").textContent = `${directDebits.length} ${directDebits.length === 1 ? "REGISTO" : "REGISTOS"}`;
  $("#direct-debit-work").innerHTML = `<option value="">Geral da empresa</option>${works.map(work => `<option value="${work.id}">Obra ${escapeHtml(work.numero)} — ${escapeHtml(work.nome)}</option>`).join("")}`;
  const startField = $("#direct-debit-form")?.elements?.data_inicio;
  if (startField && !startField.value) startField.value = new Date().toISOString().slice(0, 10);
  if (!directDebits.length) {
    list.innerHTML = `<div class="finance-empty">AINDA NÃO EXISTEM DÉBITOS DIRETOS</div>`;
    return;
  }
  list.innerHTML = [...directDebits].sort((a, b) => String(a.descricao).localeCompare(String(b.descricao), "pt")).map(debit => {
    const work = works.find(item => item.id === debit.obra_id);
    const entries = directDebitEntries.filter(entry => entry.debito_direto_id === debit.id)
      .sort((a, b) => String(b.data).localeCompare(String(a.data)));
    const next = nextDirectDebitOccurrence(debit);
    const expanded = expandedDirectDebitId === debit.id;
    return `<article class="direct-debit-card ${debit.ativo ? "active" : "inactive"}">
      <div class="direct-debit-main">
        <div><span class="direct-debit-category">${escapeHtml(DIRECT_DEBIT_CATEGORY_LABELS[debit.categoria] || debit.categoria || "Outro")}</span><h3>${escapeHtml(debit.descricao)}</h3><p>${work ? `OBRA ${escapeHtml(work.numero)} · ${escapeHtml(work.nome)}` : "GERAL DA EMPRESA"}</p></div>
        <dl><div><dt>VALOR PREVISTO</dt><dd>${euro.format(Number(debit.valor_previsto || 0))}</dd></div><div><dt>RECORRÊNCIA</dt><dd>${escapeHtml(DIRECT_DEBIT_RECURRENCE_LABELS[debit.recorrencia] || "Sem recorrência")}</dd></div><div><dt>PRÓXIMA PREVISÃO</dt><dd>${next ? formatOptionalDate(next.data) : "—"}</dd></div></dl>
        <span class="direct-debit-status ${debit.ativo ? "active" : "inactive"}">${debit.ativo ? "ATIVO" : "INATIVO"}</span>
        <button type="button" class="outline-action" data-toggle-direct-debit="${debit.id}">${expanded ? "FECHAR" : "REGISTAR LANÇAMENTO"}</button>
      </div>
      <div class="direct-debit-entry-area" ${expanded ? "" : "hidden"}>
        <form data-direct-debit-entry="${debit.id}">
          <label>DATA<input name="data" type="date" value="${new Date().toISOString().slice(0, 10)}" required></label>
          <label>VALOR REAL (€)<input name="valor" type="number" min="0.01" step="0.01" value="${Number(debit.valor_previsto || 0).toFixed(2)}" required></label>
          <button class="primary-button" type="submit">REGISTAR VALOR REAL <span>→</span></button>
          <p class="form-error"></p>
        </form>
        <div class="direct-debit-entry-history"><strong>ÚLTIMOS LANÇAMENTOS</strong>${entries.length ? entries.slice(0, 6).map(entry => `<span><time>${formatOptionalDate(entry.data)}</time><b>${euro.format(Number(entry.valor || 0))}</b></span>`).join("") : "<small>Sem lançamentos reais registados.</small>"}</div>
      </div>
    </article>`;
  }).join("");
}

async function loadData() {
  if (isSupabaseConfigured && !getSession()) return;
  await loadAccessContext();
  if (!isSupabaseConfigured) {
    works = demoWorks; suppliers = demoSuppliers; subcontracts = demoSubcontracts;
    invoices = demoInvoices.filter(invoice => invoice.estado_aprovacao === "pendente");
    financeInvoices = demoInvoices.filter(invoice => invoice.estado_aprovacao === "aprovado")
      .map(invoice => ({ ...invoice, condicao_pagamento: invoice.condicao_pagamento || "imediato", estado_pagamento: invoice.estado_pagamento || (invoice.data_pagamento ? "pago" : "por_pagar") }));
    invoiceGuides = [];
    invoiceAttachments = [];
    directDebits = [];
    directDebitEntries = [];
  } else {
    const results = await Promise.all([
      supabase("obras?select=id,numero,nome,cliente,morada,tipo,modalidade,situacao,data_inicio,data_fim_prevista,diretor_obra_id,planeamento_baseline_congelado,planeamento_baseline_congelado_em&order=numero.desc"),
      supabase("fornecedores?select=id,nome&order=nome"),
      supabase("subempreitadas?select=id,obra_id,fornecedor_id,especialidade,valor_adjudicado,estado,tipo_pagamento,fase_id&order=especialidade"),
      supabase("faturas?select=*&estado_aprovacao=eq.pendente&order=criado_em.desc"),
      supabase("faturas?select=*&estado_aprovacao=eq.aprovado&order=data_aprovacao.desc"),
      supabase("faturas_guias?select=id,fatura_id,arquivo_url,nome_arquivo,mime_type,criado_em&order=criado_em.asc"),
      supabase("faturas_anexos?select=*&order=criado_em.asc"),
    ]);
    const failed = results.find(result => !result.ok);
    if (failed) { toast(`Não foi possível carregar os dados: ${await failed.text()}`, "error"); return; }
    [works, suppliers, subcontracts, invoices, financeInvoices, invoiceGuides, invoiceAttachments] = await Promise.all(results.map(result => result.json()));
    if (allowedViews().has("finance")) {
      const [debitsResult, entriesResult] = await Promise.all([
        supabase("debitos_diretos?select=id,obra_id,descricao,categoria,valor_previsto,recorrencia,dia_mes,data_inicio,data_fim,ativo,criado_por,criado_em&order=descricao"),
        supabase("debitos_diretos_lancamentos?select=id,debito_direto_id,data,valor,criado_em&order=data.desc"),
      ]);
      if (!debitsResult.ok || !entriesResult.ok) {
        toast(`Débitos diretos indisponíveis: ${await (!debitsResult.ok ? debitsResult : entriesResult).text()}`, "error");
        directDebits = [];
        directDebitEntries = [];
      } else {
        [directDebits, directDebitEntries] = await Promise.all([debitsResult.json(), entriesResult.json()]);
      }
    } else {
      directDebits = [];
      directDebitEntries = [];
    }
    if (hasFullAccess() || isAdministrative()) {
      const collaboratorsResult = await supabase("colaboradores?select=id,nome,funcao,nivel,data_nascimento,data_admissao,permite_multiplas_obras&data_saida=is.null&order=nome");
      collaborators = collaboratorsResult.ok ? await collaboratorsResult.json() : [];
    } else collaborators = [];
  }
  renderSelectors(); renderInvoices(); renderFinance();
  renderWorks();
  renderWorkDirectors();
  await productionDashboard.refreshOverview();
  if (effectiveRole() === "encarregado" && activeView === "overview") switchView("action-plan");
}

function renderWorkDirectors() {
  const select = $("#work-form")?.diretor_obra_id;
  if (!select) return;
  select.innerHTML = `<option value="">Não definido</option>${collaborators.map(person => `<option value="${person.id}">${person.nome}${person.funcao ? ` — ${person.funcao}` : ""}</option>`).join("")}`;
}

function renderWorkTemplates() {
  const select = $("#work-form")?.modelo_obra_id;
  if (!select) return;
  const selected = select.value;
  select.innerHTML = `<option value="">Começar sem modelo</option>${[...works]
    .sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true }))
    .map(work => `<option value="${work.id}">Obra ${escapeHtml(work.numero)} — ${escapeHtml(work.nome)}</option>`).join("")}`;
  select.value = selected;
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
  const role = String(person?.funcao || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("pt-PT");
  if (role.includes("encarregado")) return "foreman";
  if (role.includes("pedreiro")) return "mason";
  if (role.includes("servente")) return "helper";
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

function isWorkforceForeman(person) {
  return person?.permite_multiplas_obras === true || workforceRoleClass(person) === "foreman";
}

function workforceAllocationType(allocation) {
  return ["garantia", "pontual"].includes(allocation?.tipo_alocacao) ? allocation.tipo_alocacao : "obra";
}

function workforceRowKey(allocation) {
  const type = workforceAllocationType(allocation);
  if (type === "obra") return allocation?.obra_id ? `obra:${allocation.obra_id}` : "";
  const description = String(allocation?.descricao_livre || "").trim();
  return description ? `${type}:${description.toLocaleLowerCase("pt-PT")}` : "";
}

function workforceRows(activeWorks, allocations) {
  const realWorkIds = new Set(activeWorks.map(work => work.id));
  allocations.filter(item => workforceAllocationType(item) === "obra" && item.obra_id)
    .forEach(item => realWorkIds.add(item.obra_id));
  pendingWorkforceRows.filter(row => row.type === "obra" && row.workId)
    .forEach(row => realWorkIds.add(row.workId));

  const realRows = [...realWorkIds].map(workId => works.find(work => work.id === workId)).filter(Boolean)
    .sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true, sensitivity: "base" }))
    .map(work => ({ key: `obra:${work.id}`, type: "obra", workId: work.id, description: "", work }));

  const customRows = new Map();
  allocations.filter(item => workforceAllocationType(item) !== "obra").forEach(item => {
    const key = workforceRowKey(item);
    if (key && !customRows.has(key)) customRows.set(key, {
      key,
      type: workforceAllocationType(item),
      workId: "",
      description: String(item.descricao_livre || "").trim(),
      work: null,
    });
  });
  pendingWorkforceRows.filter(row => row.type !== "obra").forEach(row => {
    const key = workforceRowKey({ tipo_alocacao: row.type, descricao_livre: row.description });
    if (key && !customRows.has(key)) customRows.set(key, { key, ...row, workId: "", work: null });
  });
  return [...realRows, ...[...customRows.values()].sort((a, b) =>
    a.type.localeCompare(b.type, "pt-PT") || a.description.localeCompare(b.description, "pt-PT"))];
}

function renderWorkforceLineEditor() {
  const select = $("#workforce-line-work");
  if (!select) return;
  select.innerHTML = [...works].sort((a, b) =>
    String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true }))
    .map(work => `<option value="${work.id}">OBRA ${safeText(work.numero || "—")} · ${safeText(work.nome || "Sem designação")}</option>`)
    .join("");
}

function renderWorkforceMagnet(person, allocation = null) {
  const period = allocation?.periodo || "";
  const periodLabel = period === "manha" ? "M" : period === "tarde" ? "T" : "";
  const samePerson = selectedWorkforcePersonId === person.id;
  const selected = samePerson
    && (!allocation || (selectedWorkforceSourceDate === allocation.data
      && selectedWorkforceSourcePeriod === period
      && selectedWorkforceSourceRowKey === (allocation.row_key || "")));
  return `<button type="button" class="workforce-magnet ${workforceRoleClass(person)} ${samePerson && allocation ? "selected-position" : ""} ${selected ? "selected" : ""}" data-workforce-person="${person.id}" data-source-date="${allocation?.data || ""}" data-source-period="${period}" data-source-row-key="${safeText(allocation?.row_key || "")}" data-source-ids="${safeText((allocation?.ids || []).join(","))}" title="${shortPersonName(person.nome)} · ${period ? period.replace("_", " ") : "Disponível"}"><b>${workforceInitials(person.nome)}</b>${periodLabel ? `<em>${periodLabel}</em>` : ""}</button>`;
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
        const rowKey = workforceRowKey(event);
        if (!rowKey) return;
        const entry = grouped.get(rowKey) || {
          person,
          slots: [],
          sourceEvents: [],
          obra_id: event.obra_id || null,
          tipo_alocacao: workforceAllocationType(event),
          descricao_livre: event.descricao_livre || null,
        };
        entry.slots.push(slot);
        entry.sourceEvents.push(event);
        grouped.set(rowKey, entry);
      });
    });
    grouped.forEach((entry, rowKey) => {
      const sameSource = entry.sourceEvents.length === 2 && entry.sourceEvents[0].id === entry.sourceEvents[1].id;
      result.push({
        row_key: rowKey,
        obra_id: entry.obra_id,
        tipo_alocacao: entry.tipo_alocacao,
        descricao_livre: entry.descricao_livre,
        person: entry.person,
        slots: entry.slots,
        allocation: {
          data: sameSource || entry.sourceEvents.length === 1 ? entry.sourceEvents[0].data : "",
          periodo: entry.slots.length === 2 ? "dia_inteiro" : entry.slots[0],
          row_key: rowKey,
          ids: [...new Set(entry.sourceEvents.map(event => event.id).filter(Boolean))],
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

function entityDocuments(entityType, entityId) {
  return teamData.entityDocuments.filter(item => item.entidade_tipo === entityType && item.entidade_id === entityId);
}

function documentValidity(documentItem) {
  if (!documentItem.data_validade) return { state: "neutral", label: "SEM VALIDADE" };
  const today = new Date(`${new Date().toISOString().slice(0, 10)}T12:00:00`);
  const expiry = new Date(`${documentItem.data_validade}T12:00:00`);
  const days = Math.ceil((expiry - today) / 86400000);
  if (days < 0) return { state: "expired", label: `VENCIDO HÁ ${Math.abs(days)} DIA${Math.abs(days) === 1 ? "" : "S"}` };
  if (days <= 30) return { state: "warning", label: days === 0 ? "VENCE HOJE" : `VENCE EM ${days} DIA${days === 1 ? "" : "S"}` };
  return { state: "valid", label: `VÁLIDO ATÉ ${formatOptionalDate(documentItem.data_validade)}` };
}

function renderVehicleDeadline(label, date) {
  const validity = documentValidity({ data_validade: date });
  return `<div class="vehicle-deadline"><span>${label}</span><strong>${formatOptionalDate(date)}</strong><em class="${validity.state}">${date ? validity.label : "SEM DATA"}</em></div>`;
}

function renderVehicleEditForm(vehicle) {
  const peopleOptions = collaborators.map(person => `<option value="${person.id}" ${person.id === vehicle.colaborador_atribuido_id ? "selected" : ""}>${safeText(person.nome)}</option>`).join("");
  return `<form class="vehicle-edit-form" data-vehicle-edit-form data-vehicle-id="${vehicle.id}">
    <div class="vehicle-edit-title"><span>ATUALIZAR FROTA</span><strong>${safeText(vehicle.marca_modelo)} · ${safeText(vehicle.matricula)}</strong></div>
    <label>ATRIBUÍDA A<select name="colaborador_atribuido_id"><option value="">Sem atribuição</option>${peopleOptions}</select></label>
    <label>SEGURO ATÉ<input name="seguro_data" type="date" value="${vehicle.seguro_data || ""}"></label>
    <label>PRÓXIMA INSPEÇÃO<input name="data_inspecao_proxima" type="date" value="${vehicle.data_inspecao_proxima || ""}"></label>
    <label>ÚLTIMA REVISÃO<input name="data_revisao" type="date" value="${vehicle.data_revisao || ""}"></label>
    <label>PRÓXIMA REVISÃO<input name="data_proxima_revisao" type="date" value="${vehicle.data_proxima_revisao || ""}"></label>
    <div class="vehicle-edit-actions"><button type="submit">GUARDAR</button><button type="button" data-cancel-vehicle-edit>CANCELAR</button></div>
    <p class="form-error"></p>
  </form>`;
}

function renderEntityDocuments(entityType, entity) {
  const documents = entityDocuments(entityType, entity.id);
  const title = entityType === "colaborador" ? entity.nome : `${entity.marca_modelo || "Viatura"} · ${entity.matricula || "sem matrícula"}`;
  const suggestions = ["certificado", "contrato_trabalho", "seguro", "cartao_cidadao", "carta_conducao", "ficha_aptidao", "outro"];
  return `<section class="entity-documents-panel" data-entity-documents-panel>
    <header><div><span>ARQUIVO PRIVADO</span><h3>DOCUMENTOS · ${safeText(title)}</h3></div><button type="button" data-close-entity-documents>FECHAR ×</button></header>
    <div class="entity-document-list">${documents.length ? documents.map(documentItem => {
      const validity = documentValidity(documentItem);
      return `<article class="entity-document-row">
        <span class="entity-document-icon">DOC</span>
        <div><strong>${safeText(documentItem.nome_arquivo || "Documento")}</strong><small>${safeText(String(documentItem.tipo_documento || "outro").replace(/_/g, " "))}</small></div>
        <div><span>EMISSÃO</span><strong>${formatOptionalDate(documentItem.data_emissao)}</strong></div>
        <em class="${validity.state}">${validity.label}</em>
        <button type="button" data-entity-document-download="${encodeURIComponent(documentItem.url_arquivo || "")}" data-document-name="${safeText(documentItem.nome_arquivo || "documento")}">DESCARREGAR</button>
      </article>`;
    }).join("") : `<div class="work-document-empty">AINDA NÃO EXISTEM DOCUMENTOS ASSOCIADOS</div>`}</div>
    <form class="entity-document-upload" data-entity-document-upload data-entity-type="${entityType}" data-entity-id="${entity.id}">
      <div class="entity-document-file"><span>FICHEIRO</span><input name="arquivo" type="file" accept=".pdf,.jpg,.jpeg,.png,.webp,.heic,.xls,.xlsx,.csv,.doc,.docx" required></div>
      <label>TIPO DE DOCUMENTO<input name="tipo_documento" list="document-types-${entity.id}" maxlength="80" placeholder="Ex.: certificado" required><datalist id="document-types-${entity.id}">${suggestions.map(item => `<option value="${item}">`).join("")}</datalist></label>
      <label>DATA DE EMISSÃO<input name="data_emissao" type="date"></label>
      <label>DATA DE VALIDADE<input name="data_validade" type="date"></label>
      <button type="submit">ANEXAR DOCUMENTO</button>
      <p class="form-error"></p>
    </form>
  </section>`;
}

function renderTeam() {
  renderWorkforceLineEditor();
  const workforceSearch = ($("#team-search")?.value || "").trim().toLocaleLowerCase("pt-PT");
  const directorySearch = ($("#team-directory-search")?.value || "").trim().toLocaleLowerCase("pt-PT");
  const workById = new Map(works.map(work => [work.id, work]));
  const personById = new Map(collaborators.map(person => [person.id, person]));
  const activeAbsences = teamData.absences.filter(item => personById.has(item.colaborador_id));
  const activeContracts = teamData.contracts.filter(item => personById.has(item.colaborador_id));
  const activeOvertime = teamData.overtime.filter(item => personById.has(item.colaborador_id));
  const activeMedicine = teamData.medicine.filter(item => personById.has(item.colaborador_id));
  const operationalPeople = collaborators.filter(person => workforceRoleClass(person)).sort(compareWorkforcePeople);
  const boardWeeks = [-7, 0, 7, 14].map(offset => addDaysIso(selectedTeamWeek, offset));
  const allocations = teamData.allocations.filter(item => personById.has(item.colaborador_id) && workforceRoleClass(personById.get(item.colaborador_id)));
  const currentAllocations = allocations.filter(item => item.data >= selectedTeamWeek && item.data <= addDaysIso(selectedTeamWeek, 6));
  const currentAllocatedIds = new Set(currentAllocations.map(item => item.colaborador_id));
  const currentAbsences = activeAbsences.filter(item => item.data >= selectedTeamWeek && item.data <= addDaysIso(selectedTeamWeek, 6));
  const absentIds = new Set(currentAbsences.map(item => item.colaborador_id));
  const activeWorks = works
    .filter(work => !["concluida", "concluído", "concluido", "cancelada"].includes((work.situacao || "").toLocaleLowerCase("pt-PT")))
    .sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true, sensitivity: "base" }));
  const boardRows = workforceRows(activeWorks, allocations);
  const unallocated = collaborators.filter(person => !currentAllocatedIds.has(person.id));
  const pendingHours = activeOvertime.reduce((total, item) => total + Number(item.horas || 0), 0);
  const todayIso = new Date().toISOString().slice(0, 10);
  const currentMonth = Number(todayIso.slice(5, 7));
  const birthdayPeople = collaborators.filter(person => person.data_nascimento && Number(person.data_nascimento.slice(5, 7)) === currentMonth);
  const medicineDue = activeMedicine.filter(item => {
    if (!item.data_proxima_consulta) return false;
    const days = Math.ceil((new Date(`${item.data_proxima_consulta}T12:00:00`) - new Date(`${todayIso}T12:00:00`)) / 86400000);
    return days <= 30;
  });

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
    const boardHead = `<div class="workforce-grid workforce-grid-head"><div>LINHA / OBRA E RESPONSÁVEIS</div>${boardWeeks.map((week, index) => {
      const vacationPeople = operationalPeople.filter(person => activeAbsences.some(absence => absence.colaborador_id === person.id && isVacation(absence) && absence.data >= week && absence.data <= addDaysIso(week, 4)));
      return `<div><strong>${weekLabels[index]}</strong><span>${prettyDate.format(new Date(`${week}T12:00:00`))} — ${prettyDate.format(new Date(`${addDaysIso(week, 4)}T12:00:00`))}</span><div class="workforce-vacation-box" data-vacation-week="${week}" title="Selecione um íman e clique aqui para editar os dias de férias"><b>FÉRIAS</b><span>${vacationPeople.length ? vacationPeople.map(person => `<i title="${shortPersonName(person.nome)}">${workforceInitials(person.nome)}</i>`).join("") : "—"}</span></div><div class="workforce-day-labels">${weekdays.map((day, dayIndex) => `<b>${day}<small>${addDaysIso(week, dayIndex).slice(8)}</small></b>`).join("")}</div></div>`;
    }).join("")}</div>`;
    const rows = boardRows.map(row => {
      const work = row.work;
      const rowAllocations = allocations.filter(item => workforceRowKey(item) === row.key);
      const rowSearchText = row.type === "obra"
        ? `${work?.numero || ""} ${work?.nome || ""}`
        : `${row.type} ${row.description}`;
      const matchesSearch = rowAllocations.some(item => `${personById.get(item.colaborador_id)?.nome || ""}`.toLocaleLowerCase("pt-PT").includes(workforceSearch))
        || rowSearchText.toLocaleLowerCase("pt-PT").includes(workforceSearch);
      if (workforceSearch && !matchesSearch) return "";
      const fixed = work ? fixedWorkTeam(work) : [];
      const rowHeading = row.type === "obra"
        ? `<span>OBRA ${safeText(work?.numero || "—")}</span><strong title="${safeText(work?.nome || "Sem designação")}">${safeText(compactWorkName(work?.nome || "Sem designação"))}</strong><div class="fixed-work-team">${fixed.length ? fixed.map(person => `<small><b>${person.label}</b>${safeText(shortPersonName(person.name))}</small>`).join("") : "<small>Responsáveis não definidos</small>"}</div>`
        : `<span class="workforce-line-type ${row.type}">${row.type.toUpperCase()}</span>${workforceEditing
          ? `<input class="workforce-custom-name" value="${safeText(row.description)}" maxlength="120" data-workforce-rename data-row-type="${row.type}" data-old-description="${encodeURIComponent(row.description)}" aria-label="Nome da linha ${row.type}">`
          : `<strong title="${safeText(row.description)}">${safeText(row.description)}</strong>`}<div class="fixed-work-team"><small>SEM OBRA FORMAL ASSOCIADA</small></div>`;
      return `<article class="workforce-grid team-work-row">
        <div class="team-work-name">${rowHeading}</div>
        ${boardWeeks.map((week, weekIndex) => {
          let previousSignature = "";
          let previousEffective = [];
          return `<div class="workforce-week-cell ${weekIndex === 1 ? "current" : ""}">${weekdays.map((day, dayIndex) => {
            const date = addDaysIso(week, dayIndex);
            const allExact = effectiveWorkforceForDate(allocations, date, personById);
            const exact = allExact.filter(item => item.row_key === row.key);
            const carried = previousEffective.map(previous => {
              const reassignedSlots = allExact.filter(item => item.person.id === previous.person.id && item.row_key !== row.key).flatMap(item => item.slots);
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
            return `<div class="workforce-day-cell ${!effective.length ? "empty-day" : unchanged ? "unchanged-day" : "changed-day"}" data-workforce-cell data-work-id="${row.workId || ""}" data-allocation-type="${row.type}" data-description="${encodeURIComponent(row.description || "")}" data-date="${date}">${content}</div>`;
          }).join("")}</div>`;
        }).join("")}
      </article>`;
    }).join("");
    $("#team-board").innerHTML = `${boardHead}${rows || `<div class="empty-state"><strong>SEM RESULTADOS</strong><span>Ajuste a pesquisa.</span></div>`}`;
    $("#workforce-roster").innerHTML = `<div class="roster-intro"><strong>ÍMANES DISPONÍVEIS</strong><span>Selecione uma pessoa e depois o dia/obra.</span></div><div class="roster-magnets">${operationalPeople.map(person => renderWorkforceMagnet(person)).join("")}</div><label class="roster-period">PERÍODO<select data-workforce-period><option value="dia_inteiro" ${selectedWorkforcePeriod === "dia_inteiro" ? "selected" : ""}>Dia inteiro</option><option value="manha" ${selectedWorkforcePeriod === "manha" ? "selected" : ""}>Manhã</option><option value="tarde" ${selectedWorkforcePeriod === "tarde" ? "selected" : ""}>Tarde</option></select></label>${selectedWorkforceSourceDate ? '<button class="roster-remove" type="button" data-remove-workforce>RETIRAR ALOCAÇÃO</button>' : ""}`;
  }

  const absenceTypeLabels = {
    ferias: "Férias", falta_injustificada: "Falta injustificada",
    falta_justificada_sem_remuneracao: "Falta justificada sem remuneração",
    falta_justificada_com_remuneracao: "Falta justificada com remuneração",
  };
  const absenceStateLabels = { ausente_pendente: "Justificação pendente", justificada: "Justificada", confirmada: "Confirmada" };
  const absences = [...currentAbsences].sort((a, b) => String(a.data).localeCompare(String(b.data)));
  const absenceForm = canManageTeam() ? `<form class="absence-entry-form" id="absence-entry-form">
    <div><label>COLABORADOR<select name="colaborador_id" required><option value="">Selecionar colaborador</option>${collaborators.map(person => `<option value="${person.id}">${safeText(person.nome)}</option>`).join("")}</select></label>
    <label>TIPO<select name="tipo" required><option value="ferias">Férias</option><option value="falta_injustificada">Falta injustificada</option><option value="falta_justificada_sem_remuneracao">Falta justificada sem remuneração</option><option value="falta_justificada_com_remuneracao">Falta justificada com remuneração</option></select></label>
    <label>DATA<input name="data" type="date" value="${new Date().toISOString().slice(0, 10)}" required></label>
    <label>ANEXO OPCIONAL<input name="arquivo" type="file" accept=".pdf,.jpg,.jpeg,.png,.webp,.doc,.docx"></label></div>
    <button class="primary-button" type="submit">REGISTAR AUSÊNCIA <span>→</span></button><p class="form-error"></p>
  </form><details class="team-vacation-roster"><summary>EDIÇÃO SEMANAL DE FÉRIAS</summary><header><strong>REGISTAR / EDITAR VÁRIOS DIAS</strong><span>Selecione um colaborador para editar os dias úteis da semana.</span></header><div>${collaborators.map(person => `<button type="button" data-team-vacation-person="${person.id}"><span>${personInitials(person.nome)}</span><strong>${safeText(person.nome)}</strong></button>`).join("")}</div></details>` : `<div class="readonly-note">CONSULTA · AUSÊNCIAS DOS COLABORADORES DISTRIBUÍDOS PELAS SUAS OBRAS</div>`;
  const absenceRows = absences.length ? absences.map(item => {
    const person = personById.get(item.colaborador_id);
    const attachments = teamData.absenceAttachments.filter(file => file.ausencia_id === item.id);
    return `<article class="absence-card detailed">
      <time>${formatOptionalDate(item.data)}</time><div><strong>${safeText(person?.nome || "Colaborador")}</strong><span>${absenceTypeLabels[item.tipo] || String(item.tipo || "Ausência").replace(/_/g, " ")}</span>${item.comentario ? `<small>${safeText(item.comentario)}</small>` : ""}</div>
      <em class="absence-state ${item.estado || "confirmada"}">${absenceStateLabels[item.estado] || item.estado || "Confirmada"}</em>
      ${canManageTeam() ? `<div class="absence-attachments">${attachments.map(file => `<button type="button" data-absence-download="${encodeURIComponent(file.arquivo_url)}" data-file-name="${safeText(file.nome_arquivo)}">ANEXO · ${safeText(file.nome_arquivo)}</button>`).join("")}</div>` : ""}
      ${canManageTeam() && item.estado === "ausente_pendente" ? `<form class="absence-justify-form" data-justify-absence="${item.id}"><label>COMENTÁRIO DA JUSTIFICAÇÃO<textarea name="comentario" required placeholder="Indique a justificação recebida…"></textarea></label><label>COMPROVATIVO OPCIONAL<input name="arquivo" type="file" accept=".pdf,.jpg,.jpeg,.png,.webp,.doc,.docx"></label><button type="submit">MARCAR COMO JUSTIFICADA</button><p class="form-error"></p></form>` : ""}
    </article>`;
  }).join("") : `<div class="empty-state"><strong>SEM AUSÊNCIAS</strong><span>Não existem ausências registadas nesta semana.</span></div>`;
  $("#team-absences").innerHTML = `${absenceForm}${absenceRows}`;

  const contractByPerson = new Map(activeContracts.map(item => [item.colaborador_id, item]));
  const missingContracts = collaborators.filter(person => !contractByPerson.has(person.id));
  const missingContractIds = new Set(missingContracts.map(person => person.id));
  const hoursByPerson = new Map();
  activeOvertime.forEach(item => hoursByPerson.set(item.colaborador_id, (hoursByPerson.get(item.colaborador_id) || 0) + Number(item.horas || 0)));
  const visiblePeople = collaborators.filter(person => {
    const allocation = currentAllocations.find(item => item.colaborador_id === person.id);
    const work = workById.get(allocation?.obra_id);
    const matchesQuickFilter = teamQuickFilter === "missing_contract" ? missingContractIds.has(person.id)
      : teamQuickFilter === "birthday" ? birthdayPeople.some(item => item.id === person.id)
        : true;
    const matchesSearch = !directorySearch || `${person.nome} ${person.funcao || ""} ${person.nivel || ""} ${work?.numero || ""} ${work?.nome || ""} ${allocation?.descricao_livre || ""} ${allocation?.tipo_alocacao || ""}`.toLocaleLowerCase("pt-PT").includes(directorySearch);
    return matchesQuickFilter && matchesSearch;
  });
  $("#team-result-count").textContent = `${visiblePeople.length} COLABORADOR${visiblePeople.length === 1 ? "" : "ES"} · ${pendingHours.toLocaleString("pt-PT")} H EXTRA POR PAGAR`;
  $("#team-directory").innerHTML = visiblePeople.length ? visiblePeople.map(person => {
    const allocation = currentAllocations.find(item => item.colaborador_id === person.id);
    const work = workById.get(allocation?.obra_id);
    const contract = contractByPerson.get(person.id);
    const absence = currentAbsences.find(item => item.colaborador_id === person.id);
    const allocationLabel = workforceAllocationType(allocation) === "obra"
      ? work ? `Obra ${work.numero || "—"}` : "Sem alocação"
      : `${workforceAllocationType(allocation) === "garantia" ? "Garantia" : "Pontual"} · ${allocation?.descricao_livre || "Sem nome"}`;
    const documents = entityDocuments("colaborador", person.id);
    const documentsOpen = selectedTeamEntity?.type === "colaborador" && selectedTeamEntity.id === person.id;
    return `<article class="team-directory-row">
      <span class="team-avatar">${personInitials(person.nome)}</span>
      <div class="team-person-main"><strong>${person.nome}${birthdayPeople.some(item => item.id === person.id) ? ` <em class="birthday-badge">ANIVERSÁRIO · ${formatOptionalDate(person.data_nascimento).slice(0, 5)}</em>` : ""}</strong><span>${person.funcao || "Função não definida"}${person.nivel ? ` · ${person.nivel}` : ""}</span></div>
      <div><span>SITUAÇÃO SEMANAL</span><strong class="${absence ? "text-alert" : ""}">${absence ? String(absence.tipo).replace(/_/g, " ") : safeText(allocationLabel)}</strong></div>
      <div><span>CONTRATO</span><strong>${contract?.tipo_contrato ? String(contract.tipo_contrato).replace(/_/g, " ") : "Não registado"}</strong></div>
      <div><span>HORAS EXTRA</span><strong>${(hoursByPerson.get(person.id) || 0).toLocaleString("pt-PT")} h</strong></div>
      <button class="entity-documents-button ${documentsOpen ? "active" : ""}" type="button" data-open-entity-documents="colaborador" data-entity-id="${person.id}">DOCUMENTOS <b>${documents.length}</b></button>
    </article>${documentsOpen ? renderEntityDocuments("colaborador", person) : ""}`;
  }).join("") : `<div class="empty-state"><strong>SEM RESULTADOS</strong><span>Ajuste a pesquisa.</span></div>`;

  const endingContracts = activeContracts.filter(contract => contract.data_fim_prevista && contract.data_fim_prevista <= addDaysIso(new Date().toISOString().slice(0, 10), 30));
  $("#team-alert-summary").innerHTML = [
    endingContracts.length ? `<button type="button" data-team-alert-filter="ending_contract" data-team-alert-tab="contracts" class="attention ${teamQuickFilter === "ending_contract" ? "active" : ""}"><strong>${endingContracts.length}</strong><span>CONTRATO${endingContracts.length === 1 ? "" : "S"} A TERMINAR EM 30 DIAS<small>VER PESSOAS →</small></span></button>` : "",
    missingContracts.length ? `<button type="button" data-team-alert-filter="missing_contract" data-team-alert-tab="collaborators" class="pending ${teamQuickFilter === "missing_contract" ? "active" : ""}"><strong>${missingContracts.length}</strong><span>COLABORADOR${missingContracts.length === 1 ? "" : "ES"} SEM CONTRATO REGISTADO<small>VER PESSOAS →</small></span></button>` : "",
    absentIds.size ? `<button type="button" data-team-alert-filter="absent" data-team-alert-tab="absences" class="info ${teamQuickFilter === "absent" ? "active" : ""}"><strong>${absentIds.size}</strong><span>AUSENTE${absentIds.size === 1 ? "" : "S"} ESTA SEMANA<small>VER PESSOAS →</small></span></button>` : "",
    birthdayPeople.length ? `<button type="button" data-team-alert-filter="birthday" data-team-alert-tab="collaborators" class="info ${teamQuickFilter === "birthday" ? "active" : ""}"><strong>${birthdayPeople.length}</strong><span>ANIVERSÁRIO${birthdayPeople.length === 1 ? "" : "S"} ESTE MÊS<small>VER PESSOAS →</small></span></button>` : "",
    medicineDue.length ? `<button type="button" data-team-alert-filter="medicine_due" data-team-alert-tab="medicine" class="attention ${teamQuickFilter === "medicine_due" ? "active" : ""}"><strong>${medicineDue.length}</strong><span>CONSULTA${medicineDue.length === 1 ? "" : "S"} VENCIDA${medicineDue.length === 1 ? "" : "S"} OU A 30 DIAS<small>VER PESSOAS →</small></span></button>` : "",
    pendingHours ? `<button type="button" data-team-alert-filter="overtime" data-team-alert-tab="overtime" class="attention ${teamQuickFilter === "overtime" ? "active" : ""}"><strong>${pendingHours.toLocaleString("pt-PT")} h</strong><span>HORAS EXTRA POR PAGAR<small>VER PESSOAS →</small></span></button>` : "",
  ].filter(Boolean).join("") || `<article class="ok"><strong>✓</strong><span>SEM ALERTAS DE EQUIPA</span></article>`;

  $("#team-contract-count").textContent = teamQuickFilter === "ending_contract" ? `${endingContracts.length} A TERMINAR · ${activeContracts.length} ATIVOS` : `${activeContracts.length} CONTRATOS ATIVOS`;
  const visibleContracts = teamQuickFilter === "ending_contract" ? endingContracts : activeContracts;
  $("#team-contracts").innerHTML = visibleContracts.length ? visibleContracts.map(contract => {
    const person = personById.get(contract.colaborador_id);
    return `<article class="team-detail-row"><div><strong>${person?.nome || "Colaborador"}</strong><span>${String(contract.tipo_contrato || "Tipo não definido").replace(/_/g, " ")}</span></div><div><span>INÍCIO</span><strong>${formatOptionalDate(contract.data_inicio)}</strong></div><div><span>FIM PREVISTO</span><strong>${formatOptionalDate(contract.data_fim_prevista)}</strong></div><em>${contract.estado || "ativo"}</em></article>`;
  }).join("") : `<div class="empty-state"><strong>SEM CONTRATOS</strong><span>Não existem contratos ativos registados.</span></div>`;

  $("#team-overtime-count").textContent = `${pendingHours.toLocaleString("pt-PT")} H POR PAGAR`;
  $("#team-overtime").innerHTML = activeOvertime.length ? activeOvertime.map(item => {
    const person = personById.get(item.colaborador_id);
    const work = workById.get(item.obra_id);
    return `<article class="team-detail-row"><div><strong>${person?.nome || "Colaborador"}</strong><span>${work ? `Obra ${work.numero} · ${work.nome}` : "Sem obra associada"}</span></div><div><span>DATA</span><strong>${formatOptionalDate(item.data)}</strong></div><div><span>HORAS</span><strong>${Number(item.horas || 0).toLocaleString("pt-PT")} h</strong></div><em>POR PAGAR</em></article>`;
  }).join("") : `<div class="empty-state"><strong>SEM HORAS PENDENTES</strong><span>Não existem horas extraordinárias por pagar.</span></div>`;

  $("#team-medicine-count").textContent = teamQuickFilter === "medicine_due" ? `${medicineDue.length} A EXIGIR ATENÇÃO · ${activeMedicine.length} REGISTOS` : `${activeMedicine.length} REGISTO${activeMedicine.length === 1 ? "" : "S"}`;
  const visibleMedicine = teamQuickFilter === "medicine_due" ? medicineDue : activeMedicine;
  $("#team-medicine").innerHTML = visibleMedicine.length ? visibleMedicine.map(item => {
    const person = personById.get(item.colaborador_id);
    const validity = documentValidity({ data_validade: item.data_proxima_consulta });
    return `<article class="team-detail-row medicine-row">
      <div><strong>${safeText(person?.nome || "Colaborador não encontrado")}</strong><span>${safeText(item.resultado || "Resultado não indicado")}</span></div>
      <div><span>ÚLTIMA CONSULTA</span><strong>${formatOptionalDate(item.data_ultima_consulta)}</strong></div>
      <div><span>PRÓXIMA CONSULTA</span><strong>${formatOptionalDate(item.data_proxima_consulta)}</strong></div>
      <em class="${validity.state}">${validity.label}</em>
    </article>`;
  }).join("") : `<div class="empty-state"><strong>SEM REGISTOS</strong><span>Não existem consultas de medicina do trabalho registadas.</span></div>`;

  $("#team-vehicle-count").textContent = `${teamData.vehicles.length} VIATURA${teamData.vehicles.length === 1 ? "" : "S"}`;
  $("#team-vehicles").innerHTML = teamData.vehicles.length ? teamData.vehicles.map(vehicle => {
    const assigned = personById.get(vehicle.colaborador_atribuido_id);
    const documents = entityDocuments("viatura", vehicle.id);
    const documentsOpen = selectedTeamEntity?.type === "viatura" && selectedTeamEntity.id === vehicle.id;
    return `<article class="team-vehicle-row">
      <div class="team-vehicle-identity"><span>${vehicle.numero_interno != null ? `VIATURA ${vehicle.numero_interno}` : "VIATURA"}</span><strong>${safeText(vehicle.marca_modelo || "Modelo não indicado")}</strong><small>${safeText(vehicle.matricula || "Matrícula não indicada")}</small></div>
      <div><span>ATRIBUÍDA A</span><strong>${safeText(assigned?.nome || "Sem atribuição")}</strong></div>
      ${renderVehicleDeadline("SEGURO ATÉ", vehicle.seguro_data)}
      ${renderVehicleDeadline("PRÓXIMA INSPEÇÃO", vehicle.data_inspecao_proxima)}
      <div class="vehicle-revision"><span>REVISÃO</span><strong>Última: ${formatOptionalDate(vehicle.data_revisao)}</strong>${vehicle.data_proxima_revisao ? `<small>Próxima: ${formatOptionalDate(vehicle.data_proxima_revisao)}</small>` : "<small>Próxima não definida</small>"}</div>
      <div class="vehicle-row-actions">${canManageTeam() ? `<button class="vehicle-edit-button" type="button" data-edit-vehicle="${vehicle.id}">${selectedVehicleEditId === vehicle.id ? "A EDITAR" : "EDITAR"}</button>` : ""}<button class="entity-documents-button ${documentsOpen ? "active" : ""}" type="button" data-open-entity-documents="viatura" data-entity-id="${vehicle.id}">DOCUMENTOS <b>${documents.length}</b></button></div>
    </article>${selectedVehicleEditId === vehicle.id ? renderVehicleEditForm(vehicle) : ""}${documentsOpen ? renderEntityDocuments("viatura", vehicle) : ""}`;
  }).join("") : `<div class="empty-state"><strong>SEM VIATURAS</strong><span>Não existem viaturas registadas.</span></div>`;
}

function setWorkforceEditing(enabled) {
  workforceEditing = enabled;
  selectedWorkforcePersonId = "";
  selectedWorkforceSourceDate = "";
  selectedWorkforceSourcePeriod = "";
  selectedWorkforceSourceRowKey = "";
  selectedWorkforceSourceIds = [];
  $("#workforce-edit-banner").hidden = !enabled;
  $("#workforce-roster").hidden = !enabled;
  $("#workforce-new-line").hidden = true;
  $("#remove-workforce-allocation").hidden = true;
  $("#edit-workforce").textContent = enabled ? "A EDITAR…" : "EDITAR QUADRO";
  $("#edit-workforce").classList.toggle("active", enabled);
  $("#workforce-view").classList.toggle("editing", enabled);
  $("#workforce-edit-message").textContent = "Selecione um íman e depois clique no dia e obra de destino.";
  renderTeam();
}

function toggleWorkforceLineForm(show) {
  const formElement = $("#workforce-new-line");
  formElement.hidden = !show;
  if (!show) {
    $("#workforce-line-type").value = "obra";
    $("#workforce-line-description").value = "";
  }
  const custom = $("#workforce-line-type").value !== "obra";
  formElement.querySelector("[data-workforce-existing]").hidden = custom;
  formElement.querySelector("[data-workforce-free]").hidden = !custom;
  if (show) (custom ? $("#workforce-line-description") : $("#workforce-line-work")).focus();
}

function addWorkforceLine(type, workId, description) {
  const row = type === "obra"
    ? { type: "obra", workId, description: "" }
    : { type, workId: "", description: String(description || "").trim() };
  const key = workforceRowKey({ obra_id: row.workId, tipo_alocacao: row.type, descricao_livre: row.description });
  if (!key) return false;
  const activeWorks = works.filter(work => !["concluida", "concluído", "concluido", "cancelada"].includes((work.situacao || "").toLocaleLowerCase("pt-PT")));
  if (workforceRows(activeWorks, teamData.allocations).some(item => item.key === key)) return false;
  pendingWorkforceRows.push(row);
  return true;
}

async function renameWorkforceLine(type, oldDescription, newDescription) {
  const oldName = String(oldDescription || "").trim();
  const newName = String(newDescription || "").trim();
  if (!newName) {
    toast("O nome da linha é obrigatório.", "error");
    renderTeam();
    return;
  }
  if (oldName === newName) return;
  const newKey = workforceRowKey({ tipo_alocacao: type, descricao_livre: newName });
  const duplicate = workforceRows([], teamData.allocations).some(row =>
    row.key === newKey && row.description !== oldName);
  if (duplicate) {
    toast("Já existe uma linha deste tipo com esse nome.", "error");
    renderTeam();
    return;
  }

  pendingWorkforceRows = pendingWorkforceRows.map(row =>
    row.type === type && row.description === oldName ? { ...row, description: newName } : row);
  const persisted = teamData.allocations.some(item =>
    workforceAllocationType(item) === type && String(item.descricao_livre || "").trim() === oldName);
  if (!persisted || !isSupabaseConfigured) {
    teamData.allocations.forEach(item => {
      if (workforceAllocationType(item) === type && String(item.descricao_livre || "").trim() === oldName) item.descricao_livre = newName;
    });
    renderTeam();
    return;
  }

  const response = await supabase(`quadro_pessoal_alocacao?tipo_alocacao=eq.${encodeURIComponent(type)}&descricao_livre=eq.${encodeURIComponent(oldName)}`, {
    method: "PATCH",
    headers: { Prefer: "return=minimal" },
    body: JSON.stringify({ descricao_livre: newName }),
  });
  if (!response.ok) {
    toast(`Não foi possível alterar o nome da linha: ${await response.text()}`, "error");
    pendingWorkforceRows = pendingWorkforceRows.map(row =>
      row.type === type && row.description === newName ? { ...row, description: oldName } : row);
    renderTeam();
    return;
  }
  await loadTeamData(true);
  toast("Nome da linha atualizado.");
}

async function saveWorkforceAllocation(personId, date, target) {
  const person = collaborators.find(item => item.id === personId);
  if (!person) return;
  const type = ["garantia", "pontual"].includes(target?.type) ? target.type : "obra";
  const workId = type === "obra" ? target?.workId || null : null;
  const description = type === "obra" ? null : String(target?.description || "").trim();
  const targetKey = workforceRowKey({ obra_id: workId, tipo_alocacao: type, descricao_livre: description });
  if (!targetKey || (type !== "obra" && !description)) {
    toast("A linha de destino não está corretamente identificada.", "error");
    return;
  }
  const period = selectedWorkforcePeriod;
  const vacation = teamData.absences.find(item => item.colaborador_id === personId && item.data === date && isVacation(item));
  if (vacation) {
    toast(`${shortPersonName(person.nome)} está de férias em ${formatOptionalDate(date)} e não pode ser colocado no quadro.`, "error");
    return;
  }
  const dayAllocations = teamData.allocations.filter(item => item.colaborador_id === personId && item.data === date);
  const conflicting = dayAllocations.filter(item => period === "dia_inteiro" || item.periodo === "dia_inteiro" || item.periodo === period);
  const alreadyThere = conflicting.some(item => workforceRowKey(item) === targetKey && item.periodo === period);
  if (alreadyThere) {
    toast("O colaborador já se encontra nessa posição.");
    return;
  }
  const allowsMultipleWorks = isWorkforceForeman(person);
  if (!allowsMultipleWorks && period !== "dia_inteiro" && dayAllocations.some(item => item.periodo === "dia_inteiro")) {
    toast("Retire primeiro a alocação de dia inteiro antes de dividir o dia.", "error");
    return;
  }
  const currentUser = teamData.users.find(user => user.auth_user_id === session?.user?.id);
  $("#workforce-edit-message").textContent = `A guardar ${shortPersonName(person.nome)}…`;
  let response = null;
  if (!allowsMultipleWorks && period === "dia_inteiro" && dayAllocations.length) {
    response = await supabase(`quadro_pessoal_alocacao?colaborador_id=eq.${encodeURIComponent(personId)}&data=eq.${date}`, { method: "DELETE" });
    if (!response.ok) {
      toast(await friendlyApiError(response, "Não foi possível alterar o quadro."), "error");
      return;
    }
  } else if (!allowsMultipleWorks && conflicting.length) {
    response = await supabase(`quadro_pessoal_alocacao?colaborador_id=eq.${encodeURIComponent(personId)}&data=eq.${date}&periodo=eq.${period}`, {
      method: "PATCH",
      body: JSON.stringify({ obra_id: workId, tipo_alocacao: type, descricao_livre: description, criado_por: currentUser?.id || null }),
    });
    if (response.ok) {
      selectedWorkforceSourceDate = "";
      selectedWorkforceSourcePeriod = "";
      selectedWorkforceSourceRowKey = "";
      selectedWorkforceSourceIds = [];
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
      body: JSON.stringify({ colaborador_id: personId, obra_id: workId, tipo_alocacao: type, descricao_livre: description, semana_inicio: mondayIso(date), data: date, periodo: period, criado_por: currentUser?.id || null }),
    });
  }
  if (!response.ok) {
    toast(await friendlyApiError(response, "Não foi possível alterar o quadro."), "error");
    $("#workforce-edit-message").textContent = "A alteração falhou. Confirme as permissões e tente novamente.";
    return;
  }
  selectedWorkforceSourceDate = "";
  selectedWorkforceSourcePeriod = "";
  selectedWorkforceSourceRowKey = "";
  selectedWorkforceSourceIds = [];
  await loadTeamData(true);
  $("#remove-workforce-allocation").hidden = true;
  $("#workforce-edit-message").textContent = `${shortPersonName(person.nome)} continua selecionado. Clique nos próximos dias/obras.`;
  toast("Alocação adicionada. O íman continua selecionado.");
}

async function removeWorkforceAllocation() {
  if (!selectedWorkforcePersonId || !selectedWorkforceSourceDate || !selectedWorkforceSourcePeriod) return;
  const sourceIds = selectedWorkforceSourceIds.filter(Boolean);
  const query = sourceIds.length
    ? `quadro_pessoal_alocacao?id=in.(${sourceIds.map(encodeURIComponent).join(",")})`
    : `quadro_pessoal_alocacao?colaborador_id=eq.${encodeURIComponent(selectedWorkforcePersonId)}&data=eq.${selectedWorkforceSourceDate}&periodo=eq.${selectedWorkforceSourcePeriod}`;
  const response = await supabase(query, { method: "DELETE" });
  if (!response.ok) {
    toast(`Não foi possível retirar a alocação: ${await response.text()}`, "error");
  } else {
    selectedWorkforceSourceDate = "";
    selectedWorkforceSourcePeriod = "";
    selectedWorkforceSourceRowKey = "";
    selectedWorkforceSourceIds = [];
    $("#remove-workforce-allocation").hidden = true;
    await loadTeamData(true);
    toast("Alocação retirada.");
  }
}

function openVacationDaysDialog(personId, week) {
  const person = collaborators.find(item => item.id === personId);
  if (!person) return;
  const dates = Array.from({ length: 5 }, (_, index) => addDaysIso(week, index));
  const existing = new Set(teamData.absences.filter(item => item.colaborador_id === personId && isVacation(item)).map(item => item.data));
  const weekdayNames = ["SEGUNDA", "TERÇA", "QUARTA", "QUINTA", "SEXTA"];
  $("#workflow-dialog-title").textContent = "EDITAR FÉRIAS";
  $("#workflow-dialog-content").innerHTML = `<form id="workforce-vacation-form" data-person-id="${personId}" data-week="${week}">
    <p class="dialog-copy"><strong>${safeText(shortPersonName(person.nome))}</strong><br>Marque apenas os dias em que estará de férias.</p>
    <div class="vacation-days-picker">${dates.map((date, index) => `<label><input type="checkbox" name="vacation_date" value="${date}" ${existing.has(date) ? "checked" : ""}><span><b>${weekdayNames[index]}</b><small>${prettyDate.format(new Date(`${date}T12:00:00`))}</small></span></label>`).join("")}</div>
    <p class="vacation-help">Pode desmarcar dias já registados. Se não marcar nenhum, as férias desta semana serão removidas.</p>
    <p class="form-error"></p><div class="dialog-actions"><button class="outline-action" type="button" data-close-workflow>CANCELAR</button><button class="primary-button" type="submit">GUARDAR DIAS <span>→</span></button></div>
  </form>`;
  $("#workflow-dialog").hidden = false;
  $("#workforce-vacation-form").addEventListener("submit", saveVacationDays);
}

async function saveVacationDays(event) {
  event.preventDefault();
  const formElement = event.currentTarget;
  const personId = formElement.dataset.personId;
  const week = formElement.dataset.week;
  const person = collaborators.find(item => item.id === personId);
  const weekDates = Array.from({ length: 5 }, (_, index) => addDaysIso(week, index));
  const desired = new Set(new FormData(formElement).getAll("vacation_date"));
  const existingRows = teamData.absences.filter(item => item.colaborador_id === personId && isVacation(item) && weekDates.includes(item.data));
  const existingDates = new Set(existingRows.map(item => item.data));
  const missing = [...desired].filter(date => !existingDates.has(date));
  const removeIds = existingRows.filter(item => !desired.has(item.data)).map(item => item.id);
  const button = formElement.querySelector('button[type="submit"]');
  const errorElement = formElement.querySelector(".form-error");
  button.disabled = true;
  errorElement.textContent = "";
  try {
    if (isSupabaseConfigured && missing.length) {
      const response = await supabase("ausencias", {
        method: "POST",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify(missing.map(data => ({ colaborador_id: personId, data, tipo: "ferias" }))),
      });
      if (!response.ok) throw new Error(await response.text());
    }
    if (isSupabaseConfigured && removeIds.length) {
      const response = await supabase(`ausencias?id=in.(${removeIds.map(encodeURIComponent).join(",")})`, { method: "DELETE" });
      if (!response.ok) throw new Error(await response.text());
    }
    if (!isSupabaseConfigured) {
      teamData.absences = teamData.absences.filter(item => !removeIds.includes(item.id));
      teamData.absences.push(...missing.map(data => ({ id: crypto.randomUUID(), colaborador_id: personId, data, tipo: "ferias" })));
    } else {
      await loadTeamData(true);
    }
    closeWorkflowDialog();
    renderTeam();
    $("#workforce-edit-message").textContent = `${shortPersonName(person?.nome || "")} continua selecionado. Pode editar outra semana.`;
    toast(desired.size ? `${desired.size} dia${desired.size === 1 ? "" : "s"} de férias guardado${desired.size === 1 ? "" : "s"}.` : "Férias removidas desta semana.");
  } catch (error) {
    errorElement.textContent = `Não foi possível guardar as férias: ${error.message}`;
  } finally {
    button.disabled = false;
  }
}

async function loadTeamData(force = false) {
  if (!force && teamData.loadedWeek === selectedTeamWeek) return renderTeam();
  teamData = { allocations: [], absences: [], absenceAttachments: [], contracts: [], overtime: [], responsibles: [], users: [], vehicles: [], medicine: [], entityDocuments: [], loadedWeek: selectedTeamWeek, error: "" };
  $("#team-board").innerHTML = `<div class="empty-state">A CARREGAR O QUADRO…</div>`;
  if (!isSupabaseConfigured) return renderTeam();
  const boardStart = addDaysIso(selectedTeamWeek, -7);
  const boardEnd = addDaysIso(selectedTeamWeek, 20);
  const results = await Promise.all([
    supabase(`quadro_pessoal_alocacao?select=id,colaborador_id,obra_id,tipo_alocacao,descricao_livre,semana_inicio,data,periodo&semana_inicio=gte.${boardStart}&semana_inicio=lte.${addDaysIso(selectedTeamWeek, 14)}&order=data`),
    supabase(`ausencias?select=id,colaborador_id,data,tipo,estado,comentario&data=gte.${boardStart}&data=lte.${boardEnd}&order=data`),
    canManageTeam() ? supabase("ausencias_anexos?select=id,ausencia_id,arquivo_url,nome_arquivo,criado_em&order=criado_em.desc") : Promise.resolve(new Response("[]", { status: 200 })),
    canManageTeam() ? supabase("colaboradores_contratos?select=id,colaborador_id,tipo_contrato,data_inicio,data_fim_prevista,estado&estado=eq.ativo") : Promise.resolve(new Response("[]", { status: 200 })),
    canManageTeam() ? supabase("horas_extraordinarias?select=id,colaborador_id,obra_id,data,horas,estado_pagamento&estado_pagamento=eq.por_pagar") : Promise.resolve(new Response("[]", { status: 200 })),
    supabase("obra_responsaveis?select=obra_id,utilizador_id,papel"),
    supabase("utilizadores?select=id,nome,funcao,auth_user_id"),
    canManageTeam() ? supabase("viaturas?select=*&order=numero_interno.asc.nullslast,matricula.asc") : Promise.resolve(new Response("[]", { status: 200 })),
    canManageTeam() ? supabase("medicina_trabalho?select=id,colaborador_id,data_ultima_consulta,resultado,data_proxima_consulta,criado_em&order=data_proxima_consulta.asc.nullslast") : Promise.resolve(new Response("[]", { status: 200 })),
    canManageTeam() ? supabase("documentos?select=id,empresa_id,entidade_tipo,entidade_id,tipo_documento,nome_arquivo,url_arquivo,data_emissao,data_validade,criado_em&entidade_tipo=in.(colaborador,viatura)&order=criado_em.desc") : Promise.resolve(new Response("[]", { status: 200 })),
  ]);
  const names = ["alocações", "ausências", "anexos de ausências", "contratos", "horas extraordinárias", "responsáveis de obra", "utilizadores", "viaturas", "medicina do trabalho", "documentos de RH"];
  const payloads = await Promise.all(results.map(async (result, index) => result.ok ? result.json() : { failed: names[index], detail: await result.text() }));
  const failures = payloads.filter(payload => payload?.failed);
  [teamData.allocations, teamData.absences, teamData.absenceAttachments, teamData.contracts, teamData.overtime, teamData.responsibles, teamData.users, teamData.vehicles, teamData.medicine, teamData.entityDocuments] = payloads.map(payload => Array.isArray(payload) ? payload : []);
  const essentialFailures = failures.filter(item => ["alocações", "ausências"].includes(item.failed));
  if (essentialFailures.length) teamData.error = `Não foi possível ler ${essentialFailures.map(item => item.failed).join(", ")}. Confirme as políticas RLS do módulo Equipa.`;
  const documentFailures = failures.filter(item => ["anexos de ausências", "viaturas", "medicina do trabalho", "documentos de RH"].includes(item.failed));
  if (documentFailures.length) teamData.error = `${teamData.error ? `${teamData.error} ` : ""}Não foi possível ler ${documentFailures.map(item => item.failed).join(", ")}. Confirme as migrações de Equipa e documentos de RH.`;
  renderTeam();
}

async function saveAbsenceAttachment(absenceId, file) {
  if (!file) return null;
  if (!isSupabaseConfigured) {
    const localPath = `local:${crypto.randomUUID()}`;
    localEntityDocumentFiles.set(localPath, file);
    const attachment = { id: crypto.randomUUID(), ausencia_id: absenceId, arquivo_url: localPath, nome_arquivo: file.name, criado_em: new Date().toISOString() };
    teamData.absenceAttachments.unshift(attachment);
    return attachment;
  }
  const objectPath = await uploadEntityDocument(file, "ausencia", absenceId, "comprovativo");
  const response = await supabase("ausencias_anexos?select=id,ausencia_id,arquivo_url,nome_arquivo,criado_em", {
    method: "POST",
    headers: { Prefer: "return=representation" },
    body: JSON.stringify({ ausencia_id: absenceId, arquivo_url: objectPath, nome_arquivo: file.name }),
  });
  if (!response.ok) throw new Error(await friendlyApiError(response, "O ficheiro foi enviado, mas não foi possível associá-lo à ausência."));
  const [attachment] = await response.json();
  teamData.absenceAttachments.unshift(attachment);
  return attachment;
}

async function createAbsence(formElement) {
  const button = formElement.querySelector('button[type="submit"]');
  const errorNode = formElement.querySelector(".form-error");
  const file = formElement.elements.arquivo.files[0];
  const payload = {
    colaborador_id: formElement.elements.colaborador_id.value,
    tipo: formElement.elements.tipo.value,
    data: formElement.elements.data.value,
    estado: ["ferias", "falta_justificada_com_remuneracao"].includes(formElement.elements.tipo.value) ? "confirmada" : "ausente_pendente",
  };
  button.disabled = true;
  errorNode.textContent = "";
  try {
    let saved;
    if (isSupabaseConfigured) {
      const response = await supabase("ausencias?select=id,colaborador_id,data,tipo,estado,comentario", {
        method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload),
      });
      if (!response.ok) {
        const message = await friendlyApiError(response, "Não foi possível registar a ausência.");
        throw new Error(/duplicate key|ausencias_colaborador_id_data_key/i.test(message) ? "Já existe uma ausência para este colaborador nesta data." : message);
      }
      [saved] = await response.json();
    } else saved = { id: crypto.randomUUID(), ...payload, comentario: null };
    teamData.absences.push(saved);
    if (file) await saveAbsenceAttachment(saved.id, file);
    renderTeam();
    toast(file ? "Ausência e anexo registados." : "Ausência registada.");
  } catch (error) {
    errorNode.textContent = error.message || "Não foi possível registar a ausência.";
  } finally {
    button.disabled = false;
  }
}

async function justifyAbsence(formElement) {
  const absenceId = formElement.dataset.justifyAbsence;
  const absence = teamData.absences.find(item => item.id === absenceId);
  if (!absence) return;
  const button = formElement.querySelector('button[type="submit"]');
  const errorNode = formElement.querySelector(".form-error");
  const comment = formElement.elements.comentario.value.trim();
  const file = formElement.elements.arquivo.files[0];
  button.disabled = true;
  errorNode.textContent = "";
  try {
    if (isSupabaseConfigured) {
      const response = await supabase(`ausencias?id=eq.${encodeURIComponent(absenceId)}&select=id,colaborador_id,data,tipo,estado,comentario`, {
        method: "PATCH", headers: { Prefer: "return=representation" }, body: JSON.stringify({ estado: "justificada", comentario: comment }),
      });
      if (!response.ok) throw new Error(await friendlyApiError(response, "Não foi possível justificar a ausência."));
      Object.assign(absence, (await response.json())[0]);
    } else Object.assign(absence, { estado: "justificada", comentario: comment });
    if (file) await saveAbsenceAttachment(absenceId, file);
    renderTeam();
    toast("Ausência marcada como justificada.");
  } catch (error) {
    errorNode.textContent = error.message || "Não foi possível justificar a ausência.";
  } finally {
    button.disabled = false;
  }
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
  workDetails = {
    contract: null, investment: null, impacts: [], phases: [], measurements: [], payments: [], consultations: [],
    labor: [], siteExpenses: [], directDebits: [], directDebitEntries: [],
    billings: [], billingLinks: [], documents: [], workDocuments: [], documentUsers: {},
    drawings: [], rfis: [], safetyIncidents: [], safetyInspections: [], epis: [],
    safetyCollaborators: [], canEditDocuments: false, canEditSafety: false,
    error: "", procurementError: "", billingError: "", workDocumentsError: "",
    documentIndexesError: "", safetyError: "",
  };
  renderWorks();
  const work = works.find(item => item.id === workId);
  $("#work-detail").innerHTML = `<div class="empty-state">A CARREGAR DADOS DA OBRA…</div>`;
  if (!isSupabaseConfigured) {
    workDetails = {
      contract: { venda_contratual_inicial: 553619.19, venda_contratual_efetiva: 472179.26, custo_direto_efetivo: 355023.64, valor_adiantamento: 110723.84, data_assinatura: "2026-02-11" },
      investment: null, impacts: [], labor: [], siteExpenses: [], directDebits: [], directDebitEntries: [],
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
      workDocuments: [],
      documentUsers: {},
      drawings: [],
      rfis: [],
      safetyIncidents: [],
      safetyInspections: [],
      epis: [],
      safetyCollaborators: collaborators,
      canEditDocuments: true,
      canEditSafety: true,
      error: "",
      procurementError: "",
      billingError: "",
      workDocumentsError: "",
      documentIndexesError: "",
      safetyError: "",
    };
    renderWorkDetail(work);
    return;
  }
  const investmentMode = work?.modalidade === "investimento_proprio";
  const emptyResult = () => Promise.resolve(new Response(JSON.stringify([]), { status: 200, headers: { "Content-Type": "application/json" } }));
  const [contractResult, investmentResult, impactsResult, phasesResult, measurementsResult, laborResult, siteResult, directDebitsResult] = await Promise.all([
    investmentMode ? emptyResult() : supabase(`contratos?select=id,obra_id,venda_contratual_inicial,custo_direto_inicial,venda_contratual_efetiva,custo_direto_efetivo,valor_adiantamento,percentual_retencao_garantia,data_assinatura,atualizado_em&obra_id=eq.${encodeURIComponent(workId)}`),
    investmentMode ? supabase(`investimentos?select=*&obra_id=eq.${encodeURIComponent(workId)}`) : emptyResult(),
    investmentMode ? supabase(`impactos_obra?select=*&obra_id=eq.${encodeURIComponent(workId)}&order=data.desc`) : emptyResult(),
    supabase(`fases?select=*&obra_id=eq.${encodeURIComponent(workId)}`),
    investmentMode ? emptyResult() : supabase(`autos_medicao?select=id,obra_id,mes_referencia,numero_auto,tipo,data_medicao,estado,valor_bruto_medido,valor_retencao_garantia,valor_deduzido_adiantamento,valor_a_faturar&obra_id=eq.${encodeURIComponent(workId)}&order=mes_referencia.desc`),
    investmentMode ? supabase(`lancamentos_mao_obra?select=*&obra_id=eq.${encodeURIComponent(workId)}`) : emptyResult(),
    investmentMode ? supabase(`despesas_estaleiro?select=*&obra_id=eq.${encodeURIComponent(workId)}`) : emptyResult(),
    investmentMode ? supabase(`debitos_diretos?select=id,obra_id&obra_id=eq.${encodeURIComponent(workId)}`) : emptyResult(),
  ]);
  const detailErrors = [];
  if (contractResult.ok) workDetails.contract = selectCurrentContract(await contractResult.json());
  else detailErrors.push((await contractResult.json().catch(() => ({}))).message || "Contrato indisponível");
  if (investmentResult.ok) workDetails.investment = (await investmentResult.json())[0] || null;
  else detailErrors.push((await investmentResult.json().catch(() => ({}))).message || "Investimento indisponível");
  if (impactsResult.ok) workDetails.impacts = await impactsResult.json();
  else detailErrors.push((await impactsResult.json().catch(() => ({}))).message || "Impactos indisponíveis");
  if (phasesResult.ok) workDetails.phases = await phasesResult.json();
  else detailErrors.push((await phasesResult.json().catch(() => ({}))).message || "Fases indisponíveis");
  if (measurementsResult.ok) workDetails.measurements = await measurementsResult.json();
  else detailErrors.push((await measurementsResult.json().catch(() => ({}))).message || "Autos de medição indisponíveis");
  if (laborResult.ok) workDetails.labor = await laborResult.json();
  else detailErrors.push((await laborResult.json().catch(() => ({}))).message || "Mão de obra indisponível");
  if (siteResult.ok) workDetails.siteExpenses = await siteResult.json();
  else detailErrors.push((await siteResult.json().catch(() => ({}))).message || "Estaleiro indisponível");
  if (directDebitsResult.ok) {
    workDetails.directDebits = await directDebitsResult.json();
    if (workDetails.directDebits.length) {
      const directDebitIds = workDetails.directDebits.map(item => item.id);
      const entriesResult = await supabase(`debitos_diretos_lancamentos?select=id,debito_direto_id,data,valor&debito_direto_id=in.(${directDebitIds.map(encodeURIComponent).join(",")})`);
      if (entriesResult.ok) workDetails.directDebitEntries = await entriesResult.json();
      else detailErrors.push((await entriesResult.json().catch(() => ({}))).message || "Débitos diretos indisponíveis");
    }
  } else detailErrors.push((await directDebitsResult.json().catch(() => ({}))).message || "Débitos diretos indisponíveis");
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
  if (isFinancial()) {
    renderWorkDetail(work);
    return;
  }
  const securityRequests = [
    supabase(`seguranca_incidentes?select=*&obra_id=eq.${encodeURIComponent(workId)}&order=data.desc`),
    supabase(`seguranca_inspecoes?select=*&obra_id=eq.${encodeURIComponent(workId)}&order=data.desc`),
    supabase("colaboradores?select=id,nome,funcao&data_saida=is.null&order=nome"),
    supabase("rpc/fn_pode_editar_obra", { method: "POST", body: JSON.stringify({ p_obra_id: workId }) }),
  ];
  if (hasFullAccess() || isAdministrative()) {
    securityRequests.push(supabase("epis?select=*&order=data_validade.asc.nullslast,data_entrega.desc"));
  }
  const [workDocumentsResult, editPermissionResult, drawingsResult, rfisResult, ...securityResults] = await Promise.all([
    supabase(`documentos_obra?select=*&obra_id=eq.${encodeURIComponent(workId)}&order=criado_em.desc`),
    supabase("rpc/fn_pode_editar_documentos_obra", { method: "POST", body: JSON.stringify({ p_obra_id: workId }) }),
    supabase(`desenhos?select=*&obra_id=eq.${encodeURIComponent(workId)}&order=numero.asc,revisao.desc`),
    supabase(`rfis?select=*&obra_id=eq.${encodeURIComponent(workId)}&order=numero.asc`),
    ...securityRequests,
  ]);
  if (workDocumentsResult.ok) {
    workDetails.workDocuments = await workDocumentsResult.json();
    const userIds = [...new Set(workDetails.workDocuments.map(item => item.enviado_por).filter(Boolean))];
    if (userIds.length) {
      const usersResult = await supabase(`utilizadores?select=id,nome&id=in.(${userIds.map(encodeURIComponent).join(",")})`);
      if (usersResult.ok) {
        workDetails.documentUsers = Object.fromEntries((await usersResult.json()).map(user => [user.id, user.nome]));
      }
    }
  } else {
    const detail = await workDocumentsResult.json().catch(() => ({}));
    workDetails.workDocumentsError = detail.message || "Não foi possível consultar os documentos desta obra.";
  }
  if (editPermissionResult.ok) workDetails.canEditDocuments = Boolean(await editPermissionResult.json());
  if (drawingsResult.ok) workDetails.drawings = await drawingsResult.json();
  else workDetails.documentIndexesError = "Não foi possível consultar o índice de desenhos.";
  if (rfisResult.ok) workDetails.rfis = await rfisResult.json();
  else workDetails.documentIndexesError += `${workDetails.documentIndexesError ? " " : ""}Não foi possível consultar o índice de PDEs.`;
  const [incidentsResult, inspectionsResult, safetyPeopleResult, safetyPermissionResult, episResult] = securityResults;
  const safetyFailures = [];
  if (incidentsResult?.ok) workDetails.safetyIncidents = await incidentsResult.json();
  else safetyFailures.push("incidentes");
  if (inspectionsResult?.ok) workDetails.safetyInspections = await inspectionsResult.json();
  else safetyFailures.push("inspeções");
  if (safetyPeopleResult?.ok) {
    workDetails.safetyCollaborators = await safetyPeopleResult.json();
    const activeSafetyIds = new Set(workDetails.safetyCollaborators.map(person => person.id));
    workDetails.safetyIncidents = workDetails.safetyIncidents.filter(item => !item.colaborador_id || activeSafetyIds.has(item.colaborador_id));
    workDetails.safetyInspections = workDetails.safetyInspections.filter(item => !item.responsavel_id || activeSafetyIds.has(item.responsavel_id));
  }
  else safetyFailures.push("colaboradores");
  if (safetyPermissionResult?.ok) workDetails.canEditSafety = Boolean(await safetyPermissionResult.json());
  if (episResult?.ok) {
    const activeSafetyIds = new Set(workDetails.safetyCollaborators.map(person => person.id));
    workDetails.epis = (await episResult.json()).filter(item => activeSafetyIds.has(item.colaborador_id));
  }
  else if (hasFullAccess() || isAdministrative()) safetyFailures.push("EPI's");
  if (safetyFailures.length) workDetails.safetyError = `Não foi possível consultar: ${safetyFailures.join(", ")}.`;
  renderWorkDetail(work);
}

function renderWorkSummary(work) {
  const contract = workDetails.contract;
  const subcontractRows = subcontracts.filter(item => item.obra_id === work.id);
  const subcontractTotal = subcontractRows.reduce((sum, item) => sum + Number(item.valor_adjudicado || 0), 0);
  const measuredTotal = totalClientBilling(contract, workDetails.measurements);
  const progress = workProgress(work);
  const sale = Number(contract?.venda_contratual_efetiva || contract?.venda_contratual_inicial || 0);
  const investmentMode = work.modalidade === "investimento_proprio";
  const investment = workDetails.investment || {};
  const initialBudget = Number(investment.orcamento_inicial_sem_iva || 0);
  const revisedBudget = Number(investment.orcamento_revisto_sem_iva || investment.orcamento_inicial_sem_iva || 0);
  const directDebitIds = new Set(workDetails.directDebits.map(item => item.id));
  const actualCost = workDetails.payments.reduce((total, row) => total + Number(row.valor || 0), 0)
    + workDetails.labor.reduce((total, row) => total + Number(row.valor_total || Number(row.horas || 0) * Number(row.valor_hora || 0)), 0)
    + workDetails.siteExpenses.reduce((total, row) => total + Number(row.valor_total || 0), 0)
    + workDetails.directDebitEntries.filter(row => directDebitIds.has(row.debito_direto_id)).reduce((total, row) => total + Number(row.valor || 0), 0);
  const deviation = actualCost - revisedBudget;
  if (investmentMode) return `
    <div class="work-kpis">
      <div><span>ORÇAMENTO INICIAL</span><strong>${euro.format(initialBudget)}</strong><small>sem IVA</small></div>
      <div><span>ORÇAMENTO REVISTO</span><strong>${euro.format(revisedBudget)}</strong><small>sem IVA</small></div>
      <div><span>CUSTO REALIZADO</span><strong>${euro.format(actualCost)}</strong></div>
      <div><span>DESVIO</span><strong class="${deviation > 0 ? "negative" : "positive"}">${euro.format(deviation)}</strong></div>
    </div>
    <div class="work-timeline">
      <div><span>INÍCIO</span><strong>${formatOptionalDate(work.data_inicio)}</strong></div>
      <div class="timeline-progress"><span>PRAZO DECORRIDO</span><div><i style="width:${progress ?? 0}%"></i></div><strong>${progress === null ? "—" : `${progress}%`}</strong></div>
      <div><span>FIM PREVISTO</span><strong>${formatOptionalDate(work.data_fim_prevista)}</strong></div>
    </div>
    <div class="work-detail-grid">
      <section><div class="detail-section-title"><span>INVESTIMENTO</span></div>
        <dl>
          <div><dt>Orçamento inicial sem IVA</dt><dd>${euro.format(initialBudget)}</dd></div>
          <div><dt>Orçamento inicial com IVA</dt><dd>${euro.format(Number(investment.orcamento_inicial_com_iva || 0))}</dd></div>
          <div><dt>Orçamento revisto sem IVA</dt><dd>${euro.format(revisedBudget)}</dd></div>
          <div><dt>Orçamento revisto com IVA</dt><dd>${euro.format(Number(investment.orcamento_revisto_com_iva || 0))}</dd></div>
          <div><dt>Subempreitadas adjudicadas</dt><dd>${euro.format(subcontractTotal)}</dd></div>
          <div><dt>Desvio ao orçamento</dt><dd class="${deviation > 0 ? "negative" : "positive"}">${euro.format(deviation)}</dd></div>
        </dl>
        <details><summary>IMPACTOS DA OBRA <b>${workDetails.impacts.length}</b></summary><div class="meeting-detail-list">${workDetails.impacts.map(row => `<div><span><strong>${safeText(row.numero)} · ${safeText(row.descricao)}</strong><small>${safeText(row.tipo_impacto || "Impacto")}</small></span><b>${euro.format(Number(row.valor_sem_iva || 0))}</b></div>`).join("") || '<div class="work-document-empty">SEM IMPACTOS REGISTADOS</div>'}</div></details>
      </section>
      <section><div class="detail-section-title"><span>FASES</span><small>${workDetails.phases.length}</small></div>
        <div class="phase-tags">${workDetails.phases.length ? workDetails.phases.map(phase => `<span>${phase.codigo || phase.numero || "—"}<small>${phase.descricao || ""}</small></span>`).join("") : "<em>Sem fases disponíveis</em>"}</div>
      </section>
    </div>`;
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
    <div data-procurement-root></div>`;
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
      ${canEditWork() ? `<button class="outline-action" data-new-measurement type="button">＋ NOVO AUTO</button>` : ""}
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
            ${canEditWork() && item.estado === "rascunho" ? `<button data-measure-action="enviado_cliente" data-id="${item.id}">MARCAR ENVIADO</button>` : ""}
            ${canEditWork() && item.estado === "enviado_cliente" ? `<button data-measure-action="recusado_cliente" data-id="${item.id}">RECUSAR</button><button data-measure-action="aprovado_cliente" data-id="${item.id}">APROVAR</button>` : ""}
            ${canEditWork() && item.estado === "aprovado_cliente" && !billing ? `<button class="dark" data-new-billing="${item.id}">EMITIR FATURA</button>` : ""}
            ${canEditWork() && billing && !paid ? `<button class="dark" data-mark-paid="${billing.id}">MARCAR PAGO</button>` : ""}
          </div>
        </article>`;
      }).join("") : `<div class="empty-state"><strong>SEM AUTOS DE MEDIÇÃO</strong><span>Crie o primeiro auto desta obra.</span></div>`}
    </div>`;
}

const WORK_DOCUMENT_TYPES = [
  ["contrato", "Contrato"],
  ["orcamento", "Orçamento"],
  ["plantas_projeto", "Plantas / Projeto"],
  ["desenhos_preparacao", "Desenhos de Preparação"],
  ["atas_reuniao", "Atas de Reunião"],
  ["pdes_rfis", "PDEs / RFIs"],
  ["pames", "PAMEs"],
  ["licencas", "Licenças"],
  ["planeamento_detalhado", "Planeamento Detalhado"],
  ["outro", "Outro"],
];

function safeText(value) {
  return String(value ?? "").replace(/[&<>"']/g, character => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
  })[character]);
}

function workDocumentLabel(type) {
  return WORK_DOCUMENT_TYPES.find(([value]) => value === type)?.[1] || type || "Outro";
}

function workDocumentExtension(name) {
  return String(name || "").split(".").pop()?.toLowerCase() || "";
}

function canPreviewWorkDocument(document) {
  return ["pdf", "jpg", "jpeg", "png", "webp", "heic"].includes(workDocumentExtension(document.nome_arquivo));
}

function documentIndexNumber(item) {
  return item.numero_documento || item.numero || item.codigo || "Sem número";
}

function latestDrawingRows() {
  const grouped = new Map();
  workDetails.drawings.forEach(item => {
    const number = documentIndexNumber(item);
    const current = grouped.get(number);
    const itemSort = `${item.revisao || ""}|${item.data_emissao || ""}`;
    const currentSort = current ? `${current.revisao || ""}|${current.data_emissao || ""}` : "";
    if (!current || itemSort.localeCompare(currentSort, "pt-PT", { numeric: true }) > 0) grouped.set(number, item);
  });
  return [...grouped.values()].sort((a, b) =>
    documentIndexNumber(a).localeCompare(documentIndexNumber(b), "pt-PT", { numeric: true }));
}

function renderDocumentIndexes() {
  const drawings = latestDrawingRows();
  const rfis = [...workDetails.rfis].sort((a, b) =>
    String(b.data_envio || "").localeCompare(String(a.data_envio || "")));
  return `<section class="document-indexes">
    ${workDetails.documentIndexesError ? `<div class="work-warning"><strong>ÍNDICES PARCIAIS</strong><span>${safeText(workDetails.documentIndexesError)} Confirme as políticas RLS dos índices.</span></div>` : ""}
    <div class="document-index-grid">
      <section class="document-index-card">
        <header><div><p class="eyebrow">CONTROLO DE REVISÕES</p><h3>ÍNDICE DE DESENHOS</h3></div><span>${drawings.length}</span></header>
        <div class="document-index-list">${drawings.length ? drawings.map(item => `
          <article><div><span>NÚMERO</span><strong>${safeText(documentIndexNumber(item))}</strong></div>
            <div><span>REVISÃO MAIS RECENTE</span><strong>${safeText(item.revisao || "—")}</strong></div>
            <div><span>DATA</span><strong>${formatOptionalDate(String(item.data_emissao || "").slice(0, 10))}</strong></div>
          </article>`).join("") : `<div class="work-document-empty">SEM DESENHOS INDEXADOS</div>`}</div>
      </section>
      <section class="document-index-card">
        <header><div><p class="eyebrow">PEDIDOS DE ESCLARECIMENTO</p><h3>ÍNDICE DE PDEs</h3></div><span>${rfis.length}</span></header>
        <div class="document-index-list">${rfis.length ? rfis.map(item => {
          const status = String(item.estado || (item.data_resposta ? "respondido" : "enviado")).toLocaleLowerCase("pt-PT");
          return `<article><div><span>NÚMERO</span><strong>${safeText(documentIndexNumber(item))}</strong></div>
            <div><span>ESTADO</span><strong class="index-state ${safeText(status)}">${safeText(status.replaceAll("_", " ").toUpperCase())}</strong></div>
            <div><span>DATA</span><strong>${formatOptionalDate(String(item.data_envio || "").slice(0, 10))}</strong></div>
          </article>`;
        }).join("") : `<div class="work-document-empty">SEM PDEs INDEXADOS</div>`}</div>
      </section>
    </div>
  </section>`;
}

function renderWorkDocumentsTab() {
  const grouped = new Map(WORK_DOCUMENT_TYPES.map(([type]) => [type, []]));
  workDetails.workDocuments.forEach(document => {
    const type = grouped.has(document.tipo) ? document.tipo : "outro";
    grouped.get(type).push(document);
  });
  return `
    ${workDetails.workDocumentsError ? `<div class="work-warning"><strong>DOCUMENTOS INDISPONÍVEIS</strong><span>${safeText(workDetails.workDocumentsError)} Execute a migração de documentos por obra.</span></div>` : ""}
    ${workDetails.canEditDocuments ? `<form class="work-document-upload" id="work-document-upload">
      <div>
        <p class="eyebrow">ARQUIVO DA OBRA</p>
        <h3>ADICIONAR DOCUMENTO</h3>
        <span>PDF, imagem, Excel, Word, MS Project, DWG/DXF, ZIP ou TXT · máximo 25 MB</span>
      </div>
      <label>TIPO<div class="select-wrap"><select name="tipo" required>${WORK_DOCUMENT_TYPES.map(([value, label]) => `<option value="${value}">${label}</option>`).join("")}</select><b>⌄</b></div></label>
      <label class="work-document-index-field" data-document-number hidden>NÚMERO DO DOCUMENTO<input name="numero_documento" maxlength="80" placeholder="Ex.: DES-042 ou PDE-018"></label>
      <label class="work-document-index-field" data-document-revision hidden>REVISÃO<input name="revisao" maxlength="30" placeholder="Ex.: A ou 02"></label>
      <label class="work-document-file">FICHEIRO<input name="arquivo" type="file" required accept=".pdf,.jpg,.jpeg,.png,.webp,.heic,.xls,.xlsx,.doc,.docx,.mpp,.dwg,.dxf,.zip,.txt"></label>
      <button class="primary-button" type="submit">ENVIAR <span>→</span></button>
      <p class="form-error"></p>
    </form>` : `<div class="work-document-readonly"><strong>CONSULTA DE DOCUMENTOS</strong><span>Tem acesso de leitura. O envio está reservado à equipa que pode editar esta obra.</span></div>`}
    ${renderDocumentIndexes()}
    <div class="work-document-groups">
      ${WORK_DOCUMENT_TYPES.map(([type, label]) => {
        const documents = grouped.get(type);
        return `<section class="work-document-group">
          <header><div><p class="eyebrow">${label}</p><h3>${label.toUpperCase()}</h3></div><span>${documents.length}</span></header>
          <div class="work-document-list">
            ${documents.length ? documents.map(document => {
              const uploader = workDetails.documentUsers[document.enviado_por] || "Utilizador";
              const createdAt = document.criado_em ? prettyDate.format(new Date(document.criado_em)) : "—";
              const path = encodeURIComponent(document.arquivo_url || "");
              return `<article class="work-document-row">
                <div class="work-document-icon">${safeText(workDocumentExtension(document.nome_arquivo).slice(0, 4).toUpperCase() || "DOC")}</div>
                <div class="work-document-name"><strong title="${safeText(document.nome_arquivo)}">${safeText(document.nome_arquivo)}</strong><span>${safeText(workDocumentLabel(document.tipo))}</span></div>
                <div class="work-document-meta"><span>ENVIADO POR</span><strong>${safeText(uploader)}</strong></div>
                <div class="work-document-meta"><span>DATA</span><strong>${safeText(createdAt)}</strong></div>
                <div class="work-document-actions">
                  ${canPreviewWorkDocument(document) ? `<button type="button" data-work-document-preview="${path}" data-document-name="${safeText(document.nome_arquivo)}">PRÉ-VISUALIZAR</button>` : ""}
                  <button type="button" data-work-document-download="${path}" data-document-name="${safeText(document.nome_arquivo)}">DESCARREGAR</button>
                </div>
              </article>`;
            }).join("") : `<div class="work-document-empty">SEM DOCUMENTOS NESTA CATEGORIA</div>`}
          </div>
        </section>`;
      }).join("")}
    </div>`;
}

function safetyPersonName(id) {
  return workDetails.safetyCollaborators.find(person => person.id === id)?.nome
    || collaborators.find(person => person.id === id)?.nome
    || "Colaborador não identificado";
}

function dateUrgencyClass(value, days = 30) {
  if (!value) return "";
  const today = new Date(`${new Date().toISOString().slice(0, 10)}T12:00:00`);
  const target = new Date(`${String(value).slice(0, 10)}T12:00:00`);
  const difference = Math.ceil((target - today) / 86400000);
  if (difference < 0) return "expired";
  if (difference <= days) return "attention";
  return "";
}

function renderSafetyTab() {
  const peopleOptions = workDetails.safetyCollaborators.map(person =>
    `<option value="${person.id}">${safeText(person.nome)}${person.funcao ? ` — ${safeText(person.funcao)}` : ""}</option>`).join("");
  const canManageEpis = hasFullAccess() || isAdministrative();
  return `
    ${workDetails.safetyError ? `<div class="work-warning"><strong>SEGURANÇA PARCIAL</strong><span>${safeText(workDetails.safetyError)} Execute a migração RLS deste módulo.</span></div>` : ""}
    <div class="safety-sections">
      <section class="safety-card">
        <header><div><p class="eyebrow">REGISTO E PREVENÇÃO</p><h3>INCIDENTES / ACIDENTES</h3></div><span>${workDetails.safetyIncidents.length}</span></header>
        ${workDetails.canEditSafety ? `<form class="safety-form" id="safety-incident-form">
          <label>DATA<input name="data" type="date" required value="${new Date().toISOString().slice(0, 10)}"></label>
          <label>COLABORADOR<select name="colaborador_id" required><option value="">Selecionar colaborador</option>${peopleOptions}</select></label>
          <label>TIPO<input name="tipo" required maxlength="80" placeholder="Acidente, quase acidente…"></label>
          <label>GRAVIDADE<select name="gravidade" required><option value="leve">Leve</option><option value="moderada">Moderada</option><option value="grave">Grave</option><option value="muito_grave">Muito grave</option></select></label>
          <label class="wide">DESCRIÇÃO<textarea name="descricao" required rows="3"></textarea></label>
          <label class="wide">MEDIDAS TOMADAS<textarea name="medidas_tomadas" required rows="3"></textarea></label>
          <p class="form-error wide"></p><button class="primary-button" type="submit">REGISTAR INCIDENTE <span>→</span></button>
        </form>` : ""}
        <div class="safety-list">${workDetails.safetyIncidents.length ? workDetails.safetyIncidents.map(item => `
          <article class="safety-row severity-${safeText(item.gravidade || "leve")}">
            <div><span>${formatOptionalDate(item.data)}</span><strong>${safeText(safetyPersonName(item.colaborador_id))}</strong><small>${safeText(item.tipo || "Incidente")}</small></div>
            <div><span>GRAVIDADE</span><strong>${safeText(String(item.gravidade || "—").replaceAll("_", " ").toUpperCase())}</strong></div>
            <div><span>DESCRIÇÃO</span><p>${safeText(item.descricao || "—")}</p></div>
            <div><span>MEDIDAS TOMADAS</span><p>${safeText(item.medidas_tomadas || "—")}</p></div>
          </article>`).join("") : `<div class="work-document-empty">SEM INCIDENTES REGISTADOS</div>`}</div>
      </section>
      ${canManageEpis ? `<section class="safety-card">
        <header><div><p class="eyebrow">PROTEÇÃO INDIVIDUAL</p><h3>EPI's</h3></div><span>${workDetails.epis.length}</span></header>
        <div class="safety-list">${workDetails.epis.length ? workDetails.epis.map(item => {
          const validity = item.data_validade || item.data_renovacao || item.validade;
          return `<article class="epi-row ${dateUrgencyClass(validity)}">
            <div><span>COLABORADOR</span><strong>${safeText(safetyPersonName(item.colaborador_id))}</strong></div>
            <div><span>EQUIPAMENTO</span><strong>${safeText(item.tipo_epi || item.tipo_equipamento || item.tipo || item.equipamento || "—")}</strong></div>
            <div><span>ENTREGA</span><strong>${formatOptionalDate(item.data_entrega)}</strong></div>
            <div><span>VALIDADE / RENOVAÇÃO</span><strong>${formatOptionalDate(validity)}</strong></div>
          </article>`;
        }).join("") : `<div class="work-document-empty">SEM EPI's REGISTADOS</div>`}</div>
      </section>` : ""}
      <section class="safety-card">
        <header><div><p class="eyebrow">CONTROLO EM OBRA</p><h3>INSPEÇÕES / CHECKLISTS</h3></div><span>${workDetails.safetyInspections.length}</span></header>
        ${workDetails.canEditSafety ? `<form class="safety-form inspection" id="safety-inspection-form">
          <label>DATA<input name="data" type="date" required value="${new Date().toISOString().slice(0, 10)}"></label>
          <label>RESPONSÁVEL<select name="responsavel_id" required><option value="">Selecionar responsável</option>${peopleOptions}</select></label>
          <label>CONFORMIDADE<select name="conformidade" required><option value="true">Conforme</option><option value="false">Não conforme</option></select></label>
          <label class="wide">OBSERVAÇÕES<textarea name="observacoes" rows="3"></textarea></label>
          <p class="form-error wide"></p><button class="primary-button" type="submit">REGISTAR INSPEÇÃO <span>→</span></button>
        </form>` : ""}
        <div class="safety-list">${workDetails.safetyInspections.length ? workDetails.safetyInspections.map(item => {
          const compliant = item.conformidade === true || ["true", "conforme", "sim"].includes(String(item.conformidade).toLowerCase());
          return `<article class="inspection-row ${compliant ? "compliant" : "noncompliant"}">
            <div><span>DATA</span><strong>${formatOptionalDate(item.data)}</strong></div>
            <div><span>RESPONSÁVEL</span><strong>${safeText(safetyPersonName(item.responsavel_id))}</strong></div>
            <div><span>RESULTADO</span><strong>${compliant ? "CONFORME" : "NÃO CONFORME"}</strong></div>
            <div><span>OBSERVAÇÕES</span><p>${safeText(item.observacoes || "Sem observações")}</p></div>
          </article>`;
        }).join("") : `<div class="work-document-empty">SEM INSPEÇÕES REGISTADAS</div>`}</div>
      </section>
    </div>`;
}

function renderWorkTab(work) {
  if (selectedWorkTab === "subcontracts") return renderSubcontractsTab(work);
  if (selectedWorkTab === "measurements") return renderMeasurementsTab(work);
  if (selectedWorkTab === "phases") return `<div class="empty-state"><strong>FASES</strong><span>Este separador será desenvolvido numa próxima etapa.</span></div>`;
  if (selectedWorkTab === "documents") return renderWorkDocumentsTab();
  if (selectedWorkTab === "safety") return renderSafetyTab();
  return renderWorkSummary(work);
}

function renderWorkDetail(work) {
  if (!work) return;
  const financialReadOnly = isFinancial();
  if (financialReadOnly && !["summary", "subcontracts"].includes(selectedWorkTab)) selectedWorkTab = "summary";
  $("#work-detail").innerHTML = `
    <div class="work-detail-head">
      <div><p class="eyebrow">OBRA ${work.numero || "—"}</p><h2>${work.nome || "Sem designação"}</h2><span>${work.cliente || "Cliente não indicado"}</span></div>
      <div class="work-detail-actions"><button type="button" data-open-rnc="${work.id}">RNC →</button><button type="button" data-open-meeting="${work.id}">REUNIÃO SEMANAL →</button><span class="work-status ${work.situacao || "indefinida"}">${workSituationLabel(work.situacao)}</span></div>
    </div>
    <div class="work-location">${work.morada || "Morada não indicada"}</div>
    ${workDetails.error ? `<div class="work-warning"><strong>DADOS PARCIAIS</strong><span>${workDetails.error} Execute as políticas RLS adicionais incluídas no projeto.</span></div>` : ""}
    <nav class="work-tabs">
      <button data-work-tab="summary" class="${selectedWorkTab === "summary" ? "active" : ""}">RESUMO</button>
      <button data-work-tab="subcontracts" class="${selectedWorkTab === "subcontracts" ? "active" : ""}">SUBEMPREITADAS</button>
      ${financialReadOnly ? "" : `<button data-work-tab="measurements" class="${selectedWorkTab === "measurements" ? "active" : ""}">AUTOS DE MEDIÇÃO</button>
      <button data-work-tab="phases" class="${selectedWorkTab === "phases" ? "active" : ""}">FASES</button>
      <button data-work-tab="documents" class="${selectedWorkTab === "documents" ? "active" : ""}">DOCUMENTOS</button>
      <button data-work-tab="safety" class="${selectedWorkTab === "safety" ? "active" : ""}">SEGURANÇA</button>`}
    </nav>
    ${financialReadOnly ? `<div class="readonly-note">CONSULTA FINANCEIRA · SEM PERMISSÃO PARA ALTERAR A OBRA</div>` : ""}
    <div class="work-tab-content">${renderWorkTab(work)}</div>`;
  if (selectedWorkTab === "subcontracts") procurementModule?.show(work);
}

function switchView(view, context = {}) {
  if (!allowedViews().has(view)) {
    toast("Não tem permissão para aceder a esta área.", "error");
    view = defaultViewForCurrentUser();
  }
  activeView = view;
  document.querySelectorAll(".sidebar nav [data-view]").forEach(button => button.classList.toggle("active", button.dataset.view === view));
  $("#overview-view").hidden = view !== "overview";
  $("#consolidated-view").hidden = view !== "consolidated";
  $("#action-plan-view").hidden = view !== "action-plan";
  $("#meeting-view").hidden = view !== "meeting";
  $("#invoice-view").hidden = view !== "invoices";
  $("#works-view").hidden = view !== "works";
  $("#planning-view").hidden = view !== "planning";
  $("#subcontractors-view").hidden = view !== "subcontractors";
  $("#finance-view").hidden = view !== "finance";
  $("#team-view").hidden = view !== "team";
  $("#workforce-view").hidden = view !== "workforce";
  $("#settings-view").hidden = view !== "settings";
  $("#documents-view").hidden = view !== "documents";
  $("#rnc-view").hidden = view !== "rnc";
  $("#placeholder-view").hidden = ["action-plan", "consolidated", "overview", "meeting", "invoices", "works", "planning", "subcontractors", "finance", "documents", "rnc", "team", "workforce", "settings"].includes(view);
  if (!["action-plan", "consolidated", "overview", "meeting", "invoices", "works", "planning", "subcontractors", "finance", "documents", "rnc", "team", "workforce", "settings"].includes(view)) {
    $("#placeholder-title").textContent = "MÓDULO EM PREPARAÇÃO";
  }
  if (view === "works") {
    renderWorks();
    if (!selectedWorkId && works[0]) loadWorkDetails(works[0].id);
  }
  if (view === "finance") renderFinance();
  if (view === "planning") planningModule.show(context);
  if (view === "action-plan") actionPlanModule.show();
  if (view === "documents") documentsModule.show();
  if (view === "rnc") rncModule.show(context.workId || selectedWorkId);
  if (view === "subcontractors") subcontractorsModule.show();
  if (view === "team" && !canManageTeam()) activateTeamTab("absences");
  else if (view === "team" && context.teamTab) activateTeamTab(context.teamTab);
  if (view === "team" || view === "workforce") loadTeamData();
  if (view === "settings") settingsModule?.load();
  if (view === "overview") productionDashboard.refreshOverview();
  if (view === "consolidated") consolidatedView.show();
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
  const isMaterial = button.dataset.type === "material";
  $("#material-items-editor").hidden = !isMaterial;
  if (isMaterial && extractedMaterialItems.length) showExtractedMaterialItems(extractedMaterialItems);
  else if (isMaterial && !$("#material-items-list").children.length) addMaterialItem();
}));
$("#add-material-item").addEventListener("click", () => addMaterialItem());
$("#material-items-list").addEventListener("input", event => {
  const row = event.target.closest("[data-material-item]");
  if (row) updateMaterialItemTotal(row, event.target.dataset.itemField || "");
});
$("#material-items-list").addEventListener("click", event => {
  const removeButton = event.target.closest("[data-remove-material-item]");
  if (!removeButton) return;
  const rows = $("#material-items-list").querySelectorAll("[data-material-item]");
  if (rows.length === 1) {
    rows[0].querySelectorAll("input").forEach(input => { input.value = ""; });
    updateMaterialItemTotal(rows[0]);
  } else removeButton.closest("[data-material-item]").remove();
});
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
$("#add-workforce-line").addEventListener("click", () => toggleWorkforceLineForm($("#workforce-new-line").hidden));
$("#workforce-line-type").addEventListener("change", () => toggleWorkforceLineForm(true));
$("#workforce-new-line").addEventListener("click", event => {
  if (event.target.closest("[data-cancel-workforce-line]")) toggleWorkforceLineForm(false);
});
$("#workforce-new-line").addEventListener("submit", event => {
  event.preventDefault();
  const type = $("#workforce-line-type").value;
  const workId = $("#workforce-line-work").value;
  const description = $("#workforce-line-description").value.trim();
  if (type !== "obra" && !description) {
    toast("Escreva o nome da linha.", "error");
    $("#workforce-line-description").focus();
    return;
  }
  if (!addWorkforceLine(type, workId, description)) {
    toast("Essa linha já existe no quadro.", "error");
    return;
  }
  toggleWorkforceLineForm(false);
  renderTeam();
  toast("Linha adicionada. Coloque um íman para a gravar no quadro.");
});
$("#team-board").addEventListener("change", async event => {
  const input = event.target.closest("[data-workforce-rename]");
  if (!input || !workforceEditing) return;
  await renameWorkforceLine(input.dataset.rowType, decodeURIComponent(input.dataset.oldDescription || ""), input.value);
});
$("#team-board").addEventListener("keydown", event => {
  const input = event.target.closest("[data-workforce-rename]");
  if (!input) return;
  if (event.key === "Enter") {
    event.preventDefault();
    input.blur();
  } else if (event.key === "Escape") renderTeam();
});
$("#team-board").addEventListener("click", async event => {
  if (!workforceEditing) return;
  const vacationBox = event.target.closest("[data-vacation-week]");
  if (vacationBox) {
    if (!selectedWorkforcePersonId) {
      toast("Selecione primeiro um íman.", "error");
      return;
    }
    openVacationDaysDialog(selectedWorkforcePersonId, vacationBox.dataset.vacationWeek);
    return;
  }
  const magnet = event.target.closest("[data-workforce-person]");
  if (magnet) {
    selectedWorkforcePersonId = magnet.dataset.workforcePerson;
    selectedWorkforceSourceDate = magnet.dataset.sourceDate || "";
    selectedWorkforceSourcePeriod = magnet.dataset.sourcePeriod || "";
    selectedWorkforceSourceRowKey = magnet.dataset.sourceRowKey || "";
    selectedWorkforceSourceIds = (magnet.dataset.sourceIds || "").split(",").filter(Boolean);
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
  await saveWorkforceAllocation(selectedWorkforcePersonId, cell.dataset.date, {
    type: cell.dataset.allocationType,
    workId: cell.dataset.workId,
    description: decodeURIComponent(cell.dataset.description || ""),
  });
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
  selectedWorkforceSourceRowKey = "";
  selectedWorkforceSourceIds = [];
  $("#remove-workforce-allocation").hidden = true;
  const person = collaborators.find(item => item.id === selectedWorkforcePersonId);
  $("#workforce-edit-message").textContent = `${shortPersonName(person?.nome || "")} selecionado. Escolha o período e clique no dia/obra.`;
  renderTeam();
});
$("#workforce-roster").addEventListener("change", event => {
  const select = event.target.closest("[data-workforce-period]");
  if (select) selectedWorkforcePeriod = select.value;
});
function activateTeamTab(tab, preserveFilter = false) {
  if (!canManageTeam() && tab !== "absences") tab = "absences";
  selectedTeamTab = tab;
  if (!preserveFilter) teamQuickFilter = "";
  document.querySelectorAll("[data-team-tab]").forEach(item => item.classList.toggle("active", item.dataset.teamTab === selectedTeamTab));
  document.querySelectorAll("[data-team-panel]").forEach(panel => { panel.hidden = panel.dataset.teamPanel !== selectedTeamTab; });
}

document.querySelectorAll("[data-team-tab]").forEach(button => button.addEventListener("click", () => {
  activateTeamTab(button.dataset.teamTab);
  renderTeam();
}));
$("#team-view").addEventListener("click", async event => {
  const absenceDownload = event.target.closest("[data-absence-download]");
  if (absenceDownload) {
    const path = decodeURIComponent(absenceDownload.dataset.absenceDownload || "");
    absenceDownload.disabled = true;
    try {
      const blob = localEntityDocumentFiles.get(path) || await downloadWorkDocument(path);
      const objectUrl = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = objectUrl;
      link.download = absenceDownload.dataset.fileName || "comprovativo";
      document.body.appendChild(link);
      link.click(); link.remove();
      setTimeout(() => URL.revokeObjectURL(objectUrl), 60000);
    } catch (error) { toast(error.message || "Não foi possível descarregar o comprovativo.", "error"); }
    finally { absenceDownload.disabled = false; }
    return;
  }
  const vacationPerson = event.target.closest("[data-team-vacation-person]");
  if (vacationPerson) {
    if (!canManageTeam()) return toast("A gestão de férias está reservada ao Administrativo e à Gerência.", "error");
    openVacationDaysDialog(vacationPerson.dataset.teamVacationPerson, selectedTeamWeek);
    return;
  }
  const alertButton = event.target.closest("[data-team-alert-filter]");
  if (alertButton) {
    const nextFilter = alertButton.dataset.teamAlertFilter;
    teamQuickFilter = teamQuickFilter === nextFilter ? "" : nextFilter;
    activateTeamTab(alertButton.dataset.teamAlertTab, true);
    renderTeam();
    document.querySelector(`[data-team-panel="${selectedTeamTab}"]`)?.scrollIntoView({ behavior: "smooth", block: "start" });
    return;
  }
  const editVehicleButton = event.target.closest("[data-edit-vehicle]");
  if (editVehicleButton) {
    if (!canManageTeam()) return toast("A edição da frota está reservada ao Administrativo e à Gerência.", "error");
    selectedVehicleEditId = selectedVehicleEditId === editVehicleButton.dataset.editVehicle ? "" : editVehicleButton.dataset.editVehicle;
    renderTeam();
    return;
  }
  if (event.target.closest("[data-cancel-vehicle-edit]")) {
    selectedVehicleEditId = "";
    renderTeam();
    return;
  }
  const openButton = event.target.closest("[data-open-entity-documents]");
  if (openButton) {
    const next = { type: openButton.dataset.openEntityDocuments, id: openButton.dataset.entityId };
    selectedTeamEntity = selectedTeamEntity?.type === next.type && selectedTeamEntity.id === next.id ? null : next;
    renderTeam();
    return;
  }
  if (event.target.closest("[data-close-entity-documents]")) {
    selectedTeamEntity = null;
    renderTeam();
    return;
  }
  const downloadButton = event.target.closest("[data-entity-document-download]");
  if (!downloadButton) return;
  const path = decodeURIComponent(downloadButton.dataset.entityDocumentDownload || "");
  if (!path) return toast("Este documento não tem ficheiro associado.", "error");
  downloadButton.disabled = true;
  try {
    const blob = localEntityDocumentFiles.get(path) || await downloadWorkDocument(path);
    const objectUrl = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = objectUrl;
    link.download = downloadButton.dataset.documentName || "documento";
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(objectUrl), 60000);
  } catch (error) {
    toast(error.message || "Não foi possível descarregar o documento.", "error");
  } finally {
    downloadButton.disabled = false;
  }
});
$("#team-view").addEventListener("submit", async event => {
  const absenceForm = event.target.closest("#absence-entry-form");
  if (absenceForm) {
    event.preventDefault();
    if (!canManageTeam()) return toast("A gestão de ausências está reservada ao Administrativo e à Gerência.", "error");
    await createAbsence(absenceForm);
    return;
  }
  const justificationForm = event.target.closest("[data-justify-absence]");
  if (justificationForm) {
    event.preventDefault();
    if (!canManageTeam()) return toast("A justificação de ausências está reservada ao Administrativo e à Gerência.", "error");
    await justifyAbsence(justificationForm);
    return;
  }
  const vehicleForm = event.target.closest("[data-vehicle-edit-form]");
  if (vehicleForm) {
    event.preventDefault();
    if (!canManageTeam()) return toast("A edição da frota está reservada ao Administrativo e à Gerência.", "error");
    const vehicle = teamData.vehicles.find(item => item.id === vehicleForm.dataset.vehicleId);
    if (!vehicle) return;
    const submitButton = vehicleForm.querySelector('button[type="submit"]');
    const errorNode = vehicleForm.querySelector(".form-error");
    submitButton.disabled = true;
    errorNode.textContent = "";
    const payload = {
      colaborador_atribuido_id: vehicleForm.elements.colaborador_atribuido_id.value || null,
      seguro_data: vehicleForm.elements.seguro_data.value || null,
      data_inspecao_proxima: vehicleForm.elements.data_inspecao_proxima.value || null,
      data_revisao: vehicleForm.elements.data_revisao.value || null,
      data_proxima_revisao: vehicleForm.elements.data_proxima_revisao.value || null,
    };
    try {
      if (isSupabaseConfigured) {
        const response = await supabase(`viaturas?id=eq.${vehicle.id}`, {
          method: "PATCH",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify(payload),
        });
        if (!response.ok) {
          const detail = await response.json().catch(() => ({}));
          throw new Error(detail.message || detail.details || "Não foi possível atualizar a viatura.");
        }
        const [saved] = await response.json();
        Object.assign(vehicle, saved || payload);
      } else {
        Object.assign(vehicle, payload);
      }
      selectedVehicleEditId = "";
      renderTeam();
      toast("Dados da viatura atualizados.");
    } catch (error) {
      errorNode.textContent = error.message || "Não foi possível atualizar a viatura.";
    } finally {
      submitButton.disabled = false;
    }
    return;
  }
  const uploadForm = event.target.closest("[data-entity-document-upload]");
  if (!uploadForm) return;
  event.preventDefault();
  const file = uploadForm.elements.arquivo.files[0];
  const documentType = uploadForm.elements.tipo_documento.value.trim();
  const entityType = uploadForm.dataset.entityType;
  const entityId = uploadForm.dataset.entityId;
  const submitButton = uploadForm.querySelector('button[type="submit"]');
  const errorNode = uploadForm.querySelector(".form-error");
  if (!file || !documentType) return;
  submitButton.disabled = true;
  errorNode.textContent = "";
  try {
    let savedDocument;
    if (isSupabaseConfigured) {
      const objectPath = await uploadEntityDocument(file, entityType, entityId, documentType);
      const response = await supabase("documentos?select=id,empresa_id,entidade_tipo,entidade_id,tipo_documento,nome_arquivo,url_arquivo,data_emissao,data_validade,criado_em", {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          empresa_id: PRIMELINE_COMPANY_ID,
          entidade_tipo: entityType,
          entidade_id: entityId,
          tipo_documento: documentType,
          nome_arquivo: file.name,
          url_arquivo: objectPath,
          data_emissao: uploadForm.elements.data_emissao.value || null,
          data_validade: uploadForm.elements.data_validade.value || null,
        }),
      });
      if (!response.ok) {
        const detail = await response.json().catch(() => ({}));
        throw new Error(detail.message || detail.details || "O ficheiro foi enviado, mas não foi possível registar o documento.");
      }
      [savedDocument] = await response.json();
    } else {
      const localPath = `local:${crypto.randomUUID()}`;
      localEntityDocumentFiles.set(localPath, file);
      savedDocument = {
        id: crypto.randomUUID(), empresa_id: PRIMELINE_COMPANY_ID,
        entidade_tipo: entityType, entidade_id: entityId,
        tipo_documento: documentType, nome_arquivo: file.name, url_arquivo: localPath,
        data_emissao: uploadForm.elements.data_emissao.value || null,
        data_validade: uploadForm.elements.data_validade.value || null,
        criado_em: new Date().toISOString(),
      };
    }
    teamData.entityDocuments.unshift(savedDocument);
    renderTeam();
    toast("Documento associado com sucesso.");
  } catch (error) {
    errorNode.textContent = error.message || "Não foi possível anexar o documento.";
  } finally {
    submitButton.disabled = false;
  }
});
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
  if (!hasFullAccess()) return toast("A criação de obras está reservada à Gerência.", "error");
  renderWorkDirectors();
  renderWorkTemplates();
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
  if (!hasFullAccess()) return toast("A criação de obras está reservada à Gerência.", "error");
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
    let templateResult = null;
    if (!isSupabaseConfigured) {
      payload.id = crypto.randomUUID();
      templateResult = fields.modelo_obra_id ? { fases_copiadas: 0, itens_orcamento_copiados: 0 } : null;
    } else if (fields.modelo_obra_id) {
      const response = await supabase("rpc/fn_criar_obra_de_modelo", {
        method: "POST",
        body: JSON.stringify({
          p_modelo_obra_id: fields.modelo_obra_id,
          p_numero: payload.numero,
          p_nome: payload.nome,
          p_cliente: payload.cliente,
          p_morada: payload.morada,
          p_tipo: payload.tipo,
          p_modalidade: payload.modalidade,
          p_diretor_obra_id: payload.diretor_obra_id,
          p_situacao: payload.situacao,
          p_data_inicio: payload.data_inicio,
          p_data_fim_prevista: payload.data_fim_prevista,
          p_copiar_orcamento: workForm.elements.copiar_orcamento.checked,
        }),
      });
      if (!response.ok) {
        const detail = await response.json().catch(() => ({}));
        throw new Error(detail.message || detail.details || "Não foi possível criar a obra a partir do modelo.");
      }
      templateResult = await response.json();
      Object.assign(payload, templateResult.obra);
    } else {
      const response = await supabase("obras?select=id,numero,nome,cliente,morada,tipo,modalidade,situacao,data_inicio,data_fim_prevista,diretor_obra_id,planeamento_baseline_congelado,planeamento_baseline_congelado_em", {
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
    toast(templateResult
      ? `Obra ${payload.numero} criada com ${templateResult.fases_copiadas} fases e ${templateResult.itens_orcamento_copiados} categorias de orçamento.`
      : `Obra ${payload.numero} criada com sucesso.`);
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
$("#work-detail").addEventListener("change", event => {
  if (event.target.name !== "tipo" || event.target.form?.id !== "work-document-upload") return;
  const formElement = event.target.form;
  const isDrawing = event.target.value === "desenhos_preparacao";
  const isPde = event.target.value === "pdes_rfis";
  const numberField = formElement.querySelector("[data-document-number]");
  const revisionField = formElement.querySelector("[data-document-revision]");
  numberField.hidden = !isDrawing && !isPde;
  revisionField.hidden = !isDrawing;
  formElement.elements.numero_documento.required = isDrawing || isPde;
  if (!isDrawing && !isPde) formElement.elements.numero_documento.value = "";
  if (!isDrawing) formElement.elements.revisao.value = "";
});
$("#work-detail").addEventListener("submit", async event => {
  if (event.target.id === "safety-incident-form" || event.target.id === "safety-inspection-form") {
    event.preventDefault();
    const safetyForm = event.target;
    const isIncident = safetyForm.id === "safety-incident-form";
    const values = Object.fromEntries(new FormData(safetyForm));
    const submitButton = safetyForm.querySelector('button[type="submit"]');
    const errorNode = safetyForm.querySelector(".form-error");
    submitButton.disabled = true;
    errorNode.textContent = "";
    const payload = { ...values, obra_id: selectedWorkId };
    if (!isIncident) payload.conformidade = values.conformidade === "true";
    try {
      if (isSupabaseConfigured) {
        const table = isIncident ? "seguranca_incidentes" : "seguranca_inspecoes";
        const response = await supabase(`${table}?select=*`, {
          method: "POST",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify(payload),
        });
        if (!response.ok) throw new Error(await response.text());
        const [saved] = await response.json();
        (isIncident ? workDetails.safetyIncidents : workDetails.safetyInspections).unshift(saved);
      } else {
        const saved = { ...payload, id: crypto.randomUUID(), criado_em: new Date().toISOString() };
        (isIncident ? workDetails.safetyIncidents : workDetails.safetyInspections).unshift(saved);
      }
      renderWorkDetail(works.find(item => item.id === selectedWorkId));
      toast(isIncident ? "Incidente registado." : "Inspeção registada.");
    } catch (error) {
      errorNode.textContent = error.message || "Não foi possível guardar o registo.";
    } finally {
      submitButton.disabled = false;
    }
    return;
  }
  if (event.target.id !== "work-document-upload") return;
  event.preventDefault();
  const uploadForm = event.target;
  const file = uploadForm.elements.arquivo.files[0];
  const type = uploadForm.elements.tipo.value;
  const indexed = ["desenhos_preparacao", "pdes_rfis"].includes(type);
  const documentNumber = uploadForm.elements.numero_documento.value.trim();
  const revision = uploadForm.elements.revisao.value.trim();
  const submitButton = uploadForm.querySelector('button[type="submit"]');
  const errorNode = uploadForm.querySelector(".form-error");
  if (!file) return;
  if (indexed && !documentNumber) {
    errorNode.textContent = "O número do documento é obrigatório para Desenhos e PDEs.";
    uploadForm.elements.numero_documento.focus();
    return;
  }
  submitButton.disabled = true;
  errorNode.textContent = "";
  try {
    let document;
    if (isSupabaseConfigured) {
      const objectPath = await uploadWorkDocument(file, selectedWorkId, type);
      const response = await supabase("documentos_obra?select=*", {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          obra_id: selectedWorkId,
          tipo: type,
          nome_arquivo: file.name,
          arquivo_url: objectPath,
          enviado_por: accessContext.profile?.id,
          numero_documento: indexed ? documentNumber : null,
          revisao: type === "desenhos_preparacao" ? revision || null : null,
        }),
      });
      if (!response.ok) {
        const detail = await response.json().catch(() => ({}));
        throw new Error(detail.message || "O ficheiro foi enviado, mas não foi possível registar o documento.");
      }
      document = await response.json();
      if (Array.isArray(document)) [document] = document;
    } else {
      const localPath = `local:${crypto.randomUUID()}`;
      localWorkDocumentFiles.set(localPath, file);
      document = {
        id: crypto.randomUUID(),
        obra_id: selectedWorkId,
        tipo: type,
        nome_arquivo: file.name,
        arquivo_url: localPath,
        numero_documento: indexed ? documentNumber : null,
        revisao: type === "desenhos_preparacao" ? revision || null : null,
        enviado_por: "demo",
        criado_em: new Date().toISOString(),
      };
      workDetails.documentUsers.demo = "Utilizador de demonstração";
    }
    workDetails.workDocuments.unshift(document);
    if (indexed) {
      if (isSupabaseConfigured) {
        const table = type === "desenhos_preparacao" ? "desenhos" : "rfis";
        const order = table === "desenhos" ? "numero.asc,revisao.desc" : "numero.asc";
        const indexResult = await supabase(`${table}?select=*&obra_id=eq.${encodeURIComponent(selectedWorkId)}&order=${order}`);
        if (indexResult.ok) workDetails[type === "desenhos_preparacao" ? "drawings" : "rfis"] = await indexResult.json();
      } else {
        const indexItem = { ...document, documento_obra_id: document.id };
        workDetails[type === "desenhos_preparacao" ? "drawings" : "rfis"].unshift(indexItem);
      }
    }
    renderWorkDetail(works.find(item => item.id === selectedWorkId));
    toast("Documento adicionado à obra.");
  } catch (error) {
    errorNode.textContent = error.message;
  } finally {
    submitButton.disabled = false;
  }
});
$("#work-detail").addEventListener("click", async event => {
  const rncButton = event.target.closest("[data-open-rnc]");
  if (rncButton) { selectedWorkId = rncButton.dataset.openRnc; switchView("rnc"); return; }
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
  const workDocumentButton = event.target.closest("[data-work-document-preview], [data-work-document-download]");
  if (workDocumentButton) {
    const path = decodeURIComponent(workDocumentButton.dataset.workDocumentPreview || workDocumentButton.dataset.workDocumentDownload);
    const name = workDocumentButton.dataset.documentName || "documento";
    const preview = Boolean(workDocumentButton.dataset.workDocumentPreview);
    workDocumentButton.disabled = true;
    try {
      const blob = localWorkDocumentFiles.get(path) || await downloadWorkDocument(path);
      const objectUrl = URL.createObjectURL(blob);
      if (preview) {
        openedPdfUrl = objectUrl;
        openPdfModal(objectUrl, name);
      } else {
        const link = document.createElement("a");
        link.href = objectUrl;
        link.download = name;
        document.body.appendChild(link);
        link.click();
        link.remove();
        setTimeout(() => URL.revokeObjectURL(objectUrl), 60000);
      }
    } catch (error) {
      toast(error.message, "error");
    } finally {
      workDocumentButton.disabled = false;
    }
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
  const settingsTheme = document.querySelector("[data-settings-theme]");
  const settingsTv = document.querySelector("[data-settings-tv]");
  if (settingsTheme) settingsTheme.textContent = dark ? "☀ ATIVAR TEMA CLARO" : "☾ ATIVAR TEMA ESCURO";
  if (settingsTv) settingsTv.textContent = tv ? "DESATIVAR MODO TV" : "ATIVAR MODO TV";
}
function toggleThemePreference() {
  const theme = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = theme;
  localStorage.setItem(UI_THEME_KEY, theme);
  syncDisplayToggles();
}
function toggleTvPreference() {
  const enabled = !document.documentElement.classList.contains("tv-mode");
  document.documentElement.classList.toggle("tv-mode", enabled);
  localStorage.setItem(UI_TV_KEY, String(enabled));
  syncDisplayToggles();
}
$("#theme-toggle").addEventListener("click", toggleThemePreference);
$("#tv-toggle").addEventListener("click", toggleTvPreference);
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
  for (const row of rows) {
    if (!/(fatura|invoice|nota|recibo)/i.test(row.text)) continue;
    const match = row.text.match(/\bN(?:\.?\s*[ºo°])?\.?\s*(?:[:#-]\s*)?(.+?)(?=\s+(?:data|date|emiss[aã]o)\b|$)/i);
    if (match?.[1]) return match[1].trim();
  }
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

function parsePdfNumber(value) {
  const clean = String(value || "").replace(/[^\d,.-]/g, "");
  if (!clean || clean === "-" || clean === "," || clean === ".") return null;
  let normalized = clean;
  if (clean.includes(",")) normalized = clean.replace(/\./g, "").replace(",", ".");
  const number = Number(normalized);
  return Number.isFinite(number) ? number : null;
}

function pdfHeaderColumn(row, patterns) {
  for (const pattern of patterns) {
    const position = labelPosition(row, pattern);
    if (position) return position.centerX;
  }
  return null;
}

function findMaterialItems(rows) {
  const headers = rows.map(row => ({
    row,
    designationX: pdfHeaderColumn(row, [/designa[cç][aã]o/i, /descri[cç][aã]o/i, /artigo/i, /produto/i]),
    quantityX: pdfHeaderColumn(row, [/quantidade/i, /\bqtd\.?\b/i, /\bqt\.?\b/i]),
    unitX: pdfHeaderColumn(row, [/\bunidade\b/i, /\bun\.?\b/i]),
    unitPriceX: pdfHeaderColumn(row, [/pre[cç]o\s+unit[aá]rio/i, /valor\s+unit[aá]rio/i, /\bp\.?\s*unit\.?\b/i]),
    discountX: pdfHeaderColumn(row, [/desconto/i, /\bdesc\.?\s*%?/i]),
    discountIsPercent: /(?:desconto|desc\.?).{0,8}%|%.{0,8}(?:desconto|desc\.?)/i.test(row.text),
    totalX: pdfHeaderColumn(row, [/pre[cç]o\s+total/i, /valor\s+total/i, /\btotal\b/i]),
  })).filter(candidate => candidate.designationX !== null
    && [candidate.quantityX, candidate.unitX, candidate.unitPriceX, candidate.totalX].filter(value => value !== null).length >= 2);

  if (!headers.length) return [];
  const extracted = [];
  for (const header of headers) {
    const columns = [
      ["designacao", header.designationX], ["quantidade", header.quantityX], ["unidade", header.unitX],
      ["preco_unitario", header.unitPriceX], ["desconto", header.discountX], ["preco_total", header.totalX],
    ].filter(([, x]) => x !== null).sort((a, b) => a[1] - b[1]);
    const boundaries = columns.slice(0, -1).map((column, index) => (column[1] + columns[index + 1][1]) / 2);
    const bodyRows = rows.filter(row => row.pageNumber === header.row.pageNumber && row.y < header.row.y)
      .sort((a, b) => b.y - a.y);
    let pendingDesignation = "";
    for (const row of bodyRows) {
      if (/\b(total\s+(?:do\s+documento|l[ií]quido|geral)|valor\s+a\s+pagar|incid[eê]ncia|resumo\s+de\s+iva)\b/i.test(row.text)) break;
      const cells = Object.fromEntries(columns.map(([name]) => [name, []]));
      row.items.forEach(item => {
        const index = boundaries.findIndex(boundary => item.x < boundary);
        const column = columns[index < 0 ? columns.length - 1 : index]?.[0];
        if (column) cells[column].push(item.text);
      });
      let designation = (cells.designacao || []).join(" ").replace(/\s+/g, " ").trim();
      if ((!designation && !pendingDesignation) || /^(ref\.?|c[oó]digo|artigo|designa[cç][aã]o)$/i.test(designation)) continue;
      const quantity = parsePdfNumber((cells.quantidade || []).join(" "));
      const unit = (cells.unidade || []).join(" ").trim();
      let unitPrice = parsePdfNumber((cells.preco_unitario || []).join(" "));
      const discountText = (cells.desconto || []).join(" ").trim();
      let discountPercent = (header.discountIsPercent || /%/.test(discountText)) ? parsePdfNumber(discountText) : null;
      let discountValue = discountText && discountPercent === null ? parsePdfNumber(discountText) : null;
      let total = parsePdfNumber((cells.preco_total || []).join(" "));
      if (!(quantity > 0) && unitPrice === null && total === null) {
        pendingDesignation = `${pendingDesignation} ${designation}`.trim();
        continue;
      }
      if (pendingDesignation) designation = `${pendingDesignation} ${designation}`.trim();
      if (unitPrice === null && quantity > 0 && total !== null) {
        if (discountPercent !== null && discountPercent < 100) unitPrice = total / (1 - discountPercent / 100) / quantity;
        else if (discountValue !== null) unitPrice = (total + discountValue) / quantity;
        else unitPrice = total / quantity;
      }
      const gross = quantity > 0 && unitPrice !== null ? quantity * unitPrice : null;
      if (gross !== null && discountPercent !== null) discountValue = gross * discountPercent / 100;
      if (gross !== null && discountValue !== null && discountPercent === null) discountPercent = gross ? discountValue / gross * 100 : 0;
      if (total === null && gross !== null) total = Math.max(0, gross - Number(discountValue || 0));
      if (gross !== null && total !== null && discountValue === null && total < gross) {
        discountValue = gross - total;
        discountPercent = gross ? discountValue / gross * 100 : 0;
      }
      if (!(quantity > 0) || unitPrice === null || total === null) continue;
      extracted.push({
        designacao: designation, unidade: unit, quantidade: quantity, preco_unitario: unitPrice,
        desconto_percentual: discountPercent, valor_desconto: discountValue, preco_total: total,
      });
      pendingDesignation = "";
    }
    if (extracted.length) break;
  }
  return extracted.slice(0, 100);
}
async function extractPdfData(file) {
  $("#extraction-panel").hidden = false;
  $("#extraction-status").textContent = "A ANALISAR…";
  $("#extraction-results").innerHTML = "";
  $("#extraction-note").textContent = "Os dados encontrados continuam editáveis e devem ser confirmados.";
  showExtractedMaterialItems([]);
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
    const materialItems = findMaterialItems(rows);
    showExtractedMaterialItems(materialItems);

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
      extractionRow("Cond. pagamento (sugestão)", paymentConditionSuggestion, "manual") +
      extractionRow("Artigos sugeridos", materialItems.length ? `${materialItems.length} linha${materialItems.length === 1 ? "" : "s"}` : "", materialItems.length ? "provavel" : "manual");
    $("#payment-condition-suggestion").textContent = paymentConditionSuggestion
      ? `Sugestão lida no PDF: ${paymentConditionSuggestion}. Confirme manualmente uma das opções.`
      : "Selecione manualmente; este campo nunca é preenchido automaticamente.";
    const itemNote = materialItems.length
      ? " Os artigos foram apenas sugeridos: reveja designação, unidade, quantidade e preços antes de gravar."
      : "";
    $("#extraction-note").textContent = (exactSupplier
      ? "Fornecedor encontrado por correspondência exata. Confirme os restantes campos e escolha manualmente a subempreitada, quando aplicável."
      : "O fornecedor não corresponde exatamente a nenhum registo existente. Selecione-o manualmente na lista; nenhum fornecedor foi criado.") + itemNote;
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
  extractedMaterialItems = [];
  extractedMaterialItemsApplied = false;
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
  if (!canInsertInvoices()) return toast("O lançamento de faturas está reservado ao Administrativo e à Gerência.", "error");
  const payload = Object.fromEntries(new FormData(form));
  payload.valor = Number(payload.valor); payload.subempreitada_id ||= null;
  const materialItems = payload.tipo_origem === "material" ? collectMaterialItems() : [];
  if (payload.tipo_origem === "material") {
    const invalidItem = materialItems.find(item =>
      !item.designacao || !item.unidade || !Number.isFinite(item.quantidade)
      || !(item.quantidade > 0) || !Number.isFinite(item.preco_unitario) || item.preco_unitario < 0
      || (item.desconto_percentual != null && (!Number.isFinite(item.desconto_percentual) || item.desconto_percentual < 0 || item.desconto_percentual > 100))
      || (item.valor_desconto != null && (!Number.isFinite(item.valor_desconto) || item.valor_desconto < 0 || item.valor_desconto > item.quantidade * item.preco_unitario)));
    if (!materialItems.length || invalidItem) {
      toast("Preencha pelo menos um artigo com designação, unidade, quantidade e preço unitário.", "error");
      return;
    }
  }
  const submit = form.querySelector(".primary-button"); submit.disabled = true; submit.firstChild.textContent = "A GUARDAR… ";
  let saved = false;
  if (!isSupabaseConfigured) {
    const demoInvoice = { ...payload, id: `demo-${Date.now()}`, estado_aprovacao: "pendente", criado_em: new Date().toISOString() };
    invoices.unshift(demoInvoice);
    materialItems.forEach(item => item.fatura_id = demoInvoice.id);
    saved = true;
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
    } else {
      const [inserted] = await result.json();
      invoices.unshift(inserted);
      if (materialItems.length) {
        submit.firstChild.textContent = "A REGISTAR ARTIGOS… ";
        const itemResult = await supabase("faturas_itens", {
          method: "POST",
          headers: { Prefer: "return=minimal" },
          body: JSON.stringify(materialItems.map(item => ({
            fatura_id: inserted.id,
            designacao: item.designacao,
            unidade: item.unidade,
            quantidade: item.quantidade,
            valor_unitario: item.preco_unitario,
            valor_total: item.preco_total,
            desconto_percentual: item.desconto_percentual,
            valor_desconto: item.valor_desconto,
          }))),
        });
        if (!itemResult.ok) {
          toast(`A fatura foi registada, mas os artigos não foram guardados: ${await itemResult.text()}`, "error");
        } else toast("Fatura e artigos registados e enviados para aprovação.");
      } else toast("Fatura registada e enviada para aprovação.");
      saved = true;
    }
  }
  if (!saved) {
    submit.disabled = false;
    submit.firstChild.textContent = "REGISTAR FATURA ";
    return;
  }
  const keepWork = form.obra_id.value, keepType = form.tipo_origem.value;
  form.reset(); form.obra_id.value = keepWork; form.tipo_origem.value = keepType; form.data_fatura.value = new Date().toISOString().slice(0, 10);
  resetMaterialItems();
  extractedMaterialItems = [];
  extractedMaterialItemsApplied = false;
  $("#material-items-editor").hidden = keepType !== "material";
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
  const pdfButton = event.target.closest("[data-pdf], [data-guide], [data-invoice-attachment]");
  if (pdfButton) {
    pdfButton.disabled = true;
    try {
      const objectPath = decodeURIComponent(pdfButton.dataset.pdf || pdfButton.dataset.guide || pdfButton.dataset.invoiceAttachment);
      const blob = await downloadInvoicePdf(objectPath);
      openedPdfUrl = URL.createObjectURL(blob);
      openPdfModal(openedPdfUrl, pdfButton.dataset.guide ? "GUIA DE REMESSA" : pdfButton.dataset.invoiceAttachment ? "ANEXO ADICIONAL" : "FATURA");
    } catch (error) {
      toast(error.message || "Não foi possível abrir o PDF.", "error");
    } finally {
      pdfButton.disabled = false;
    }
    return;
  }
  const button = event.target.closest("[data-action]"); if (!button) return;
  if (!canApproveInvoices()) return toast("Não tem permissão para aprovar ou recusar faturas.", "error");
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
    const result = await supabase("rpc/fn_decidir_fatura", {
      method: "POST",
      body: JSON.stringify({ p_fatura_id: invoice.id, p_decisao: decision }),
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
  const attachmentInput = event.target.closest("[data-invoice-attachment-input]");
  if (attachmentInput) {
    const files = [...attachmentInput.files];
    if (!files.length) return;
    const invoice = invoices.find(item => String(item.id) === attachmentInput.dataset.invoiceAttachmentInput);
    if (!invoice) return;
    attachmentInput.disabled = true;
    (async () => {
      for (const file of files) {
        const path = await uploadInvoiceAttachment(file, invoice.obra_id, invoice.id);
        const response = await supabase("faturas_anexos?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ fatura_id: invoice.id, arquivo_url: path, nome_arquivo: file.name }) });
        if (!response.ok) throw new Error(await response.text());
        invoiceAttachments.push((await response.json())[0]);
      }
      toast("Anexos adicionais enviados."); renderInvoices();
    })().catch(error => toast(error.message || "Não foi possível enviar os anexos.", "error")).finally(() => { attachmentInput.disabled = false; });
    return;
  }
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
  const guideButton = event.target.closest("[data-guide], [data-invoice-attachment]");
  if (guideButton) {
    try {
      const path = decodeURIComponent(guideButton.dataset.guide || guideButton.dataset.invoiceAttachment);
      const title = guideButton.dataset.guide ? "GUIA DE REMESSA" : "ANEXO ADICIONAL";
      if (path.startsWith("blob:")) return openPdfModal(path, title);
      const blob = await downloadInvoicePdf(path);
      openedPdfUrl = URL.createObjectURL(blob);
      openPdfModal(openedPdfUrl, title);
    } catch (error) { toast(error.message || "Não foi possível abrir a guia.", "error"); }
    return;
  }
  const button = event.target.closest("[data-mark-paid]");
  if (!button) return;
  if (!canPayInvoices()) return toast("O pagamento está reservado ao papel Financeiro.", "error");
  const invoice = financeInvoices.find(item => String(item.id) === button.dataset.markPaid);
  if (!invoice) return;
  button.disabled = true;
  const paymentDate = button.closest(".finance-card")?.querySelector("[data-payment-date]")?.value || new Date().toISOString().slice(0, 10);
  const paidAt = `${paymentDate}T12:00:00`;
  if (isSupabaseConfigured) {
    const result = await supabase("rpc/fn_marcar_fatura_paga", {
      method: "POST",
      body: JSON.stringify({ p_fatura_id: invoice.id, p_data_pagamento: paymentDate }),
    });
    if (!result.ok) {
      toast(`Não foi possível marcar a fatura como paga: ${await result.text()}`, "error");
      button.disabled = false;
      return;
    }
  }
  invoice.data_pagamento = paidAt;
  invoice.estado_pagamento = "pago";
  invoice.pago_por = accessContext.profile?.id || null;
  renderFinance();
  toast(`Fatura marcada como paga${isSupabaseConfigured ? "" : " em modo de demonstração"}.`);
});

document.querySelector(".finance-tabs").addEventListener("click", event => {
  const button = event.target.closest("[data-finance-tab]");
  if (!button) return;
  selectedFinanceTab = button.dataset.financeTab;
  renderFinanceTabs();
});

$("#direct-debit-form").addEventListener("submit", async event => {
  event.preventDefault();
  if (!canManageDirectDebits()) return toast("Sem permissão para criar débitos diretos.", "error");
  const form = event.currentTarget;
  const fields = Object.fromEntries(new FormData(form).entries());
  const error = $("#direct-debit-form-error");
  error.textContent = "";
  if (fields.recorrencia && !fields.dia_mes) {
    error.textContent = "Indique o dia do mês para gerar as previsões recorrentes.";
    return;
  }
  if (fields.data_fim && fields.data_fim < fields.data_inicio) {
    error.textContent = "A data de fim não pode ser anterior à data de início.";
    return;
  }
  const payload = {
    obra_id: fields.obra_id || null,
    descricao: fields.descricao.trim(),
    categoria: fields.categoria || "outro",
    valor_previsto: Number(fields.valor_previsto),
    recorrencia: fields.recorrencia || null,
    dia_mes: fields.recorrencia ? Number(fields.dia_mes) : null,
    data_inicio: fields.data_inicio,
    data_fim: fields.data_fim || null,
    ativo: form.elements.ativo.checked,
    criado_por: accessContext.profile?.id || null,
  };
  const submit = form.querySelector('button[type="submit"]');
  submit.disabled = true;
  try {
    if (isSupabaseConfigured) {
      const response = await supabase("debitos_diretos?select=*", {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        const detail = await response.json().catch(() => ({}));
        throw new Error(detail.message || detail.details || "Não foi possível criar o débito direto.");
      }
      Object.assign(payload, (await response.json())[0]);
    } else payload.id = crypto.randomUUID();
    directDebits.push(payload);
    form.reset();
    form.elements.ativo.checked = true;
    form.elements.data_inicio.value = new Date().toISOString().slice(0, 10);
    renderDirectDebits();
    toast("Débito direto criado com sucesso.");
  } catch (submitError) {
    error.textContent = submitError.message || "Não foi possível criar o débito direto.";
  } finally {
    submit.disabled = false;
  }
});

$("#direct-debit-list").addEventListener("click", event => {
  const button = event.target.closest("[data-toggle-direct-debit]");
  if (!button) return;
  expandedDirectDebitId = expandedDirectDebitId === button.dataset.toggleDirectDebit ? "" : button.dataset.toggleDirectDebit;
  renderDirectDebits();
});

$("#direct-debit-list").addEventListener("submit", async event => {
  const form = event.target.closest("[data-direct-debit-entry]");
  if (!form) return;
  event.preventDefault();
  if (!canManageDirectDebits()) return toast("Sem permissão para registar lançamentos.", "error");
  const fields = Object.fromEntries(new FormData(form).entries());
  const error = form.querySelector(".form-error");
  error.textContent = "";
  const payload = {
    debito_direto_id: form.dataset.directDebitEntry,
    data: fields.data,
    valor: Number(fields.valor),
  };
  const submit = form.querySelector('button[type="submit"]');
  submit.disabled = true;
  try {
    if (isSupabaseConfigured) {
      const response = await supabase("debitos_diretos_lancamentos?select=*", {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        const detail = await response.json().catch(() => ({}));
        throw new Error(detail.code === "23505" ? "Já existe um lançamento deste débito nesta data." : detail.message || detail.details || "Não foi possível registar o lançamento.");
      }
      Object.assign(payload, (await response.json())[0]);
    } else payload.id = crypto.randomUUID();
    directDebitEntries.push(payload);
    renderDirectDebits();
    toast("Lançamento real registado com sucesso.");
  } catch (submitError) {
    error.textContent = submitError.message || "Não foi possível registar o lançamento.";
    submit.disabled = false;
  }
});

settingsModule = createSettingsModule({
  root: $("#settings-view"),
  supabase,
  isConfigured: isSupabaseConfigured,
  companyId: PRIMELINE_COMPANY_ID,
  getProfile: () => accessContext.profile,
  getSession,
  getWorks: () => works,
  isAdmin: hasFullAccess,
  toast,
  requestPasswordReset,
  toggleTheme: toggleThemePreference,
  toggleTv: toggleTvPreference,
  syncPreferences: syncDisplayToggles,
});
procurementModule = createProcurementModule({
  host: $("#work-detail"),
  supabase,
  isConfigured: isSupabaseConfigured,
  getPhases: () => workDetails.phases,
  getSuppliers: () => suppliers,
  getSubcontracts: () => subcontracts,
  euro,
  toast,
  onConsultationsChanged: rows => { workDetails.consultations = rows; },
  onAdjudicated: async result => {
    const row = Array.isArray(result) ? result[0] : result;
    if (!row?.id) return;
    const existing = subcontracts.find(item => item.id === row.id);
    if (existing) Object.assign(existing, row); else subcontracts.push(row);
  },
});
renderUser();
loadData();
