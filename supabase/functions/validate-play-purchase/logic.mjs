/**
 * Pure billing validation/mapping logic (no Deno/Supabase/Google I/O).
 * Unit-tested without calling Google Play.
 */

export const PACKAGE_NAME = "com.kloovi.app";

export const PRODUCT_MONTHLY = "kloovi_pro_monthly";
export const PRODUCT_FOUNDER_ANNUAL = "kloovi_pro_founder_annual";

/** Base plan anual correcto (renovación anual). */
export const FOUNDER_BASE_PLAN = "founder-annual-v2";
/** Legacy mal configurado como mensual; solo revalidación de compras antiguas. */
export const FOUNDER_BASE_PLAN_LEGACY = "annual";

export const ALLOWED_FOUNDER_BASE_PLANS = [
  FOUNDER_BASE_PLAN,
  FOUNDER_BASE_PLAN_LEGACY,
];

export const ALLOWED_PRODUCT_IDS = [
  PRODUCT_MONTHLY,
  PRODUCT_FOUNDER_ANNUAL,
];

export function isAllowedProductId(value) {
  return typeof value === "string" && ALLOWED_PRODUCT_IDS.includes(value);
}

export function parseValidateRequestBody(body) {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, error: "invalid_request" };
  }
  const purchaseToken = body.purchase_token;
  const productId = body.product_id;

  if (typeof purchaseToken !== "string" || purchaseToken.trim().length === 0) {
    return { ok: false, error: "invalid_request" };
  }
  if (!isAllowedProductId(productId)) {
    return { ok: false, error: "invalid_request" };
  }

  return {
    ok: true,
    value: {
      purchase_token: purchaseToken.trim(),
      product_id: productId,
    },
  };
}

export function pickPrimaryLineItem(purchase) {
  const items = purchase.lineItems;
  if (!Array.isArray(items) || items.length === 0) return null;
  return items[0] ?? null;
}

export function detectIsTrial(lineItem) {
  if (lineItem.offerPhase?.freeTrial != null) return true;
  const offerId = lineItem.offerDetails?.offerId;
  return offerId === "trial-14d";
}

export function isExpiryInFuture(expiryTime, nowMs) {
  if (!expiryTime) return false;
  const ms = Date.parse(expiryTime);
  if (Number.isNaN(ms)) return false;
  return ms > nowMs;
}

/**
 * Map Google subscriptionState (+ expiry/trial) → Kloovi billing status.
 * Does not invent Google enums.
 */
export function mapGoogleStateToKloovi(params) {
  const state = params.subscriptionState ?? "SUBSCRIPTION_STATE_UNSPECIFIED";
  const future = isExpiryInFuture(params.expiresAt, params.nowMs);

  switch (state) {
    case "SUBSCRIPTION_STATE_ACTIVE":
      if (!future) return "expired";
      return params.isTrial ? "trial" : "active";
    case "SUBSCRIPTION_STATE_IN_GRACE_PERIOD":
      // Período de gracia de pago: Pro sigue vigente hasta expires_at.
      if (!future) return "expired";
      return "grace";
    case "SUBSCRIPTION_STATE_CANCELED":
      return future ? "canceled" : "expired";
    case "SUBSCRIPTION_STATE_EXPIRED":
      return "expired";
    case "SUBSCRIPTION_STATE_PENDING":
    case "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED":
      return "pending";
    case "SUBSCRIPTION_STATE_ON_HOLD":
      // Account hold / espera de pago: sin Pro hasta recuperar.
      return "on_hold";
    case "SUBSCRIPTION_STATE_PAUSED":
      return "expired";
    case "SUBSCRIPTION_STATE_REVOKED":
      return "revoked";
    case "SUBSCRIPTION_STATE_UNSPECIFIED":
    default:
      return future ? "pending" : "expired";
  }
}

export function grantsProAccess(status) {
  return (
    status === "active" ||
    status === "trial" ||
    status === "canceled" ||
    status === "grace"
  );
}

/**
 * Persistencia de `revoked_at` en revalidaciones.
 *
 * - status revoked → fija timestamp (conserva el existente si ya había).
 * - Limpia solo con evidencia comercial válida de Google (active/trial/canceled/grace).
 * - Si ya estaba revocada y el mapeo no aporta esa evidencia, no borra.
 */
export function resolveRevokedAt(params) {
  const mappedStatus = params.mappedStatus ?? null;
  const existing = params.existingRevokedAt ?? null;
  const nowIso = params.nowIso;

  if (mappedStatus === "revoked") {
    return typeof existing === "string" && existing.trim() !== ""
      ? existing
      : nowIso;
  }

  const clearEvidence =
    mappedStatus === "active" ||
    mappedStatus === "trial" ||
    mappedStatus === "canceled" ||
    mappedStatus === "grace";

  if (existing != null && String(existing).trim() !== "" && !clearEvidence) {
    return existing;
  }

  if (clearEvidence) {
    return null;
  }

  return existing != null && String(existing).trim() !== "" ? existing : null;
}

