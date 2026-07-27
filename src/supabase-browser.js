const url = window.PRIMELINE_CONFIG?.supabaseUrl || "";
const anonKey = window.PRIMELINE_CONFIG?.supabaseAnonKey || "";

export const isSupabaseConfigured = Boolean(url && anonKey);
const SESSION_KEY = "primeline_supabase_session";

export function getSession() {
  try {
    const session = JSON.parse(localStorage.getItem(SESSION_KEY));
    if (!session?.access_token) return null;
    return session;
  } catch {
    return null;
  }
}

export function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}

export async function signIn(email, password) {
  const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error_description || payload.msg || "Não foi possível iniciar sessão.");
  localStorage.setItem(SESSION_KEY, JSON.stringify(payload));
  return payload;
}

export async function signOut() {
  const session = getSession();
  if (session?.access_token) {
    await fetch(`${url}/auth/v1/logout`, {
      method: "POST",
      headers: { apikey: anonKey, Authorization: `Bearer ${session.access_token}` },
    }).catch(() => {});
  }
  clearSession();
}

export async function requestPasswordReset(email) {
  const redirectTo = "https://plataforma-primeline.pages.dev/reset-password";
  const response = await fetch(`${url}/auth/v1/recover?redirect_to=${encodeURIComponent(redirectTo)}`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error_description || payload.msg || payload.message || "Não foi possível enviar o email.");
    error.code = payload.code || payload.error_code;
    throw error;
  }
  return payload;
}

export function readRecoverySession() {
  const params = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const errorDescription = params.get("error_description");
  if (errorDescription) {
    const error = new Error(errorDescription);
    error.code = params.get("error_code") || params.get("error");
    throw error;
  }
  if (params.get("type") !== "recovery" || !params.get("access_token")) return null;
  return {
    access_token: params.get("access_token"),
    refresh_token: params.get("refresh_token"),
    expires_in: Number(params.get("expires_in") || 0),
    token_type: params.get("token_type") || "bearer",
    type: "recovery",
  };
}

export async function updateRecoveryPassword(accessToken, password) {
  const response = await fetch(`${url}/auth/v1/user`, {
    method: "PUT",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ password }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.error_description || payload.msg || payload.message || "Não foi possível alterar a palavra-passe.");
    error.code = payload.code || payload.error_code;
    throw error;
  }
  return payload;
}

export const supabase = (path, options = {}) => {
  const session = getSession();
  return fetch(`${url}/rest/v1/${path}`, {
  ...options,
  headers: {
    apikey: anonKey,
    Authorization: `Bearer ${session?.access_token || anonKey}`,
    "Content-Type": "application/json",
    ...options.headers,
  },
});
};
