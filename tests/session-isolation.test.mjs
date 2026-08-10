import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(new URL("../src/supabase-browser.js", import.meta.url), "utf8");

function memoryStorage() {
  const values = new Map();
  return {
    getItem(key) { return values.has(key) ? values.get(key) : null; },
    setItem(key, value) { values.set(key, String(value)); },
    removeItem(key) { values.delete(key); },
  };
}

async function loadAuthModule(sessionStorage, localStorage, suffix) {
  globalThis.window = {
    PRIMELINE_CONFIG: { supabaseUrl: "https://example.supabase.co", supabaseAnonKey: "anon" },
    sessionStorage,
    localStorage,
  };
  const encoded = Buffer.from(`${source}\n// ${suffix}`).toString("base64");
  return import(`data:text/javascript;base64,${encoded}`);
}

test("sessões autenticadas ficam isoladas por separador e sobrevivem ao refresh", async () => {
  const sharedLocalStorage = memoryStorage();
  const financeTab = memoryStorage();
  const adminTab = memoryStorage();
  let loginEmail = "financeiro@primeline.pt";

  globalThis.fetch = async () => new Response(JSON.stringify({
    access_token: `token:${loginEmail}`,
    refresh_token: `refresh:${loginEmail}`,
    user: { email: loginEmail },
  }), { status: 200, headers: { "Content-Type": "application/json" } });

  const financeAuth = await loadAuthModule(financeTab, sharedLocalStorage, "finance");
  await financeAuth.signIn(loginEmail, "password");

  loginEmail = "geral@primeline.pt";
  const adminAuth = await loadAuthModule(adminTab, sharedLocalStorage, "admin");
  await adminAuth.signIn(loginEmail, "password");

  assert.equal(financeAuth.getSession().user.email, "financeiro@primeline.pt");
  assert.equal(adminAuth.getSession().user.email, "geral@primeline.pt");

  const financeAfterRefresh = await loadAuthModule(financeTab, sharedLocalStorage, "finance-refresh");
  assert.equal(financeAfterRefresh.getSession().user.email, "financeiro@primeline.pt");
  assert.equal(sharedLocalStorage.getItem("primeline_supabase_session"), null);
});
