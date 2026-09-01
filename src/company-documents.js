import { platformConfirm } from "./platform-dialogs.js?v=1";

const DOCUMENT_TYPES = [
  ["certidao_permanente_comercial", "Certidão permanente / comercial"],
  ["rcbe", "RCBE"],
  ["certidao_nao_divida_financas", "Certidão de não dívida — Finanças"],
  ["certidao_nao_divida_seguranca_social", "Certidão de não dívida — Segurança Social"],
  ["inpi", "INPI"],
  ["seguro_acidentes_trabalho", "Seguro de acidentes de trabalho"],
  ["seguro_responsabilidade_civil", "Seguro de responsabilidade civil"],
];

const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
const typeLabel = value => DOCUMENT_TYPES.find(([key]) => key === value)?.[1] || String(value || "Outro documento").replaceAll("_", " ");
const formatDate = value => value ? new Intl.DateTimeFormat("pt-PT").format(new Date(`${value}T12:00:00`)) : "Sem data";

function validityInfo(value) {
  if (!value) return { tone: "neutral", label: "SEM VALIDADE DEFINIDA", days: null };
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const expiry = new Date(`${value}T00:00:00`);
  const days = Math.ceil((expiry - today) / 86400000);
  if (days < 0) return { tone: "expired", label: `VENCIDO HÁ ${Math.abs(days)} DIA${Math.abs(days) === 1 ? "" : "S"}`, days };
  if (days === 0) return { tone: "critical", label: "VENCE HOJE", days };
  if (days <= 3) return { tone: "critical", label: `VENCE EM ${days} DIA${days === 1 ? "" : "S"}`, days };
  if (days <= 7) return { tone: "urgent", label: `VENCE EM ${days} DIAS`, days };
  if (days <= 15) return { tone: "warning", label: `VENCE EM ${days} DIAS`, days };
  return { tone: "valid", label: `VÁLIDO ATÉ ${formatDate(value)}`, days };
}

