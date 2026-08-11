const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" })[character]);
const CATEGORY_LABELS = { materiais: "Materiais", estaleiro: "Despesas de Estaleiro", mao_obra: "Pessoal em Obra / Mão de Obra", subempreitadas: "Subempreitadas" };

export function createManagementMapModule({ root, supabase, isConfigured, getWorks, euro, toast }) {
  const state = { loaded: false, loading: false, error: "", rows: [] };

  async function load(force = false) {
    if (state.loading || (state.loaded && !force)) return render();
    state.loading = true; state.error = ""; render();
    try {
      if (!isConfigured) state.rows = [];
      else {
        const response = await supabase("rpc/fn_mapa_gestao_obras", { method: "POST", body: "{}" });
        if (!response.ok) {
          const payload = await response.json().catch(() => ({}));
          throw new Error(payload.message || payload.details || "Não foi possível consultar os lançamentos pagos.");
        }
        state.rows = await response.json();
      }
      state.loaded = true;
    } catch (error) { state.error = error.message; }
    finally { state.loading = false; render(); }
  }

  function filteredRows() {
    const form = root.querySelector("[data-management-map-filters]");
    if (!form) return state.rows;
    const filters = Object.fromEntries(new FormData(form));
    const needle = String(filters.entidade || "").trim().toLocaleLowerCase("pt-PT");
    return state.rows.filter(row =>
      (!filters.obra_id || row.obra_id === filters.obra_id)
      && (!filters.categoria || row.categoria === filters.categoria)
      && (!filters.data_inicio || row.data_lancamento >= filters.data_inicio)
      && (!filters.data_fim || row.data_lancamento <= filters.data_fim)
      && (!needle || `${row.entidade_nome || ""} ${row.descricao || ""} ${row.documento || ""}`.toLocaleLowerCase("pt-PT").includes(needle))
    );
  }

  function renderTable() {
    const rows = filteredRows();
    const total = rows.reduce((sum, row) => sum + Number(row.valor || 0), 0);
    return `<div class="management-map-result"><div class="management-map-summary"><span><small>LANÇAMENTOS VISÍVEIS</small><strong>${rows.length}</strong></span><span><small>TOTAL PAGO</small><strong>${euro.format(total)}</strong></span></div>
      <div class="management-map-scroll"><table><thead><tr><th>DATA</th><th>OBRA</th><th>CATEGORIA</th><th>FORNECEDOR / COLABORADOR</th><th>DESCRIÇÃO</th><th>DOCUMENTO</th><th>VALOR PAGO</th></tr></thead><tbody>
        ${rows.length ? rows.map(row => `<tr><td>${esc(row.data_lancamento || "—")}</td><td><strong>${esc(row.obra_numero || "—")}</strong><small>${esc(row.obra_nome || "")}</small></td><td><span class="management-category ${esc(row.categoria)}">${esc(CATEGORY_LABELS[row.categoria] || row.categoria)}</span></td><td>${esc(row.entidade_nome || "—")}</td><td>${esc(row.descricao || "—")}</td><td>${esc(row.documento || "—")}</td><td class="management-value">${euro.format(Number(row.valor || 0))}</td></tr>`).join("") : `<tr><td colspan="7" class="management-map-empty">SEM LANÇAMENTOS PAGOS NESTE FILTRO</td></tr>`}
      </tbody></table></div></div>`;
  }

  function render() {
    const works = [...getWorks()].sort((a, b) => String(a.numero || "").localeCompare(String(b.numero || ""), "pt-PT", { numeric: true }));
    root.innerHTML = `<section class="panel management-map"><header><div><p class="eyebrow">CONSOLIDADO DA EMPRESA</p><h2>MAPA DE GESTÃO DE OBRAS</h2><p>Todos os lançamentos pagos, apresentados individualmente por obra e categoria.</p></div><button type="button" class="outline-action" data-refresh-management-map>ATUALIZAR</button></header>
      ${state.error ? `<div class="work-warning"><strong>DADOS INDISPONÍVEIS</strong><span>${esc(state.error)} Confirme se executou o SQL deste módulo.</span></div>` : ""}
      <form class="management-map-filters" data-management-map-filters>
        <label>OBRA<select name="obra_id"><option value="">Todas as obras</option>${works.map(work => `<option value="${work.id}">Obra ${esc(work.numero)} — ${esc(work.nome)}</option>`).join("")}</select></label>
        <label>CATEGORIA<select name="categoria"><option value="">Todas as categorias</option>${Object.entries(CATEGORY_LABELS).map(([value, label]) => `<option value="${value}">${label}</option>`).join("")}</select></label>
        <label>DE<input type="date" name="data_inicio"></label><label>ATÉ<input type="date" name="data_fim"></label>
        <label class="management-map-search">FORNECEDOR / COLABORADOR<input name="entidade" placeholder="Pesquisar nome, descrição ou documento"></label>
        <button type="reset" class="outline-action">LIMPAR FILTROS</button>
      </form>
      ${state.loading ? `<div class="fleet-loading">A CARREGAR LANÇAMENTOS…</div>` : renderTable()}
    </section>`;
  }

  root.addEventListener("input", event => { if (event.target.closest("[data-management-map-filters]")) root.querySelector(".management-map-result")?.replaceWith(fragment(renderTable())); });
  root.addEventListener("change", event => { if (event.target.closest("[data-management-map-filters]")) root.querySelector(".management-map-result")?.replaceWith(fragment(renderTable())); });
  root.addEventListener("reset", () => setTimeout(() => root.querySelector(".management-map-result")?.replaceWith(fragment(renderTable())), 0));
  root.addEventListener("click", event => { if (event.target.closest("[data-refresh-management-map]")) load(true).catch(error => toast(error.message, "error")); });

  function fragment(html) { const template = document.createElement("template"); template.innerHTML = html.trim(); return template.content.firstElementChild; }
  return { show: () => load(), refresh: () => load(true) };
}
