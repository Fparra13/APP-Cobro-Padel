import { PACKAGE_NAME } from "./logic.mjs";

const PUBLISHER_BASE =
  "https://androidpublisher.googleapis.com/androidpublisher/v3";

export async function getSubscriptionPurchaseV2(params: {
  accessToken: string;
  purchaseToken: string;
  packageName?: string;
}): Promise<
  | { ok: true; purchase: Record<string, unknown> }
  | { ok: false; status: number; error: "google_play_validation_failed" }
> {
  const packageName = params.packageName ?? PACKAGE_NAME;
  const url =
    `${PUBLISHER_BASE}/applications/${encodeURIComponent(packageName)}` +
    `/purchases/subscriptionsv2/tokens/${encodeURIComponent(params.purchaseToken)}`;

  const response = await fetch(url, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${params.accessToken}`,
      Accept: "application/json",
    },
  });

  if (!response.ok) {
    console.error("subscriptionsv2.get failed", { status: response.status });
    return { ok: false, status: response.status, error: "google_play_validation_failed" };
  }

  const purchase = await response.json() as Record<string, unknown>;
  return { ok: true, purchase };
}

/**
 * Legacy acknowledge endpoint (still required). subscriptionId = product_id.
 * Since May 2025 subscriptionId is optional for add-ons; we still pass product_id.
 */
export async function acknowledgeSubscription(params: {
  accessToken: string;
  productId: string;
  purchaseToken: string;
  packageName?: string;
}): Promise<{ ok: true } | { ok: false; status: number }> {
  const packageName = params.packageName ?? PACKAGE_NAME;
  const url =
    `${PUBLISHER_BASE}/applications/${encodeURIComponent(packageName)}` +
    `/purchases/subscriptions/${encodeURIComponent(params.productId)}` +
    `/tokens/${encodeURIComponent(params.purchaseToken)}:acknowledge`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${params.accessToken}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({}),
  });

  if (!response.ok) {
    console.error("subscriptions.acknowledge failed", { status: response.status });
    return { ok: false, status: response.status };
  }
  return { ok: true };
}
