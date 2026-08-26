const url = window.PRIMELINE_CONFIG?.supabaseUrl || "";
const anonKey = window.PRIMELINE_CONFIG?.supabaseAnonKey || "";

export const isSupabaseConfigured = Boolean(url && anonKey);
const SESSION_KEY = "primeline_supabase_session";
const sessionStore = window.sessionStorage;
let refreshPromise = null;

// As sessões são isoladas por separador/janela. O localStorage era partilhado
// pelo navegador e fazia um segundo login substituir o utilizador da primeira janela.
try {
  window.localStorage.removeItem(SESSION_KEY);
} catch {
  // A aplicação continua funcional mesmo quando o browser bloqueia localStorage.
}

export function getSession() {
  try {
    const session = JSON.parse(sessionStore.getItem(SESSION_KEY));
    if (!session?.access_token) return null;
    return session;
  } catch {
    return null;
  }
}

export function clearSession() {
  sessionStore.removeItem(SESSION_KEY);
}

export async function signIn(email, password) {
  const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const payload = await response.json();
  if (!response.ok) throw new Error(payload.error_description || payload.msg || "Não foi possível iniciar sessão.");
  sessionStore.setItem(SESSION_KEY, JSON.stringify(payload));
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

export async function refreshSession() {
  const current = getSession();
  if (!current?.refresh_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  if (refreshPromise) return refreshPromise;
  refreshPromise = (async () => {
    const response = await fetch(`${url}/auth/v1/token?grant_type=refresh_token`, {
      method: "POST",
      headers: { apikey: anonKey, "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: current.refresh_token }),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok || !payload.access_token) {
      clearSession();
      window.dispatchEvent(new CustomEvent("primeline:session-expired"));
      throw new Error("A sessão expirou. Inicie sessão novamente.");
    }
    sessionStore.setItem(SESSION_KEY, JSON.stringify(payload));
    return payload;
  })();
  try {
    return await refreshPromise;
  } finally {
    refreshPromise = null;
  }
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

function storageBucketUrl(bucket, path, mode = "object") {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/");
  return `${url}/storage/v1/${mode}/${encodeURIComponent(bucket)}/${encodedPath}`;
}

function storageObjectUrl(path, mode = "object") {
  return storageBucketUrl("faturas", path, mode);
}

export async function uploadInvoicePdf(file, obraId) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  if (file.type !== "application/pdf") throw new Error("Apenas são aceites ficheiros PDF.");
  if (file.size > 10 * 1024 * 1024) throw new Error("O PDF excede o limite de 10 MB.");

  const safeName = file.name
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(-100) || "fatura.pdf";
  const now = new Date();
  const folder = `${now.getFullYear()}/${String(now.getMonth() + 1).padStart(2, "0")}`;
  const objectPath = `${obraId}/${folder}/${crypto.randomUUID()}-${safeName}`;
  const response = await fetch(storageObjectUrl(objectPath), {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": "application/pdf",
      "x-upsert": "false",
    },
    body: file,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(payload.message || payload.error || "Não foi possível enviar o PDF.");
    error.code = payload.statusCode;
    throw error;
  }
  return objectPath;
}

export async function uploadDeliveryNote(file, obraId, invoiceId) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  const allowedTypes = ["application/pdf", "image/jpeg", "image/png", "image/webp"];
  if (!allowedTypes.includes(file.type)) throw new Error("A guia deve ser PDF, JPG, PNG ou WEBP.");
  if (file.size > 10 * 1024 * 1024) throw new Error("A guia excede o limite de 10 MB.");
  const safeName = file.name.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(-100) || "guia";
  const objectPath = `${obraId}/guias-remessa/${invoiceId}/${crypto.randomUUID()}-${safeName}`;
  const response = await fetch(storageObjectUrl(objectPath), {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": file.type,
      "x-upsert": "false",
    },
    body: file,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || payload.error || "Não foi possível enviar a guia.");
  return objectPath;
}

export async function uploadWorkflowPdf(file, obraId, entityType) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  if (file.type !== "application/pdf") throw new Error("Apenas são aceites ficheiros PDF.");
  if (file.size > 10 * 1024 * 1024) throw new Error("O PDF excede o limite de 10 MB.");
  const safeName = file.name.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(-100) || "documento.pdf";
  const objectPath = `${obraId}/${entityType}/${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}-${safeName}`;
  const response = await fetch(storageObjectUrl(objectPath), {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": "application/pdf",
      "x-upsert": "false",
    },
    body: file,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || payload.error || "Não foi possível enviar o PDF.");
  return objectPath;
}

export async function downloadInvoicePdf(objectPath) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  const response = await fetch(storageObjectUrl(objectPath, "object/authenticated"), {
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${session.access_token}`,
    },
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.message || payload.error || "Não foi possível abrir o PDF.");
  }
  return response.blob();
}

export async function uploadInvoiceAttachment(file, obraId, invoiceId) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  const allowedTypes = ["application/pdf", "image/jpeg", "image/png", "image/webp"];
  if (!allowedTypes.includes(file.type)) throw new Error("O anexo deve ser PDF, JPG, PNG ou WEBP.");
  if (file.size > 10 * 1024 * 1024) throw new Error("O anexo excede o limite de 10 MB.");
  const safeName = file.name.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(-100) || "anexo";
  const objectPath = `${obraId}/faturas-anexos/${invoiceId}/${crypto.randomUUID()}-${safeName}`;
  const response = await fetch(storageObjectUrl(objectPath), {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${session.access_token}`, "Content-Type": file.type, "x-upsert": "false" },
    body: file,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || payload.error || "Não foi possível enviar o anexo.");
  return objectPath;
}

const WORK_DOCUMENT_EXTENSIONS = new Set([
  "pdf", "jpg", "jpeg", "png", "webp", "heic",
  "xls", "xlsx", "csv", "doc", "docx", "mpp", "dwg", "dxf", "zip", "txt",
]);

export async function uploadWorkDocument(file, obraId, documentType) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  const extension = file.name.split(".").pop()?.toLowerCase() || "";
  if (!WORK_DOCUMENT_EXTENSIONS.has(extension)) {
    throw new Error("Formato não suportado. Use PDF, imagem, Excel, Word, MPP, DWG/DXF, ZIP ou TXT.");
  }
  if (file.size > 25 * 1024 * 1024) throw new Error("O documento excede o limite de 25 MB.");
  const safeName = file.name.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(-140) || `documento.${extension || "bin"}`;
  const safeType = String(documentType || "outro").replace(/[^a-z0-9_-]/gi, "-");
  const objectPath = `${obraId}/${safeType}/${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}-${safeName}`;
  const response = await fetch(storageBucketUrl("documentos", objectPath), {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": file.type || "application/octet-stream",
      "x-upsert": "false",
    },
    body: file,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || payload.error || "Não foi possível enviar o documento.");
  return objectPath;
}