/** Tipos RTDN de suscripción (Google Play Developer Notifications). */
export const RTDN_SUBSCRIPTION = {
  RECOVERED: 1,
  RENEWED: 2,
  CANCELED: 3,
  PURCHASED: 4,
  ON_HOLD: 5,
  IN_GRACE: 6,
  RESTARTED: 7,
  PRICE_CHANGE_CONFIRMED: 8,
  DEFERRED: 9,
  PAUSED: 10,
  PAUSE_SCHEDULE_CHANGED: 11,
  REVOKED: 12,
  EXPIRED: 13,
};

/**
 * Parsea el envelope Pub/Sub push de RTDN.
 * No inventa tokens: exige purchaseToken en subscriptionNotification.
 */
export function parseRtdnPubSubBody(body) {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return { ok: false, error: "invalid_request" };
  }
  const message = body.message;
  if (message === null || typeof message !== "object") {
    return { ok: false, error: "invalid_request" };
  }
  const dataB64 = message.data;
  if (typeof dataB64 !== "string" || dataB64.trim().length === 0) {
    return { ok: false, error: "invalid_request" };
  }

  let decoded;
  try {
    let jsonText;
    if (typeof Buffer !== "undefined") {
      jsonText = Buffer.from(dataB64, "base64").toString("utf8");
    } else if (typeof atob === "function") {
      jsonText = atob(dataB64);
    } else {
      return { ok: false, error: "invalid_request" };
    }
    decoded = JSON.parse(jsonText);
  } catch {
    return { ok: false, error: "invalid_request" };
  }

  if (decoded === null || typeof decoded !== "object") {
    return { ok: false, error: "invalid_request" };
  }

  const packageName = decoded.packageName;
  const sub = decoded.subscriptionNotification;
  if (packageName !== PACKAGE_NAME) {
    return { ok: false, error: "package_mismatch" };
  }
  if (sub === null || typeof sub !== "object") {
    // oneTimeProductNotification u otros: ack sin procesar billing sub.
    return { ok: true, value: { ignored: true } };
  }

  const purchaseToken = sub.purchaseToken;
  const subscriptionId = sub.subscriptionId;
  const notificationType = sub.notificationType;

  if (typeof purchaseToken !== "string" || purchaseToken.trim().length === 0) {
    return { ok: false, error: "invalid_request" };
  }
  if (
    typeof subscriptionId === "string" &&
    subscriptionId.length > 0 &&
    !isAllowedProductId(subscriptionId)
  ) {
    return { ok: false, error: "invalid_request" };
  }

  return {
    ok: true,
    value: {
      ignored: false,
      purchaseToken: purchaseToken.trim(),
      productId: typeof subscriptionId === "string" && subscriptionId.length > 0
        ? subscriptionId
        : null,
      notificationType: typeof notificationType === "number"
        ? notificationType
        : null,
    },
  };
}

export function validateProductAgainstGoogle(params) {
  const line = pickPrimaryLineItem(params.purchase);
  if (!line || typeof line.productId !== "string" || !line.productId) {
    return { ok: false, error: "product_mismatch" };
  }

  if (line.productId !== params.requestedProductId) {
    return { ok: false, error: "product_mismatch" };
  }

  const basePlanId = line.offerDetails?.basePlanId ?? "";
  const offerId = line.offerDetails?.offerId ?? null;
  const isTrial = detectIsTrial(line);
  const expiresAt = typeof line.expiryTime === "string" ? line.expiryTime : null;
  const startsAt = typeof params.purchase.startTime === "string"
    ? params.purchase.startTime
    : null;
  const autoRenewing = line.autoRenewingPlan?.autoRenewEnabled ?? null;
  const orderId = line.latestSuccessfulOrderId ??
    params.purchase.latestOrderId ??
    null;

  if (params.requestedProductId === PRODUCT_MONTHLY) {
    if (basePlanId !== "monthly") {
      return { ok: false, error: "product_mismatch" };
    }
    if (offerId != null && offerId !== "trial-14d") {
      return { ok: false, error: "product_mismatch" };
    }
  } else if (params.requestedProductId === PRODUCT_FOUNDER_ANNUAL) {
    if (!ALLOWED_FOUNDER_BASE_PLANS.includes(basePlanId)) {
      return { ok: false, error: "product_mismatch" };
    }
    if (isTrial || offerId === "trial-14d") {
      return { ok: false, error: "product_mismatch" };
    }
    if (offerId != null) {
      return { ok: false, error: "product_mismatch" };
    }
  } else {
    return { ok: false, error: "invalid_request" };
  }

  const status = mapGoogleStateToKloovi({
    subscriptionState: params.purchase.subscriptionState,
    isTrial: params.requestedProductId === PRODUCT_MONTHLY ? isTrial : false,
    expiresAt,
    nowMs: params.nowMs,
  });

  const grantsPro = grantsProAccess(status) &&
    isExpiryInFuture(expiresAt, params.nowMs);

  return {
    ok: true,
    value: {
      productId: params.requestedProductId,
      basePlan: basePlanId,
      offerId,
      isTrial: params.requestedProductId === PRODUCT_MONTHLY ? isTrial : false,
      isFounder: params.requestedProductId === PRODUCT_FOUNDER_ANNUAL,
      status,
      expiresAt,
      startsAt,
      autoRenewing,
      orderId,
      acknowledgementState: params.purchase.acknowledgementState ?? null,
      linkedPurchaseToken: params.purchase.linkedPurchaseToken ?? null,
      grantsPro,
      shouldAcknowledge: grantsPro,
    },
  };
}

