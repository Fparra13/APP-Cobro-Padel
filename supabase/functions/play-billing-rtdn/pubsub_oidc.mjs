/**
 * Autenticación OIDC para Google Cloud Pub/Sub Push.
 * Verifica firma RS256 con JWKS (Google o inyectado en tests).
 * No loguear tokens ni secretos.
 */

export const GOOGLE_OIDC_ISSUERS = Object.freeze([
  "https://accounts.google.com",
  "accounts.google.com",
]);

export const GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs";

function base64UrlToBytes(s) {
  const pad = "=".repeat((4 - (s.length % 4)) % 4);
  const b64 = (s + pad).replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function bytesToBase64Url(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function decodeJwtJson(part) {
  const text = new TextDecoder().decode(base64UrlToBytes(part));
  return JSON.parse(text);
}

export function extractBearerToken(authorizationHeader) {
  if (typeof authorizationHeader !== "string") return null;
  if (!authorizationHeader.startsWith("Bearer ")) return null;
  const token = authorizationHeader.slice("Bearer ".length).trim();
  return token.length > 0 ? token : null;
}

export function readOidcConfig(env = {}) {
  const email = typeof env.PLAY_BILLING_RTDN_OIDC_EMAIL === "string"
    ? env.PLAY_BILLING_RTDN_OIDC_EMAIL.trim()
    : "";
  const audience = typeof env.PLAY_BILLING_RTDN_OIDC_AUDIENCE === "string"
    ? env.PLAY_BILLING_RTDN_OIDC_AUDIENCE.trim()
    : "";
  const allowStatic = env.PLAY_BILLING_RTDN_ALLOW_STATIC_BEARER === "true";
  const staticSecret = typeof env.PLAY_BILLING_RTDN_SECRET === "string"
    ? env.PLAY_BILLING_RTDN_SECRET.trim()
    : "";
  return {
    email,
    audience,
    allowStaticBearer: allowStatic,
    staticSecret,
    oidcConfigured: email.length > 0 && audience.length > 0,
    staticConfigured: allowStatic && staticSecret.length >= 16,
  };
}

export function audienceMatches(claimAud, expected) {
  if (typeof expected !== "string" || expected.length === 0) return false;
  if (typeof claimAud === "string") return claimAud === expected;
  if (Array.isArray(claimAud)) return claimAud.includes(expected);
  return false;
}

/**
 * Valida claims tras verificar firma.
 * @returns {{ ok: true } | { ok: false, reason: string }}
 */
export function validateOidcClaims(payload, config) {
  if (!payload || typeof payload !== "object") {
    return { ok: false, reason: "payload_missing" };
  }
  if (!GOOGLE_OIDC_ISSUERS.includes(payload.iss)) {
    return { ok: false, reason: "iss_mismatch" };
  }
  if (!audienceMatches(payload.aud, config.audience)) {
    return { ok: false, reason: "aud_mismatch" };
  }
  const nowSec = typeof config.nowSec === "number"
    ? config.nowSec
    : Math.floor(Date.now() / 1000);
  const skew = typeof config.clockSkewSec === "number" ? config.clockSkewSec : 60;
  if (typeof payload.exp !== "number" || payload.exp + skew < nowSec) {
    return { ok: false, reason: "exp_invalid" };
  }
  if (typeof payload.email !== "string" || payload.email !== config.email) {
    return { ok: false, reason: "email_mismatch" };
  }
  if (payload.email_verified !== true && payload.email_verified !== "true") {
    return { ok: false, reason: "email_not_verified" };
  }
  return { ok: true };
}

async function importRsaVerifyKey(jwk) {
  return crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

/**
 * Verifica firma RS256 del JWT con una clave JWK o CryptoKey.
 */
export async function verifyJwtRs256Signature(token, key) {
  if (typeof token !== "string" || token.split(".").length !== 3) {
    return { ok: false, reason: "malformed_jwt" };
  }
  const [headerB64, payloadB64, sigB64] = token.split(".");
  let header;
  try {
    header = decodeJwtJson(headerB64);
  } catch {
    return { ok: false, reason: "malformed_jwt" };
  }
  if (header.alg !== "RS256") {
    return { ok: false, reason: "alg_unsupported" };
  }

  let cryptoKey;
  try {
    cryptoKey = key instanceof CryptoKey ? key : await importRsaVerifyKey(key);
  } catch {
    return { ok: false, reason: "key_import_failed" };
  }

  const data = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  let signature;
  try {
    signature = base64UrlToBytes(sigB64);
  } catch {
    return { ok: false, reason: "malformed_jwt" };
  }

  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    signature,
    data,
  );
  if (!valid) return { ok: false, reason: "invalid_signature" };

  let payload;
  try {
    payload = decodeJwtJson(payloadB64);
  } catch {
    return { ok: false, reason: "malformed_jwt" };
  }
  return { ok: true, header, payload };
}

const JWKS_CACHE_TTL_MS = 60 * 60 * 1000;

let cachedGoogleJwks = null;
let cachedGoogleJwksAt = 0;

/** Solo tests: limpia la caché JWKS del módulo. */
export function resetGoogleJwksCacheForTests() {
  cachedGoogleJwks = null;
  cachedGoogleJwksAt = 0;
}

function findRsaJwkByKid(bundle, kid) {
  const keys = Array.isArray(bundle?.keys) ? bundle.keys : [];
  return keys.find((k) => k && k.kid === kid && k.kty === "RSA") ?? null;
}

async function downloadGoogleJwks(fetchImpl) {
  const res = await fetchImpl(GOOGLE_JWKS_URL);
  if (!res.ok) throw new Error("jwks_fetch_failed");
  const json = await res.json();
  cachedGoogleJwks = json;
  cachedGoogleJwksAt = Date.now();
  return json;
}

async function loadGoogleJwks(fetchImpl, { force = false } = {}) {
  const now = Date.now();
  const cacheFresh = cachedGoogleJwks &&
    now - cachedGoogleJwksAt <= JWKS_CACHE_TTL_MS;
  if (!force && cacheFresh) {
    return cachedGoogleJwks;
  }
  return downloadGoogleJwks(fetchImpl);
}

/**
 * Obtiene la JWK RSA para header.kid.
 * Usa caché TTL; si el kid no está, invalida y re-descarga una sola vez.
 */
export async function defaultFetchGoogleJwk(header, fetchImpl = fetch) {
  const kid = header?.kid;
  let bundle = await loadGoogleJwks(fetchImpl, { force: false });
  let jwk = findRsaJwkByKid(bundle, kid);
  if (jwk) return jwk;

  // Rotación: kid ausente en caché vigente → un único refresh, sin bucles.
  bundle = await loadGoogleJwks(fetchImpl, { force: true });
  jwk = findRsaJwkByKid(bundle, kid);
  if (!jwk) throw new Error("jwk_not_found");
  return jwk;
}

/**
 * Verifica JWT OIDC de Pub/Sub (firma + claims).
 * @param {string} token
 * @param {{ email: string, audience: string, nowSec?: number, getJwk?: Function }} config
 */
export async function verifyPubSubOidcToken(token, config) {
  if (typeof token !== "string" || token.trim().length === 0) {
    return { ok: false, reason: "token_missing" };
  }
  if (!config?.email || !config?.audience) {
    return { ok: false, reason: "oidc_config_missing" };
  }

  let header;
  try {
    header = decodeJwtJson(token.split(".")[0]);
  } catch {
    return { ok: false, reason: "malformed_jwt" };
  }

  const getJwk = typeof config.getJwk === "function"
    ? config.getJwk
    : (h) => defaultFetchGoogleJwk(h, config.fetchImpl);

  let jwk;
  try {
    jwk = await getJwk(header);
  } catch {
    return { ok: false, reason: "jwks_unavailable" };
  }

  const sig = await verifyJwtRs256Signature(token, jwk);
  if (!sig.ok) return sig;

  const claims = validateOidcClaims(sig.payload, {
    email: config.email,
    audience: config.audience,
    nowSec: config.nowSec,
  });
  if (!claims.ok) return claims;
  return { ok: true, payload: sig.payload };
}

/**
 * Autoriza la request RTDN: OIDC Pub/Sub (requerido) o Bearer estático opcional.
 * El estático solo si PLAY_BILLING_RTDN_ALLOW_STATIC_BEARER=true (opt-in).
 */
export async function authorizeRtdnRequest(req, env, options = {}) {
  const config = readOidcConfig(env ?? {});
  const authHeader = req.headers?.get?.("Authorization") ??
    req.headers?.authorization ??
    null;
  const bearer = extractBearerToken(authHeader);

  if (!bearer) {
    return { ok: false, status: 401, reason: "token_missing" };
  }

  // Vía opt-in solo para pruebas manuales (no es el camino Pub/Sub).
  if (config.staticConfigured && bearer === config.staticSecret) {
    return { ok: true, method: "static_bearer" };
  }

  if (!config.oidcConfigured) {
    console.error("rtdn_oidc_config_missing");
    return { ok: false, status: 401, reason: "oidc_config_missing" };
  }

  const verified = await verifyPubSubOidcToken(bearer, {
    email: config.email,
    audience: config.audience,
    getJwk: options.getJwk,
    fetchImpl: options.fetchImpl,
    nowSec: options.nowSec,
  });

  if (!verified.ok) {
    console.error("rtdn_oidc_rejected", { reason: verified.reason });
    return { ok: false, status: 401, reason: verified.reason };
  }
  return { ok: true, method: "pubsub_oidc" };
}

/** Utilidad de test: firma RS256 con CryptoKey privada. */
export async function signJwtRs256ForTests(payload, privateKey, header = {}) {
  const hdr = { alg: "RS256", typ: "JWT", ...header };
  const enc = new TextEncoder();
  const h = bytesToBase64Url(enc.encode(JSON.stringify(hdr)));
  const p = bytesToBase64Url(enc.encode(JSON.stringify(payload)));
  const data = enc.encode(`${h}.${p}`);
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", privateKey, data),
  );
  return `${h}.${p}.${bytesToBase64Url(sig)}`;
}

export async function generateRsaKeyPairForTests() {
  return crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
}
