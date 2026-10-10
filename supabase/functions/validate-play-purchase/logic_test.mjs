/**
 * Pure-logic unit tests for validate-play-purchase.
 * Run: node --test supabase/functions/validate-play-purchase/logic_test.mjs
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ACK_STATE_ACKNOWLEDGED,
  ACK_STATE_PENDING,
  canAcknowledgeAfterPersist,
  detectIsTrial,
  grantsProAccess,
  isAllowedProductId,
  isExpiryInFuture,
  isGoogleAcknowledgementConfirmed,
  mapGoogleStateToKloovi,
  PACKAGE_NAME,
  parseRtdnPubSubBody,
  parseValidateRequestBody,
  PRODUCT_FOUNDER_ANNUAL,
  PRODUCT_MONTHLY,
  resolveAcknowledgementResult,
  resolveRevokedAt,
  resolveTokenBinding,
  sanitizePurchasePayload,
  validateProductAgainstGoogle,
} from "./logic.mjs";

const NOW = Date.parse("2026-10-06T12:00:00.000Z");
const FUTURE = "2026-11-06T12:00:00.000Z";
const PAST = "2026-09-06T12:00:00.000Z";

function monthlyPurchase(overrides = {}) {
  const offerId = overrides.offerId === undefined
    ? "trial-14d"
    : overrides.offerId;
  return {
    kind: "androidpublisher#subscriptionPurchaseV2",
    startTime: "2026-10-01T12:00:00.000Z",
    subscriptionState: overrides.subscriptionState ??
      "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: overrides.acknowledgementState ??
      "ACKNOWLEDGEMENT_STATE_PENDING",
    latestOrderId: "GPA.1234",
    linkedPurchaseToken: overrides.linkedPurchaseToken ?? null,
    lineItems: [
      {
        productId: overrides.productId ?? PRODUCT_MONTHLY,
        expiryTime: overrides.expiryTime ?? FUTURE,
        latestSuccessfulOrderId: "GPA.1234",
        autoRenewingPlan: { autoRenewEnabled: true },
        offerDetails: {
          basePlanId: overrides.basePlanId ?? "monthly",
          ...(offerId == null ? {} : { offerId }),
        },
        offerPhase: overrides.freeTrial
          ? { freeTrial: {} }
          : offerId === "trial-14d"
          ? { freeTrial: {} }
          : { basePrice: {} },
      },
    ],
    ...overrides,
  };
}

function founderPurchase(overrides = {}) {
  return {
    kind: "androidpublisher#subscriptionPurchaseV2",
    startTime: "2026-10-01T12:00:00.000Z",
    subscriptionState: overrides.subscriptionState ??
      "SUBSCRIPTION_STATE_ACTIVE",
    acknowledgementState: "ACKNOWLEDGEMENT_STATE_PENDING",
    lineItems: [
      {
        productId: overrides.productId ?? PRODUCT_FOUNDER_ANNUAL,
        expiryTime: overrides.expiryTime ?? FUTURE,
        autoRenewingPlan: { autoRenewEnabled: true },
        offerDetails: {
          basePlanId: overrides.basePlanId ?? "founder-annual-v2",
          ...(overrides.offerId ? { offerId: overrides.offerId } : {}),
        },
        offerPhase: { basePrice: {} },
      },
    ],
    ...overrides,
  };
}

test("allowlist accepts only known product ids", () => {
  assert.equal(isAllowedProductId(PRODUCT_MONTHLY), true);
  assert.equal(isAllowedProductId(PRODUCT_FOUNDER_ANNUAL), true);
  assert.equal(isAllowedProductId("com.other.sku"), false);
  assert.equal(isAllowedProductId(""), false);
  assert.equal(isAllowedProductId(null), false);
});

test("parseValidateRequestBody rejects invalid bodies", () => {
  assert.equal(parseValidateRequestBody(null).ok, false);
  assert.equal(parseValidateRequestBody({}).ok, false);
  assert.equal(
    parseValidateRequestBody({
      purchase_token: "",
      product_id: PRODUCT_MONTHLY,
    }).ok,
    false,
  );
  assert.equal(
    parseValidateRequestBody({
      purchase_token: "tok",
      product_id: "unknown",
    }).ok,
    false,
  );
  const ok = parseValidateRequestBody({
    purchase_token: "  tok  ",
    product_id: PRODUCT_MONTHLY,
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.value.purchase_token, "tok");
});

test("maps ACTIVE free trial to trial", () => {
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      isTrial: true,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "trial",
  );
});

test("maps ACTIVE paid to active", () => {
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "active",
  );
});

test("maps CANCELED with future expiry to canceled", () => {
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_CANCELED",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "canceled",
  );
});

test("maps CANCELED with past expiry to expired", () => {
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_CANCELED",
      isTrial: false,
      expiresAt: PAST,
      nowMs: NOW,
    }),
    "expired",
  );
});

test("maps SUBSCRIPTION_STATE_REVOKED to revoked", () => {
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_REVOKED",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "revoked",
  );
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_REVOKED",
      isTrial: false,
      expiresAt: PAST,
      nowMs: NOW,
    }),
    "revoked",
  );
});

test("maps EXPIRED / PENDING / ON_HOLD / PAUSED conservatively", () => {
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
      isTrial: false,
      expiresAt: PAST,
      nowMs: NOW,
    }),
    "expired",
  );
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_PENDING",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "pending",
  );
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "pending",
  );
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_ON_HOLD",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "on_hold",
  );
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_PAUSED",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "expired",
  );
});

test("IN_GRACE_PERIOD maps to grace and grants Pro while expiry is future", () => {
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_IN_GRACE_PERIOD",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "grace",
  );
  assert.equal(grantsProAccess("grace"), true);
  assert.equal(grantsProAccess("on_hold"), false);
  assert.equal(grantsProAccess("pending"), false);
  assert.equal(grantsProAccess("revoked"), false);
});

test("parseRtdnPubSubBody extracts purchase token", () => {
  const inner = {
    version: "1.0",
    packageName: PACKAGE_NAME,
    subscriptionNotification: {
      notificationType: 2,
      purchaseToken: "tok-rtdn-1",
      subscriptionId: PRODUCT_MONTHLY,
    },
  };
  const body = {
    message: {
      data: Buffer.from(JSON.stringify(inner), "utf8").toString("base64"),
    },
  };
  const parsed = parseRtdnPubSubBody(body);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.value.ignored, false);
  assert.equal(parsed.value.purchaseToken, "tok-rtdn-1");
  assert.equal(parsed.value.productId, PRODUCT_MONTHLY);
});

test("token binding rejects other user (idempotent ownership)", () => {
  assert.equal(
    resolveTokenBinding({
      existingUserId: "user-a",
      requestUserId: "user-b",
    }),
    "token_bound_to_other_user",
  );
  assert.equal(
    resolveTokenBinding({
      existingUserId: "user-a",
      requestUserId: "user-a",
    }),
    "ok",
  );
});

test("expiry gate: past expiry never grants Pro", () => {
  assert.equal(isExpiryInFuture(PAST, NOW), false);
  assert.equal(isExpiryInFuture(FUTURE, NOW), true);
  assert.equal(grantsProAccess("active"), true);
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({
      offerId: null,
      freeTrial: false,
      expiryTime: PAST,
      subscriptionState: "SUBSCRIPTION_STATE_ACTIVE",
    }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.grantsPro, false);
  assert.equal(mapped.value.shouldAcknowledge, false);
});

test("monthly trial-14d accepted", () => {
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({ offerId: "trial-14d", freeTrial: true }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.isTrial, true);
  assert.equal(mapped.value.status, "trial");
  assert.equal(mapped.value.basePlan, "monthly");
  assert.equal(mapped.value.grantsPro, true);
});

test("monthly paid (no offer) accepted", () => {
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({ offerId: null, freeTrial: false }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.isTrial, false);
  assert.equal(mapped.value.status, "active");
});

test("monthly rejects wrong base plan or unknown offer", () => {
  assert.equal(
    validateProductAgainstGoogle({
      requestedProductId: PRODUCT_MONTHLY,
      purchase: monthlyPurchase({ basePlanId: "annual" }),
      nowMs: NOW,
    }).ok,
    false,
  );
  assert.equal(
    validateProductAgainstGoogle({
      requestedProductId: PRODUCT_MONTHLY,
      purchase: monthlyPurchase({ offerId: "weird-offer" }),
      nowMs: NOW,
    }).ok,
    false,
  );
});

test("founder annual-v2 accepted without trial", () => {
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_FOUNDER_ANNUAL,
    purchase: founderPurchase(),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.isFounder, true);
  assert.equal(mapped.value.isTrial, false);
  assert.equal(mapped.value.basePlan, "founder-annual-v2");
  assert.equal(mapped.value.grantsPro, true);
});

test("founder legacy annual base plan still accepted on revalidate", () => {
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_FOUNDER_ANNUAL,
    purchase: founderPurchase({ basePlanId: "annual" }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.basePlan, "annual");
});

test("founder rejects trial or wrong base plan", () => {
  assert.equal(
    validateProductAgainstGoogle({
      requestedProductId: PRODUCT_FOUNDER_ANNUAL,
      purchase: founderPurchase({ offerId: "trial-14d" }),
      nowMs: NOW,
    }).ok,
    false,
  );
  assert.equal(
    validateProductAgainstGoogle({
      requestedProductId: PRODUCT_FOUNDER_ANNUAL,
      purchase: founderPurchase({ basePlanId: "monthly" }),
      nowMs: NOW,
    }).ok,
    false,
  );
});

test("product_id mismatch vs Google line item rejected", () => {
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({ productId: PRODUCT_FOUNDER_ANNUAL }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, false);
});

test("token binding blocks other users", () => {
  assert.equal(
    resolveTokenBinding({ existingUserId: null, requestUserId: "u1" }),
    "ok",
  );
  assert.equal(
    resolveTokenBinding({ existingUserId: "u1", requestUserId: "u1" }),
    "ok",
  );
  assert.equal(
    resolveTokenBinding({ existingUserId: "u1", requestUserId: "u2" }),
    "token_bound_to_other_user",
  );
});

test("acknowledge only after persist + grantsPro + not founderBlocked", () => {
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: false,
      grantsPro: true,
      founderBlocked: false,
      googleAckState: ACK_STATE_PENDING,
    }),
    false,
  );
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: true,
      founderBlocked: true,
      googleAckState: ACK_STATE_PENDING,
    }),
    false,
  );
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: false,
      founderBlocked: false,
      googleAckState: ACK_STATE_PENDING,
    }),
    false,
  );
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: true,
      founderBlocked: false,
      googleAckState: ACK_STATE_ACKNOWLEDGED,
    }),
    false,
  );
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: true,
      founderBlocked: false,
      googleAckState: ACK_STATE_PENDING,
    }),
    true,
  );
});

test("local acknowledged=true but Google PENDING → still attempt acknowledge", () => {
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: true,
      founderBlocked: false,
      alreadyAcknowledged: true, // ignored when googleAckState is present
      googleAckState: ACK_STATE_PENDING,
    }),
    true,
  );
  assert.equal(isGoogleAcknowledgementConfirmed(ACK_STATE_PENDING), false);
  assert.equal(isGoogleAcknowledgementConfirmed(ACK_STATE_ACKNOWLEDGED), true);
});

test("ack: Google already ACKNOWLEDGED → confirmed, no ack call needed", () => {
  const r = resolveAcknowledgementResult({
    initialAckState: ACK_STATE_ACKNOWLEDGED,
    acknowledgeHttpOk: null,
    verifyOk: null,
    verifiedAckState: null,
    persistAckFlagOk: true,
  });
  assert.equal(r.acknowledged, true);
  assert.equal(r.acknowledgePending, false);
  assert.equal(r.reason, "already_acknowledged_on_google");
});

test("ack: PENDING + acknowledge 2xx + verify ACKNOWLEDGED → confirmed", () => {
  const r = resolveAcknowledgementResult({
    initialAckState: ACK_STATE_PENDING,
    acknowledgeHttpOk: true,
    verifyOk: true,
    verifiedAckState: ACK_STATE_ACKNOWLEDGED,
    persistAckFlagOk: true,
  });
  assert.equal(r.acknowledged, true);
  assert.equal(r.acknowledgePending, false);
  assert.equal(r.reason, "verified_acknowledged");
});

test("ack: PENDING + acknowledge 2xx + verify still PENDING → pending", () => {
  const r = resolveAcknowledgementResult({
    initialAckState: ACK_STATE_PENDING,
    acknowledgeHttpOk: true,
    verifyOk: true,
    verifiedAckState: ACK_STATE_PENDING,
    persistAckFlagOk: null,
  });
  assert.equal(r.acknowledged, false);
  assert.equal(r.acknowledgePending, true);
  assert.equal(r.reason, "ack_unconfirmed");
});

test("ack: acknowledge HTTP 5xx → pending, not confirmed", () => {
  const r = resolveAcknowledgementResult({
    initialAckState: ACK_STATE_PENDING,
    acknowledgeHttpOk: false,
    verifyOk: null,
    verifiedAckState: null,
    persistAckFlagOk: null,
  });
  assert.equal(r.acknowledged, false);
  assert.equal(r.acknowledgePending, true);
  assert.equal(r.reason, "acknowledge_http_failed");
});

test("ack: verify get fails after acknowledge → pending", () => {
  const r = resolveAcknowledgementResult({
    initialAckState: ACK_STATE_PENDING,
    acknowledgeHttpOk: true,
    verifyOk: false,
    verifiedAckState: null,
    persistAckFlagOk: null,
  });
  assert.equal(r.acknowledged, false);
  assert.equal(r.acknowledgePending, true);
  assert.equal(r.reason, "verify_get_failed");
});

test("ack: Google confirmed but persist flag fails → pending recoverable", () => {
  const r = resolveAcknowledgementResult({
    initialAckState: ACK_STATE_PENDING,
    acknowledgeHttpOk: true,
    verifyOk: true,
    verifiedAckState: ACK_STATE_ACKNOWLEDGED,
    persistAckFlagOk: false,
  });
  assert.equal(r.acknowledged, false);
  assert.equal(r.acknowledgePending, true);
  assert.equal(r.reason, "ack_persist_failed");
});

test("ack: unexpected/absent verify state → not confirmed", () => {
  const r = resolveAcknowledgementResult({
    initialAckState: ACK_STATE_PENDING,
    acknowledgeHttpOk: true,
    verifyOk: true,
    verifiedAckState: null,
    persistAckFlagOk: null,
  });
  assert.equal(r.acknowledged, false);
  assert.equal(r.acknowledgePending, true);
  assert.equal(r.reason, "ack_unconfirmed");
});

test("grantsPro false when expired even if acknowledgement ACKNOWLEDGED", () => {
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({
      acknowledgementState: ACK_STATE_ACKNOWLEDGED,
      expiryTime: PAST,
      subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
    }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.grantsPro, false);
  assert.equal(mapped.value.status, "expired");
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: mapped.value.grantsPro,
      founderBlocked: false,
      googleAckState: ACK_STATE_ACKNOWLEDGED,
    }),
    false,
  );
});

test("revoked / on_hold do not grant Pro", () => {
  const onHold = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({
      subscriptionState: "SUBSCRIPTION_STATE_ON_HOLD",
      acknowledgementState: ACK_STATE_ACKNOWLEDGED,
    }),
    nowMs: NOW,
  });
  assert.equal(onHold.ok, true);
  assert.equal(onHold.value.grantsPro, false);
  assert.equal(onHold.value.status, "on_hold");

  const revoked = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({
      subscriptionState: "SUBSCRIPTION_STATE_REVOKED",
      acknowledgementState: ACK_STATE_ACKNOWLEDGED,
      expiryTime: FUTURE,
    }),
    nowMs: NOW,
  });
  assert.equal(revoked.ok, true);
  assert.equal(revoked.value.status, "revoked");
  assert.equal(revoked.value.grantsPro, false);
  assert.equal(grantsProAccess("revoked"), false);
  assert.equal(grantsProAccess("expired"), false);
  assert.equal(isExpiryInFuture(PAST, NOW), false);
});

test("resolveRevokedAt sets and preserves revoked_at", () => {
  const nowIso = "2026-10-09T12:00:00.000Z";
  const prior = "2026-10-01T00:00:00.000Z";

  assert.equal(
    resolveRevokedAt({
      mappedStatus: "revoked",
      existingRevokedAt: null,
      nowIso,
    }),
    nowIso,
  );
  assert.equal(
    resolveRevokedAt({
      mappedStatus: "revoked",
      existingRevokedAt: prior,
      nowIso,
    }),
    prior,
  );
});

test("resolveRevokedAt does not clear without valid commercial evidence", () => {
  const nowIso = "2026-10-09T12:00:00.000Z";
  const prior = "2026-10-01T00:00:00.000Z";

  for (const status of ["pending", "on_hold", "expired", null]) {
    assert.equal(
      resolveRevokedAt({
        mappedStatus: status,
        existingRevokedAt: prior,
        nowIso,
      }),
      prior,
      `status=${status}`,
    );
  }
});

test("resolveRevokedAt clears only with active/trial/canceled/grace", () => {
  const nowIso = "2026-10-09T12:00:00.000Z";
  const prior = "2026-10-01T00:00:00.000Z";

  for (const status of ["active", "trial", "canceled", "grace"]) {
    assert.equal(
      resolveRevokedAt({
        mappedStatus: status,
        existingRevokedAt: prior,
        nowIso,
      }),
      null,
      `status=${status}`,
    );
  }
});

test("valid active + PENDING ack still grantsPro (entitlement ≠ ack)", () => {
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({
      acknowledgementState: ACK_STATE_PENDING,
    }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.grantsPro, true);
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: true,
      founderBlocked: false,
      googleAckState: ACK_STATE_PENDING,
    }),
    true,
  );
});

test("sanitizePurchasePayload keeps acknowledgementState, never tokens/secrets", () => {
  const sanitized = sanitizePurchasePayload(
    monthlyPurchase({
      acknowledgementState: ACK_STATE_ACKNOWLEDGED,
      testPurchase: { some: "flag" },
    }),
  );
  assert.equal(sanitized.acknowledgementState, ACK_STATE_ACKNOWLEDGED);
  assert.equal("purchaseToken" in sanitized, false);
  assert.equal("purchase_token" in sanitized, false);
  assert.equal("private_key" in sanitized, false);
  assert.equal("access_token" in sanitized, false);
  assert.deepEqual(sanitized.testPurchase, { present: true });
});

test("detectIsTrial uses offerPhase or trial-14d", () => {
  assert.equal(
    detectIsTrial({
      offerDetails: { offerId: "trial-14d" },
      offerPhase: {},
    }),
    true,
  );
  assert.equal(
    detectIsTrial({
      offerDetails: {},
      offerPhase: { freeTrial: {} },
    }),
    true,
  );
  assert.equal(
    detectIsTrial({
      offerDetails: {},
      offerPhase: { basePrice: {} },
    }),
    false,
  );
});

test("sanitizePurchasePayload never invents secrets and marks testPurchase", () => {
  const sanitized = sanitizePurchasePayload(
    monthlyPurchase({ testPurchase: { some: "flag" } }),
  );
  assert.ok(sanitized.subscriptionState);
  assert.deepEqual(sanitized.testPurchase, { present: true });
  assert.equal("private_key" in sanitized, false);
  assert.equal("access_token" in sanitized, false);
});

test("idempotency conceptual: same user+token binding stays ok", () => {
  assert.equal(
    resolveTokenBinding({
      existingUserId: "same-user",
      requestUserId: "same-user",
    }),
    "ok",
  );
});

test("founder sold-out path must not acknowledge", () => {
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: false,
      grantsPro: true,
      founderBlocked: true,
      alreadyAcknowledged: false,
    }),
    false,
  );
});
