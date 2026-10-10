/**
 * Pruebas criptográficas OIDC Pub/Sub (firma RS256 real con Web Crypto).
 * Run: node --test supabase/functions/play-billing-rtdn/pubsub_oidc_test.mjs
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  GOOGLE_JWKS_URL,
  authorizeRtdnRequest,
  defaultFetchGoogleJwk,
  generateRsaKeyPairForTests,
  readOidcConfig,
  resetGoogleJwksCacheForTests,
  signJwtRs256ForTests,
  validateOidcClaims,
  verifyJwtRs256Signature,
  verifyPubSubOidcToken,
} from "./pubsub_oidc.mjs";
import { processAuthorizedRtdnBody } from "./rtdn_process.mjs";
import { PACKAGE_NAME, PRODUCT_MONTHLY } from "./logic.mjs";

const EXPECTED_EMAIL = "pubsub-rtdn-push@padel-cobro.iam.gserviceaccount.com";
const EXPECTED_AUD =
  "https://qduybfdxpyfjzosakdlq.supabase.co/functions/v1/play-billing-rtdn";

async function fixtureKeys() {
  const { publicKey, privateKey } = await generateRsaKeyPairForTests();
  const publicJwk = await crypto.subtle.exportKey("jwk", publicKey);
  publicJwk.kid = "test-kid-1";
  publicJwk.alg = "RS256";
  publicJwk.use = "sig";
  return { publicKey, privateKey, publicJwk };
}

function baseClaims(overrides = {}) {
  const now = Math.floor(Date.now() / 1000);
  return {
    iss: "https://accounts.google.com",
    aud: EXPECTED_AUD,
    email: EXPECTED_EMAIL,
    email_verified: true,
    iat: now,
    exp: now + 3600,
    ...overrides,
  };
}

test("JWT ausente → rechazado", async () => {
  const auth = await authorizeRtdnRequest(
    { headers: { get: () => null } },
    {
      PLAY_BILLING_RTDN_OIDC_EMAIL: EXPECTED_EMAIL,
      PLAY_BILLING_RTDN_OIDC_AUDIENCE: EXPECTED_AUD,
    },
  );
  assert.equal(auth.ok, false);
  assert.equal(auth.reason, "token_missing");
});

test("JWT malformado → rechazado", async () => {
  const verified = await verifyPubSubOidcToken("not-a-jwt", {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    getJwk: async () => {
      throw new Error("should_not_fetch");
    },
  });
  assert.equal(verified.ok, false);
});

test("firma inválida → rechazado", async () => {
  const a = await fixtureKeys();
  const b = await fixtureKeys();
  const token = await signJwtRs256ForTests(
    baseClaims(),
    a.privateKey,
    { kid: "test-kid-1" },
  );
  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    getJwk: async () => b.publicJwk,
  });
  assert.equal(verified.ok, false);
  assert.equal(verified.reason, "invalid_signature");
});

test("aud incorrecto → rechazado", async () => {
  const { privateKey, publicJwk } = await fixtureKeys();
  const token = await signJwtRs256ForTests(
    baseClaims({ aud: "https://evil.example/push" }),
    privateKey,
    { kid: "test-kid-1" },
  );
  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    getJwk: async () => publicJwk,
  });
  assert.equal(verified.ok, false);
  assert.equal(verified.reason, "aud_mismatch");
});

test("email no permitido → rechazado", async () => {
  const { privateKey, publicJwk } = await fixtureKeys();
  const token = await signJwtRs256ForTests(
    baseClaims({ email: "other@padel-cobro.iam.gserviceaccount.com" }),
    privateKey,
    { kid: "test-kid-1" },
  );
  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    getJwk: async () => publicJwk,
  });
  assert.equal(verified.ok, false);
  assert.equal(verified.reason, "email_mismatch");
});

test("email_verified falso → rechazado", async () => {
  assert.equal(
    validateOidcClaims(baseClaims({ email_verified: false }), {
      email: EXPECTED_EMAIL,
      audience: EXPECTED_AUD,
    }).ok,
    false,
  );
  const { privateKey, publicJwk } = await fixtureKeys();
  const token = await signJwtRs256ForTests(
    baseClaims({ email_verified: false }),
    privateKey,
    { kid: "test-kid-1" },
  );
  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    getJwk: async () => publicJwk,
  });
  assert.equal(verified.ok, false);
  assert.equal(verified.reason, "email_not_verified");
});

test("token válido firmado (mismo material que JWKS) → aceptado", async () => {
  const { privateKey, publicJwk } = await fixtureKeys();
  const token = await signJwtRs256ForTests(baseClaims(), privateKey, {
    kid: "test-kid-1",
  });
  const sigOnly = await verifyJwtRs256Signature(token, publicJwk);
  assert.equal(sigOnly.ok, true);

  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    getJwk: async () => publicJwk,
  });
  assert.equal(verified.ok, true);

  const auth = await authorizeRtdnRequest(
    {
      headers: {
        get: (name) =>
          name === "Authorization" ? `Bearer ${token}` : null,
      },
    },
    {
      PLAY_BILLING_RTDN_OIDC_EMAIL: EXPECTED_EMAIL,
      PLAY_BILLING_RTDN_OIDC_AUDIENCE: EXPECTED_AUD,
    },
    { getJwk: async () => publicJwk },
  );
  assert.equal(auth.ok, true);
  assert.equal(auth.method, "pubsub_oidc");
});

test("OIDC config ausente → rechazado (no anónimo)", async () => {
  const cfg = readOidcConfig({});
  assert.equal(cfg.oidcConfigured, false);
  const auth = await authorizeRtdnRequest(
    {
      headers: {
        get: () => "Bearer aaaa.bbbb.cccc",
      },
    },
    {},
  );
  assert.equal(auth.ok, false);
  assert.equal(auth.reason, "oidc_config_missing");
});

test("Bearer estático deshabilitado por defecto", async () => {
  const auth = await authorizeRtdnRequest(
    {
      headers: {
        get: () => "Bearer static-secret-at-least-16",
      },
    },
    {
      PLAY_BILLING_RTDN_OIDC_EMAIL: EXPECTED_EMAIL,
      PLAY_BILLING_RTDN_OIDC_AUDIENCE: EXPECTED_AUD,
      PLAY_BILLING_RTDN_SECRET: "static-secret-at-least-16",
      // ALLOW_STATIC_BEARER omitido → false
    },
    {
      getJwk: async () => {
        throw new Error("oidc_only");
      },
    },
  );
  assert.equal(auth.ok, false);
});

test("Pub/Sub body válido + purchase token ficticio → 200 skipped, sin upsert", async () => {
  const inner = {
    version: "1.0",
    packageName: PACKAGE_NAME,
    subscriptionNotification: {
      notificationType: 13,
      purchaseToken: "fictitious-token-not-in-db",
      subscriptionId: PRODUCT_MONTHLY,
    },
  };
  const body = {
    message: {
      messageId: "msg-test-1",
      data: Buffer.from(JSON.stringify(inner), "utf8").toString("base64"),
    },
  };

  let upsertPurchaseCalls = 0;
  let upsertSubCalls = 0;
  let googleCalls = 0;

  const result = await processAuthorizedRtdnBody(body, {
    lookupPurchase: async () => null,
    getSubscriptionPurchaseV2: async () => {
      googleCalls++;
      return { ok: false, status: 500, error: "google_play_validation_failed" };
    },
    upsertPurchase: async () => {
      upsertPurchaseCalls++;
      return {};
    },
    upsertSubscription: async () => {
      upsertSubCalls++;
      return {};
    },
  });

  assert.equal(result.status, 200);
  assert.equal(result.body.ok, true);
  assert.equal(result.body.skipped, "unknown_token");
  assert.equal(upsertPurchaseCalls, 0);
  assert.equal(upsertSubCalls, 0);
  assert.equal(googleCalls, 0);
});

test("payload Pub/Sub inválido → 400 sin cambios de estado", async () => {
  let upserts = 0;
  const result = await processAuthorizedRtdnBody({ not: "pubsub" }, {
    lookupPurchase: async () => {
      throw new Error("should_not_lookup");
    },
    getSubscriptionPurchaseV2: async () => ({ ok: false }),
    upsertPurchase: async () => {
      upserts++;
      return {};
    },
    upsertSubscription: async () => {
      upserts++;
      return {};
    },
  });
  assert.equal(result.status, 400);
  assert.equal(result.body.ok, false);
  assert.equal(upserts, 0);
});

function jwksResponse(keys) {
  return {
    ok: true,
    async json() {
      return { keys };
    },
  };
}

test("kid desconocido en caché → una sola actualización JWKS", async () => {
  resetGoogleJwksCacheForTests();
  const oldKey = await fixtureKeys();
  oldKey.publicJwk.kid = "old-kid";
  const newKey = await fixtureKeys();
  newKey.publicJwk.kid = "rotated-kid";

  let fetchCount = 0;
  const fetchImpl = async (url) => {
    assert.equal(url, GOOGLE_JWKS_URL);
    fetchCount++;
    if (fetchCount === 1) return jwksResponse([oldKey.publicJwk]);
    return jwksResponse([oldKey.publicJwk, newKey.publicJwk]);
  };

  // Calienta caché con kid conocido (1 fetch).
  const warm = await defaultFetchGoogleJwk({ kid: "old-kid" }, fetchImpl);
  assert.equal(warm.kid, "old-kid");
  assert.equal(fetchCount, 1);

  // kid rotado ausente → exactamente un refresh (2.º fetch), sin bucle.
  const rotated = await defaultFetchGoogleJwk({ kid: "rotated-kid" }, fetchImpl);
  assert.equal(rotated.kid, "rotated-kid");
  assert.equal(fetchCount, 2);

  // kid ya en caché tras refresh → sin nuevo fetch.
  const again = await defaultFetchGoogleJwk({ kid: "rotated-kid" }, fetchImpl);
  assert.equal(again.kid, "rotated-kid");
  assert.equal(fetchCount, 2);
});

test("kid que aparece tras actualización JWKS → JWT válido aceptado", async () => {
  resetGoogleJwksCacheForTests();
  const stale = await fixtureKeys();
  stale.publicJwk.kid = "stale-kid";
  const fresh = await fixtureKeys();
  fresh.publicJwk.kid = "fresh-kid";

  let fetchCount = 0;
  const fetchImpl = async () => {
    fetchCount++;
    if (fetchCount === 1) return jwksResponse([stale.publicJwk]);
    return jwksResponse([stale.publicJwk, fresh.publicJwk]);
  };

  await defaultFetchGoogleJwk({ kid: "stale-kid" }, fetchImpl);
  assert.equal(fetchCount, 1);

  const token = await signJwtRs256ForTests(baseClaims(), fresh.privateKey, {
    kid: "fresh-kid",
  });
  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    fetchImpl,
  });
  assert.equal(verified.ok, true);
  assert.equal(fetchCount, 2);
});

test("kid ausente tras refresh → rechazado de forma segura", async () => {
  resetGoogleJwksCacheForTests();
  const only = await fixtureKeys();
  only.publicJwk.kid = "only-kid";

  let fetchCount = 0;
  const fetchImpl = async () => {
    fetchCount++;
    return jwksResponse([only.publicJwk]);
  };

  await defaultFetchGoogleJwk({ kid: "only-kid" }, fetchImpl);
  assert.equal(fetchCount, 1);

  await assert.rejects(
    () => defaultFetchGoogleJwk({ kid: "never-published" }, fetchImpl),
    (err) => err instanceof Error && err.message === "jwk_not_found",
  );
  assert.equal(fetchCount, 2);

  const token = await signJwtRs256ForTests(baseClaims(), only.privateKey, {
    kid: "never-published",
  });
  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    fetchImpl,
  });
  assert.equal(verified.ok, false);
  assert.equal(verified.reason, "jwks_unavailable");
});

test("error de red al actualizar JWKS → falla seguro", async () => {
  resetGoogleJwksCacheForTests();
  const oldKey = await fixtureKeys();
  oldKey.publicJwk.kid = "net-old";

  let fetchCount = 0;
  const fetchImpl = async () => {
    fetchCount++;
    if (fetchCount === 1) return jwksResponse([oldKey.publicJwk]);
    throw new Error("network_down");
  };

  await defaultFetchGoogleJwk({ kid: "net-old" }, fetchImpl);
  assert.equal(fetchCount, 1);

  await assert.rejects(
    () => defaultFetchGoogleJwk({ kid: "net-new" }, fetchImpl),
    (err) => err instanceof Error && err.message === "network_down",
  );
  assert.equal(fetchCount, 2);

  const other = await fixtureKeys();
  const token = await signJwtRs256ForTests(baseClaims(), other.privateKey, {
    kid: "net-new",
  });
  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    fetchImpl: async () => {
      throw new Error("network_down");
    },
  });
  assert.equal(verified.ok, false);
  assert.equal(verified.reason, "jwks_unavailable");
});

test("firma inválida tras JWKS fresco → no se acepta", async () => {
  resetGoogleJwksCacheForTests();
  const published = await fixtureKeys();
  published.publicJwk.kid = "sig-kid";
  const attacker = await fixtureKeys();

  const fetchImpl = async () => jwksResponse([published.publicJwk]);

  // Token firmado con otra clave; el kid apunta a la JWK publicada.
  const token = await signJwtRs256ForTests(baseClaims(), attacker.privateKey, {
    kid: "sig-kid",
  });
  const verified = await verifyPubSubOidcToken(token, {
    email: EXPECTED_EMAIL,
    audience: EXPECTED_AUD,
    fetchImpl,
  });
  assert.equal(verified.ok, false);
  assert.equal(verified.reason, "invalid_signature");
});
