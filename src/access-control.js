const FULL_VIEWS = [
  "overview", "meeting", "invoices", "works", "planning", "subcontractors",
  "finance", "documents", "team", "workforce", "settings",
];

const ACCESS_BY_ROLE = {
  gerencia: {
    views: FULL_VIEWS,
    insertInvoices: true,
    approveInvoices: true,
    payInvoices: true,
    editWork: true,
    createWorks: true,
  },
  administrativo: {
    views: FULL_VIEWS,
    insertInvoices: true,
    approveInvoices: false,
    payInvoices: false,
    editWork: false,
    createWorks: false,
  },
  financeiro: {
    views: ["overview", "meeting", "works", "planning", "finance", "settings"],
    insertInvoices: false,
    approveInvoices: false,
    payInvoices: true,
    editWork: false,
    createWorks: false,
  },
  diretor_obra: {
    views: ["overview", "meeting", "invoices", "works", "planning", "subcontractors", "documents", "settings"],
    insertInvoices: false,
    approveInvoices: true,
    payInvoices: false,
    editWork: true,
    createWorks: false,
  },
  preparador: {
    views: ["overview", "meeting", "invoices", "works", "planning", "subcontractors", "documents", "settings"],
    insertInvoices: false,
    approveInvoices: true,
    payInvoices: false,
    editWork: true,
    createWorks: false,
  },
  encarregado: {
    views: ["action-plan", "overview", "meeting", "works", "planning", "documents", "settings"],
    insertInvoices: false,
    approveInvoices: false,
    payInvoices: false,
    editWork: false,
    createWorks: false,
  },
};

const NO_ACCESS = {
  views: ["settings"],
  insertInvoices: false,
  approveInvoices: false,
  payInvoices: false,
  editWork: false,
  createWorks: false,
};

export function effectiveAccessRole(context = {}) {
  return context.isAdmin || context.role === "gerencia" ? "gerencia" : context.role || "";
}

export function accessFor(context = {}) {
  const role = effectiveAccessRole(context);
  const access = ACCESS_BY_ROLE[role] || NO_ACCESS;
  return { ...access, role, views: [...access.views] };
}
