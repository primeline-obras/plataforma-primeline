const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

const timeValue = value => value ? String(value).slice(0, 5) : "";
const today = () => new Date().toISOString().slice(0, 10);

export function createAttendanceModule({ root, supabase, isConfigured, toast }) {
  const state = { date: today(), workId: "", works: [], rows: [], canValidate: false, loading: false, error: "", loaded: false };

  async function rpc(name, body) {
    const response = await supabase(`rpc/${name}`, { method: "POST", body: JSON.stringify(body) });
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}));
      throw new Error(payload.message || payload.details || "Não foi possível concluir a operação.");
    }
    return response.json();
  }

  function defaultTimes(periods) {
    return {
      entrada_manha: periods.includes("manha") ? "08:00" : "",
      saida_manha: periods.includes("manha") ? "12:00" : "",
      entrada_tarde: periods.includes("tarde") ? "13:00" : "",
      saida_tarde: periods.includes("tarde") ? "17:00" : "",
    };
  }

  function rowForm(row) {
    const point = row.ponto || {};
    const periods = row.periodos || [];
    const officialAbsence = row.ausencia;
    if (officialAbsence && (officialAbsence.tipo === "ferias" || ["confirmada", "justificada"].includes(officialAbsence.estado))) {
      const label = officialAbsence.tipo === "ferias" ? "FÉRIAS CONFIRMADAS" : String(officialAbsence.tipo || "AUSÊNCIA CONFIRMADA").replaceAll("_", " ").toUpperCase();
      return `<article class="attendance-row attendance-locked"><div class="attendance-person"><strong>${esc(row.nome)}</strong><span>${esc(row.funcao || "Função não indicada")}</span><em>${periods.map(period => period === "manha" ? "MANHÃ" : "TARDE").join(" + ")}</em></div><div class="attendance-official-absence"><strong>${esc(label)}</strong><span>${esc(officialAbsence.comentario || "Registo oficial de ausência; o ponto não pode substituí-lo.")}</span></div></article>`;
    }
    const defaults = defaultTimes(periods);
    const status = point.estado || "presente";
    const absent = status !== "presente";
    const hours = Number(point.horas ?? (periods.length * 4));
    return `<form class="attendance-row ${absent ? "absent" : "present"}" data-attendance-row data-person-id="${row.colaborador_id}">
      <div class="attendance-person"><strong>${esc(row.nome)}</strong><span>${esc(row.funcao || "Função não indicada")}</span><em>${periods.map(period => period === "manha" ? "MANHÃ" : "TARDE").join(" + ")}</em></div>
      <label><span>ESTADO</span><select name="estado">
        <option value="presente" ${status === "presente" ? "selected" : ""}>Presente</option>
        <option value="falta_com_justificacao" ${status === "falta_com_justificacao" ? "selected" : ""}>Falta · justificação apresentada</option>
        <option value="falta_sem_justificacao" ${status === "falta_sem_justificacao" ? "selected" : ""}>Falta · sem justificação</option>
      </select></label>
      <fieldset data-attendance-times ${absent ? "disabled" : ""}>
        <label><span>ENTRADA MANHÃ</span><input name="entrada_manha" type="time" value="${timeValue(point.entrada_manha) || defaults.entrada_manha}" ${!periods.includes("manha") ? "disabled" : ""}></label>
        <label><span>SAÍDA MANHÃ</span><input name="saida_manha" type="time" value="${timeValue(point.saida_manha) || defaults.saida_manha}" ${!periods.includes("manha") ? "disabled" : ""}></label>
        <label><span>ENTRADA TARDE</span><input name="entrada_tarde" type="time" value="${timeValue(point.entrada_tarde) || defaults.entrada_tarde}" ${!periods.includes("tarde") ? "disabled" : ""}></label>
        <label><span>SAÍDA TARDE</span><input name="saida_tarde" type="time" value="${timeValue(point.saida_tarde) || defaults.saida_tarde}" ${!periods.includes("tarde") ? "disabled" : ""}></label>
      </fieldset>
      <label class="attendance-note"><span>OBSERVAÇÃO</span><input name="observacao" maxlength="1000" value="${esc(point.observacao || "")}" placeholder="Obrigatória quando existe justificação" ${status === "falta_com_justificacao" ? "required" : ""}></label>
      <div class="attendance-result"><span>TOTAL</span><strong data-attendance-total>${absent ? "0" : hours.toLocaleString("pt-PT")} h</strong>
        ${point.justificacao_estado === "pendente" ? `<em>PENDENTE DE VALIDAÇÃO</em>` : point.justificacao_estado === "validada" ? `<em class="validated">JUSTIFICAÇÃO VALIDADA</em>` : point.justificacao_estado === "rejeitada" ? `<em class="rejected">JUSTIFICAÇÃO REJEITADA</em>` : ""}
      </div>
      <div class="attendance-actions"><button type="submit">${point.id ? "ATUALIZAR" : "GUARDAR PONTO"}</button>
        ${state.canValidate && point.id && point.justificacao_estado === "pendente" ? `<button type="button" data-attendance-decision="validada" data-point-id="${point.id}">VALIDAR</button><button type="button" class="danger" data-attendance-decision="rejeitada" data-point-id="${point.id}">REJEITAR</button>` : ""}
      </div><p class="form-error"></p>
    </form>`;
  }

  function render() {
    if (!root) return;
    root.innerHTML = `<section class="attendance-toolbar">
      <label><span>DATA</span><input type="date" data-attendance-date value="${state.date}"></label>
      <label><span>OBRA</span><select data-attendance-work><option value="">Selecionar obra</option>${state.works.map(work => `<option value="${work.id}" ${state.workId === work.id ? "selected" : ""}>Obra ${esc(work.numero || "—")} · ${esc(work.nome)}</option>`).join("")}</select></label>
      <button type="button" data-attendance-refresh>ATUALIZAR</button>
    </section>
    <div class="attendance-guidance"><strong>PONTO DIÁRIO</strong><span>Os horários padrão são 08:00–12:00 e 13:00–17:00. Ajuste apenas quando o horário real for diferente. As justificações apresentadas ficam pendentes de validação administrativa.</span></div>
    ${state.loading ? `<div class="empty-state"><strong>A CARREGAR PONTO…</strong></div>` : state.error ? `<div class="work-warning"><strong>NÃO FOI POSSÍVEL CARREGAR</strong><span>${esc(state.error)}</span></div>` : !state.workId ? `<div class="empty-state"><strong>SELECIONE UMA OBRA</strong><span>Serão apresentados apenas os colaboradores alocados nessa data.</span></div>` : state.rows.length ? `<div class="attendance-list">${state.rows.map(rowForm).join("")}</div>` : `<div class="empty-state"><strong>SEM PESSOAL ALOCADO</strong><span>O Administrativo deve primeiro colocar a equipa nesta obra no Quadro de Pessoal.</span></div>`}`;
  }

  async function load() {
    if (!isConfigured) { state.error = "O ponto necessita de ligação à base de dados."; render(); return; }
    state.loading = true; state.error = ""; render();
    try {
      const payload = await rpc("fn_listar_ponto_obra", { p_data: state.date, p_obra_id: state.workId || null });
      state.works = payload.obras || [];
      if (!state.workId && state.works.length === 1) {
        state.workId = state.works[0].id;
        const selected = await rpc("fn_listar_ponto_obra", { p_data: state.date, p_obra_id: state.workId });
        state.rows = selected.linhas || [];
        state.canValidate = Boolean(selected.pode_validar);
      } else {
        if (state.workId && !state.works.some(work => work.id === state.workId)) state.workId = "";
        state.rows = payload.linhas || [];
        state.canValidate = Boolean(payload.pode_validar);
      }
      state.loaded = true;
    } catch (error) { state.error = error.message; state.rows = []; }
    finally { state.loading = false; render(); }
  }

  function calculate(form) {
    if (form.elements.estado.value !== "presente") return 0;
    const minutes = value => { if (!value) return null; const [hour, minute] = value.split(":").map(Number); return hour * 60 + minute; };
    const duration = (start, end) => start == null || end == null ? 0 : Math.max(0, end - start);
    return (duration(minutes(form.elements.entrada_manha.value), minutes(form.elements.saida_manha.value))
      + duration(minutes(form.elements.entrada_tarde.value), minutes(form.elements.saida_tarde.value))) / 60;
  }

  root?.addEventListener("change", async event => {
    if (event.target.matches("[data-attendance-date]")) { state.date = event.target.value; await load(); return; }
    if (event.target.matches("[data-attendance-work]")) { state.workId = event.target.value; await load(); return; }
    const form = event.target.closest("[data-attendance-row]");
    if (!form) return;
    if (event.target.name === "estado") {
      const absent = event.target.value !== "presente";
      form.classList.toggle("absent", absent); form.classList.toggle("present", !absent);
      form.querySelector("[data-attendance-times]").disabled = absent;
      if (event.target.value === "falta_com_justificacao") form.elements.observacao.required = true;
      else form.elements.observacao.required = false;
    }
    form.querySelector("[data-attendance-total]").textContent = `${calculate(form).toLocaleString("pt-PT")} h`;
  });

  root?.addEventListener("input", event => {
    const form = event.target.closest("[data-attendance-row]");
    if (form) form.querySelector("[data-attendance-total]").textContent = `${calculate(form).toLocaleString("pt-PT")} h`;
  });

  root?.addEventListener("click", async event => {
    if (event.target.closest("[data-attendance-refresh]")) { await load(); return; }
    const decision = event.target.closest("[data-attendance-decision]");
    if (!decision) return;
    decision.disabled = true;
    try {
      await rpc("fn_validar_justificacao_ponto", { p_ponto_id: decision.dataset.pointId, p_decisao: decision.dataset.attendanceDecision });
      toast(decision.dataset.attendanceDecision === "validada" ? "Justificação validada." : "Justificação rejeitada.");
      await load();
    } catch (error) { toast(error.message, "error"); decision.disabled = false; }
  });

  root?.addEventListener("submit", async event => {
    const form = event.target.closest("[data-attendance-row]");
    if (!form) return;
    event.preventDefault();
    const button = form.querySelector('button[type="submit"]');
    const error = form.querySelector(".form-error");
    button.disabled = true; error.textContent = "";
    try {
      await rpc("fn_guardar_ponto_obra", {
        p_obra_id: state.workId,
        p_colaborador_id: form.dataset.personId,
        p_data: state.date,
        p_estado: form.elements.estado.value,
        p_entrada_manha: form.elements.entrada_manha.value || null,
        p_saida_manha: form.elements.saida_manha.value || null,
        p_entrada_tarde: form.elements.entrada_tarde.value || null,
        p_saida_tarde: form.elements.saida_tarde.value || null,
        p_observacao: form.elements.observacao.value.trim() || null,
      });
      toast("Ponto guardado.");
      await load();
    } catch (failure) { error.textContent = failure.message; button.disabled = false; }
  });

  return { show: load, refresh: load };
}