export async function uploadEntityDocument(file, entityType, entityId, documentType) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  if (!['colaborador', 'viatura', 'ausencia', 'empresa'].includes(entityType)) throw new Error("Tipo de entidade inválido.");
  const extension = file.name.split(".").pop()?.toLowerCase() || "";
  if (!WORK_DOCUMENT_EXTENSIONS.has(extension)) {
    throw new Error("Formato não suportado. Use PDF, imagem, Excel/CSV, Word ou outro formato documental permitido.");
  }
  if (file.size > 25 * 1024 * 1024) throw new Error("O documento excede o limite de 25 MB.");
  const safeName = file.name.normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(-140) || `documento.${extension || "bin"}`;
  const safeType = String(documentType || "outro").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9_-]/gi, "-").replace(/^-+|-+$/g, "").slice(0, 70) || "outro";
  const rootPath = entityType === "empresa" ? `empresa/${entityId}` : `rh/${entityType}/${entityId}`;
  const objectPath = `${rootPath}/${safeType}/${new Date().toISOString().slice(0, 7)}/${crypto.randomUUID()}-${safeName}`;
  const response = await fetch(storageBucketUrl("documentos", objectPath), {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${session.access_token}`,
      "Content-Type": file.type || "application/octet-stream",
      "x-upsert": "false",
    },
    body: file,
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || payload.error || "Não foi possível enviar o documento.");
  return objectPath;
}

export async function downloadWorkDocument(objectPath) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  const response = await fetch(storageBucketUrl("documentos", objectPath, "object/authenticated"), {
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${session.access_token}`,
    },
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.message || payload.error || "Não foi possível abrir o documento.");
  }
  return response.blob();
}

export async function deleteWorkDocument(objectPath) {
  const session = getSession();
  if (!session?.access_token) throw new Error("A sessão expirou. Inicie sessão novamente.");
  const response = await fetch(storageBucketUrl("documentos", objectPath), {
    method: "DELETE",
    headers: { apikey: anonKey, Authorization: `Bearer ${session.access_token}` },
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.message || payload.error || "Não foi possível apagar o ficheiro.");
  }
}

function enforceActiveCollaborators(path) {
  const [resource, query = ""] = String(path).split("?", 2);
  if (resource !== "colaboradores") return path;
  const params = new URLSearchParams(query);
  params.set("data_saida", "is.null");
  return `${resource}?${params.toString()}`;
}

export const supabase = async (path, options = {}) => {
  const filteredPath = enforceActiveCollaborators(path);
  let tokenUsed = "";
  const request = () => {
    const session = getSession();
    tokenUsed = session?.access_token || anonKey;
    return fetch(`${url}/rest/v1/${filteredPath}`, {
      ...options,
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${tokenUsed}`,
        "Content-Type": "application/json",
        ...options.headers,
      },
    });
  };
  let response = await request();
  if (response.status === 401 && getSession()?.refresh_token) {
    const detail = await response.clone().json().catch(() => ({}));
    if (detail.code === "PGRST303" || /jwt.*expired/i.test(detail.message || "")) {
      try {
        if (getSession()?.access_token === tokenUsed) await refreshSession();
        response = await request();
      } catch {
        return response;
      }
    }
  }
  return response;
};
