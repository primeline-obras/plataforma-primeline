import { isSupabaseConfigured, readRecoverySession, updateRecoveryPassword } from "./supabase-browser.js";

const root = document.querySelector("#reset-root");

function brand() {
  return `<div class="brand" aria-label="PRIMELINE GO">
    <span class="brand-logo-wrap" aria-hidden="true">
      <img class="brand-logo brand-logo-dark" src="/assets/brand/logo.png" alt="">
      <img class="brand-logo brand-logo-light" src="/assets/brand/logo_branco.png" alt="">
    </span>
    <span class="brand-separator" aria-hidden="true"></span>
    <strong class="brand-go" aria-hidden="true">GO</strong>
  </div>`;
}

function friendlyRecoveryError(error) {
  const code = error?.code || "";
  if (code === "otp_expired" || code === "access_denied" || /expired/i.test(error?.message || "")) {
    return "Esta ligação expirou ou já foi utilizada. Volte ao login e peça um novo email.";
  }
  if (/weak|password/i.test(error?.message || "")) {
    return "A palavra-passe não cumpre os requisitos de segurança. Use pelo menos 8 caracteres, incluindo letras, números e símbolos.";
  }
  return error?.message || "A ligação é inválida. Peça um novo email de recuperação.";
}

root.innerHTML = `
  <main class="reset-screen">
    <aside class="reset-brand">${brand()}</aside>
    <section class="reset-content">
      <div class="reset-card">
        <p class="eyebrow">ACESSO RESERVADO</p>
        <h1>NOVA PALAVRA-PASSE</h1>
        <p class="reset-intro">Escolha uma palavra-passe segura para a sua conta PRIMELINE.</p>
        <div id="invalid-link" class="reset-message error" hidden>
          <strong>LIGAÇÃO INVÁLIDA</strong>
          <span id="invalid-message"></span>
          <a href="/">VOLTAR AO LOGIN</a>
        </div>
        <form id="reset-form" hidden>
          <label>NOVA PALAVRA-PASSE
            <input name="password" type="password" autocomplete="new-password" minlength="8" placeholder="Mínimo de 8 caracteres" required>
          </label>
          <label>CONFIRMAR PALAVRA-PASSE
            <input name="confirmation" type="password" autocomplete="new-password" minlength="8" placeholder="Repita a palavra-passe" required>
          </label>
          <p class="password-hint">Utilize pelo menos 8 caracteres. Recomendamos letras maiúsculas e minúsculas, números e símbolos.</p>
          <p class="auth-error" id="reset-error"></p>
          <button class="primary-button login-button" type="submit">GUARDAR PALAVRA-PASSE <span>→</span></button>
        </form>
        <div id="reset-success" class="reset-message success" hidden>
          <strong>PALAVRA-PASSE ALTERADA</strong>
          <span>Já pode iniciar sessão com a nova palavra-passe.</span>
          <a href="/">IR PARA O LOGIN</a>
        </div>
      </div>
    </section>
  </main>`;

let recoverySession = null;
try {
  if (!isSupabaseConfigured) throw new Error("A ligação ao serviço de autenticação não está configurada.");
  recoverySession = readRecoverySession();
  if (!recoverySession) throw new Error("Esta página deve ser aberta através da ligação recebida por email.");
  document.querySelector("#reset-form").hidden = false;
  history.replaceState(null, "", `${location.pathname}${location.search}`);
} catch (error) {
  document.querySelector("#invalid-link").hidden = false;
  document.querySelector("#invalid-message").textContent = friendlyRecoveryError(error);
}

document.querySelector("#reset-form").addEventListener("submit", async event => {
  event.preventDefault();
  const form = event.currentTarget;
  const button = form.querySelector("button");
  const password = form.password.value;
  const confirmation = form.confirmation.value;
  const errorBox = document.querySelector("#reset-error");
  errorBox.textContent = "";

  if (password !== confirmation) {
    errorBox.textContent = "As palavras-passe não coincidem.";
    return;
  }
  if (password.length < 8) {
    errorBox.textContent = "A palavra-passe deve ter pelo menos 8 caracteres.";
    return;
  }

  button.disabled = true;
  button.firstChild.textContent = "A GUARDAR… ";
  try {
    await updateRecoveryPassword(recoverySession.access_token, password);
    form.hidden = true;
    document.querySelector("#reset-success").hidden = false;
  } catch (error) {
    errorBox.textContent = friendlyRecoveryError(error);
  } finally {
    button.disabled = false;
    button.firstChild.textContent = "GUARDAR PALAVRA-PASSE ";
  }
});
