const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

const TRUST_STATES = {
  ativo: { label: "ATIVO", tone: "positive" },
  recomendado: { label: "RECOMENDADO", tone: "positive" },
  recomendado_com_ressalvas: { label: "RECOMENDADO COM RESSALVAS", tone: "warning" },
  nao_avaliado: { label: "NÃO AVALIADO", tone: "neutral" },
  nao_recomendado: { label: "NÃO RECOMENDADO", tone: "negative" },
  bloqueado: { label: "BLOQUEADO", tone: "negative" },
  inativo: { label: "INATIVO", tone: "inactive" },
};

const SCORE_FIELDS = [
  ["qualidade", "QUALIDADE"],
  ["cumprimento_prazo", "PRAZO"],
  ["seguranca", "SEGURANÇA"],
  ["comunicacao", "COMUNICAÇÃO"],
];

const OPERATIONAL_ZONES = {
  lisboa_cascais: "LISBOA / CASCAIS",
  algarve: "ALGARVE",
};

const ENTITY_TYPES = {
  fornecedor: "FORNECEDOR",
  subempreiteiro: "SUBEMPREITEIRO",
  ambos: "FORNECEDOR E SUBEMPREITEIRO",
};

const normalizeState = value => String(value || "nao_avaliado")
  .trim().toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "")
  .replaceAll("-", "_").replaceAll(" ", "_");

const normalizeEntityType = value => {
  const normalized = normalizeState(value || "por_classificar");
  return Object.hasOwn(ENTITY_TYPES, normalized) ? normalized : "por_classificar";
};

const isoDate = value => value ? String(value).slice(0, 10) : "";

const average = values => {
  const valid = values
    .filter(value => value !== null && value !== undefined && value !== "")
    .map(Number).filter(Number.isFinite);
  return valid.length ? valid.reduce((sum, value) => sum + value, 0) / valid.length : null;
};

const formatScore = value => Number.isFinite(value) ? value.toFixed(1).replace(".", ",") : "—";

export function supplierProfileStatus(supplier = {}, { zones = [], specialties = [] } = {}) {
  const hasValue = value => String(value ?? "").trim().length > 0;
  const fields = [
    ["NIF", hasValue(supplier.nif)],
    ["EMAIL", hasValue(supplier.email || supplier.email_contacto)],
    ["TELEFONE", hasValue(supplier.telefone || supplier.telemovel || supplier.telefone_contacto)],
    ["REPRESENTANTE", hasValue(supplier.representante || supplier.contacto || supplier.nome_contacto || supplier.pessoa_contacto || supplier.responsavel)],
    ["NOTAS", hasValue(supplier.notas)],
    ["TIPO", normalizeEntityType(supplier.tipo_entidade) !== "por_classificar"],
    ["ZONA", zones.length > 0],
    ["ESPECIALIDADE", specialties.length > 0],
  ];
  const missing = fields.filter(([, present]) => !present).map(([label]) => label);
  return { complete: missing.length === 0, missing };
}

