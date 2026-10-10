/**
 * Procesamiento del body RTDN tras autenticación (inyectable para tests).
 */
import {
  isGoogleAcknowledgementConfirmed,
  PACKAGE_NAME,
  parseRtdnPubSubBody,
  persistAcknowledgedFromGoogle,
  resolveRevokedAt,
  RTDN_SUBSCRIPTION,
  sanitizePurchasePayload,
  validateProductAgainstGoogle,
} from "./logic.mjs";

/**
 * @param {unknown} bodyUnknown
 * @param {{
 *   lookupPurchase: (token: string) => Promise<{ user_id?: string, product_id?: string, acknowledged?: boolean, revoked_at?: string | null } | null>,
 *   getSubscriptionPurchaseV2: (params: object) => Promise<object>,
 *   upsertPurchase: (row: object) => Promise<{ error?: unknown }>,
 *   upsertSubscription: (row: object) => Promise<{ error?: unknown }>,
 *   nowMs?: number,
 * }} deps
 */
export async function processAuthorizedRtdnBody(bodyUnknown, deps) {
  const parsed = parseRtdnPubSubBody(bodyUnknown);
  if (!parsed.ok) {
    return { status: 400, body: { ok: false, error: parsed.error } };
  }
  if (parsed.value.ignored) {
    return { status: 200, body: { ok: true, ignored: true } };
  }

  const { purchaseToken, productId: rtdnProductId, notificationType } =
    parsed.value;

  let existingPurchase;
  try {
    existingPurchase = await deps.lookupPurchase(purchaseToken);
  } catch {
    console.error("billing_purchases select failed");
    return { status: 500, body: { ok: false, error: "internal_error" } };
  }

  if (!existingPurchase?.user_id) {
    console.error("rtdn_unknown_purchase_token");
    return { status: 200, body: { ok: true, skipped: "unknown_token" } };
  }

  const userId = existingPurchase.user_id;
  const productId = rtdnProductId ?? existingPurchase.product_id;

  const googleResult = await deps.getSubscriptionPurchaseV2({
    purchaseToken,
    packageName: PACKAGE_NAME,
  });
  if (!googleResult.ok) {
    return {
      status: 502,
      body: { ok: false, error: "google_play_validation_failed" },
    };
  }

  const googlePurchase = googleResult.purchase;
  const mapped = validateProductAgainstGoogle({
    requestedProductId: productId,
    purchase: googlePurchase,
    nowMs: typeof deps.nowMs === "number" ? deps.nowMs : Date.now(),
  });
  if (!mapped.ok) {
    console.error("rtdn product mapping failed", mapped.error);
    return { status: 409, body: { ok: false, error: mapped.error } };
  }

  let status = mapped.value.status;
  const nowIso = new Date(
    typeof deps.nowMs === "number" ? deps.nowMs : Date.now(),
  ).toISOString();

  if (notificationType === RTDN_SUBSCRIPTION.REVOKED) {
    status = "revoked";
  } else if (
    notificationType === RTDN_SUBSCRIPTION.EXPIRED &&
    status !== "revoked"
  ) {
    status = "expired";
  }

  const revokedAt = resolveRevokedAt({
    mappedStatus: status,
    existingRevokedAt: existingPurchase.revoked_at ?? null,
    nowIso,
  });

  const googleAckState =
    typeof googlePurchase.acknowledgementState === "string"
      ? googlePurchase.acknowledgementState
      : null;
  const acknowledged = persistAcknowledgedFromGoogle(googleAckState);
  if (
    existingPurchase.acknowledged === true &&
    !isGoogleAcknowledgementConfirmed(googleAckState)
  ) {
    console.error("rtdn_ack_reconcile_local_flag", {
      google_state: googleAckState ?? "absent",
    });
  }

  const purchaseRow = {
    user_id: userId,
    purchase_token: purchaseToken,
    product_id: mapped.value.productId,
    purchase_state: status,
    order_id: mapped.value.orderId,
    package_name: PACKAGE_NAME,
    purchase_time: mapped.value.startsAt,
    expires_at: mapped.value.expiresAt,
    auto_renewing: mapped.value.autoRenewing,
    acknowledged,
    obfuscated_account_id:
      googlePurchase.externalAccountIdentifiers
        ?.obfuscatedExternalAccountId ?? null,
    raw_payload: sanitizePurchasePayload(googlePurchase),
    updated_at: nowIso,
    last_verified_at: nowIso,
  };

  const upPurchase = await deps.upsertPurchase(purchaseRow);
  if (upPurchase?.error) {
    console.error("billing_purchases upsert failed");
    return { status: 500, body: { ok: false, error: "internal_error" } };
  }

  const subscriptionRow = {
    user_id: userId,
    purchase_token: purchaseToken,
    product_id: mapped.value.productId,
    base_plan: mapped.value.basePlan,
    status,
    starts_at: mapped.value.startsAt,
    expires_at: mapped.value.expiresAt,
    auto_renewing: mapped.value.autoRenewing,
    is_trial: mapped.value.isTrial,
    is_founder: mapped.value.isFounder && mapped.value.grantsPro &&
      status !== "revoked",
    revoked_at: revokedAt,
    last_verified_at: nowIso,
    updated_at: nowIso,
  };

  const upSub = await deps.upsertSubscription(subscriptionRow);
  if (upSub?.error) {
    console.error("billing_subscriptions upsert failed");
    return { status: 500, body: { ok: false, error: "internal_error" } };
  }

  return {
    status: 200,
    body: {
      ok: true,
      status,
      notification_type: notificationType,
    },
  };
}
