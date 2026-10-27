const esc = value => String(value ?? "").replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;",
})[character]);

function openPlatformDialog({ title, message, confirmLabel = "CONFIRMAR", cancelLabel = "CANCELAR", danger = false, input = null }) {
  return new Promise(resolve => {
    const dialog = document.createElement("dialog");
    dialog.className = "platform-decision-dialog";
    dialog.innerHTML = `<form method="dialog"><header><p class="eyebrow">CONFIRMAÇÃO</p><h2>${esc(title)}</h2></header><p>${esc(message).replace(/\n/g, "<br>")}</p>${input ? `<label>${esc(input.label || "INFORMAÇÃO")}<textarea name="value" rows="4" ${input.required ? "required" : ""} placeholder="${esc(input.placeholder || "")}">${esc(input.value || "")}</textarea></label><p class="form-error"></p>` : ""}<footer><button type="button" class="outline-action" data-dialog-cancel>${esc(cancelLabel)}</button><button type="submit" class="${danger ? "danger-action" : "primary-button"}">${esc(confirmLabel)}</button></footer></form>`;
    document.body.append(dialog);
    const finish = value => { dialog.close(); dialog.remove(); resolve(value); };
    dialog.querySelector("[data-dialog-cancel]").addEventListener("click", () => finish(input ? null : false));
    dialog.addEventListener("cancel", event => { event.preventDefault(); finish(input ? null : false); });
    dialog.querySelector("form").addEventListener("submit", event => {
      event.preventDefault();
      if (!input) return finish(true);
      const value = dialog.querySelector('[name="value"]').value.trim();
      if (input.required && !value) { dialog.querySelector(".form-error").textContent = "Este campo é obrigatório."; return; }
      finish(value);
    });
    dialog.showModal();
    dialog.querySelector(input ? '[name="value"]' : 'button[type="submit"]')?.focus();
  });
}

export const platformConfirm = (message, options = {}) => openPlatformDialog({
  title: options.title || "Confirmar ação", message,
  confirmLabel: options.confirmLabel || "CONFIRMAR", cancelLabel: options.cancelLabel || "CANCELAR",
  danger: Boolean(options.danger),
});

export const platformPrompt = (message, value = "", options = {}) => openPlatformDialog({
  title: options.title || "Informação necessária", message,
  confirmLabel: options.confirmLabel || "CONTINUAR", cancelLabel: options.cancelLabel || "CANCELAR",
  input: { label: options.label || "MOTIVO / VALOR", placeholder: options.placeholder || "", required: options.required !== false, value },
});
