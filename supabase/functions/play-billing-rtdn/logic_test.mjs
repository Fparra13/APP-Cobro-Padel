/**
 * Pure-logic unit tests for play-billing-rtdn acknowledgement coherence.
 * Run: node --test supabase/functions/play-billing-rtdn/logic_test.mjs
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  ACK_STATE_ACKNOWLEDGED,
  ACK_STATE_PENDING,
  canAcknowledgeAfterPersist,
  isGoogleAcknowledgementConfirmed,
  mapGoogleStateToKloovi,
  persistAcknowledgedFromGoogle,
  resolveRevokedAt,
  sanitizePurchasePayload,
  validateProductAgainstGoogle,
  PRODUCT_MONTHLY,
} from "./logic.mjs";

const NOW = Date.parse("2026-10-09T16:00:00.000Z");
const FUTURE = "2026-11-09T16:00:00.000Z";
const PAST = "2026-09-09T16:00:00.000Z";

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
      ACK_STATE_PENDING,
    latestOrderId: "GPA.RTDN.1",
    lineItems: [
      {
        productId: PRODUCT_MONTHLY,
        expiryTime: overrides.expiryTime ?? FUTURE,
        latestSuccessfulOrderId: "GPA.RTDN.1",
        autoRenewingPlan: { autoRenewEnabled: false },
        offerDetails: {
          basePlanId: "monthly",
          ...(offerId == null ? {} : { offerId }),
        },
      },
    ],
  };
}

/** Simula el campo que RTDN persistiría (Google actual, no flag previo). */
function rtdnPersistAcknowledged(prevLocalAck, googleAckState) {
  void prevLocalAck; // ignorado a propósito
  return persistAcknowledgedFromGoogle(googleAckState);
}

test("prev acknowledged=true + Google PENDING → no queda confirmado", () => {
  assert.equal(
    rtdnPersistAcknowledged(true, ACK_STATE_PENDING),
    false,
  );
  const payload = sanitizePurchasePayload(
    monthlyPurchase({ acknowledgementState: ACK_STATE_PENDING }),
  );
  assert.equal(payload.acknowledgementState, ACK_STATE_PENDING);
  assert.equal(
    persistAcknowledgedFromGoogle(payload.acknowledgementState),
    false,
  );
});

test("prev acknowledged=false + Google ACKNOWLEDGED → confirmado", () => {
  assert.equal(
    rtdnPersistAcknowledged(false, ACK_STATE_ACKNOWLEDGED),
    true,
  );
  const payload = sanitizePurchasePayload(
    monthlyPurchase({ acknowledgementState: ACK_STATE_ACKNOWLEDGED }),
  );
  assert.equal(payload.acknowledgementState, ACK_STATE_ACKNOWLEDGED);
  assert.equal(
    persistAcknowledgedFromGoogle(payload.acknowledgementState),
    true,
  );
});

test("payload acknowledgementState coherente con flag persistido", () => {
  for (const state of [ACK_STATE_PENDING, ACK_STATE_ACKNOWLEDGED, null]) {
    const purchase = monthlyPurchase({
      acknowledgementState: state ?? ACK_STATE_PENDING,
    });
    if (state == null) delete purchase.acknowledgementState;
    const payload = sanitizePurchasePayload(
      state == null ? { ...purchase, acknowledgementState: undefined } : purchase,
    );
    const flag = persistAcknowledgedFromGoogle(
      payload.acknowledgementState ?? null,
    );
    if (flag) {
      assert.equal(payload.acknowledgementState, ACK_STATE_ACKNOWLEDGED);
    } else {
      assert.notEqual(payload.acknowledgementState, ACK_STATE_ACKNOWLEDGED);
    }
  }
});

test("PENDING + suscripción vencida → no Pro y no intentar :acknowledge", () => {
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({
      acknowledgementState: ACK_STATE_PENDING,
      expiryTime: PAST,
      subscriptionState: "SUBSCRIPTION_STATE_EXPIRED",
    }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.grantsPro, false);
  assert.equal(
    persistAcknowledgedFromGoogle(mapped.value.acknowledgementState),
    false,
  );
  assert.equal(
    canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: mapped.value.grantsPro,
      founderBlocked: false,
      googleAckState: ACK_STATE_PENDING,
    }),
    false,
  );
});

test("estado Google ausente/inesperado → no inventar confirmación", () => {
  assert.equal(persistAcknowledgedFromGoogle(null), false);
  assert.equal(persistAcknowledgedFromGoogle(undefined), false);
  assert.equal(persistAcknowledgedFromGoogle(""), false);
  assert.equal(persistAcknowledgedFromGoogle("ACKNOWLEDGEMENT_STATE_UNSPECIFIED"), false);
  assert.equal(isGoogleAcknowledgementConfirmed(ACK_STATE_PENDING), false);
});

test("RTDN repetido idempotente: mismo estado Google → mismo flag", () => {
  const first = rtdnPersistAcknowledged(true, ACK_STATE_ACKNOWLEDGED);
  const second = rtdnPersistAcknowledged(first, ACK_STATE_ACKNOWLEDGED);
  assert.equal(first, true);
  assert.equal(second, true);

  const a = rtdnPersistAcknowledged(true, ACK_STATE_PENDING);
  const b = rtdnPersistAcknowledged(a, ACK_STATE_PENDING);
  assert.equal(a, false);
  assert.equal(b, false);
});

test("sanitizePurchasePayload no expone tokens ni secretos", () => {
  const sanitized = sanitizePurchasePayload(
    monthlyPurchase({ acknowledgementState: ACK_STATE_ACKNOWLEDGED }),
  );
  assert.equal("purchaseToken" in sanitized, false);
  assert.equal("purchase_token" in sanitized, false);
  assert.equal("private_key" in sanitized, false);
  assert.equal("access_token" in sanitized, false);
  assert.equal("acceso_ilimitado" in sanitized, false);
});

test("maps SUBSCRIPTION_STATE_REVOKED to revoked (no Pro)", () => {
  assert.equal(
    mapGoogleStateToKloovi({
      subscriptionState: "SUBSCRIPTION_STATE_REVOKED",
      isTrial: false,
      expiresAt: FUTURE,
      nowMs: NOW,
    }),
    "revoked",
  );
  const mapped = validateProductAgainstGoogle({
    requestedProductId: PRODUCT_MONTHLY,
    purchase: monthlyPurchase({
      subscriptionState: "SUBSCRIPTION_STATE_REVOKED",
      acknowledgementState: ACK_STATE_ACKNOWLEDGED,
      expiryTime: FUTURE,
    }),
    nowMs: NOW,
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.value.status, "revoked");
  assert.equal(mapped.value.grantsPro, false);
});

test("resolveRevokedAt preserves prior revoke without clear evidence", () => {
  const nowIso = "2026-10-09T16:00:00.000Z";
  const prior = "2026-10-01T00:00:00.000Z";
  assert.equal(
    resolveRevokedAt({
      mappedStatus: "expired",
      existingRevokedAt: prior,
      nowIso,
    }),
    prior,
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

test("lógica RTDN no toca profiles.acceso_ilimitado", () => {
  // Contrato: helpers de ack/entitlement de esta función no referencian staff bypass.
  const src = persistAcknowledgedFromGoogle.toString() +
    canAcknowledgeAfterPersist.toString() +
    validateProductAgainstGoogle.toString();
  assert.equal(src.includes("acceso_ilimitado"), false);
});
