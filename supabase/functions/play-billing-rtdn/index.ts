import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  fetchGoogleAccessToken,
  parseServiceAccountJson,
} from "./google_auth.ts";
import { authorizeRtdnRequest } from "./pubsub_oidc.mjs";
import { getSubscriptionPurchaseV2 } from "./play_api.ts";
import { processAuthorizedRtdnBody } from "./rtdn_process.mjs";

/**
 * Google Play Real-time Developer Notifications (RTDN) via Pub/Sub push.
 *
 * Auth: Google Pub/Sub Push OIDC JWT (Bearer), verified with Google JWKS.
 * verify_jwt=false — la función valida OIDC explícitamente.
 * Does not grant Pro from the notification alone — re-verifies with Google
 * and updates billing_* for the user already bound to the purchase_token.
 */

function jsonResponse(
  body: Record<string, unknown>,
  status: number,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function envMap(): Record<string, string | undefined> {
  return {
    PLAY_BILLING_RTDN_OIDC_EMAIL: Deno.env.get("PLAY_BILLING_RTDN_OIDC_EMAIL"),
    PLAY_BILLING_RTDN_OIDC_AUDIENCE: Deno.env.get(
      "PLAY_BILLING_RTDN_OIDC_AUDIENCE",
    ),
    PLAY_BILLING_RTDN_ALLOW_STATIC_BEARER: Deno.env.get(
      "PLAY_BILLING_RTDN_ALLOW_STATIC_BEARER",
    ),
    PLAY_BILLING_RTDN_SECRET: Deno.env.get("PLAY_BILLING_RTDN_SECRET"),
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "method_not_allowed" }, 405);
  }

  const auth = await authorizeRtdnRequest(req, envMap());
  if (!auth.ok) {
    return jsonResponse({ ok: false, error: "unauthorized" }, auth.status ?? 401);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceKey) {
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    let bodyUnknown: unknown;
    try {
      bodyUnknown = await req.json();
    } catch {
      return jsonResponse({ ok: false, error: "invalid_request" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

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
      console.error(
        "google access token failed",
        e instanceof Error ? e.message : "error",
      );
      return jsonResponse({ ok: false, error: "internal_error" }, 500);
    }

    const result = await processAuthorizedRtdnBody(bodyUnknown, {
      lookupPurchase: async (purchaseToken) => {
        const { data, error } = await admin
          .from("billing_purchases")
          .select("user_id, product_id, acknowledged")
          .eq("purchase_token", purchaseToken)
          .maybeSingle();
        if (error) throw error;
        if (!data?.user_id) return data;
        const { data: sub, error: subErr } = await admin
          .from("billing_subscriptions")
          .select("revoked_at")
          .eq("user_id", data.user_id)
          .maybeSingle();
        if (subErr) throw subErr;
        return {
          ...data,
          revoked_at: (sub?.revoked_at as string | null | undefined) ?? null,
        };
      },
      getSubscriptionPurchaseV2: (params) =>
        getSubscriptionPurchaseV2({
          accessToken,
          purchaseToken: params.purchaseToken,
          packageName: params.packageName,
        }),
      upsertPurchase: async (row) => {
        const { error } = await admin
          .from("billing_purchases")
          .upsert(row, { onConflict: "purchase_token" });
        return { error };
      },
      upsertSubscription: async (row) => {
        const { error } = await admin
          .from("billing_subscriptions")
          .upsert(row, { onConflict: "user_id" });
        return { error };
      },
    });

    return jsonResponse(result.body, result.status);
  } catch (e) {
    console.error(
      "play-billing-rtdn",
      e instanceof Error ? e.message : "error",
    );
    return jsonResponse({ ok: false, error: "internal_error" }, 500);
  }
});
