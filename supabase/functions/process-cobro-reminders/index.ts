import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * Worker de recordatorios automáticos de cobro.
 *
 * Idempotencia: claim_cobro_recordatorios_due (SKIP LOCKED + claim_until).
 * Éxito: completar_cobro_recordatorio_envio (solo tras FCM OK).
 * Fallo temporal: reintentar_cobro_recordatorio_backoff (15m → 1h → 6h → freq).
 * Token inválido: diferir_cobro_recordatorio_sin_token (limpia fcm_token).
 *
 * Auth: Bearer service_role | REMINDERS_CRON_SECRET | PURGE_CRON_SECRET
 */

const BATCH = 50;

/** Identificador de esta invocación del worker (logs / carreras). */
const WORKER_INSTANCE_ID = crypto.randomUUID().slice(0, 8);

type ClaimedRow = {
  id: number;
  detalle_partido_id: number;
  partido_id: number;
  organizador_id: string;
  jugador_id: string;
  next_send_at: string;
  ultimo_envio: string | null;
  fail_count: number;
  frecuencia_dias: number;
  timezone: string;
  hora_local: string;
  pendiente: number;
  fcm_token: string | null;
  preferred_locale: string;
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function formatMoney(amount: number, locale: string): string {
  try {
    return new Intl.NumberFormat(
      locale.startsWith("pt")
        ? "pt-BR"
        : locale.startsWith("en")
        ? "en-US"
        : "es-CL",
      {
        style: "currency",
        currency: locale.startsWith("en") ? "USD" : "CLP",
        maximumFractionDigits: 0,
      },
    ).format(amount);
  } catch {
    return `$${Math.round(amount)}`;
  }
}

function reminderCopy(
  locale: string,
  amountLabel: string,
): { title: string; body: string } {
  const lang = (locale || "es").toLowerCase().slice(0, 2);
  if (lang === "en") {
    return {
      title: `Contribution reminder · ${amountLabel}`,
      body:
        `You have ${amountLabel} pending. Open the alert to see how to contribute.`,
    };
  }
  if (lang === "pt") {
    return {
      title: `Lembrete de contribuição · ${amountLabel}`,
      body:
        `Você tem ${amountLabel} pendente. Abra o aviso para ver como contribuir.`,
    };
  }
  return {
    title: `Recordatorio de aporte · ${amountLabel}`,
    body:
      `Tienes ${amountLabel} pendiente. Abre el aviso para ver cómo aportar.`,
  };
}

function isInvalidTokenError(message: string): boolean {
  const m = message.toLowerCase();
  return (
    m.includes("unregistered") ||
    m.includes("not-found") ||
    m.includes("invalid-argument") ||
    m.includes("registration-token-not-registered") ||
    m.includes("requested entity was not found") ||
    m.includes("sin tokens")
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204 });
  }

  const started = Date.now();
  console.log(
    JSON.stringify({
      event: "process-cobro-reminders:start",
      worker: WORKER_INSTANCE_ID,
    }),
  );

  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const cronSecret = Deno.env.get("REMINDERS_CRON_SECRET") ??
    Deno.env.get("PURGE_CRON_SECRET") ??
    "";

  if (!serviceKey || !supabaseUrl) {
    console.error("process-cobro-reminders: missing_env");
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

  const { data: claimed, error: claimErr } = await admin.rpc(
    "claim_cobro_recordatorios_due",
    { p_limit: BATCH },
  );

  if (claimErr) {
    console.error(
      JSON.stringify({
        event: "process-cobro-reminders:claim_error",
        worker: WORKER_INSTANCE_ID,
      }),
    );
    return json({ ok: false, error: claimErr.message }, 500);
  }

  const rows = (claimed ?? []) as ClaimedRow[];
  let sent = 0;
  let retried = 0;
  let deferred = 0;
  let omitted = 0;
  let errors = 0;

  if (rows.length === 0) {
    console.log(
      JSON.stringify({
        event: "process-cobro-reminders:done",
        worker: WORKER_INSTANCE_ID,
        claimed: 0,
        sent: 0,
        retried: 0,
        deferred: 0,
        omitted: 0,
        errors: 0,
        ms: Date.now() - started,
      }),
    );
    return json({
      ok: true,
      worker: WORKER_INSTANCE_ID,
      claimed: 0,
      sent: 0,
      retried: 0,
      deferred: 0,
      omitted: 0,
      errors: 0,
    });
  }

  for (const row of rows) {
    const deliveryId = crypto.randomUUID();
    try {
      const { data: eligible, error: eligErr } = await admin.rpc(
        "cobro_recordatorio_sigue_elegible",
        { p_detalle_id: row.detalle_partido_id },
      );

      if (eligErr) {
        console.error(
          JSON.stringify({
            event: "process-cobro-reminders:elig_error",
            worker: WORKER_INSTANCE_ID,
            recordatorio_id: row.id,
          }),
        );
        await admin.rpc("reintentar_cobro_recordatorio_backoff", {
          p_id: row.id,
        });
        errors++;
        retried++;
        continue;
      }

      if (!eligible) {
        await admin.rpc("liberar_cobro_recordatorio_ineligible", {
          p_id: row.id,
        });
        omitted++;
        continue;
      }

      const token = (row.fcm_token ?? "").trim();
      if (!token) {
        await admin.rpc("diferir_cobro_recordatorio_sin_token", {
          p_id: row.id,
          p_clear_token: false,
        });
        deferred++;
        continue;
      }

      const amount = Number(row.pendiente) || 0;
      const amountLabel = formatMoney(amount, row.preferred_locale || "es");
      const copy = reminderCopy(row.preferred_locale || "es", amountLabel);

      const pushRes = await fetch(`${supabaseUrl}/functions/v1/send-push`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${serviceKey}`,
        },
        body: JSON.stringify({
          user_ids: [row.jugador_id],
          title: copy.title,
          body: copy.body,
          data: {
            type: "cobro_recordatorio_auto",
            partido_id: String(row.partido_id),
            detalle_id: String(row.detalle_partido_id),
            organizador_id: row.organizador_id,
            amount: String(amount),
            delivery_id: deliveryId,
          },
        }),
      });

      const pushJson = await pushRes.json().catch(() => ({})) as {
        sent?: number;
        error?: string;
        results?: Array<{ ok?: boolean; error?: string }>;
        message?: string;
      };

      const firstErr = String(
        pushJson.results?.find((r) => !r.ok)?.error ??
          pushJson.error ??
          pushJson.message ??
          "",
      );
      const sentCount = Number(pushJson.sent ?? 0);

      if (!pushRes.ok || sentCount <= 0) {
        const noTokenMsg = (pushJson.message ?? "").toLowerCase().includes(
          "sin tokens",
        );
        if (isInvalidTokenError(firstErr) || noTokenMsg) {
          await admin.rpc("diferir_cobro_recordatorio_sin_token", {
            p_id: row.id,
            p_clear_token: isInvalidTokenError(firstErr),
          });
          deferred++;
          continue;
        }

        await admin.rpc("reintentar_cobro_recordatorio_backoff", {
          p_id: row.id,
        });
        retried++;
        errors++;
        continue;
      }

      // Solo avanzar schedule tras FCM OK; guarda delivery_id del intento.
      await admin.rpc("completar_cobro_recordatorio_envio", {
        p_id: row.id,
        p_delivery_id: deliveryId,
      });
      sent++;
    } catch (e) {
      console.error(
        JSON.stringify({
          event: "process-cobro-reminders:row_error",
          worker: WORKER_INSTANCE_ID,
          recordatorio_id: row.id,
        }),
      );
      await admin.rpc("reintentar_cobro_recordatorio_backoff", {
        p_id: row.id,
      });
      retried++;
      errors++;
    }
  }

  const summary = {
    event: "process-cobro-reminders:done",
    worker: WORKER_INSTANCE_ID,
    claimed: rows.length,
    sent,
    retried,
    deferred,
    omitted,
    errors,
    ms: Date.now() - started,
  };
  console.log(JSON.stringify(summary));

  return json({
    ok: true,
    worker: WORKER_INSTANCE_ID,
    claimed: rows.length,
    sent,
    retried,
    deferred,
    omitted,
    errors,
  });
});
