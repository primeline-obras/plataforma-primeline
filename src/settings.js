const ROLES = ["gerencia", "diretor_obra", "preparador", "encarregado", "administrativo", "financeiro"];
const RESPONSIBILITY_ROLES = ["diretor_obra", "adjunto", "preparador", "encarregado"];

const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
const roleLabel = value => ({ gerencia: "Gerência", diretor_obra: "Diretor de obra", adjunto: "Adjunto", preparador: "Preparador", encarregado: "Encarregado", administrativo: "Administrativo", financeiro: "Financeiro" })[value] || value || "—";
const roleOptions = (values, selected = "") => values.map(value => `<option value="${value}" ${value === selected ? "selected" : ""}>${roleLabel(value)}</option>`).join("");

export function createSettingsModule({
  root,
  supabase,
  isConfigured,
  companyId,
  getProfile,
  getSession,
  getWorks,
  isAdmin,
  toast,
  requestPasswordReset,
  toggleTheme,
  toggleTv,
  syncPreferences,
}) {
  const state = { loaded: false, users: [], responsibilities: [], admins: [], company: null };

  function shell() {
    root.innerHTML = `
      <div class="page-heading settings-heading"><div><p class="eyebrow">CONFIGURAÇÃO</p><h1>DEFINIÇÕES</h1><p>Perfil, preferências e administração da plataforma.</p></div></div>
      <div class="settings-grid settings-personal-grid">
        <section class="panel settings-card"><header><div><p class="eyebrow">CONTA</p><h2>PERFIL</h2></div></header><div id="settings-profile"></div></section>
        <section class="panel settings-card"><header><div><p class="eyebrow">INTERFACE</p><h2>PREFERÊNCIAS</h2></div></header><div class="settings-preferences"><button type="button" data-settings-theme>ALTERAR TEMA</button><button type="button" data-settings-tv>MODO TV</button><p>As preferências ficam guardadas neste dispositivo.</p></div></section>
      </div>
      <section id="settings-admin" class="settings-admin" hidden>
        <div class="settings-divider"><span>ADMINISTRAÇÃO DA PLATAFORMA</span></div>
        <div class="settings-grid">
          <section class="panel settings-card settings-wide"><header><div><p class="eyebrow">ACESSOS</p><h2>GESTÃO DE UTILIZADORES</h2></div><span id="settings-user-count"></span></header>
            <form id="settings-user-form" class="settings-inline-form"><label>NOME<input name="nome" required maxlength="160"></label><label>EMAIL<input name="email" type="email" required maxlength="240"></label><label>FUNÇÃO<select name="funcao">${roleOptions(ROLES, "diretor_obra")}</select></label><button type="submit">＋ CRIAR REGISTO</button></form>
            <div id="settings-users" class="settings-list"></div>
          </section>
          <section class="panel settings-card settings-wide"><header><div><p class="eyebrow">OBRAS</p><h2>RESPONSÁVEIS POR OBRA</h2></div><span id="settings-responsibility-count"></span></header>
            <form id="settings-responsibility-form" class="settings-inline-form"><label>OBRA<select name="obra_id" required></select></label><label>UTILIZADOR<select name="utilizador_id" required></select></label><label>PAPEL<select name="papel">${roleOptions(RESPONSIBILITY_ROLES, "diretor_obra")}</select></label><button type="submit">＋ ASSOCIAR</button></form>
            <div id="settings-responsibilities" class="settings-list"></div>
          </section>
          <section class="panel settings-card"><header><div><p class="eyebrow">ACESSO TOTAL</p><h2>ADMINISTRADORES</h2></div></header>
            <form id="settings-admin-form" class="settings-stack-form"><label>UTILIZADOR<select name="utilizador_id" required></select></label><button type="submit">＋ ADICIONAR ADMINISTRADOR</button></form><div id="settings-admins" class="settings-list compact"></div>
          </section>
          <section class="panel settings-card"><header><div><p class="eyebrow">ORGANIZAÇÃO</p><h2>DADOS DA EMPRESA</h2></div></header>
            <form id="settings-company-form" class="settings-stack-form"><label>NOME<input name="nome" required></label><label>NIF<input name="nif" maxlength="20"></label><label>MORADA<textarea name="morada" rows="3"></textarea></label><button type="submit">GUARDAR DADOS</button></form>
          </section>
        </div>
      </section>`;
    bindEvents();
  }

  function renderProfile() {
    const profile = getProfile() || {};
    const session = getSession();
    const email = profile.email || session?.user?.email || "—";
    root.querySelector("#settings-profile").innerHTML = `<dl class="settings-profile-list">
      <div><dt>NOME</dt><dd>${escapeHtml(profile.nome || "Utilizador")}</dd></div>
      <div><dt>EMAIL</dt><dd>${escapeHtml(email)}</dd></div>
      <div><dt>FUNÇÃO</dt><dd>${escapeHtml(roleLabel(profile.funcao))}</dd></div>
    </dl><button class="settings-secondary-button" type="button" data-settings-password>ENVIAR LINK PARA TROCAR PALAVRA-PASSE</button>`;
  }

  function renderUsers() {
    root.querySelector("#settings-user-count").textContent = `${state.users.length} UTILIZADORES`;
    root.querySelector("#settings-users").innerHTML = state.users.map(user => {
      const current = user.id === getProfile()?.id;
      return `<article class="settings-user-row ${user.ativo ? "" : "inactive"}" data-user-row="${user.id}">
        <div class="settings-user-identity"><strong>${escapeHtml(user.nome)}</strong><span>${escapeHtml(user.email)}</span></div>
        <div class="settings-auth-state ${user.auth_user_id ? "linked" : "unlinked"}"><b>${user.auth_user_id ? "CONTA DE LOGIN LIGADA" : "SEM CONTA DE LOGIN ASSOCIADA"}</b><span>${user.auth_user_id ? "Pode autenticar-se na plataforma" : "Criar a conta no Supabase Auth e ligar auth_user_id"}</span></div>
        <label>FUNÇÃO<select data-user-role="${user.id}">${roleOptions(ROLES, user.funcao)}</select></label>
        <span class="settings-status ${user.ativo ? "active" : "inactive"}">${user.ativo ? "ATIVO" : "INATIVO"}</span>
        <div class="settings-row-actions"><button type="button" data-save-user-role="${user.id}">GUARDAR</button><button type="button" data-toggle-user="${user.id}" ${current ? "disabled title=\"Não pode desativar a própria conta\"" : ""}>${user.ativo ? "DESATIVAR" : "ATIVAR"}</button></div>
      </article>`;
    }).join("") || `<div class="settings-empty">SEM UTILIZADORES</div>`;
  }

  function renderResponsibilities() {
    const works = getWorks();
    const form = root.querySelector("#settings-responsibility-form");
    form.elements.obra_id.innerHTML = `<option value="">Selecionar obra</option>${works.map(work => `<option value="${work.id}">Obra ${escapeHtml(work.numero)} — ${escapeHtml(work.nome)}</option>`).join("")}`;
    form.elements.utilizador_id.innerHTML = `<option value="">Selecionar utilizador</option>${state.users.filter(user => user.ativo).map(user => `<option value="${user.id}">${escapeHtml(user.nome)} · ${escapeHtml(roleLabel(user.funcao))}</option>`).join("")}`;
    root.querySelector("#settings-responsibility-count").textContent = `${state.responsibilities.length} ASSOCIAÇÕES`;
    root.querySelector("#settings-responsibilities").innerHTML = state.responsibilities.map(item => {
      const work = works.find(row => row.id === item.obra_id);
      const user = state.users.find(row => row.id === item.utilizador_id);
      return `<article class="settings-simple-row"><div><strong>OBRA ${escapeHtml(work?.numero || "—")} · ${escapeHtml(work?.nome || "Obra")}</strong><span>${escapeHtml(user?.nome || "Utilizador")} · ${escapeHtml(roleLabel(item.papel))}</span></div><button type="button" data-remove-responsibility="${item.id}">REMOVER</button></article>`;
    }).join("") || `<div class="settings-empty">SEM RESPONSÁVEIS ASSOCIADOS</div>`;
  }

  function renderAdmins() {
    const adminIds = new Set(state.admins.map(item => item.utilizador_id));
    const form = root.querySelector("#settings-admin-form");
    form.elements.utilizador_id.innerHTML = `<option value="">Selecionar utilizador</option>${state.users.filter(user => user.ativo && !adminIds.has(user.id)).map(user => `<option value="${user.id}">${escapeHtml(user.nome)}</option>`).join("")}`;
    root.querySelector("#settings-admins").innerHTML = state.admins.map(item => {
      const user = state.users.find(row => row.id === item.utilizador_id);
      const current = item.utilizador_id === getProfile()?.id;
      return `<article class="settings-simple-row"><div><strong>${escapeHtml(user?.nome || "Utilizador")}</strong><span>${escapeHtml(user?.email || "")}</span></div><button type="button" data-remove-admin="${item.id}" ${current ? "disabled title=\"Não pode remover o próprio acesso total\"" : ""}>REMOVER</button></article>`;
    }).join("") || `<div class="settings-empty">SEM ADMINISTRADORES ADICIONAIS</div>`;
  }

  function renderCompany() {
    const company = state.company || { id: companyId, nome: "PRIMELINE", nif: "", morada: "" };
    const form = root.querySelector("#settings-company-form");
    form.elements.nome.value = company.nome || "";
    form.elements.nif.value = company.nif || "";
    form.elements.morada.value = company.morada || "";
  }

  function renderAdmin() {
    root.querySelector("#settings-admin").hidden = !isAdmin();
    if (!isAdmin()) return;
    renderUsers(); renderResponsibilities(); renderAdmins(); renderCompany();
  }

  async function request(path, options, failureMessage) {
    const response = await supabase(path, options);
    if (!response.ok) throw new Error(`${failureMessage}: ${await response.text()}`);
    if (response.status === 204) return null;
    return response.json();
  }

  async function load(force = false) {
    if (!root.innerHTML) shell();
    renderProfile();
    syncPreferences();
    root.querySelector("#settings-admin").hidden = !isAdmin();
    if (!isAdmin() || (state.loaded && !force)) return;
    if (!isConfigured) {
      const profile = getProfile();
      state.users = [{ ...profile, id: profile?.id || "demo", email: "demo@primeline.pt", ativo: true, auth_user_id: "demo-auth", empresa_id: companyId }];
      state.company = { id: companyId, nome: "PRIMELINE", nif: "", morada: "" };
      state.loaded = true; renderAdmin(); return;
    }
    try {
      const results = await Promise.all([
        request("utilizadores?select=id,empresa_id,nome,email,funcao,ativo,auth_user_id,criado_em&order=nome", {}, "Não foi possível carregar os utilizadores"),
        request("obra_responsaveis?select=id,obra_id,utilizador_id,papel,criado_em&order=criado_em", {}, "Não foi possível carregar os responsáveis"),
        request("administradores_plataforma?select=id,utilizador_id,criado_em&order=criado_em", {}, "Não foi possível carregar os administradores"),
        request(`empresas?select=id,nome,morada,nif&id=eq.${companyId}&limit=1`, {}, "Não foi possível carregar a empresa"),
      ]);
      [state.users, state.responsibilities, state.admins] = results;
      state.company = results[3][0] || null;
      state.loaded = true;
      renderAdmin();
    } catch (error) { toast(error.message, "error"); }
  }

  async function withButton(button, callback) {
    button.disabled = true;
    try { await callback(); } catch (error) { toast(error.message, "error"); } finally { button.disabled = false; }
  }

  function bindEvents() {
    root.addEventListener("click", event => {
      const theme = event.target.closest("[data-settings-theme]");
      if (theme) return toggleTheme();
      const tv = event.target.closest("[data-settings-tv]");
      if (tv) return toggleTv();
      const password = event.target.closest("[data-settings-password]");
      if (password) return withButton(password, async () => { await requestPasswordReset(getProfile()?.email || getSession()?.user?.email); toast("Ligação para alterar a palavra-passe enviada por email."); });
      const saveRole = event.target.closest("[data-save-user-role]");
      if (saveRole) return withButton(saveRole, async () => {
        const id = saveRole.dataset.saveUserRole;
        const funcao = root.querySelector(`[data-user-role="${id}"]`).value;
        await request(`utilizadores?id=eq.${id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ funcao }) }, "Não foi possível alterar a função");
        const user = state.users.find(item => item.id === id); user.funcao = funcao; renderAdmin(); toast("Função atualizada.");
      });
      const toggle = event.target.closest("[data-toggle-user]");
      if (toggle) return withButton(toggle, async () => {
        const user = state.users.find(item => item.id === toggle.dataset.toggleUser);
        const ativo = !user.ativo;
        await request(`utilizadores?id=eq.${user.id}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify({ ativo }) }, "Não foi possível alterar o estado");
        user.ativo = ativo; renderAdmin(); toast(ativo ? "Utilizador ativado." : "Utilizador desativado sem apagar o histórico.");
      });
      const removeResponsibility = event.target.closest("[data-remove-responsibility]");
      if (removeResponsibility) return withButton(removeResponsibility, async () => {
        const id = removeResponsibility.dataset.removeResponsibility;
        await request(`obra_responsaveis?id=eq.${id}`, { method: "DELETE", headers: { Prefer: "return=minimal" } }, "Não foi possível remover a associação");
        state.responsibilities = state.responsibilities.filter(item => item.id !== id); renderResponsibilities(); toast("Responsabilidade removida.");
      });
      const removeAdmin = event.target.closest("[data-remove-admin]");
      if (removeAdmin) return withButton(removeAdmin, async () => {
        const id = removeAdmin.dataset.removeAdmin;
        await request(`administradores_plataforma?id=eq.${id}`, { method: "DELETE", headers: { Prefer: "return=minimal" } }, "Não foi possível remover o administrador");
        state.admins = state.admins.filter(item => item.id !== id); renderAdmins(); toast("Acesso total removido.");
      });
    });

    root.addEventListener("submit", event => {
      event.preventDefault();
      const form = event.target;
      const button = form.querySelector("button[type=submit]");
      if (form.id === "settings-user-form") return withButton(button, async () => {
        const payload = { empresa_id: state.company?.id || companyId, nome: form.elements.nome.value.trim(), email: form.elements.email.value.trim().toLowerCase(), funcao: form.elements.funcao.value, ativo: true };
        const rows = await request("utilizadores", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) }, "Não foi possível criar o utilizador");
        state.users.push(rows[0]); form.reset(); renderAdmin(); toast("Registo criado. Falta criar e ligar a conta no Supabase Auth.");
      });
      if (form.id === "settings-responsibility-form") return withButton(button, async () => {
        const payload = { obra_id: form.elements.obra_id.value, utilizador_id: form.elements.utilizador_id.value, papel: form.elements.papel.value };
        const rows = await request("obra_responsaveis", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) }, "Não foi possível associar o responsável");
        state.responsibilities.push(rows[0]); form.reset(); renderResponsibilities(); toast("Responsável associado à obra.");
      });
      if (form.id === "settings-admin-form") return withButton(button, async () => {
        const rows = await request("administradores_plataforma", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify({ utilizador_id: form.elements.utilizador_id.value }) }, "Não foi possível adicionar o administrador");
        state.admins.push(rows[0]); form.reset(); renderAdmins(); toast("Administrador da plataforma adicionado.");
      });
      if (form.id === "settings-company-form") return withButton(button, async () => {
        const payload = { nome: form.elements.nome.value.trim(), nif: form.elements.nif.value.trim() || null, morada: form.elements.morada.value.trim() || null };
        await request(`empresas?id=eq.${state.company?.id || companyId}`, { method: "PATCH", headers: { Prefer: "return=minimal" }, body: JSON.stringify(payload) }, "Não foi possível guardar os dados da empresa");
        state.company = { ...(state.company || { id: companyId }), ...payload }; toast("Dados da empresa atualizados.");
      });
    });
  }

  shell();
  return { load, refresh: () => load(true) };
}
