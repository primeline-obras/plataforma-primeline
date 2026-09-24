// Apenas apresentação: não copia nem guarda credenciais.
export function setupLoginPassword(form) {
  const input = form.querySelector('input[name="password"]');
  const wrapper = document.createElement('span');
  wrapper.className = 'login-password-field';
  input.id = 'login-password';
  input.before(wrapper);
  wrapper.append(input);
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'login-password-toggle';
  button.setAttribute('aria-controls', input.id);
  wrapper.append(button);
  function hide() { setVisible(false); }
  function setVisible(visible) {
    input.type = visible ? 'text' : 'password';
    button.setAttribute('aria-label', visible ? 'Ocultar palavra-passe' : 'Mostrar palavra-passe');
    button.title = button.getAttribute('aria-label');
    button.setAttribute('aria-pressed', String(visible));
    button.innerHTML = '<svg aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>' + (visible ? '<path d="m3 3 18 18"/>' : '') + '</svg>';
  }
  button.addEventListener('click', () => setVisible(input.type === 'password'));
  form.addEventListener('submit', hide);
  form.addEventListener('reset', hide);
  hide();
  return hide;
}
