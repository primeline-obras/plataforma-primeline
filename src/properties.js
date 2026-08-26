const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);
const today = () => new Date().toISOString().slice(0, 10);

export function createPropertiesModule({ root, supabase, isConfigured, getProfile, prettyDate, toast }) {
  const state = { loaded: false, loading: false, properties: [], meetings: [], selectedId: "", error: "" };

  async function api(path, options) {
    const response = await supabase(path, options);
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      throw new Error(payload.message || payload.details || "Não foi possível consultar os imóveis.");
    }
    return response.status === 204 ? [] : response.json();
  }

  async function load(force = false) {
    if (state.loading || (state.loaded && !force)) return render();
    state.loading = true; state.error = ""; render();
    try {
      if (!isConfigured) {
        state.properties = []; state.meetings = [];
      } else {
        [state.properties, state.meetings] = await Promise.all([
          api("imoveis_empresa?select=*&order=nome.asc"),
          api("imoveis_reunioes_condominio?select=*&order=data.asc,hora.asc.nullslast"),
        ]);
      }
      state.loaded = true;
      if (!state.selectedId || !state.properties.some(row => row.id === state.selectedId)) state.selectedId = state.properties[0]?.id || "";
    } catch (error) { state.error = `${error.message} Confirme se executou o SQL do Bloco 13.`; }
    finally { state.loading = false; render(); }
  }

  const propertyName = id => state.properties.find(row => row.id === id)?.nome || "Imóvel não identificado";
  const dateLabel = value => value ? prettyDate.format(new Date(`${value}T12:00:00`)) : "—";
  const timeLabel = value => String(value || "").slice(0, 5) || "Hora não indicada";

  function propertyForm() {
    return `<details class="operations-form-card"><summary>＋ NOVO IMÓVEL</summary><form data-property-form>
      <label>NOME<input name="nome" required maxlength="160" placeholder="Ex. Escritório de Lisboa"></label>
      <label>MORADA<textarea name="morada" rows="2"></textarea></label>
      <button class="primary-button" type="submit">GUARDAR IMÓVEL <span>→</span></button><p class="form-error"></p>
    </form></details>`;
  }

  function meetingForm() {
    return `<details class="operations-form-card" ${state.properties.length ? "" : "disabled"}><summary>＋ NOVA REUNIÃO DE CONDOMÍNIO</summary><form data-property-meeting-form>
      <label>IMÓVEL<select name="imovel_id" required><option value="">Selecionar imóvel</option>${state.properties.map(row => `<option value="${row.id}" ${row.id === state.selectedId ? "selected" : ""}>${esc(row.nome)}</option>`).join("")}</select></label>
      <div class="operations-form-grid"><label>DATA<input name="data" type="date" required min="${today()}"></label><label>HORA<input name="hora" type="time"></label></div>
      <label>LOCAL<input name="local" maxlength="200" placeholder="Ex. Administração do condomínio"></label>
      <label>NOTAS<textarea name="notas" rows="3"></textarea></label>
      <button class="primary-button" type="submit">AGENDAR REUNIÃO <span>→</span></button><p class="form-error"></p>
    </form></details>`;
  }

  function renderProperties() {
    return `<section class="panel operations-directory"><header><div><p class="eyebrow">PATRIMÓNIO</p><h2>IMÓVEIS DA EMPRESA</h2></div><span>${state.properties.length}</span></header>
      ${propertyForm()}<div class="property-cards">${state.properties.length ? state.properties.map(row => {
        const count = state.meetings.filter(meeting => meeting.imovel_id === row.id).length;
        return `<article class="property-card-wrap"><button type="button" class="property-card ${row.id === state.selectedId ? "active" : ""}" data-property-id="${row.id}"><span>IMÓVEL</span><strong>${esc(row.nome)}</strong><p>${esc(row.morada || "Morada não indicada")}</p><small>${count} REUNIÃO${count === 1 ? "" : "ÕES"}</small></button><button type="button" class="danger-action" data-delete-property="${row.id}" data-property-name="${esc(row.nome)}">APAGAR</button></article>`;
      }).join("") : `<div class="operations-empty">AINDA NÃO EXISTEM IMÓVEIS REGISTADOS</div>`}</div>
    </section>`;
  }

  function renderMeetings() {
    const rows = state.meetings.filter(row => !state.selectedId || row.imovel_id === state.selectedId);
    const upcoming = rows.filter(row => row.data >= today());
    return `<section class="panel operations-detail"><header><div><p class="eyebrow">CONDOMÍNIO</p><h2>REUNIÕES AGENDADAS</h2></div><span>${upcoming.length} FUTURAS</span></header>
      ${meetingForm()}<div class="condo-meeting-list">${rows.length ? rows.map(row => `<article class="${row.data < today() ? "past" : ""}"><time><b>${dateLabel(row.data)}</b><span>${timeLabel(row.hora)}</span></time><div><strong>${esc(propertyName(row.imovel_id))}</strong><p>${esc(row.local || "Local não indicado")}</p><small>${esc(row.notas || "Sem notas")}</small></div><button type="button" class="danger-action" data-delete-property-meeting="${row.id}">APAGAR</button></article>`).join("") : `<div class="operations-empty">SEM REUNIÕES PARA ESTE IMÓVEL</div>`}</div>
    </section>`;
  }

  function render() {
    root.innerHTML = `<div class="page-heading"><div><p class="eyebrow">GESTÃO PATRIMONIAL</p><h1>IMÓVEIS</h1><p>Património da empresa e reuniões de condomínio, sem ligação às obras.</p></div><div class="heading-stat"><span>IMÓVEIS</span><strong>${String(state.properties.length).padStart(2, "0")}</strong></div></div>
      ${state.error ? `<div class="work-warning"><strong>DADOS INDISPONÍVEIS</strong><span>${esc(state.error)}</span></div>` : ""}
      ${state.loading ? `<div class="fleet-loading">A CARREGAR IMÓVEIS…</div>` : `<div class="operations-layout">${renderProperties()}${renderMeetings()}</div>`}`;
  }

  root.addEventListener("click", event => {
    const button = event.target.closest("[data-property-id]");
    if (button) { state.selectedId = button.dataset.propertyId; render(); }
    const meetingDelete = event.target.closest("[data-delete-property-meeting]");
    if (meetingDelete) {
      if (!window.confirm("Apagar esta reunião de condomínio? A ação fica registada na auditoria.")) return;
      meetingDelete.disabled = true;
      api("rpc/fn_apagar_reuniao_condominio", { method: "POST", body: JSON.stringify({ p_reuniao_id: meetingDelete.dataset.deletePropertyMeeting }) })
        .then(() => { state.meetings = state.meetings.filter(row => row.id !== meetingDelete.dataset.deletePropertyMeeting); toast("Reunião apagada."); render(); })
        .catch(error => { toast(error.message, "error"); meetingDelete.disabled = false; });
      return;
    }
    const propertyDelete = event.target.closest("[data-delete-property]");
    if (propertyDelete) {
      if (!window.confirm(`Apagar o imóvel “${propertyDelete.dataset.propertyName}” e as respetivas reuniões? A ação fica registada na auditoria.`)) return;
      propertyDelete.disabled = true;
      api("rpc/fn_apagar_imovel_empresa", { method: "POST", body: JSON.stringify({ p_imovel_id: propertyDelete.dataset.deleteProperty }) })
        .then(() => { const id = propertyDelete.dataset.deleteProperty; state.properties = state.properties.filter(row => row.id !== id); state.meetings = state.meetings.filter(row => row.imovel_id !== id); state.selectedId = state.properties[0]?.id || ""; toast("Imóvel apagado."); render(); })
        .catch(error => { toast(error.message, "error"); propertyDelete.disabled = false; });
    }
  });

  root.addEventListener("submit", async event => {
    const propertyFormNode = event.target.closest("[data-property-form]");
    const meetingFormNode = event.target.closest("[data-property-meeting-form]");
    if (!propertyFormNode && !meetingFormNode) return;
    event.preventDefault();
    const form = propertyFormNode || meetingFormNode;
    const errorNode = form.querySelector(".form-error"); const button = form.querySelector('button[type="submit"]');
    button.disabled = true; errorNode.textContent = "";
    try {
      const fields = Object.fromEntries(new FormData(form));
      if (propertyFormNode) {
        const payload = { empresa_id: getProfile()?.empresa_id, nome: fields.nome.trim(), morada: fields.morada.trim() || null };
        let saved = { id: crypto.randomUUID(), criado_em: new Date().toISOString(), ...payload };
        if (isConfigured) [saved] = await api("imoveis_empresa?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        state.properties.push(saved); state.properties.sort((a, b) => a.nome.localeCompare(b.nome, "pt-PT")); state.selectedId = saved.id;
        toast("Imóvel criado.");
      } else {
        const payload = { imovel_id: fields.imovel_id, data: fields.data, hora: fields.hora || null, local: fields.local.trim() || null, notas: fields.notas.trim() || null };
        let saved = { id: crypto.randomUUID(), criado_em: new Date().toISOString(), ...payload };
        if (isConfigured) [saved] = await api("imoveis_reunioes_condominio?select=*", { method: "POST", headers: { Prefer: "return=representation" }, body: JSON.stringify(payload) });
        state.meetings.push(saved); state.meetings.sort((a, b) => `${a.data}${a.hora || ""}`.localeCompare(`${b.data}${b.hora || ""}`)); state.selectedId = saved.imovel_id;
        toast("Reunião de condomínio agendada.");
      }
      render();
    } catch (error) { errorNode.textContent = error.message || "Não foi possível guardar."; button.disabled = false; }
  });

  return { show: () => load(), refresh: () => load(true) };
}
