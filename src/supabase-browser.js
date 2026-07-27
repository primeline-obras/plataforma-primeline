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
