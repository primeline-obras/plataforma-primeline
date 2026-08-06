const DOCUMENT_TYPES = [
  ["articulado_original", "Articulado — Orçamento original"],
  ["articulado_tee", "Articulado — TEE aprovado"],
  ["orcamento", "Orçamento"],
  ["desenho", "Desenho"],
  ["desenhos_preparacao", "Desenho de preparação"],
  ["plantas_projeto", "Plantas / Projeto"],
  ["pdes_rfis", "PDE / RFI"],
  ["pames", "PAME"],
  ["atas_reuniao", "Ata de reunião"],
  ["contrato", "Contrato"],
  ["licencas", "Licença"],
  ["planeamento_detalhado", "Planeamento detalhado"],
  ["outro", "Outro"],
];

const PRIMARY_SECTIONS = [
  { id: "articulado", label: "Articulado", description: "Orçamento original e TEEs aprovados", types: ["articulado_original", "articulado_tee", "orcamento"] },
  { id: "drawings", label: "Desenhos", description: "Últimas revisões de preparação", types: ["desenho", "desenhos_preparacao", "plantas_projeto"] },
  { id: "technical", label: "PDEs / PAMEs", description: "Pedidos e aprovações técnicas", types: ["pdes_rfis", "pames"] },
  { id: "minutes", label: "Atas", description: "Registos de reunião", types: ["atas_reuniao"] },
];

const GENERAL_SECTION = {
  id: "general",
  label: "Arquivo geral",
  description: "Restantes documentos da obra",
  types: ["contrato", "licencas", "planeamento_detalhado", "outro"],
};

const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

const extension = name => String(name || "").split(".").pop()?.toLowerCase() || "";
const canPreview = document => ["pdf", "jpg", "jpeg", "png", "webp", "heic"].includes(extension(document.nome_arquivo));
const typeLabel = type => DOCUMENT_TYPES.find(([value]) => value === type)?.[1] || "Outro";
const indexNumber = item => item.numero_documento || item.numero || item.codigo || "Sem número";

function latestByDocumentNumber(documents) {
  const grouped = new Map();
  documents.forEach(document => {
    const key = document.numero_documento || document.nome_arquivo || document.id;
    const current = grouped.get(key);
    const rank = `${document.revisao || ""}|${document.criado_em || ""}`;
    const currentRank = current ? `${current.revisao || ""}|${current.criado_em || ""}` : "";
    if (!current || rank.localeCompare(currentRank, "pt-PT", { numeric: true }) > 0) grouped.set(key, document);
  });
  return [...grouped.values()];
}

