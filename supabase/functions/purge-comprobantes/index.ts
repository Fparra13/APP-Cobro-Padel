import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * Purga diaria de comprobantes (pago + gastos) con más de 14 días en Storage.
 * Invocar con Authorization: Bearer <service_role> (pg_cron / pg_net).
 */
const RETENTION_DAYS = 14;
const BUCKET = "comprobantes";
const BATCH = 100;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204 });
  }

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const cronSecret = Deno.env.get("PURGE_CRON_SECRET") ?? "";
  if (!serviceKey || !supabaseUrl) {
    return json({ ok: false, error: "missing_env" }, 500);
  }

  const auth = req.headers.get("Authorization") ?? "";
  const bearer = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  const authorized = bearer === serviceKey ||
    (cronSecret.length > 0 && bearer === cronSecret);
  if (!authorized) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: rows, error: listErr } = await admin.rpc(
    "listar_comprobantes_storage_expirados",
    { p_dias: RETENTION_DAYS },
  );

  if (listErr) {
    console.error("listar_comprobantes_storage_expirados", listErr);
    return json({ ok: false, error: listErr.message }, 500);
  }

  const paths = (rows as { storage_path: string }[] | null)
    ?.map((r) => r.storage_path)
    .filter((p) => typeof p === "string" && p.length > 0) ?? [];

  if (paths.length === 0) {
    return json({ ok: true, deleted: 0, cleaned_refs: 0 });
  }

  let deleted = 0;
  for (let i = 0; i < paths.length; i += BATCH) {
    const chunk = paths.slice(i, i + BATCH);
    const { error: rmErr } = await admin.storage.from(BUCKET).remove(chunk);
    if (rmErr) {
      console.error("storage.remove", rmErr, chunk.length);
      // Sigue limpiando refs de lo que pudo borrar / paths huérfanos en DB.
    } else {
      deleted += chunk.length;
    }
  }

  const { data: cleaned, error: cleanErr } = await admin.rpc(
    "limpiar_refs_comprobantes",
    { p_paths: paths },
  );

  if (cleanErr) {
    console.error("limpiar_refs_comprobantes", cleanErr);
    return json({
      ok: false,
      error: cleanErr.message,
      deleted,
    }, 500);
  }

  return json({
    ok: true,
    deleted,
    paths: paths.length,
    cleaned_refs: cleaned,
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
