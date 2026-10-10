import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  fetchGoogleAccessToken,
  parseServiceAccountJson,
} from "./google_auth.ts";
import {
  canAcknowledgeAfterPersist,
  isGoogleAcknowledgementConfirmed,
  PACKAGE_NAME,
  parseValidateRequestBody,
  PRODUCT_FOUNDER_ANNUAL,
  resolveAcknowledgementResult,
  resolveRevokedAt,
  resolveTokenBinding,
  sanitizePurchasePayload,
  validateProductAgainstGoogle,
} from "./logic.mjs";
import {
  acknowledgeSubscription,
  getSubscriptionPurchaseV2,
} from "./play_api.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !anonKey || !serviceKey) {
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ ok: false, error: "unauthorized" }, 401);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return jsonResponse({ ok: false, error: "unauthorized" }, 401);
    }

    let bodyUnknown: unknown;
    try {
      bodyUnknown = await req.json();
    } catch {
      return jsonResponse({ ok: false, error: "invalid_request" }, 400);
    }

    const parsed = parseValidateRequestBody(bodyUnknown);
    if (!parsed.ok) {
      return jsonResponse({ ok: false, error: parsed.error }, 400);
    }

    const { purchase_token, product_id } = parsed.value;
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // --- Token binding (pre-check) ---
    const { data: existingPurchase, error: existingErr } = await admin
      .from("billing_purchases")
      .select("user_id, acknowledged")
      .eq("purchase_token", purchase_token)
      .maybeSingle();

    if (existingErr) {
      console.error("billing_purchases select failed");
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    const binding = resolveTokenBinding({
      existingUserId: (existingPurchase?.user_id as string | undefined) ?? null,
      requestUserId: user.id,
    });
    if (binding === "token_bound_to_other_user") {
      return jsonResponse({ ok: false, error: "token_bound_to_other_user" }, 409);
    }

    // --- Google Play auth + validation ---
    const sa = parseServiceAccountJson(
      Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"),
    );
    if (!sa) {
      console.error("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON missing or invalid");
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    let accessToken: string;
    try {
      accessToken = await fetchGoogleAccessToken(sa);
    } catch (e) {
      console.error("google access token failed", e instanceof Error ? e.message : "error");
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    const googleResult = await getSubscriptionPurchaseV2({
      accessToken,
      purchaseToken: purchase_token,
      packageName: PACKAGE_NAME,
    });
    if (!googleResult.ok) {
      return jsonResponse(
        { ok: false, error: "google_play_validation_failed" },
        502,
      );
    }

    // deno-lint-ignore no-explicit-any
    const googlePurchase = googleResult.purchase as any;

    const mapped = validateProductAgainstGoogle({
      requestedProductId: product_id,
      purchase: googlePurchase,
      nowMs: Date.now(),
    });
    if (!mapped.ok) {
      const status = mapped.error === "product_mismatch" ? 409 : 400;
      return jsonResponse({ ok: false, error: mapped.error }, status);
    }

    const mappedPurchase = mapped.value;
    const nowIso = new Date().toISOString();

    // --- Founder atomic claim (only when granting Founder access) ---
    let founderBlocked = false;
    let founderClaimNumber: number | null = null;
    if (
      product_id === PRODUCT_FOUNDER_ANNUAL &&
      mappedPurchase.grantsPro
    ) {
      const { data: claimRows, error: claimErr } = await admin.rpc(
        "claim_founder_entitlement",
        {
          p_user_id: user.id,
          p_purchase_token: purchase_token,
        },
      );

      if (claimErr) {
        console.error("claim_founder_entitlement rpc failed");
        return jsonResponse({ ok: false, error: "internal_error" }, 500);
      }

      const claim = Array.isArray(claimRows) ? claimRows[0] : claimRows;
      const claimOk = claim?.ok === true;
      const errorCode = (claim?.error_code as string | null) ?? null;

      if (!claimOk) {
        if (errorCode === "founder_sold_out") {
          founderBlocked = true;
          return jsonResponse({ ok: false, error: "founder_sold_out" }, 409);
        }
        if (
          errorCode === "founder_already_claimed" ||
          errorCode === "founder_token_taken"
        ) {
          return jsonResponse({ ok: false, error: errorCode }, 409);
        }
        console.error("claim_founder_entitlement rejected", errorCode);
        return jsonResponse({ ok: false, error: "internal_error" }, 500);
      }
      founderClaimNumber = typeof claim?.claim_number === "number"
        ? claim.claim_number
        : null;
    }

    // Flag local solo refleja reconocimiento confirmado por Google (no el flag previo).
    const initialAckState = mappedPurchase.acknowledgementState ?? null;
    const googleAckConfirmedInitially =
      isGoogleAcknowledgementConfirmed(initialAckState);
    if (
      existingPurchase?.acknowledged === true &&
      !googleAckConfirmedInitially
    ) {
      console.error("ack_reconcile_local_flag", {
        google_state: initialAckState ?? "absent",
      });
    }

    // --- Persist purchase ledger ---
    const purchaseRow = {
      user_id: user.id,
      purchase_token,
      product_id: mappedPurchase.productId,
      purchase_state: mappedPurchase.status,
      order_id: mappedPurchase.orderId,
      package_name: PACKAGE_NAME,
      purchase_time: mappedPurchase.startsAt,
      expires_at: mappedPurchase.expiresAt,
      auto_renewing: mappedPurchase.autoRenewing,
      acknowledged: googleAckConfirmedInitially,
      obfuscated_account_id:
        googlePurchase.externalAccountIdentifiers
          ?.obfuscatedExternalAccountId ?? null,
      raw_payload: sanitizePurchasePayload(googlePurchase),
      updated_at: nowIso,
      last_verified_at: nowIso,
    };

    const { error: upsertPurchaseErr } = await admin
      .from("billing_purchases")
      .upsert(purchaseRow, { onConflict: "purchase_token" });

    if (upsertPurchaseErr) {
      console.error("billing_purchases upsert failed");
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    // --- Upsert commercial subscription (one per user) ---
    const { data: existingSub, error: existingSubErr } = await admin
      .from("billing_subscriptions")
      .select("revoked_at")
      .eq("user_id", user.id)
      .maybeSingle();

    if (existingSubErr) {
      console.error("billing_subscriptions select failed");
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    const revokedAt = resolveRevokedAt({
      mappedStatus: mappedPurchase.status,
      existingRevokedAt:
        (existingSub?.revoked_at as string | null | undefined) ?? null,
      nowIso,
    });

    const subscriptionRow = {
      user_id: user.id,
      purchase_token,
      product_id: mappedPurchase.productId,
      base_plan: mappedPurchase.basePlan,
      status: mappedPurchase.status,
      starts_at: mappedPurchase.startsAt,
      expires_at: mappedPurchase.expiresAt,
      auto_renewing: mappedPurchase.autoRenewing,
      is_trial: mappedPurchase.isTrial,
      is_founder: mappedPurchase.isFounder && mappedPurchase.grantsPro,
      revoked_at: revokedAt,
      last_verified_at: nowIso,
      updated_at: nowIso,
    };

    const { error: upsertSubErr } = await admin
      .from("billing_subscriptions")
      .upsert(subscriptionRow, { onConflict: "user_id" });

    if (upsertSubErr) {
      console.error("billing_subscriptions upsert failed");
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    // --- Server acknowledgement (máx. 1 :acknowledge + 1 re-get) ---
    let acknowledgeHttpOk: boolean | null = null;
    let verifyOk: boolean | null = null;
    let verifiedAckState: string | null = null;
    // deno-lint-ignore no-explicit-any
    let verifiedPurchase: any = null;
    let persistAckFlagOk: boolean | null = null;

    const shouldAck = canAcknowledgeAfterPersist({
      persisted: true,
      grantsPro: mappedPurchase.grantsPro,
      founderBlocked,
      googleAckState: initialAckState,
    });

    if (googleAckConfirmedInitially) {
      persistAckFlagOk = true; // ya escrito en upsert
    } else if (shouldAck) {
      const ack = await acknowledgeSubscription({
        accessToken,
        productId: mappedPurchase.productId,
        purchaseToken: purchase_token,
        packageName: PACKAGE_NAME,
      });
      acknowledgeHttpOk = ack.ok;
      if (ack.ok) {
        const verify = await getSubscriptionPurchaseV2({
          accessToken,
          purchaseToken: purchase_token,
          packageName: PACKAGE_NAME,
        });
        verifyOk = verify.ok;
        if (verify.ok) {
          verifiedPurchase = verify.purchase;
          verifiedAckState =
            typeof verify.purchase.acknowledgementState === "string"
              ? verify.purchase.acknowledgementState
              : null;
        } else {
          console.error("ack_verify_get_failed", {
            status: verify.status,
          });
        }
      } else {
        console.error("acknowledge_http_failed", {
          status: ack.status,
        });
      }
    }

    let ackOutcome = resolveAcknowledgementResult({
      initialAckState,
      acknowledgeHttpOk,
      verifyOk,
      verifiedAckState,
      persistAckFlagOk,
    });

    // Persistencia post-verify: flag + raw_payload del snapshot verificado.
    if (
      ackOutcome.reason === "verified_acknowledged" &&
      verifiedPurchase != null
    ) {
      const { error: ackUpdateErr } = await admin
        .from("billing_purchases")
        .update({
          acknowledged: true,
          raw_payload: sanitizePurchasePayload(verifiedPurchase),
          updated_at: nowIso,
          last_verified_at: nowIso,
        })
        .eq("purchase_token", purchase_token)
        .eq("user_id", user.id);
      if (ackUpdateErr) {
        console.error("billing_purchases ack flag update failed");
        persistAckFlagOk = false;
        ackOutcome = resolveAcknowledgementResult({
          initialAckState,
          acknowledgeHttpOk,
          verifyOk,
          verifiedAckState,
          persistAckFlagOk: false,
        });
      } else {
        persistAckFlagOk = true;
      }
    } else if (
      ackOutcome.acknowledgePending &&
      !googleAckConfirmedInitially &&
      existingPurchase?.acknowledged === true
    ) {
      // Reconciliar flag local obsoleto (Google sigue PENDING / no confirmado).
      const { error: reconcileErr } = await admin
        .from("billing_purchases")
        .update({
          acknowledged: false,
          updated_at: nowIso,
          last_verified_at: nowIso,
        })
        .eq("purchase_token", purchase_token)
        .eq("user_id", user.id);
      if (reconcileErr) {
        console.error("billing_purchases ack reconcile failed");
      }
    } else if (
      ackOutcome.reason === "ack_unconfirmed" &&
      verifiedPurchase != null
    ) {
      // Actualizar snapshot post-ack sin afirmar reconocimiento.
      const { error: pendingPayloadErr } = await admin
        .from("billing_purchases")
        .update({
          acknowledged: false,
          raw_payload: sanitizePurchasePayload(verifiedPurchase),
          updated_at: nowIso,
          last_verified_at: nowIso,
        })
        .eq("purchase_token", purchase_token)
        .eq("user_id", user.id);
      if (pendingPayloadErr) {
        console.error("billing_purchases pending ack payload update failed");
      }
    }

    if (ackOutcome.acknowledgePending) {
      console.error("ack_pending", { reason: ackOutcome.reason });
    }

    const acknowledged = ackOutcome.acknowledged;
    const acknowledgePending = ackOutcome.acknowledgePending;

    // Entitlement from central RPC (same truth FeatureGate will use later).
    const { data: entitlementRows, error: entitlementErr } = await userClient
      .rpc("get_my_billing_entitlement");

    if (entitlementErr) {
      console.error("get_my_billing_entitlement failed");
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    const entitlement = Array.isArray(entitlementRows)
      ? entitlementRows[0] ?? null
      : entitlementRows;

    return jsonResponse(
      {
        ok: true,
        entitlement: entitlement
          ? {
            is_pro: entitlement.is_pro === true,
            source: entitlement.source ?? "none",
            status: entitlement.status ?? null,
            product_id: entitlement.product_id ?? null,
            expires_at: entitlement.expires_at ?? null,
            is_trial: entitlement.is_trial === true,
            is_founder: entitlement.is_founder === true,
            auto_renewing: entitlement.auto_renewing ?? null,
            last_verified_at: entitlement.last_verified_at ?? null,
          }
          : null,
        acknowledged,
        acknowledge_pending: acknowledgePending,
        founder_claim_number: founderClaimNumber,
      },
      200,
    );
  } catch (e) {
    console.error(
      "validate-play-purchase",
      e instanceof Error ? e.message : "error",
    );
    return jsonResponse({ ok: false, error: "internal_error" }, 500);
  }
});