export function createCompanyDocumentsModule({ root, supabase, isConfigured, companyId, uploadDocument, downloadDocument, deleteDocument, toast }) {
  const state = { loaded: false, loading: false, documents: [], error: "" };
  const localFiles = new Map();

  function render() {
    const expiring = state.documents.filter(item => {
      const info = validityInfo(item.data_validade);
      return info.days !== null && info.days <= 15;
    }).length;
    root.innerHTML = `<div class="page-heading company-documents-heading">
      <div><p class="eyebrow">ARQUIVO INSTITUCIONAL</p><h1>DOCUMENTOS DA EMPRESA</h1><p>Certidões, registos e seguros da PRIMELINE.</p></div>
      <div class="heading-stat"><span>A VENCER / VENCIDOS</span><strong>${String(expiring).padStart(2, "0")}</strong></div>
    </div>
    ${state.error ? `<div class="work-warning"><strong>DOCUMENTOS INDISPONÍVEIS</strong><span>${escapeHtml(state.error)}</span></div>` : ""}
    <section class="panel company-document-upload-panel">
      <header><div><p class="eyebrow">NOVO REGISTO</p><h2>CARREGAR DOCUMENTO</h2></div><span>PDF, imagem, Excel/CSV ou Word · máximo 25 MB</span></header>
      <form id="company-document-form" class="company-document-form">
        <label>TIPO DE DOCUMENTO<select name="tipo_documento" required><option value="">Selecionar tipo</option>${DOCUMENT_TYPES.map(([value, label]) => `<option value="${value}">${label}</option>`).join("")}</select></label>
        <label>DATA DE EMISSÃO<input name="data_emissao" type="date"></label>
        <label>DATA DE VALIDADE<input name="data_validade" type="date"><small>Os alertas de 15, 7 e 3 dias usam esta data.</small></label>
        <label class="company-document-file">FICHEIRO<input name="file" type="file" accept=".pdf,.jpg,.jpeg,.png,.webp,.heic,.xls,.xlsx,.csv,.doc,.docx" required></label>
        <button class="primary-button" type="submit">CARREGAR DOCUMENTO <span>→</span></button>
        <p class="form-error"></p>
      </form>
    </section>
    <section class="panel company-document-directory">
      <header><div><p class="eyebrow">ARQUIVO</p><h2>DOCUMENTOS REGISTADOS</h2></div><span>${state.documents.length} DOCUMENTO${state.documents.length === 1 ? "" : "S"}</span></header>
      <div class="company-document-list">${state.loading ? '<div class="empty-state">A CARREGAR DOCUMENTOS…</div>' : renderDocuments()}</div>
    </section>`;
    bindEvents();
  }

  function renderDocuments() {
    if (!state.documents.length) return '<div class="empty-state"><strong>SEM DOCUMENTOS REGISTADOS</strong><span>Use “Carregar documento” para criar o primeiro registo.</span></div>';
    return [...state.documents].sort((left, right) => {
      if (!left.data_validade) return 1;
      if (!right.data_validade) return -1;
      return left.data_validade.localeCompare(right.data_validade);
    }).map(item => {
      const validity = validityInfo(item.data_validade);
      return `<article class="company-document-row ${validity.tone}">
        <div class="company-document-icon">▤</div>
        <div class="company-document-identity"><span>${escapeHtml(typeLabel(item.tipo_documento))}</span><strong>${escapeHtml(item.nome_arquivo || "Documento")}</strong><small>Emitido em ${formatDate(item.data_emissao)} · carregado em ${formatDate(String(item.criado_em || "").slice(0, 10))}</small></div>
        <div class="company-document-validity"><span>VALIDADE</span><strong>${formatDate(item.data_validade)}</strong><b>${escapeHtml(validity.label)}</b></div>
        <div><button type="button" class="outline-action" data-company-document-download="${encodeURIComponent(item.url_arquivo || "")}" data-file-name="${escapeHtml(item.nome_arquivo || "documento")}">DESCARREGAR</button><button type="button" class="danger-action" data-company-document-delete="${item.id}" data-object-path="${encodeURIComponent(item.url_arquivo || "")}" data-file-name="${escapeHtml(item.nome_arquivo || "documento")}">APAGAR</button></div>
      </article>`;
    }).join("");
  }

  async function load(force = false) {
    if (state.loading || (state.loaded && !force)) return;
    state.loading = true; state.error = ""; render();
    try {
      if (!isConfigured) {
        state.documents = [];
      } else {
        const response = await supabase(`documentos?select=id,empresa_id,entidade_tipo,entidade_id,tipo_documento,nome_arquivo,url_arquivo,data_emissao,data_validade,criado_em&entidade_tipo=eq.empresa&entidade_id=eq.${encodeURIComponent(companyId)}&order=criado_em.desc`);
        if (!response.ok) throw new Error((await response.json().catch(() => ({}))).message || "Não foi possível consultar o arquivo da empresa.");
        state.documents = await response.json();
      }
      state.loaded = true;
    } catch (error) { state.error = error.message; }
    finally { state.loading = false; render(); }
  }

  async function submit(form) {
    const error = form.querySelector(".form-error");
    const button = form.querySelector('button[type="submit"]');
    const file = form.elements.file.files[0];
    const type = form.elements.tipo_documento.value;
    error.textContent = "";
    if (!file) { error.textContent = "Selecione um ficheiro."; return; }
    button.disabled = true;
    try {
      let objectPath;
      if (isConfigured) objectPath = await uploadDocument(file, "empresa", companyId, type);
      else {
        objectPath = `demo/empresa/${crypto.randomUUID()}-${file.name}`;
        localFiles.set(objectPath, file);
      }
      const payload = {
        empresa_id: companyId, entidade_tipo: "empresa", entidade_id: companyId,
        tipo_documento: type, nome_arquivo: file.name, url_arquivo: objectPath,
        data_emissao: form.elements.data_emissao.value || null,
        data_validade: form.elements.data_validade.value || null,
      };
      if (isConfigured) {
        const response = await supabase("documentos?select=id,empresa_id,entidade_tipo,entidade_id,tipo_documento,nome_arquivo,url_arquivo,data_emissao,data_validade,criado_em", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        if (!response.ok) throw new Error((await response.json().catch(() => ({}))).message || "Não foi possível guardar o documento.");
        Object.assign(payload, (await response.json())[0]);
      } else Object.assign(payload, { id: crypto.randomUUID(), criado_em: new Date().toISOString() });
      state.documents.unshift(payload); form.reset(); render(); toast("Documento da empresa carregado com sucesso.");
    } catch (uploadError) { error.textContent = uploadError.message || "Não foi possível carregar o documento."; }
    finally { button.disabled = false; }
  }

  function bindEvents() {
    root.querySelector("#company-document-form")?.addEventListener("submit", event => { event.preventDefault(); submit(event.currentTarget); });
    root.querySelector(".company-document-list")?.addEventListener("click", async event => {
      const deleteButton = event.target.closest("[data-company-document-delete]");
      if (deleteButton) {
        if (!await platformConfirm(`Apagar “${deleteButton.dataset.fileName}”? Esta ação fica registada na auditoria.`, { title: "Apagar documento da empresa", danger: true, confirmLabel: "APAGAR" })) return;
        deleteButton.disabled = true;
        try {
          const id = deleteButton.dataset.companyDocumentDelete;
          const path = decodeURIComponent(deleteButton.dataset.objectPath || "");
          if (isConfigured) {
            const response = await supabase("rpc/fn_apagar_documento_entidade", { method: "POST", body: JSON.stringify({ p_documento_id: id }) });
            if (!response.ok) throw new Error((await response.json().catch(() => ({}))).message || "Não foi possível apagar o documento.");
            if (path) await deleteDocument(path);
          } else { localFiles.delete(path); state.documents = state.documents.filter(item => item.id !== id); }
          toast("Documento apagado e registado na auditoria.");
          if (isConfigured) await load(true); else render();
        } catch (error) { toast(error.message || "Não foi possível apagar o documento.", "error"); deleteButton.disabled = false; }
        return;
      }
      const button = event.target.closest("[data-company-document-download]");
      if (!button) return;
      const path = decodeURIComponent(button.dataset.companyDocumentDownload || "");
      button.disabled = true;
      try {
        const blob = localFiles.get(path) || await downloadDocument(path);
        const objectUrl = URL.createObjectURL(blob);
        const link = document.createElement("a"); link.href = objectUrl; link.download = button.dataset.fileName || "documento";
        document.body.appendChild(link); link.click(); link.remove(); setTimeout(() => URL.revokeObjectURL(objectUrl), 60000);
      } catch (error) { toast(error.message || "Não foi possível descarregar o documento.", "error"); }
      finally { button.disabled = false; }
    });
  }

  function show() { render(); load(); }
  return { show, refresh: () => load(true) };
}
