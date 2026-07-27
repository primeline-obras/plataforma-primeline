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

let works = [], suppliers = [], subcontracts = [], invoices = [];
let currentFilter = "all";
let session = getSession();
let selectedPdf = null;
let localPdfUrl = "";
let openedPdfUrl = "";

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
        <button>▦ <span>Visão geral</span></button><button>▥ <span>Obras</span></button>
        <button class="active">▤ <span>Faturas</span></button><button>□ <span>Documentos</span></button><button>♙ <span>Equipa</span></button>
        <p>CONFIGURAÇÃO</p><button>⚙ <span>Definições</span></button>
      </nav>
      <div class="sidebar-user"><span id="user-initials">PL</span><div><strong id="user-name">UTILIZADOR</strong><small id="user-role">SESSÃO AUTENTICADA</small></div><button class="logout-button" id="logout" title="Terminar sessão">↗</button></div>
    </aside>
    <main>
      <header class="topbar"><button class="mobile-menu" id="menu">${icon("menu")}</button><div class="mobile-brand">${brand()}</div>
        <div class="top-actions">${!isSupabaseConfigured ? '<span class="demo-badge">MODO DEMONSTRAÇÃO</span>' : ""}<button class="icon-button">${icon("bell")}<i>3</i></button></div>
      </header>
      <div class="page">
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
    </main>
    <div id="toast"></div>
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
      supabase("obras?select=id,numero,nome&order=numero.desc"),
      supabase("fornecedores?select=id,nome&estado_confianca=neq.inativo&order=nome"),
      supabase("subempreitadas?select=id,obra_id,fornecedor_id,especialidade&order=especialidade"),
      supabase("faturas?select=*&estado_aprovacao=eq.pendente&order=criado_em.desc"),
    ]);
    const failed = results.find(result => !result.ok);
    if (failed) { toast(`Não foi possível carregar os dados: ${await failed.text()}`, "error"); return; }
    [works, suppliers, subcontracts, invoices] = await Promise.all(results.map(result => result.json()));
  }
  renderSelectors(); renderInvoices();
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
$("#menu").addEventListener("click", () => $(".sidebar").classList.add("open"));
$("#scrim").addEventListener("click", () => $(".sidebar").classList.remove("open"));
$("#choose-pdf").addEventListener("click", () => $("#pdf-input").click());
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