export function resolveTokenBinding(params) {
  if (params.existingUserId == null) return "ok";
  if (params.existingUserId === params.requestUserId) return "ok";
  return "token_bound_to_other_user";
}

export const ACK_STATE_ACKNOWLEDGED = "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED";
export const ACK_STATE_PENDING = "ACKNOWLEDGEMENT_STATE_PENDING";

/** True solo cuando Google reporta reconocimiento confirmado. */
export function isGoogleAcknowledgementConfirmed(state) {
  return state === ACK_STATE_ACKNOWLEDGED;
}

/**
 * ¿Intentar Publisher `:acknowledge`?
 * La decisión se basa en el estado de Google, no en el flag local.
 * Si Google ya está ACKNOWLEDGED, no repetir.
 */
export function canAcknowledgeAfterPersist(params) {
  if (!params.persisted) return false;
  if (params.founderBlocked) return false;
  if (!params.grantsPro) return false;
  if (Object.prototype.hasOwnProperty.call(params, "googleAckState")) {
    if (isGoogleAcknowledgementConfirmed(params.googleAckState)) return false;
    return true;
  }
  // Compat: callers legacy sin googleAckState.
  if (params.alreadyAcknowledged) return false;
  return true;
}

/**
 * Resultado determinista del reconocimiento servidor (máx. 1 ack + 1 verify por request).
 *
 * acknowledgeHttpOk / verifyOk / persistAckFlagOk:
 *   true | false | null (null = paso no ejecutado).
 */
export function resolveAcknowledgementResult(params) {
  const initialConfirmed = isGoogleAcknowledgementConfirmed(
    params.initialAckState,
  );

  if (initialConfirmed && params.acknowledgeHttpOk == null) {
    if (params.persistAckFlagOk === false) {
      return {
        acknowledged: false,
        acknowledgePending: true,
        reason: "ack_persist_failed",
      };
    }
    return {
      acknowledged: true,
      acknowledgePending: false,
      reason: "already_acknowledged_on_google",
    };
  }

  if (params.acknowledgeHttpOk === false) {
    return {
      acknowledged: false,
      acknowledgePending: true,
      reason: "acknowledge_http_failed",
    };
  }

  if (params.acknowledgeHttpOk == null && !initialConfirmed) {
    return {
      acknowledged: false,
      acknowledgePending: false,
      reason: "acknowledge_skipped",
    };
  }

  // Tras :acknowledge (o necesidad de verify), hace falta evidencia de Google.
  if (params.verifyOk !== true) {
    return {
      acknowledged: false,
      acknowledgePending: true,
      reason: params.verifyOk === false ? "verify_get_failed" : "verify_missing",
    };
  }

  if (isGoogleAcknowledgementConfirmed(params.verifiedAckState)) {
    if (params.persistAckFlagOk === false) {
      return {
        acknowledged: false,
        acknowledgePending: true,
        reason: "ack_persist_failed",
      };
    }
    return {
      acknowledged: true,
      acknowledgePending: false,
      reason: "verified_acknowledged",
    };
  }

  return {
    acknowledged: false,
    acknowledgePending: true,
    reason: "ack_unconfirmed",
  };
}

export function sanitizePurchasePayload(purchase) {
  return {
    kind: purchase.kind ?? null,
    startTime: purchase.startTime ?? null,
    regionCode: purchase.regionCode ?? null,
    subscriptionState: purchase.subscriptionState ?? null,
    latestOrderId: purchase.latestOrderId ?? null,
    linkedPurchaseToken: purchase.linkedPurchaseToken ?? null,
    acknowledgementState: purchase.acknowledgementState ?? null,
    canceledStateContext: purchase.canceledStateContext ?? null,
    lineItems: purchase.lineItems ?? [],
    testPurchase: purchase.testPurchase ? { present: true } : null,
  };
}
