import assert from "node:assert/strict";
import { accessFor } from "../src/access-control.js";

const matrix = {
  gerencia: {
    views: ["finance", "team", "workforce", "planning"],
    actions: ["insertInvoices", "approveInvoices", "payInvoices", "editWork", "createWorks"],
  },
  administrativo: {
    views: ["finance", "team", "workforce", "planning", "documents"],
    actions: ["insertInvoices"],
    deniedActions: ["approveInvoices", "payInvoices", "editWork", "createWorks"],
  },
  financeiro: {
    views: ["overview", "meeting", "works", "planning", "subcontractors", "finance"],
    deniedViews: ["invoices", "documents", "team", "workforce"],
    actions: ["payInvoices"],
    deniedActions: ["insertInvoices", "approveInvoices", "editWork", "createWorks"],
  },
  diretor_obra: {
    views: ["overview", "works", "invoices", "planning", "documents", "subcontractors"],
    deniedViews: ["finance", "team", "workforce"],
    actions: ["approveInvoices", "editWork"],
    deniedActions: ["insertInvoices", "payInvoices", "createWorks"],
  },
  preparador: {
    views: ["overview", "works", "invoices", "planning", "documents", "subcontractors"],
    deniedViews: ["finance", "team", "workforce"],
    actions: ["approveInvoices", "editWork"],
    deniedActions: ["insertInvoices", "payInvoices", "createWorks"],
  },
};

for (const [role, expected] of Object.entries(matrix)) {
  const access = accessFor({ role, isAdmin: false });
  expected.views.forEach(view => assert(access.views.includes(view), `${role} deve ver ${view}`));
  (expected.deniedViews || []).forEach(view => assert(!access.views.includes(view), `${role} não deve ver ${view}`));
  expected.actions.forEach(action => assert.equal(access[action], true, `${role} deve poder ${action}`));
  (expected.deniedActions || []).forEach(action => assert.equal(access[action], false, `${role} não deve poder ${action}`));
}

const platformAdmin = accessFor({ role: "preparador", isAdmin: true });
assert.equal(platformAdmin.role, "gerencia");
assert.equal(platformAdmin.createWorks, true);
assert(platformAdmin.views.includes("team"));

console.log("Matriz de acesso do frontend validada para 5 papéis e administrador da plataforma.");
