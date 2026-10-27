// A new authenticated identity gets a new document/JS realm. This also disposes
// module closures, timers, detached dialogs, Maps and object URLs, not just app.js.
export function installSessionBoundary({ onReset, window: host = window }) {
  let quarantined = false;
  let navigating = false;
  onReset(reason => {
    if (!quarantined) {
      quarantined = true;
      host.document.documentElement.style.setProperty('visibility', 'hidden', 'important');
      try { host.localStorage.removeItem('primeline_planning_work_id'); } catch { /* fail closed below */ }
      const status = host.document.createElement('p');
      status.setAttribute('role', 'status');
      status.textContent = 'A atualizar sessão…';
      host.document.body.replaceChildren(status);
      // Old asynchronous renderers cannot put protected DOM back on screen.
      host.document.body.inert = true;
    }
    if (reason !== 'login-start' && !navigating) {
      navigating = true;
      // Do not carry a work/record selection, recovery fragment or prior view.
      host.location.replace(host.location.origin + host.location.pathname);
    }
  });
  host.addEventListener('unhandledrejection', event => {
    if (quarantined && event.reason?.name === 'AbortError') event.preventDefault();
  });
  // BFCache can otherwise restore an old authenticated DOM without re-running JS.
  host.addEventListener('pageshow', event => {
    if (event.persisted) {
      host.document.body.replaceChildren();
      host.location.reload();
    }
  });
  host.addEventListener('pagehide', () => {
    host.document.body.replaceChildren();
  });
}