export function createSubcontractorsModule({
  supabase,
  isSupabaseConfigured,
  getWorks,
  getSuppliers,
  getSubcontracts,
  euro,
  toast,
  canManageSpecialties = () => false,
  onSupplierUpdated = () => {},
  onSupplierMerged = () => {},
}) {
  const state = {
    suppliers: [],
    allSuppliers: [],
    subcontracts: [],
    evaluations: [],
    specialties: [],
    supplierSpecialties: [],
    supplierZones: [],
    priceRows: [],
    priceError: "",
    priceSearch: "",
    priceSupplier: "all",
    priceLoading: false,
    activeTab: "directory",
    search: "",
    trustFilter: "all",
    entityFilter: "all",
    specialtyFilter: "all",
    zoneFilter: "all",
    profileFilter: "all",
    sort: "rating",
    selectedSupplierId: null,
    creatingSupplier: false,
    mergeSourceId: null,
    mergeTargetId: "",
    mergePreview: null,
    mergeLoading: false,
    mergeError: "",
    loaded: false,
  };
  let priceSearchTimer = null;
  const content = document.querySelector("#subcontractors-content");

  function supplierName(id) {
    return state.allSuppliers.find(item => item.id === id)?.nome
      || state.suppliers.find(item => item.id === id)?.nome
      || "Fornecedor não identificado";
  }

  function workName(id) {
    const work = getWorks().find(item => item.id === id);
    return work ? `OBRA ${work.numero || "—"} · ${work.nome || "Sem nome"}` : "OBRA NÃO IDENTIFICADA";
  }

  function supplierContacts(supplier) {
    const contactName = supplier.representante || supplier.contacto || supplier.nome_contacto ||
      supplier.pessoa_contacto || supplier.responsavel || "";
    const phone = supplier.telefone || supplier.telemovel || supplier.telefone_contacto || "";
    const email = supplier.email || supplier.email_contacto || "";
    return [...new Set([contactName, phone, email].map(value => String(value || "").trim()).filter(Boolean))];
  }

  function supplierMetrics(supplier) {
    const history = state.subcontracts.filter(item => item.fornecedor_id === supplier.id);
    const evaluations = state.evaluations.filter(item => item.fornecedor_id === supplier.id);
    const workCount = new Set(history.map(item => item.obra_id).filter(Boolean)).size;
    const total = history.reduce((sum, item) => sum + Number(item.valor_adjudicado || 0), 0);
    const criteria = Object.fromEntries(SCORE_FIELDS.map(([field]) => [
      field,
      average(evaluations.map(item => item[field])),
    ]));
    const rating = average(evaluations.flatMap(item =>
      SCORE_FIELDS.map(([field]) => item[field])));
    return { history, evaluations, workCount, total, criteria, rating };
  }

  const specialtyName = id => state.specialties.find(item => item.id === id)?.nome || "Especialidade";
  const specialtiesFor = supplierId => state.supplierSpecialties
    .filter(item => item.fornecedor_id === supplierId)
    .map(item => ({ ...item, nome: specialtyName(item.especialidade_id) }))
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-PT", { sensitivity: "base" }));

  function specialtyBadges(supplierId) {
    const rows = specialtiesFor(supplierId);
    return rows.length
      ? `<span class="supplier-specialty-badges">${rows.map(item => `<em>${escapeHtml(item.nome)}</em>`).join("")}</span>`
      : `<span class="supplier-specialty-badges empty">SEM ESPECIALIDADES CLASSIFICADAS</span>`;
  }

  const zonesFor = supplierId => state.supplierZones
    .filter(item => item.fornecedor_id === supplierId)
    .map(item => item.zona);

  function zoneBadges(supplierId) {
    const zones = zonesFor(supplierId);
    return `<span class="supplier-zone-badges ${zones.length ? "" : "empty"}">${zones.length
      ? zones.map(zone => `<em>${escapeHtml(OPERATIONAL_ZONES[zone] || zone)}</em>`).join("")
      : "<em>POR CLASSIFICAR</em>"}</span>`;
  }

  function directoryRows() {
    const needle = state.search.trim().toLocaleLowerCase("pt-PT");
    return state.suppliers.map(supplier => ({
      supplier,
      trust: normalizeState(supplier.estado_confianca),
      entityType: normalizeEntityType(supplier.tipo_entidade),
      metrics: supplierMetrics(supplier),
      contacts: supplierContacts(supplier),
      profile: supplierProfileStatus(supplier, {
        zones: zonesFor(supplier.id),
        specialties: specialtiesFor(supplier.id),
      }),
    })).filter(row => {
      const matchesState = state.trustFilter === "all" || row.trust === state.trustFilter;
      const matchesEntity = state.entityFilter === "all" || row.entityType === state.entityFilter;
      const specialtyRows = specialtiesFor(row.supplier.id);
      const matchesSpecialty = state.specialtyFilter === "all"
        || specialtyRows.some(item => item.especialidade_id === state.specialtyFilter);
      const zones = zonesFor(row.supplier.id);
      const matchesZone = state.zoneFilter === "all"
        || (state.zoneFilter === "unclassified" ? !zones.length
          : state.zoneFilter === "both"
            ? Object.keys(OPERATIONAL_ZONES).every(zone => zones.includes(zone))
            : zones.includes(state.zoneFilter));
      const matchesProfile = state.profileFilter === "all"
        || (state.profileFilter === "complete" ? row.profile.complete : !row.profile.complete);
      const searchable = [row.supplier.nome, row.supplier.nif, row.supplier.notas, ...row.contacts,
        ...specialtyRows.map(item => item.nome), ...zones.map(zone => OPERATIONAL_ZONES[zone])]
        .join(" ").toLocaleLowerCase("pt-PT");
      return matchesState && matchesEntity && matchesSpecialty && matchesZone && matchesProfile && (!needle || searchable.includes(needle));
    }).sort((left, right) => {
      const ratingDifference = (right.metrics.rating ?? -1) - (left.metrics.rating ?? -1);
      if (ratingDifference) return ratingDifference;
      return String(left.supplier.nome || "").localeCompare(
        String(right.supplier.nome || ""), "pt-PT", { sensitivity: "base" });
    });
  }

  function directoryGroups(rows) {
    const groups = new Map();
    rows.forEach(row => {
      const specialties = specialtiesFor(row.supplier.id);
      const memberships = specialties.length ? specialties : [{ especialidade_id: "unclassified", nome: "Sem especialidade definida" }];
      memberships.forEach(specialty => {
        if (!groups.has(specialty.especialidade_id)) groups.set(specialty.especialidade_id, { id: specialty.especialidade_id, nome: specialty.nome, rows: [] });
        groups.get(specialty.especialidade_id).rows.push(row);
      });
    });
    return [...groups.values()].sort((left, right) => {
      if (left.id === "unclassified") return 1;
      if (right.id === "unclassified") return -1;
      return left.nome.localeCompare(right.nome, "pt-PT", { sensitivity: "base" });
    }).map(group => ({ ...group, rows: group.rows.sort((left, right) =>
      (right.metrics.rating ?? -1) - (left.metrics.rating ?? -1)
      || String(left.supplier.nome || "").localeCompare(String(right.supplier.nome || ""), "pt-PT", { sensitivity: "base" })) }));
  }

  function trustBadge(value) {
    const normalized = normalizeState(value);
    const config = TRUST_STATES[normalized] || {
      label: String(value || "NÃO AVALIADO").replaceAll("_", " ").toUpperCase(),
      tone: "neutral",
    };
    return `<span class="supplier-trust ${config.tone}">${escapeHtml(config.label)}</span>`;
  }

  function entityBadge(value) {
    const normalized = normalizeEntityType(value);
    return `<span class="supplier-entity-type ${normalized}">${escapeHtml(
      ENTITY_TYPES[normalized] || "TIPO POR CLASSIFICAR")}</span>`;
  }

  function renderRating(metrics, compact = false) {
    if (!metrics.evaluations.length) {
      return `<div class="supplier-rating empty"><strong>—</strong><span>SEM AVALIAÇÕES</span></div>`;
    }
    return `<div class="supplier-rating">
      <strong>${formatScore(metrics.rating)}<small>/5</small></strong>
      <span>${metrics.evaluations.length} AVALIA${metrics.evaluations.length === 1 ? "ÇÃO" : "ÇÕES"}</span>
      ${compact ? "" : `<div>${SCORE_FIELDS.map(([field, label]) =>
        `<em title="${label}">${label.slice(0, 3)} ${formatScore(metrics.criteria[field])}</em>`
      ).join("")}</div>`}
    </div>`;
  }

  function renderDirectoryCard(row) {
    const selected = state.selectedSupplierId === row.supplier.id;
    return `<button type="button" class="supplier-directory-row ${selected ? "selected" : ""}"
      data-supplier-detail="${row.supplier.id}" aria-expanded="${selected}">
      <div class="supplier-identity">
        <span class="supplier-avatar">${escapeHtml(String(row.supplier.nome || "?")
          .split(/\s+/).slice(0, 2).map(part => part[0]).join("").toUpperCase())}</span>
        <div><strong>${escapeHtml(row.supplier.nome || "Fornecedor sem nome")}</strong>
          ${trustBadge(row.supplier.estado_confianca)}
          ${entityBadge(row.supplier.tipo_entidade)}
          ${zoneBadges(row.supplier.id)}
          ${specialtyBadges(row.supplier.id)}
          ${row.profile.complete
            ? `<span class="supplier-profile-status complete">CADASTRO COMPLETO</span>`
            : `<span class="supplier-profile-status incomplete" title="Em falta: ${escapeHtml(row.profile.missing.join(", "))}">${row.profile.missing.length} DADOS EM FALTA</span>`}
          <small>${row.contacts.length
            ? row.contacts.map(escapeHtml).join(" · ")
            : "CONTACTO NÃO INDICADO"}</small></div>
      </div>
      ${renderRating(row.metrics)}
      <div class="supplier-stat"><span>OBRAS</span><strong>${row.metrics.workCount}</strong></div>
      <span class="supplier-open-arrow">${selected ? "↑" : "→"}</span>
    </button>`;
  }

  function renderSubcontractHistory(item) {
    return `<article class="supplier-history-row">
      <div><span>${escapeHtml(workName(item.obra_id))}</span>
        <strong>${escapeHtml(item.especialidade || "Especialidade não indicada")}</strong></div>
      <div><span>VALOR ADJUDICADO</span><strong>${euro.format(Number(item.valor_adjudicado || 0))}</strong></div>
      <div><span>DATAS PREVISTAS</span><strong>${isoDate(item.data_inicio_prevista) || "—"} → ${isoDate(item.data_fim_prevista) || "—"}</strong></div>
      <span class="supplier-work-state ${escapeHtml(item.estado || "")}">${escapeHtml(
        String(item.estado || "sem_estado").replaceAll("_", " ").toUpperCase())}</span>
    </article>`;
  }

  function renderEvaluation(item) {
    return `<article class="supplier-evaluation-card">
      <div class="supplier-evaluation-head"><div><span>${escapeHtml(workName(item.obra_id))}</span>
        <strong>${isoDate(item.criado_em) || "DATA NÃO INDICADA"}</strong></div>
        <b>${formatScore(average(SCORE_FIELDS.map(([field]) => item[field])))}<small>/5</small></b></div>
      <div class="supplier-score-grid">${SCORE_FIELDS.map(([field, label]) =>
        `<div><span>${label}</span><strong>${formatScore(average([item[field]]))}</strong></div>`
      ).join("")}</div>
      ${item.observacoes
        ? `<p>${escapeHtml(item.observacoes)}</p>`
        : `<p class="empty-note">SEM OBSERVAÇÕES</p>`}
    </article>`;
  }

  function renderSupplierEditor(supplier = {}, creating = false) {
    const supplierId = supplier.id || "";
    const selectedZones = supplierId ? zonesFor(supplierId) : [];
    const selectedSpecialties = supplierId ? specialtiesFor(supplierId) : [];
    return `<form class="supplier-profile-editor" data-supplier-editor="${supplierId}" data-supplier-mode="${creating ? "create" : "edit"}">
      <div class="supplier-editor-heading"><strong>${creating ? "NOVO FORNECEDOR / SUBEMPREITEIRO" : "CADASTRO DA EMPRESA"}</strong><span>Dados comuns às compras, faturas, subempreitadas e mapas comparativos.</span></div>
      <label class="wide"><span>NOME *</span><input name="nome" required value="${escapeHtml(supplier.nome || "")}" placeholder="Nome fiscal ou designação habitual"></label>
      <label><span>NIF</span><input name="nif" inputmode="numeric" value="${escapeHtml(supplier.nif || "")}"></label>
      <label><span>TIPO DE PARCEIRO *</span><select name="tipo_entidade" required>
        <option value="">Selecione o tipo</option>
        ${Object.entries(ENTITY_TYPES).map(([value, label]) => `<option value="${value}" ${normalizeEntityType(supplier.tipo_entidade) === value ? "selected" : ""}>${label}</option>`).join("")}
      </select></label>
      <label><span>ESTADO</span><select name="estado_confianca">${Object.entries(TRUST_STATES).map(([value, config]) => `<option value="${value}" ${normalizeState(supplier.estado_confianca) === value ? "selected" : ""}>${config.label}</option>`).join("")}</select></label>
      <label><span>EMAIL</span><input name="email" type="email" value="${escapeHtml(supplier.email || "")}"></label>
      <label><span>TELEFONE</span><input name="telefone" value="${escapeHtml(supplier.telefone || "")}"></label>
      <label class="wide"><span>REPRESENTANTE / CONTACTO</span><input name="representante" value="${escapeHtml(supplier.representante || "")}"></label>
      <label class="full"><span>NOTAS / OBSERVAÇÕES</span><textarea name="notas" rows="3" placeholder="Referências, condições habituais ou informação útil…">${escapeHtml(supplier.notas || "")}</textarea></label>
      <section class="supplier-editor-section supplier-zones-editor">
        <div><strong>ZONAS OPERACIONAIS</strong><span>Uma empresa pode trabalhar nas duas regiões.</span></div>
        <div>${Object.entries(OPERATIONAL_ZONES).map(([zone, label]) => `<label><input type="checkbox" name="zona" value="${zone}" ${selectedZones.includes(zone) ? "checked" : ""}><span>${label}</span></label>`).join("")}</div>
      </section>
      <section class="supplier-editor-section supplier-specialties-editor" data-specialties-editor>
        <div><strong>ESPECIALIDADES</strong><span>Selecione todas as áreas em que esta empresa pode ser consultada.</span></div>
        <div class="supplier-specialties-options">${state.specialties.map(item => `<label><input type="checkbox" name="especialidade_id" value="${item.id}" ${selectedSpecialties.some(link => link.especialidade_id === item.id) ? "checked" : ""}><span>${escapeHtml(item.nome)}</span></label>`).join("")}</div>
      </section>
      <section class="supplier-editor-section supplier-new-specialty">
        <div><strong>NOVA ESPECIALIDADE</strong><span>Se a especialidade ainda não existir, escreva-a aqui. Será criada e associada ao guardar o cadastro.</span></div>
        <input name="nova_especialidade" maxlength="120" placeholder="Ex. Projetista de AVAC">
      </section>
      <div class="supplier-editor-actions"><button type="submit" class="primary-button">${creating ? "CRIAR PARCEIRO" : "GUARDAR"}</button>${creating ? `<button type="button" data-cancel-new-supplier>CANCELAR</button>` : ""}<p class="form-error"></p></div>
    </form>`;
  }

  function renderNewSupplier() {
    if (!state.creatingSupplier || !canManageSpecialties()) return "";
    return `<section class="supplier-detail supplier-create-detail">
      <div class="supplier-detail-head"><div><p class="eyebrow">NOVO CADASTRO</p><h2>FORNECEDOR OU SUBEMPREITEIRO</h2>
        <p>Preencha o que já conhece. Nome e tipo são obrigatórios; a plataforma verifica nome e NIF antes de criar.</p></div>
        <div class="supplier-detail-head-actions"><button type="button" data-cancel-new-supplier>FECHAR ×</button></div>
      </div>
      ${renderSupplierEditor({ estado_confianca: "nao_avaliado" }, true)}
    </section>`;
  }

  function renderSupplierMerge(source) {
    if (state.mergeSourceId !== source.id) return "";
    const targets = state.suppliers
      .filter(item => item.id !== source.id)
      .slice()
      .sort((a, b) => String(a.nome || "").localeCompare(String(b.nome || ""), "pt-PT", { sensitivity: "base" }));
    const preview = state.mergePreview;
    const conflicts = preview?.conflitos || [];
    return `<section class="supplier-merge-panel">
      <div class="supplier-merge-heading"><div><p class="eyebrow">CONSOLIDAÇÃO SEGURA</p>
        <h3>MESCLAR “${escapeHtml(source.nome)}” NOUTRA EMPRESA</h3>
        <p>O registo acima será removido. Faturas, subempreitadas, propostas, avaliações e restantes referências passam para a empresa mantida. O nome antigo fica guardado como alias.</p></div>
        <button type="button" data-cancel-supplier-merge>FECHAR ×</button></div>
      <label><span>REGISTO CORRETO A MANTER *</span><select data-merge-target>
        <option value="">Selecione a empresa correta</option>
        ${targets.map(item => `<option value="${item.id}" ${state.mergeTargetId === item.id ? "selected" : ""}>${escapeHtml(item.nome)}${item.nif ? ` · NIF ${escapeHtml(item.nif)}` : ""}</option>`).join("")}
      </select></label>
      <div class="supplier-merge-actions">
        <button type="button" data-preview-supplier-merge ${!state.mergeTargetId || state.mergeLoading ? "disabled" : ""}>${state.mergeLoading ? "A VERIFICAR…" : "VERIFICAR IMPACTO"}</button>
        ${preview?.pode_mesclar ? `<button type="button" class="danger-action" data-confirm-supplier-merge ${state.mergeLoading ? "disabled" : ""}>CONFIRMAR MESCLAGEM</button>` : ""}
      </div>
      ${preview ? `<div class="supplier-merge-preview ${preview.pode_mesclar ? "safe" : "blocked"}">
        <strong>${preview.pode_mesclar ? "PRONTO PARA MESCLAR" : "MESCLAGEM BLOQUEADA"}</strong>
        <span>${Number(preview.total_referencias || 0)} referência(s) de negócio serão transferidas para <b>${escapeHtml(preview.destino?.nome || "o registo correto")}</b>.</span>
        ${(preview.referencias || []).length ? `<ul>${preview.referencias.map(item => `<li><span>${escapeHtml(item.tabela)}</span><b>${Number(item.registos || 0)}</b></li>`).join("")}</ul>` : `<em>Este duplicado não tem histórico de negócio associado.</em>`}
        ${conflicts.length ? `<div class="supplier-merge-conflicts">${conflicts.map(item => `<p>${escapeHtml(item.mensagem)} (${Number(item.registos || 0)})</p>`).join("")}</div>` : ""}
      </div>` : ""}
      ${state.mergeError ? `<p class="form-error">${escapeHtml(state.mergeError)}</p>` : ""}
    </section>`;
  }

  function renderDetail() {
    if (state.creatingSupplier) return renderNewSupplier();
    const supplier = state.suppliers.find(item => item.id === state.selectedSupplierId);
    if (!supplier) return "";
    const metrics = supplierMetrics(supplier);
    const history = metrics.history.slice().sort((a, b) =>
      String(b.data_inicio_prevista || b.criado_em || "").localeCompare(
        String(a.data_inicio_prevista || a.criado_em || "")));
    const evaluations = metrics.evaluations.slice().sort((a, b) =>
      String(b.criado_em || "").localeCompare(String(a.criado_em || "")));
    const contacts = supplierContacts(supplier);
    const profile = supplierProfileStatus(supplier, {
      zones: zonesFor(supplier.id),
      specialties: specialtiesFor(supplier.id),
    });
    return `<section class="supplier-detail">
      <div class="supplier-detail-head">
        <div><p class="eyebrow">HISTÓRICO COMPLETO</p><h2>${escapeHtml(supplier.nome || "Subempreiteiro")}</h2>
          <div class="supplier-detail-meta">${trustBadge(supplier.estado_confianca)}
            ${entityBadge(supplier.tipo_entidade)}
            <span>${contacts.length ? contacts.map(escapeHtml).join(" · ") : "CONTACTO NÃO INDICADO"}</span></div>
          ${zoneBadges(supplier.id)}
          ${specialtyBadges(supplier.id)}
          <div class="supplier-profile-summary ${profile.complete ? "complete" : "incomplete"}">${profile.complete
            ? "CADASTRO COMPLETO"
            : `POR COMPLETAR: ${escapeHtml(profile.missing.join(" · "))}`}</div></div>
        <div class="supplier-detail-head-actions">
          ${canManageSpecialties() ? `<button type="button" data-merge-supplier="${supplier.id}">MESCLAR DUPLICADO</button>` : ""}
          ${canManageSpecialties() ? `<button type="button" class="danger-action" data-delete-supplier="${supplier.id}">ELIMINAR DUPLICADO</button>` : ""}
          <button type="button" data-close-supplier-detail>FECHAR ×</button>
        </div>
      </div>
      ${renderSupplierMerge(supplier)}
      <div class="supplier-detail-kpis">
        <div><span>OBRAS</span><strong>${metrics.workCount}</strong></div>
        <div><span>SUBEMPREITADAS</span><strong>${metrics.history.length}</strong></div>
        <div>${renderRating(metrics, true)}</div>
      </div>
      ${canManageSpecialties() ? renderSupplierEditor(supplier) : ""}
      <div class="supplier-detail-columns">
        <section><div class="supplier-subsection-title"><div><p class="eyebrow">EXECUÇÃO</p>
          <h3>HISTÓRICO DE SUBEMPREITADAS</h3></div><span>${history.length}</span></div>
          <div class="supplier-history-list">${history.length
            ? history.map(renderSubcontractHistory).join("")
            : `<div class="subcontract-empty">SEM SUBEMPREITADAS REGISTADAS</div>`}</div>
        </section>
        <section><div class="supplier-subsection-title"><div><p class="eyebrow">QUALIDADE</p>
          <h3>AVALIAÇÕES RECEBIDAS</h3></div><span>${evaluations.length}</span></div>
          <div class="supplier-evaluation-list">${evaluations.length
            ? evaluations.map(renderEvaluation).join("")
            : `<div class="subcontract-empty">AINDA NÃO EXISTEM AVALIAÇÕES</div>`}</div>
        </section>
      </div>
    </section>`;
  }

  function renderModuleTabs() {
    return `<nav class="subcontractor-module-tabs">
      <button type="button" data-subcontractor-tab="directory" class="${state.activeTab === "directory" ? "active" : ""}">DIRETÓRIO GERAL</button>
      <button type="button" data-subcontractor-tab="prices" class="${state.activeTab === "prices" ? "active" : ""}">COMPARATIVO DE PREÇOS</button>
    </nav>`;
  }

  function filteredPriceRows() {
    return state.priceRows.filter(row => {
      const matchesSupplier = state.priceSupplier === "all" || row.fornecedor_id === state.priceSupplier;
      return matchesSupplier;
    }).sort((a, b) => supplierName(a.fornecedor_id).localeCompare(supplierName(b.fornecedor_id), "pt-PT")
      || String(b.data || "").localeCompare(String(a.data || "")));
  }

  function renderPriceRows(rows) {
    if (state.priceLoading) return `<tr><td colspan="8"><div class="subcontract-empty">A PESQUISAR PREÇOS…</div></td></tr>`;
    if (!state.priceSearch.trim()) return `<tr><td colspan="8"><div class="subcontract-empty">ESCREVA UMA PALAVRA-CHAVE PARA PESQUISAR</div></td></tr>`;
    if (!rows.length) return `<tr><td colspan="8"><div class="subcontract-empty">SEM PREÇOS PARA A PALAVRA PESQUISADA</div></td></tr>`;
    let previousSupplier = null;
    return rows.map(row => {
      const supplier = supplierName(row.fornecedor_id);
      const group = supplier !== previousSupplier
        ? `<tr class="price-supplier-group"><td colspan="8">${escapeHtml(supplier)}</td></tr>` : "";
      previousSupplier = supplier;
      const discount = row.desconto_percentual != null
        ? `${Number(row.desconto_percentual).toFixed(2).replace(".", ",")}%`
        : Number(row.valor_desconto) > 0 ? euro.format(Number(row.valor_desconto)) : "SEM DESCONTO";
      return `${group}<tr>
        <td><strong>${escapeHtml(supplier)}</strong></td>
        <td>${escapeHtml(row.artigo || "Sem designação")}</td>
        <td>${escapeHtml(row.unidade || "—")}</td>
        <td>${euro.format(Number(row.preco_bruto || 0))}</td>
        <td>${escapeHtml(discount)}</td>
        <td><strong>${euro.format(Number(row.preco_liquido || 0))}</strong></td>
        <td>${escapeHtml(isoDate(row.data) || "—")}</td>
        <td><span class="price-origin ${row.origem === "Material" ? "material" : "estaleiro"}">${escapeHtml(row.origem)}</span></td>
      </tr>`;
    }).join("");
  }

  function renderPriceComparison() {
    const rows = filteredPriceRows();
    const supplierIds = [...new Set(state.priceRows.map(item => item.fornecedor_id).filter(Boolean))]
      .sort((a, b) => supplierName(a).localeCompare(supplierName(b), "pt-PT"));
    return `${renderModuleTabs()}
      <section class="price-comparison-panel">
        <div class="price-comparison-head"><div><p class="eyebrow">HISTÓRICO DE COMPRAS</p><h2>COMPARATIVO DE PREÇOS</h2>
          <span>Pesquisa parcial por designação. O preço bruto, o desconto e o preço líquido unitário são apresentados separadamente.</span></div>
          <strong>${rows.length} REGISTOS</strong></div>
        ${state.priceError ? `<div class="subcontract-price-warning">${escapeHtml(state.priceError)}</div>` : ""}
        <div class="price-comparison-filters">
          <label class="supplier-search"><span>⌕</span><input type="search" data-price-search value="${escapeHtml(state.priceSearch)}" placeholder="Pesquisar artigo ou designação…"></label>
          <label><span>FORNECEDOR</span><div class="select-wrap"><select data-price-supplier><option value="all">Todos os fornecedores</option>
            ${supplierIds.map(id => `<option value="${escapeHtml(id)}" ${state.priceSupplier === id ? "selected" : ""}>${escapeHtml(supplierName(id))}</option>`).join("")}
          </select><b>⌄</b></div></label>
        </div>
        <div class="price-comparison-table-wrap"><table class="price-comparison-table">
          <thead><tr><th>FORNECEDOR</th><th>ARTIGO</th><th>UNIDADE</th><th>PREÇO BRUTO/UN.</th><th>DESCONTO</th><th>PREÇO LÍQUIDO/UN.</th><th>DATA</th><th>ORIGEM</th></tr></thead>
          <tbody>${renderPriceRows(rows)}</tbody>
        </table></div>
      </section>`;
  }

  function render() {
    if (!state.loaded) {
      content.innerHTML = `<div class="empty-state"><strong>A CARREGAR DIRETÓRIO…</strong></div>`;
      return;
    }
    if (state.activeTab === "prices") {
      content.innerHTML = renderPriceComparison();
      return;
    }
    const rows = directoryRows();
    const groups = directoryGroups(rows);
    const allMetrics = state.suppliers.map(supplier => supplierMetrics(supplier));
    const evaluated = allMetrics.filter(item => item.evaluations.length).length;
    const recommended = state.suppliers.filter(item =>
      ["ativo", "recomendado", "recomendado_com_ressalvas"].includes(normalizeState(item.estado_confianca))).length;
    const trustOptions = [...new Set(state.suppliers.map(item =>
      normalizeState(item.estado_confianca)))].sort();
    const zoneCounts = Object.fromEntries(Object.keys(OPERATIONAL_ZONES).map(zone => [zone,
      state.suppliers.filter(item => zonesFor(item.id).includes(zone)).length]));
    const bothZones = state.suppliers.filter(item =>
      Object.keys(OPERATIONAL_ZONES).every(zone => zonesFor(item.id).includes(zone))).length;
    const unclassifiedZones = state.suppliers.filter(item => !zonesFor(item.id).length).length;
    const incompleteProfiles = state.suppliers.filter(supplier => !supplierProfileStatus(supplier, {
      zones: zonesFor(supplier.id), specialties: specialtiesFor(supplier.id),
    }).complete).length;

    content.innerHTML = `${renderModuleTabs()}
      <section class="subcontractors-kpis">
        <article><span>FORNECEDORES / SUBEMPREITEIROS</span><strong>${state.suppliers.length}</strong></article>
        <article><span>ATIVOS / RECOMENDADOS</span><strong>${recommended}</strong></article>
        <article><span>COM AVALIAÇÃO</span><strong>${evaluated}</strong></article>
        <article><span>CADASTROS POR COMPLETAR</span><strong>${incompleteProfiles}</strong></article>
      </section>
      ${renderDetail()}
      <section class="supplier-directory-panel">
        <div class="supplier-directory-toolbar">
          <label class="supplier-search"><span>⌕</span><input type="search" data-supplier-search
            value="${escapeHtml(state.search)}" placeholder="Pesquisar nome, contacto, telefone ou email…"></label>
          <label><span>ZONA OPERACIONAL</span><div class="select-wrap"><select data-supplier-zone-filter>
            <option value="all">Todas as zonas (${state.suppliers.length})</option>
            <option value="lisboa_cascais" ${state.zoneFilter === "lisboa_cascais" ? "selected" : ""}>Lisboa / Cascais (${zoneCounts.lisboa_cascais})</option>
            <option value="algarve" ${state.zoneFilter === "algarve" ? "selected" : ""}>Algarve (${zoneCounts.algarve})</option>
            <option value="both" ${state.zoneFilter === "both" ? "selected" : ""}>Lisboa / Cascais e Algarve (${bothZones})</option>
            <option value="unclassified" ${state.zoneFilter === "unclassified" ? "selected" : ""}>Por classificar (${unclassifiedZones})</option>
          </select><b>⌄</b></div></label>
          <label><span>ESTADO DE CONFIANÇA</span><div class="select-wrap"><select data-supplier-trust>
            <option value="all">Todos os estados</option>
            ${trustOptions.map(value => {
              const config = TRUST_STATES[value];
              return `<option value="${escapeHtml(value)}" ${state.trustFilter === value ? "selected" : ""}>${
                escapeHtml(config?.label || value.replaceAll("_", " ").toUpperCase())}</option>`;
            }).join("")}
          </select><b>⌄</b></div></label>
          <label><span>ESPECIALIDADE</span><div class="select-wrap"><select data-supplier-specialty>
            <option value="all">Todas as especialidades</option>
            ${state.specialties.map(item => `<option value="${item.id}" ${state.specialtyFilter === item.id ? "selected" : ""}>${escapeHtml(item.nome)}</option>`).join("")}
          </select><b>⌄</b></div></label>
          <label><span>TIPO DE PARCEIRO</span><div class="select-wrap"><select data-supplier-entity>
            <option value="all">Todos os tipos</option>
            ${Object.entries(ENTITY_TYPES).map(([value, label]) => `<option value="${value}" ${state.entityFilter === value ? "selected" : ""}>${label}</option>`).join("")}
            <option value="por_classificar" ${state.entityFilter === "por_classificar" ? "selected" : ""}>Por classificar</option>
          </select><b>⌄</b></div></label>
          <label><span>COMPLETUDE DO CADASTRO</span><div class="select-wrap"><select data-supplier-profile>
            <option value="all">Todos os cadastros</option>
            <option value="incomplete" ${state.profileFilter === "incomplete" ? "selected" : ""}>Por completar</option>
            <option value="complete" ${state.profileFilter === "complete" ? "selected" : ""}>Completos</option>
          </select><b>⌄</b></div></label>
        </div>
        <div class="supplier-directory-heading">
          <div><p class="eyebrow">BASE DE FORNECEDORES</p><h2>DIRETÓRIO GERAL</h2></div>
          <div class="supplier-directory-heading-actions"><span>${rows.length} DE ${state.suppliers.length}</span>
            ${canManageSpecialties() ? `<button type="button" class="primary-button" data-new-supplier>+ NOVO PARCEIRO</button>` : ""}</div>
        </div>
        <div class="supplier-directory-list grouped">${rows.length
          ? groups.map(group => `<section class="supplier-specialty-group"><header><div><span>ESPECIALIDADE</span><h3>${escapeHtml(group.nome)}</h3></div><b>${group.rows.length}</b></header><div>${group.rows.map(renderDirectoryCard).join("")}</div></section>`).join("")
          : `<div class="subcontract-empty">NENHUM FORNECEDOR OU SUBEMPREITEIRO CORRESPONDE AOS FILTROS</div>`}</div>
      </section>`;
  }

  async function query(path, options = {}) {
    const response = await supabase(path, options);
    if (!response.ok) {
      const body = await response.text();
      try {
        const parsed = JSON.parse(body);
        throw new Error(parsed.message || parsed.details || body);
      } catch (error) {
        if (error instanceof SyntaxError) throw new Error(body);
        throw error;
      }
    }
    if (response.status === 204) return null;
    return response.json();
  }

  async function loadPriceRows(searchTerm) {
    const term = String(searchTerm || "").trim();
    if (!term || !isSupabaseConfigured) {
      state.priceRows = [];
      state.priceError = "";
      state.priceLoading = false;
      render();
      return;
    }
    state.priceLoading = true;
    state.priceError = "";
    render();
    const pattern = encodeURIComponent(`*${term.replace(/[*,]/g, " ")}*`);
    const results = await Promise.allSettled([
      query("faturas?select=id,fornecedor_id,data_fatura,tipo_origem&tipo_origem=eq.material"),
      query(`faturas_itens?select=*&designacao=ilike.${pattern}`),
      query(`despesas_estaleiro?select=*&designacao=ilike.${pattern}`),
    ]);
    if (term !== state.priceSearch.trim()) return;
    const [invoiceResult, itemResult, expenseResult] = results;
    const materialInvoices = invoiceResult.status === "fulfilled" ? invoiceResult.value : [];
    const invoiceItems = itemResult.status === "fulfilled" ? itemResult.value : [];
    const expenses = expenseResult.status === "fulfilled" ? expenseResult.value : [];
    const invoiceById = new Map(materialInvoices.map(item => [item.id, item]));
    state.priceRows = invoiceItems.map(item => {
      const invoice = invoiceById.get(item.fatura_id) || {};
      const quantity = Number(item.quantidade || 0);
      const grossUnit = Number(item.valor_unitario ?? item.preco_unitario ?? 0);
      const discountPercent = item.desconto_percentual == null ? null : Number(item.desconto_percentual);
      const discountValue = item.valor_desconto == null ? null : Number(item.valor_desconto);
      const storedTotal = item.valor_total ?? item.preco_total;
      const netUnit = quantity > 0 && storedTotal != null
        ? Number(storedTotal) / quantity
        : grossUnit - (discountValue != null && quantity > 0
          ? discountValue / quantity
          : grossUnit * Number(discountPercent || 0) / 100);
      return {
        fornecedor_id: invoice.fornecedor_id || item.fornecedor_id,
        artigo: item.designacao,
        unidade: item.unidade,
        preco_bruto: grossUnit,
        preco_liquido: Math.max(0, netUnit),
        desconto_percentual: discountPercent,
        valor_desconto: discountValue,
        data: invoice.data_fatura || item.data || item.criado_em,
        origem: "Material",
      };
    }).filter(item => item.artigo && Number.isFinite(Number(item.preco_liquido)))
      .concat(expenses.map(item => ({
        fornecedor_id: item.fornecedor_id,
        artigo: item.designacao,
        unidade: item.unidade,
        preco_bruto: item.preco_unitario ?? item.valor_unitario ?? (
          Number(item.quantidade) ? Number(item.valor_total || item.valor) / Number(item.quantidade) : item.valor_total || item.valor
        ),
        preco_liquido: item.preco_unitario ?? item.valor_unitario ?? (
          Number(item.quantidade) ? Number(item.valor_total || item.valor) / Number(item.quantidade) : item.valor_total || item.valor
        ),
        desconto_percentual: null,
        valor_desconto: null,
        data: item.data_pagamento || item.data || item.criado_em,
        origem: "Estaleiro",
      })).filter(item => item.artigo && Number.isFinite(Number(item.preco_liquido))));
    state.priceError = results.some(result => result.status === "rejected")
      ? "Algumas origens ainda não estão disponíveis para esta pesquisa."
      : "";
    state.priceLoading = false;
    render();
  }

  async function load() {
    state.loaded = false;
    state.priceLoading = false;
    render();
    if (!isSupabaseConfigured) {
      state.suppliers = getSuppliers().map(item => ({
        ...item,
        tipo_entidade: "subempreiteiro",
        estado_confianca: item.estado_confianca || "nao_avaliado",
      }));
      state.allSuppliers = state.suppliers;
      state.subcontracts = typeof getSubcontracts === "function" ? getSubcontracts() : [];
      state.evaluations = [];
      state.specialties = [];
      state.supplierSpecialties = [];
      state.supplierZones = [];
      state.priceRows = [];
      state.loaded = true;
      render();
      return;
    }
    try {
      state.suppliers = await query("fornecedores?select=*&order=nome");
      const optional = await Promise.allSettled([
        query("subempreitadas?select=*&order=criado_em.desc"),
        query("avaliacoes_subempreiteiro?select=*&order=criado_em.desc"),
        query("especialidades?select=*&aplicavel_subempreiteiro=eq.true&order=nome"),
        query("fornecedores_especialidades?select=*&order=criado_em"),
        query("fornecedores_zonas?select=*&order=zona"),
      ]);
      [state.subcontracts, state.evaluations, state.specialties, state.supplierSpecialties, state.supplierZones] = optional
        .map(result => result.status === "fulfilled" ? result.value : []);
      if (optional.some(result => result.status === "rejected")) {
        toast("O diretório foi carregado, mas alguns dados complementares estão indisponíveis.", "warning");
      }
      state.allSuppliers = state.suppliers;
      state.priceRows = [];
      state.priceError = "";
    } catch (error) {
      state.suppliers = [];
      state.subcontracts = [];
      state.evaluations = [];
      state.specialties = [];
      state.supplierSpecialties = [];
      state.supplierZones = [];
      state.priceRows = [];
      state.priceLoading = false;
      state.priceError = "Não foi possível carregar o comparativo de preços.";
      toast(`Não foi possível carregar o diretório: ${error.message}`, "error");
    }
    state.loaded = true;
    render();
  }

  content.addEventListener("input", event => {
    if (event.target.matches("[data-price-search]")) {
      state.priceSearch = event.target.value;
      state.priceRows = [];
      state.priceError = "";
      state.priceLoading = Boolean(state.priceSearch.trim());
      render();
      const search = content.querySelector("[data-price-search]");
      search?.focus();
      search?.setSelectionRange(state.priceSearch.length, state.priceSearch.length);
      clearTimeout(priceSearchTimer);
      priceSearchTimer = setTimeout(() => loadPriceRows(state.priceSearch), 350);
      return;
    }
    if (!event.target.matches("[data-supplier-search]")) return;
    state.search = event.target.value;
    state.selectedSupplierId = null;
    render();
    const search = content.querySelector("[data-supplier-search]");
    search?.focus();
    search?.setSelectionRange(state.search.length, state.search.length);
  });

  content.addEventListener("change", event => {
    if (event.target.matches("[data-price-supplier]")) {
      state.priceSupplier = event.target.value;
      render();
      return;
    }
    if (event.target.matches("[data-supplier-trust]")) {
      state.trustFilter = event.target.value;
      state.selectedSupplierId = null;
      render();
    }
    if (event.target.matches("[data-supplier-specialty]")) {
      state.specialtyFilter = event.target.value;
      state.selectedSupplierId = null;
      render();
    }
    if (event.target.matches("[data-supplier-entity]")) {
      state.entityFilter = event.target.value;
      state.selectedSupplierId = null;
      render();
    }
    if (event.target.matches("[data-supplier-profile]")) {
      state.profileFilter = event.target.value;
      state.selectedSupplierId = null;
      render();
    }
    if (event.target.matches("[data-supplier-zone-filter]")) {
      state.zoneFilter = event.target.value;
      state.selectedSupplierId = null;
      render();
    }
    if (event.target.matches("[data-merge-target]")) {
      state.mergeTargetId = event.target.value;
      state.mergePreview = null;
      state.mergeError = "";
      render();
    }
  });

  content.addEventListener("click", async event => {
    if (event.target.closest("[data-new-supplier]")) {
      state.creatingSupplier = true;
      state.selectedSupplierId = null;
      render();
      content.querySelector(".supplier-create-detail")?.scrollIntoView({ behavior: "smooth", block: "start" });
      content.querySelector('[data-supplier-mode="create"] [name="nome"]')?.focus();
      return;
    }
    if (event.target.closest("[data-cancel-new-supplier]")) {
      state.creatingSupplier = false;
      render();
      return;
    }
    const tab = event.target.closest("[data-subcontractor-tab]");
    if (tab) {
      state.activeTab = tab.dataset.subcontractorTab;
      state.selectedSupplierId = null;
      render();
      return;
    }
    const row = event.target.closest("[data-supplier-detail]");
    if (row) {
      state.creatingSupplier = false;
      state.selectedSupplierId = row.dataset.supplierDetail;
      render();
      content.querySelector(".supplier-detail")?.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    if (event.target.closest("[data-close-supplier-detail]")) {
      state.creatingSupplier = false;
      state.selectedSupplierId = null;
      state.mergeSourceId = null;
      state.mergeTargetId = "";
      state.mergePreview = null;
      render();
      return;
    }
    const mergeButton = event.target.closest("[data-merge-supplier]");
    if (mergeButton) {
      state.mergeSourceId = mergeButton.dataset.mergeSupplier;
      state.mergeTargetId = "";
      state.mergePreview = null;
      state.mergeError = "";
      render();
      content.querySelector(".supplier-merge-panel")?.scrollIntoView({ behavior: "smooth", block: "center" });
      return;
    }
    if (event.target.closest("[data-cancel-supplier-merge]")) {
      state.mergeSourceId = null;
      state.mergeTargetId = "";
      state.mergePreview = null;
      state.mergeError = "";
      render();
      return;
    }
    if (event.target.closest("[data-preview-supplier-merge]")) {
      if (!state.mergeSourceId || !state.mergeTargetId) return;
      state.mergeLoading = true;
      state.mergeError = "";
      render();
      try {
        state.mergePreview = await query("rpc/fn_previsualizar_mesclagem_fornecedor", {
          method: "POST",
          body: JSON.stringify({
            p_fornecedor_origem_id: state.mergeSourceId,
            p_fornecedor_destino_id: state.mergeTargetId,
          }),
        });
      } catch (error) {
        state.mergePreview = null;
        state.mergeError = error.message;
      } finally {
        state.mergeLoading = false;
        render();
      }
      return;
    }
    if (event.target.closest("[data-confirm-supplier-merge]")) {
      const source = state.suppliers.find(item => item.id === state.mergeSourceId);
      const target = state.suppliers.find(item => item.id === state.mergeTargetId);
      if (!source || !target || !state.mergePreview?.pode_mesclar) return;
      const confirmed = window.confirm(
        `Mesclar “${source.nome}” em “${target.nome}”?\n\n` +
        `${Number(state.mergePreview.total_referencias || 0)} referência(s) serão transferidas. ` +
        "A operação é transacional e o nome antigo será preservado como alias."
      );
      if (!confirmed) return;
      state.mergeLoading = true;
      state.mergeError = "";
      render();
      try {
        const result = await query("rpc/fn_mesclar_fornecedor", {
          method: "POST",
          body: JSON.stringify({
            p_fornecedor_origem_id: source.id,
            p_fornecedor_destino_id: target.id,
          }),
        });
        state.mergeSourceId = null;
        state.mergeTargetId = "";
        state.mergePreview = null;
        state.selectedSupplierId = null;
        await load();
        onSupplierMerged({
          sourceId: source.id,
          target: state.suppliers.find(item => item.id === target.id) || target,
        });
        toast(`${source.nome} foi mesclado em ${target.nome}. ${Number(result?.total_movidos || 0)} referência(s) transferidas.`);
      } catch (error) {
        state.mergeError = error.message;
        state.mergeLoading = false;
        render();
      }
      return;
    }
    const deleteButton = event.target.closest("[data-delete-supplier]");
    if (deleteButton) {
      const supplier = state.suppliers.find(item => item.id === deleteButton.dataset.deleteSupplier);
      if (!supplier) return;
      const confirmed = window.confirm(
        `Eliminar definitivamente o registo duplicado “${supplier.nome}”?\n\n` +
        "A eliminação só será permitida se este registo não tiver documentos, obras, faturas, propostas ou subempreitadas associados."
      );
      if (!confirmed) return;
      deleteButton.disabled = true;
      try {
        await query("rpc/fn_eliminar_fornecedor_duplicado", {
          method: "POST",
          body: JSON.stringify({ p_fornecedor_id: supplier.id }),
        });
        state.suppliers = state.suppliers.filter(item => item.id !== supplier.id);
        state.allSuppliers = state.allSuppliers.filter(item => item.id !== supplier.id);
        state.supplierZones = state.supplierZones.filter(item => item.fornecedor_id !== supplier.id);
        state.supplierSpecialties = state.supplierSpecialties.filter(item => item.fornecedor_id !== supplier.id);
        state.selectedSupplierId = null;
        toast("Registo duplicado eliminado.");
        render();
      } catch (error) {
        toast(error.message, "error");
        deleteButton.disabled = false;
      }
    }
  });

  content.addEventListener("submit", async event => {
    const supplierForm = event.target.closest("[data-supplier-editor]");
    if (supplierForm) {
      event.preventDefault();
      const button = supplierForm.querySelector("button[type=submit]");
      const errorNode = supplierForm.querySelector(".form-error");
      const fields = Object.fromEntries(new FormData(supplierForm).entries());
      const zones = [...supplierForm.querySelectorAll('[name="zona"]:checked')].map(input => input.value);
      const specialtyIds = [...supplierForm.querySelectorAll('[name="especialidade_id"]:checked')].map(input => input.value);
      const creating = supplierForm.dataset.supplierMode === "create";
      button.disabled = true;
      errorNode.textContent = "";
      try {
        const result = await query("rpc/fn_guardar_cadastro_fornecedor", {
          method: "POST",
          body: JSON.stringify({
            p_fornecedor_id: supplierForm.dataset.supplierEditor || null,
            p_nome: fields.nome,
            p_tipo_entidade: fields.tipo_entidade,
            p_nif: fields.nif,
            p_email: fields.email,
            p_telefone: fields.telefone,
            p_representante: fields.representante,
            p_notas: fields.notas,
            p_estado_confianca: fields.estado_confianca,
            p_zonas: zones,
            p_especialidades: specialtyIds,
            p_nova_especialidade: fields.nova_especialidade,
          }),
        });
        const [suppliers, specialties, supplierSpecialties, supplierZones] = await Promise.all([
          query("fornecedores?select=*&order=nome"),
          query("especialidades?select=*&aplicavel_subempreiteiro=eq.true&order=nome"),
          query("fornecedores_especialidades?select=*&order=criado_em"),
          query("fornecedores_zonas?select=*&order=zona"),
        ]);
        state.suppliers = suppliers;
        state.specialties = specialties;
        state.supplierSpecialties = supplierSpecialties;
        state.supplierZones = supplierZones;
        const savedId = supplierForm.dataset.supplierEditor || result?.id || result?.[0]?.id;
        const saved = state.suppliers.find(item => item.id === savedId)
          || state.suppliers.find(item => String(item.nome || "").localeCompare(String(fields.nome || ""), "pt-PT", { sensitivity: "base" }) === 0);
        if (saved) onSupplierUpdated(saved);
        state.creatingSupplier = false;
        state.selectedSupplierId = null;
        toast(creating ? "Novo parceiro criado." : "Cadastro completo atualizado.");
        render();
      } catch (error) {
        errorNode.textContent = error.message;
      } finally { button.disabled = false; }
      return;
    }
  });

  return { show: load, refresh: load };
}