export function createDocumentsModule({
  root,
  supabase,
  isConfigured,
  getWorks,
  getProfile,
  getRole,
  uploadWorkDocument,
  downloadWorkDocument,
  prettyDate,
  toast,
  previewBlob,
}) {
  let selectedWorkId = "";
  let selectedSection = "articulado";
  let loading = false;
  let data = emptyData();
  const localFiles = new Map();

  function emptyData() {
    return { documents: [], users: {}, drawings: [], rfis: [], canEdit: false, error: "", indexError: "" };
  }

  function sections() {
    return getRole() === "encarregado" ? PRIMARY_SECTIONS : [...PRIMARY_SECTIONS, GENERAL_SECTION];
  }

  function currentSection() {
    return sections().find(section => section.id === selectedSection) || sections()[0];
  }

  function sectionCount(section) {
    const rows = data.documents.filter(document => section.types.includes(document.tipo));
    return section.id === "drawings" ? latestByDocumentNumber(rows).length : rows.length;
  }

  function renderHeading() {
    const works = getWorks();
    return `<div class="page-heading documents-heading">
      <div><p class="eyebrow">ARQUIVO TÉCNICO</p><h1>DOCUMENTOS</h1><p>Documentação operacional organizada por obra e categoria.</p></div>
      <label class="documents-work-picker">OBRA<div class="select-wrap"><select data-documents-work ${works.length ? "" : "disabled"}>
        ${works.length ? works.map(work => `<option value="${work.id}" ${work.id === selectedWorkId ? "selected" : ""}>Obra ${escapeHtml(work.numero || "—")} · ${escapeHtml(work.nome)}</option>`).join("") : '<option>Sem obras disponíveis</option>'}
      </select><b>⌄</b></div></label>
    </div>`;
  }

  function renderNavigation() {
    return `<nav class="document-section-nav" aria-label="Grupos de documentos">${sections().map(section => `
      <button type="button" data-document-section="${section.id}" class="${section.id === currentSection().id ? "active" : ""}">
        <span>${escapeHtml(section.label)}</span><small>${escapeHtml(section.description)}</small><b>${sectionCount(section)}</b>
      </button>`).join("")}</nav>`;
  }

  function renderUpload(section) {
    if (!data.canEdit) return `<div class="work-document-readonly"><strong>CONSULTA DE DOCUMENTOS</strong><span>Pode consultar e descarregar. O envio está reservado à equipa autorizada da obra.</span></div>`;
    const allowedTypes = DOCUMENT_TYPES.filter(([type]) => section.types.includes(type));
    return `<details class="document-upload-panel">
      <summary>＋ CARREGAR FICHEIRO</summary>
      <form class="work-document-upload" id="documents-center-upload">
        <div><p class="eyebrow">${escapeHtml(section.label)}</p><h3>ADICIONAR DOCUMENTO</h3><span>PDF, imagem, Excel, Word, MS Project, DWG/DXF, ZIP ou TXT · máximo 25 MB</span></div>
        <label>TIPO<div class="select-wrap"><select name="tipo" required>${allowedTypes.map(([value, label]) => `<option value="${value}">${escapeHtml(label)}</option>`).join("")}</select><b>⌄</b></div></label>
        <label class="work-document-index-field" data-document-number hidden>NÚMERO / REFERÊNCIA<input name="numero_documento" maxlength="80" placeholder="Ex.: DES-042, PDE-018 ou TEE 20"></label>
        <label class="work-document-index-field" data-document-revision hidden>REVISÃO<input name="revisao" maxlength="30" placeholder="Ex.: A ou 02"></label>
        <label class="work-document-file">FICHEIRO<input name="arquivo" type="file" required accept=".pdf,.jpg,.jpeg,.png,.webp,.heic,.xls,.xlsx,.doc,.docx,.mpp,.dwg,.dxf,.zip,.txt"></label>
        <button class="primary-button" type="submit">ENVIAR <span>→</span></button><p class="form-error"></p>
      </form>
    </details>`;
  }

  function drawingIndex() {
    const rows = [...data.drawings].reduce((grouped, item) => {
      const key = indexNumber(item);
      const current = grouped.get(key);
      const rank = `${item.revisao || ""}|${item.data_emissao || ""}`;
      const currentRank = current ? `${current.revisao || ""}|${current.data_emissao || ""}` : "";
      if (!current || rank.localeCompare(currentRank, "pt-PT", { numeric: true }) > 0) grouped.set(key, item);
      return grouped;
    }, new Map());
    const drawings = [...rows.values()].sort((a, b) => indexNumber(a).localeCompare(indexNumber(b), "pt-PT", { numeric: true }));
    return `<section class="document-index-card"><header><div><p class="eyebrow">CONTROLO DE REVISÕES</p><h3>ÚLTIMA VERSÃO DOS DESENHOS</h3></div><span>${drawings.length}</span></header>
      <div class="document-index-list">${drawings.length ? drawings.map(item => `<article><div><span>NÚMERO</span><strong>${escapeHtml(indexNumber(item))}</strong></div><div><span>REVISÃO ATUAL</span><strong>${escapeHtml(item.revisao || "—")}</strong></div><div><span>DATA</span><strong>${formatDate(item.data_emissao)}</strong></div></article>`).join("") : '<div class="work-document-empty">SEM DESENHOS INDEXADOS</div>'}</div></section>`;
  }

  function pdeIndex() {
    const rows = [...data.rfis].sort((a, b) => String(b.data_envio || "").localeCompare(String(a.data_envio || "")));
    return `<section class="document-index-card"><header><div><p class="eyebrow">PEDIDOS DE ESCLARECIMENTO</p><h3>ÍNDICE DE PDEs</h3></div><span>${rows.length}</span></header>
      <div class="document-index-list">${rows.length ? rows.map(item => { const status = String(item.estado || (item.data_resposta ? "respondido" : "enviado")).toLowerCase(); return `<article><div><span>NÚMERO</span><strong>${escapeHtml(indexNumber(item))}</strong></div><div><span>ESTADO</span><strong class="index-state ${escapeHtml(status)}">${escapeHtml(status.replaceAll("_", " ").toUpperCase())}</strong></div><div><span>DATA</span><strong>${formatDate(item.data_envio)}</strong></div></article>`; }).join("") : '<div class="work-document-empty">SEM PDEs INDEXADOS</div>'}</div></section>`;
  }

  function formatDate(value) {
    if (!value) return "—";
    const date = new Date(`${String(value).slice(0, 10)}T12:00:00`);
    return Number.isNaN(date.getTime()) ? "—" : prettyDate.format(date);
  }

  function renderDocumentRows(section) {
    let documents = data.documents.filter(document => section.types.includes(document.tipo));
    if (section.id === "drawings") documents = latestByDocumentNumber(documents);
    if (!documents.length) return '<div class="document-section-empty"><strong>AINDA SEM FICHEIROS</strong><span>Use “Carregar ficheiro” para adicionar o primeiro documento deste grupo.</span></div>';
    const grouped = new Map(section.types.map(type => [type, []]));
    documents.forEach(document => (grouped.get(document.tipo) || grouped.get(section.types[0]))?.push(document));
    return `<div class="work-document-groups">${section.types.map(type => {
      const rows = grouped.get(type) || [];
      if (!rows.length && section.types.length > 1) return "";
      return `<section class="work-document-group"><header><div><p class="eyebrow">${escapeHtml(typeLabel(type))}</p><h3>${escapeHtml(typeLabel(type).toUpperCase())}</h3></div><span>${rows.length}</span></header><div class="work-document-list">
        ${rows.length ? rows.map(document => { const path = encodeURIComponent(document.arquivo_url || ""); return `<article class="work-document-row"><div class="work-document-icon">${escapeHtml(extension(document.nome_arquivo).slice(0, 4).toUpperCase() || "DOC")}</div><div class="work-document-name"><strong title="${escapeHtml(document.nome_arquivo)}">${escapeHtml(document.nome_arquivo)}</strong><span>${escapeHtml(typeLabel(document.tipo))}${document.numero_documento ? ` · ${escapeHtml(document.numero_documento)}` : ""}${document.revisao ? ` · REV. ${escapeHtml(document.revisao)}` : ""}</span></div><div class="work-document-meta"><span>ENVIADO POR</span><strong>${escapeHtml(data.users[document.enviado_por] || "Utilizador")}</strong></div><div class="work-document-meta"><span>DATA</span><strong>${formatDate(document.criado_em)}</strong></div><div class="work-document-actions">${canPreview(document) ? `<button type="button" data-document-preview="${path}" data-document-name="${escapeHtml(document.nome_arquivo)}">PRÉ-VISUALIZAR</button>` : ""}<button type="button" data-document-download="${path}" data-document-name="${escapeHtml(document.nome_arquivo)}">DESCARREGAR</button></div></article>`; }).join("") : '<div class="work-document-empty">SEM DOCUMENTOS NESTA CATEGORIA</div>'}
      </div></section>`;
    }).join("")}</div>`;
  }

  function render() {
    const works = getWorks();
    if (!selectedWorkId && works[0]) selectedWorkId = works[0].id;
    if (!works.length) {
      root.innerHTML = `${renderHeading()}<div class="empty-state"><strong>SEM OBRAS DISPONÍVEIS</strong><span>Não existem obras associadas a este utilizador.</span></div>`;
      return;
    }
    if (loading) {
      root.innerHTML = `${renderHeading()}<div class="empty-state">A CARREGAR DOCUMENTOS…</div>`;
      return;
    }
    const section = currentSection();
    root.innerHTML = `${renderHeading()}${data.error ? `<div class="work-warning"><strong>DADOS PARCIAIS</strong><span>${escapeHtml(data.error)}</span></div>` : ""}<section class="documents-center-panel">${renderNavigation()}<div class="document-section-head"><div><p class="eyebrow">${escapeHtml(section.label)}</p><h2>${escapeHtml(section.description)}</h2></div></div>${renderUpload(section)}${data.indexError ? `<div class="work-warning"><strong>ÍNDICES PARCIAIS</strong><span>${escapeHtml(data.indexError)}</span></div>` : ""}${section.id === "drawings" ? `<div class="document-indexes">${drawingIndex()}</div>` : ""}${section.id === "technical" ? `<div class="document-indexes">${pdeIndex()}</div>` : ""}${renderDocumentRows(section)}</section>`;
    syncUploadFields(root.querySelector("#documents-center-upload"));
  }

  async function load(workId = selectedWorkId) {
    selectedWorkId = workId || getWorks()[0]?.id || "";
    if (!selectedWorkId) return render();
    loading = true;
    data = emptyData();
    render();
    if (!isConfigured) {
      data.canEdit = true;
      loading = false;
      render();
      return;
    }
    const encoded = encodeURIComponent(selectedWorkId);
    const [documentsResult, permissionResult, drawingsResult, rfisResult] = await Promise.all([
      supabase(`documentos_obra?select=*&obra_id=eq.${encoded}&order=criado_em.desc`),
      supabase("rpc/fn_pode_editar_documentos_obra", { method: "POST", body: JSON.stringify({ p_obra_id: selectedWorkId }) }),
      supabase(`desenhos?select=*&obra_id=eq.${encoded}&order=numero.asc,revisao.desc`),
      supabase(`rfis?select=*&obra_id=eq.${encoded}&order=numero.asc`),
    ]);
    if (documentsResult.ok) data.documents = await documentsResult.json();
    else data.error = "Não foi possível consultar os documentos desta obra. Confirme as políticas RLS.";
    if (permissionResult.ok) data.canEdit = Boolean(await permissionResult.json());
    if (drawingsResult.ok) data.drawings = await drawingsResult.json(); else data.indexError = "Não foi possível consultar o índice de desenhos.";
    if (rfisResult.ok) data.rfis = await rfisResult.json(); else data.indexError += `${data.indexError ? " " : ""}Não foi possível consultar o índice de PDEs.`;
    const userIds = [...new Set(data.documents.map(item => item.enviado_por).filter(Boolean))];
    if (userIds.length) {
      const usersResult = await supabase(`utilizadores?select=id,nome&id=in.(${userIds.map(encodeURIComponent).join(",")})`);
      if (usersResult.ok) data.users = Object.fromEntries((await usersResult.json()).map(user => [user.id, user.nome]));
    }
    loading = false;
    render();
  }

  function syncUploadFields(form) {
    if (!form) return;
    const type = form.elements.tipo.value;
    const needsNumber = ["desenho", "desenhos_preparacao", "pdes_rfis"].includes(type);
    const showsReference = needsNumber || type === "articulado_tee";
    form.querySelector("[data-document-number]").hidden = !showsReference;
    form.querySelector("[data-document-revision]").hidden = !["desenho", "desenhos_preparacao"].includes(type);
    form.elements.numero_documento.required = needsNumber;
  }

  async function submitUpload(form) {
    const file = form.elements.arquivo.files[0];
    const type = form.elements.tipo.value;
    const documentNumber = form.elements.numero_documento.value.trim();
    const revision = form.elements.revisao.value.trim();
    const indexed = ["desenho", "desenhos_preparacao", "pdes_rfis"].includes(type);
    const error = form.querySelector(".form-error");
    const button = form.querySelector('button[type="submit"]');
    if (!file) return;
    if (indexed && !documentNumber) {
      error.textContent = "O número do documento é obrigatório para Desenhos e PDEs.";
      return form.elements.numero_documento.focus();
    }
    button.disabled = true;
    error.textContent = "";
    try {
      let saved;
      if (isConfigured) {
        const objectPath = await uploadWorkDocument(file, selectedWorkId, type);
        const response = await supabase("documentos_obra?select=*", {
          method: "POST",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify({ obra_id: selectedWorkId, tipo: type, nome_arquivo: file.name, arquivo_url: objectPath, enviado_por: getProfile()?.id, numero_documento: documentNumber || null, revisao: ["desenho", "desenhos_preparacao"].includes(type) ? revision || null : null }),
        });
        if (!response.ok) {
          const detail = await response.json().catch(() => ({}));
          throw new Error(detail.message || "O ficheiro foi enviado, mas não foi possível registar o documento.");
        }
        [saved] = await response.json();
      } else {
        const objectPath = `local:${crypto.randomUUID()}`;
        localFiles.set(objectPath, file);
        saved = { id: crypto.randomUUID(), obra_id: selectedWorkId, tipo: type, nome_arquivo: file.name, arquivo_url: objectPath, numero_documento: documentNumber || null, revisao: revision || null, enviado_por: "demo", criado_em: new Date().toISOString() };
        data.users.demo = "Utilizador de demonstração";
      }
      data.documents.unshift(saved);
      toast("Documento adicionado à obra.");
      if (isConfigured) await load(selectedWorkId);
      else render();
    } catch (uploadError) {
      error.textContent = uploadError.message || "Não foi possível enviar o documento.";
      button.disabled = false;
    }
  }

  async function openDocument(button, preview) {
    const path = decodeURIComponent(button.dataset.documentPreview || button.dataset.documentDownload || "");
    const name = button.dataset.documentName || "documento";
    button.disabled = true;
    try {
      const blob = localFiles.get(path) || await downloadWorkDocument(path);
      if (preview) previewBlob(blob, name);
      else {
        const url = URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = url;
        link.download = name;
        link.click();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      }
    } catch (error) {
      toast(error.message || "Não foi possível abrir o documento.", "error");
    } finally {
      button.disabled = false;
    }
  }

  root.addEventListener("change", event => {
    if (event.target.matches("[data-documents-work]")) return load(event.target.value);
    if (event.target.name === "tipo" && event.target.form?.id === "documents-center-upload") syncUploadFields(event.target.form);
  });
  root.addEventListener("submit", event => {
    if (event.target.id !== "documents-center-upload") return;
    event.preventDefault();
    submitUpload(event.target);
  });
  root.addEventListener("click", event => {
    const sectionButton = event.target.closest("[data-document-section]");
    if (sectionButton) {
      selectedSection = sectionButton.dataset.documentSection;
      render();
      return;
    }
    const previewButton = event.target.closest("[data-document-preview]");
    if (previewButton) return openDocument(previewButton, true);
    const downloadButton = event.target.closest("[data-document-download]");
    if (downloadButton) return openDocument(downloadButton, false);
  });

  return {
    show() {
      const availableWorks = getWorks();
      if (!availableWorks.some(work => work.id === selectedWorkId)) selectedWorkId = availableWorks[0]?.id || "";
      load(selectedWorkId);
    },
    refresh() { return load(selectedWorkId); },
  };
}
