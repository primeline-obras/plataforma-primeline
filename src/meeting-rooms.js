const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

const isoToday = () => new Date().toISOString().slice(0, 10);
const monthKey = value => String(value || isoToday()).slice(0, 7);
const normalizeTime = value => String(value || "").slice(0, 5);
const monthLabel = value => new Intl.DateTimeFormat("pt-PT", { month: "long", year: "numeric" }).format(new Date(`${value}-01T12:00:00`));
const dayLabel = value => new Intl.DateTimeFormat("pt-PT", { weekday: "short", day: "2-digit", month: "short" }).format(new Date(`${value}T12:00:00`));

function changeMonth(value, offset) {
  const date = new Date(`${value}-01T12:00:00`); date.setMonth(date.getMonth() + offset); return date.toISOString().slice(0, 7);
}

function calendarDays(value) {
  const [year, month] = value.split("-").map(Number);
  const first = new Date(year, month - 1, 1, 12);
  return [...Array.from({ length: (first.getDay() + 6) % 7 }, () => null), ...Array.from({ length: new Date(year, month, 0, 12).getDate() }, (_, index) => `${year}-${String(month).padStart(2, "0")}-${String(index + 1).padStart(2, "0")}`)];
}

export function createMeetingRoomsModule({ root, supabase, isConfigured, getProfile, toast }) {
  const state = { loaded: false, loading: false, rooms: [], reservations: [], participants: [], users: [], error: "", month: monthKey(), selectedDate: isoToday(), selectedRoomId: "", editingId: "" };

  async function api(path, options) {
    const response = await supabase(path, options);
    if (!response.ok) { const payload = await response.json().catch(() => ({})); throw new Error(payload.message || payload.details || "Não foi possível consultar as reservas."); }
    return response.status === 204 ? [] : response.json();
  }

  const isForeman = () => String(getProfile()?.funcao || "").toLowerCase() === "encarregado";
  const roomReservations = () => state.reservations.filter(row => row.sala_id === state.selectedRoomId);
  const reservationsFor = date => roomReservations().filter(row => row.data === date).sort((a, b) => String(a.hora_inicio).localeCompare(String(b.hora_inicio)));
  const participantIds = reservationId => state.participants.filter(row => row.reserva_id === reservationId).map(row => row.utilizador_id);
  const canManage = row => row?.criado_por === getProfile()?.id || ["administrativo", "gerencia"].includes(String(getProfile()?.funcao || "").toLowerCase());
  const overlaps = (date, start, end, ignoredId = "") => reservationsFor(date).some(row => row.id !== ignoredId && start < normalizeTime(row.hora_fim) && end > normalizeTime(row.hora_inicio));

  async function load(force = false) {
    if (isForeman()) { root.innerHTML = ""; return; }
    if (state.loading || (state.loaded && !force)) return render();
    state.loading = true; state.error = ""; render();
    try {
      if (!isConfigured) { state.rooms = [{ id: "demo-room", nome: "Sala de Reuniões" }]; state.reservations = []; state.participants = []; }
      else [state.rooms, state.reservations, state.participants, state.users] = await Promise.all([
        api("salas_reuniao?select=*&order=nome.asc"), api("reservas_salas?select=*&order=data.asc,hora_inicio.asc"),
        api("reservas_salas_participantes?select=reserva_id,utilizador_id"),
        api("rpc/fn_listar_participantes_reuniao", { method: "POST", body: "{}" }),
      ]);
      state.loaded = true;
      if (!state.selectedRoomId || !state.rooms.some(room => room.id === state.selectedRoomId)) state.selectedRoomId = state.rooms[0]?.id || "";
    } catch (error) { state.error = `${error.message} Confirme se executou o SQL das Salas de Reunião.`; }
    finally { state.loading = false; render(); }
  }

  const actionButtons = row => canManage(row) ? `<div class="meeting-reservation-actions"><button type="button" data-edit-reservation="${row.id}">EDITAR</button><button type="button" class="danger" data-delete-reservation="${row.id}">APAGAR</button></div>` : "";

  function renderCalendar() {
    return `<section class="meeting-calendar panel"><header><button type="button" data-room-month="-1" aria-label="Mês anterior">←</button><div><p class="eyebrow">CALENDÁRIO</p><h2>${esc(monthLabel(state.month))}</h2></div><button type="button" data-room-month="1" aria-label="Mês seguinte">→</button></header><div class="meeting-weekdays">${["SEG","TER","QUA","QUI","SEX","SÁB","DOM"].map(day => `<span>${day}</span>`).join("")}</div><div class="meeting-month-grid">${calendarDays(state.month).map(date => {
      if (!date) return `<span class="meeting-day empty"></span>`;
      const rows = reservationsFor(date);
      return `<button type="button" class="meeting-day ${date === state.selectedDate ? "selected" : ""} ${date === isoToday() ? "today" : ""}" data-room-date="${date}"><b>${Number(date.slice(-2))}</b><span>${rows.slice(0,3).map(row => `<i>${normalizeTime(row.hora_inicio)} ${esc(row.titulo)}</i>`).join("")}</span>${rows.length > 3 ? `<em>+${rows.length - 3}</em>` : ""}</button>`;
    }).join("")}</div></section>`;
  }

  function renderDayAgenda() {
    const rows = reservationsFor(state.selectedDate);
    return `<section class="meeting-agenda panel"><header><div><p class="eyebrow">HORÁRIOS OCUPADOS</p><h2>${esc(dayLabel(state.selectedDate))}</h2></div><span>${rows.length}</span></header><div>${rows.length ? rows.map(row => `<article><time>${normalizeTime(row.hora_inicio)}–${normalizeTime(row.hora_fim)}</time><strong>${esc(row.titulo)}</strong>${actionButtons(row)}</article>`).join("") : `<p class="meeting-empty">Sala livre durante todo o dia.</p>`}</div></section>`;
  }

  function renderForm() {
    const editing = state.reservations.find(row => row.id === state.editingId);
    const checked = new Set(editing ? participantIds(editing.id) : []);
    return `<section class="meeting-form panel"><header><p class="eyebrow">SELF-SERVICE</p><h2>${editing ? "EDITAR RESERVA" : "NOVA RESERVA"}</h2><p>Sem aprovação prévia. Confirme os horários ocupados antes de gravar.</p></header><form data-room-form>
      <label>TÍTULO / PARA QUEM<input name="titulo" required maxlength="160" value="${esc(editing?.titulo || "")}" placeholder="Ex. Reunião de produção — Eng. Henrique"></label>
      <label>DATA<input name="data" type="date" required value="${editing?.data || state.selectedDate}"></label>
      <div><label>HORA INÍCIO<input name="hora_inicio" type="time" required value="${normalizeTime(editing?.hora_inicio)}"></label><label>HORA FIM<input name="hora_fim" type="time" required value="${normalizeTime(editing?.hora_fim)}"></label></div>
      <fieldset class="meeting-participants"><legend>PARTICIPANTES</legend><p>Selecione os utilizadores que devem receber esta reunião na Visão Geral.</p><div>${state.users.map(user => `<label><input type="checkbox" name="participantes" value="${user.id}" ${checked.has(user.id) ? "checked" : ""}><span>${esc(user.nome)}</span><small>${esc(String(user.funcao || "Utilizador").replaceAll("_", " "))}</small></label>`).join("") || '<span class="meeting-empty">Não existem utilizadores disponíveis.</span>'}</div></fieldset>
      <div class="meeting-form-occupied">${reservationsFor(editing?.data || state.selectedDate).filter(row => row.id !== editing?.id).map(row => `<span>${normalizeTime(row.hora_inicio)}–${normalizeTime(row.hora_fim)}</span>`).join("") || "<span>LIVRE</span>"}</div>
      <div class="meeting-form-actions"><button class="primary-button" type="submit">${editing ? "GUARDAR ALTERAÇÕES" : "RESERVAR SALA"} <span>→</span></button>${editing ? `<button type="button" class="outline-action" data-cancel-reservation-edit>CANCELAR</button>` : ""}</div><p class="form-error"></p>
    </form></section>`;
  }

  function renderUpcoming() {
    const rows = roomReservations().filter(row => row.data >= isoToday()).slice(0,12);
    return `<section class="meeting-upcoming panel"><header><div><p class="eyebrow">AGENDA</p><h2>PRÓXIMAS RESERVAS</h2></div><span>${rows.length}</span></header><div>${rows.length ? rows.map(row => `<article><time>${esc(dayLabel(row.data))}<b>${normalizeTime(row.hora_inicio)}–${normalizeTime(row.hora_fim)}</b></time><strong>${esc(row.titulo)}</strong>${actionButtons(row)}</article>`).join("") : `<p class="meeting-empty">Ainda não existem reservas futuras.</p>`}</div></section>`;
  }

  function render() {
    if (isForeman()) { root.innerHTML = ""; return; }
    const room = state.rooms.find(item => item.id === state.selectedRoomId);
    root.innerHTML = `<div class="page-heading"><div><p class="eyebrow">ORGANIZAÇÃO INTERNA</p><h1>SALAS DE REUNIÃO</h1><p>Consulte a disponibilidade e reserve diretamente, sem aprovação prévia.</p></div><div class="heading-stat"><span>SALA</span><strong>${esc(room?.nome || "—")}</strong></div></div>${state.error ? `<div class="work-warning"><strong>DADOS INDISPONÍVEIS</strong><span>${esc(state.error)}</span></div>` : ""}${state.loading ? `<div class="fleet-loading">A CARREGAR RESERVAS…</div>` : `<div class="meeting-room-layout"><div>${renderCalendar()}${renderDayAgenda()}</div><div>${renderForm()}${renderUpcoming()}</div></div>`}`;
  }

  root.addEventListener("click", event => {
    const edit = event.target.closest("[data-edit-reservation]");
    if (edit) { const row = state.reservations.find(item => item.id === edit.dataset.editReservation); if (!canManage(row)) return toast("Não tem permissão para editar esta reserva.", "error"); state.editingId = row.id; state.selectedDate = row.data; state.month = monthKey(row.data); render(); return; }
    if (event.target.closest("[data-cancel-reservation-edit]")) { state.editingId = ""; render(); return; }
    const remove = event.target.closest("[data-delete-reservation]");
    if (remove) {
      const row = state.reservations.find(item => item.id === remove.dataset.deleteReservation);
      if (!canManage(row)) return toast("Não tem permissão para apagar esta reserva.", "error");
      if (!window.confirm(`Apagar a reserva “${row.titulo}” de ${dayLabel(row.data)}? Os participantes serão notificados.`)) return;
      remove.disabled = true;
      (async () => { if (isConfigured) await api("rpc/fn_apagar_reserva_sala", { method:"POST", body:JSON.stringify({ p_reserva_id:row.id }) }); state.reservations = state.reservations.filter(item => item.id !== row.id); state.participants = state.participants.filter(item => item.reserva_id !== row.id); if (state.editingId === row.id) state.editingId = ""; toast("Reserva apagada e participantes notificados."); render(); })().catch(error => { toast(error.message || "Não foi possível apagar a reserva.", "error"); remove.disabled = false; }); return;
    }
    const month = event.target.closest("[data-room-month]"); if (month) { state.month = changeMonth(state.month, Number(month.dataset.roomMonth)); render(); return; }
    const day = event.target.closest("[data-room-date]"); if (day) { state.selectedDate = day.dataset.roomDate; state.editingId = ""; render(); }
  });

  root.addEventListener("change", event => {
    const form = event.target.closest("[data-room-form]");
    if (form && event.target.name === "data") { const values = Object.fromEntries(new FormData(form)); const selected = new Set(new FormData(form).getAll("participantes")); state.selectedDate = form.elements.data.value || isoToday(); state.month = monthKey(state.selectedDate); render(); const next = root.querySelector("[data-room-form]"); if (next) { next.elements.titulo.value = values.titulo || ""; next.elements.hora_inicio.value = values.hora_inicio || ""; next.elements.hora_fim.value = values.hora_fim || ""; next.querySelectorAll('[name="participantes"]').forEach(input => { input.checked = selected.has(input.value); }); } }
  });

  root.addEventListener("submit", async event => {
    const form = event.target.closest("[data-room-form]"); if (!form) return; event.preventDefault();
    const button = form.querySelector('button[type="submit"]'), errorNode = form.querySelector(".form-error"), formData = new FormData(form), fields = Object.fromEntries(formData), participants = formData.getAll("participantes"); errorNode.textContent = "";
    if (fields.hora_fim <= fields.hora_inicio) return void (errorNode.textContent = "A hora de fim tem de ser posterior à hora de início.");
    if (overlaps(fields.data, fields.hora_inicio, fields.hora_fim, state.editingId)) return void (errorNode.textContent = "Este horário sobrepõe-se a uma reserva existente. Consulte os horários ocupados acima.");
    button.disabled = true;
    try {
      const payload = { sala_id:state.selectedRoomId, titulo:fields.titulo.trim(), data:fields.data, hora_inicio:fields.hora_inicio, hora_fim:fields.hora_fim, criado_por:getProfile()?.id || null };
      let saved = state.editingId ? { ...state.reservations.find(row => row.id === state.editingId), ...payload } : { id:crypto.randomUUID(), criado_em:new Date().toISOString(), ...payload };
      if (isConfigured) { const result = await api(state.editingId ? "rpc/fn_editar_reserva_sala" : "rpc/fn_criar_reserva_sala", { method:"POST", body:JSON.stringify({ ...(state.editingId ? { p_reserva_id:state.editingId } : {}), p_titulo:payload.titulo, p_data:payload.data, p_hora_inicio:payload.hora_inicio, p_hora_fim:payload.hora_fim, p_participantes:participants }) }); saved = Array.isArray(result) ? result[0] : result; }
      if (state.editingId) state.reservations = state.reservations.map(row => row.id === state.editingId ? saved : row); else state.reservations.push(saved);
      state.participants = state.participants.filter(row => row.reserva_id !== saved.id).concat(participants.map(utilizador_id => ({ reserva_id:saved.id, utilizador_id })));
      state.reservations.sort((a,b) => `${a.data}${a.hora_inicio}`.localeCompare(`${b.data}${b.hora_inicio}`)); toast(state.editingId ? "Reserva atualizada e participantes notificados." : "Sala reservada com sucesso."); state.editingId = ""; render();
    } catch (error) { const message = String(error.message || ""); errorNode.textContent = message.includes("Já existe uma reserva") ? "Já existe uma reserva para esta sala neste horário. Escolha outro período." : message || "Não foi possível guardar a reserva."; button.disabled = false; }
  });

  // Recarrega sempre os nomes reais dos utilizadores ao entrar no módulo.
  return { show: () => load(true), refresh: () => load(true) };
}
