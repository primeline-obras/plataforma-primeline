import assert from "node:assert/strict";
import { accessFor } from "../src/access-control.js";

const matrix = {
  gerencia: {
    views: ["consolidated", "finance", "vehicles", "rooms", "properties", "budget-requests", "team", "workforce", "planning", "rnc", "settings"],
    actions: ["insertInvoices", "approveInvoices", "payInvoices", "editWork", "createWorks"],
  },
  administrativo: {
    views: ["finance", "vehicles", "rooms", "properties", "budget-requests", "team", "workforce", "planning", "documents", "rnc", "settings"],
    actions: ["insertInvoices"],
    deniedViews: ["consolidated"],
    deniedActions: ["approveInvoices", "payInvoices", "editWork", "createWorks"],
  },
  financeiro: {
    views: ["overview", "meeting", "works", "finance", "rooms", "settings"],
    deniedViews: ["consolidated", "invoices", "subcontractors", "planning", "documents", "vehicles", "team", "workforce"],
    actions: ["payInvoices"],
    deniedActions: ["insertInvoices", "approveInvoices", "editWork", "createWorks"],
  },
  diretor_obra: {
    views: ["overview", "works", "invoices", "planning", "documents", "subcontractors", "rnc", "rooms", "team", "settings"],
    deniedViews: ["consolidated", "finance", "vehicles", "workforce"],
    actions: ["approveInvoices", "editWork"],
    deniedActions: ["insertInvoices", "payInvoices", "createWorks"],
  },
  preparador: {
    views: ["overview", "works", "invoices", "planning", "documents", "subcontractors", "rnc", "rooms", "team", "settings"],
    deniedViews: ["consolidated", "finance", "vehicles", "workforce"],
    actions: ["approveInvoices", "editWork"],
    deniedActions: ["insertInvoices", "payInvoices", "createWorks"],
  },
  encarregado: {
    views: ["action-plan", "planning", "documents", "rnc", "rooms", "team", "workforce", "settings"],
    deniedViews: ["consolidated", "overview", "meeting", "works", "invoices", "finance", "subcontractors", "vehicles"],
    actions: [],
    deniedActions: ["insertInvoices", "approveInvoices", "payInvoices", "editWork", "createWorks"],
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

const noProfile = accessFor({ role: "", isAdmin: false });
assert.deepEqual(noProfile.views, ["rooms", "settings"]);

console.log("Matriz de acesso do frontend validada para 6 papéis e administrador da plataforma.");
