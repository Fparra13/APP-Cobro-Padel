import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function base64UrlEncode(data: string): string {
  return btoa(data)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const payload = base64UrlEncode(JSON.stringify(claim));

  const toSign = `${header}.${payload}`;

  const pem = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binary = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(toSign),
  );

  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const jwt = `${toSign}.${sigB64}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const tokenJson = await tokenRes.json();
  if (!tokenJson.access_token) {
    throw new Error(`OAuth error: ${JSON.stringify(tokenJson)}`);
  }
  return tokenJson.access_token as string;
}

async function sendFcm(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<{ ok: boolean; error?: string; invalidToken?: boolean }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "HIGH",
            notification: {
              channel_id: "kloovi_convocatorias_v2",
              default_sound: true,
              notification_priority: "PRIORITY_HIGH",
            },
          },
        },
      }),
    },
  );

  if (!res.ok) {
    const err = await res.text();
    console.error(`FCM error for token ${token.slice(0, 8)}…: ${err}`);
    // Solo limpiar tokens muertos. INVALID_ARGUMENT genérico puede ser
    // payload/canal y no debe borrar tokens válidos.
    const invalidToken =
      /UNREGISTERED|SENDER_ID_MISMATCH|registration.?token/i.test(err);
    return { ok: false, error: err, invalidToken };
  }
  return { ok: true };
}

async function clearDeadFcmToken(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  reason: string,
): Promise<void> {
  console.error(`Clearing fcm_token for ${userId}: ${reason.slice(0, 200)}`);
  await supabaseAdmin
    .from("profiles")
    .update({
      fcm_token: null,
      fcm_register_error: `cleared_by_send_push:${reason.slice(0, 180)}`,
      fcm_last_push_at: new Date().toISOString(),
      fcm_last_push_ok: false,
      fcm_last_push_detail: `cleared:${reason.slice(0, 300)}`,
    })
    .eq("id", userId);
}

async function recordPushResult(
  supabaseAdmin: ReturnType<typeof createClient>,
  userId: string,
  ok: boolean,
  detail: string,
): Promise<void> {
  await supabaseAdmin
    .from("profiles")
    .update({
      fcm_last_push_at: new Date().toISOString(),
      fcm_last_push_ok: ok,
      fcm_last_push_detail: detail.slice(0, 400),
    })
    .eq("id", userId);
}

type ProfileToken = { id: string; token: string };

async function sendToProfiles(
  supabaseAdmin: ReturnType<typeof createClient>,
  profiles: Array<{ id: string; fcm_token: string | null }>,
  accessToken: string,
  projectId: string,
  title: string,
  body: string,
  stringData: Record<string, string>,
): Promise<{
  sent: number;
  failed: number;
  cleared: number;
  results: Array<{
    user_id: string;
    ok: boolean;
    error?: string;
    cleared?: boolean;
  }>;
}> {
  const targets: ProfileToken[] = [];
  for (const p of profiles) {
    const token = (p.fcm_token ?? "").trim();
    if (token) targets.push({ id: p.id, token });
  }

  let sent = 0;
  let failed = 0;
  let cleared = 0;
  const results: Array<{
    user_id: string;
    ok: boolean;
    error?: string;
    cleared?: boolean;
  }> = [];

  for (const t of targets) {
    const result = await sendFcm(
      accessToken,
      projectId,
      t.token,
      title,
      body,
      stringData,
    );
    if (result.ok) {
      sent++;
      await recordPushResult(supabaseAdmin, t.id, true, "fcm_accepted");
      results.push({ user_id: t.id, ok: true });
      continue;
    }
    failed++;
    let didClear = false;
    if (result.invalidToken) {
      await clearDeadFcmToken(supabaseAdmin, t.id, result.error ?? "invalid");
      cleared++;
      didClear = true;
    } else {
      await recordPushResult(
        supabaseAdmin,
        t.id,
        false,
        (result.error ?? "fcm_error").slice(0, 400),
      );
    }
    results.push({
      user_id: t.id,
      ok: false,
      error: (result.error ?? "").slice(0, 300),
      cleared: didClear,
    });
  }

  return { sent, failed, cleared, results };
}

async function playerBelongsToPartido(
  supabaseAdmin: ReturnType<typeof createClient>,
  partidoId: number,
  userId: string,
  userEmail: string | undefined,
): Promise<boolean> {
  const { data: membership } = await supabaseAdmin
    .from("convocatoria_jugadores")
    .select("id")
    .eq("partido_id", partidoId)
    .eq("jugador_id", userId)
    .maybeSingle();
  if (membership) return true;

  const { data: detalle } = await supabaseAdmin
    .from("detalles_partido")
    .select("id")
    .eq("partido_id", partidoId)
    .eq("jugador_id", userId)
    .maybeSingle();
  if (detalle) return true;

  if (!userEmail) return false;

  const normalized = userEmail.toLowerCase().trim();
  const { data: profiles } = await supabaseAdmin
    .from("profiles")
    .select("id")
    .or(`email.eq.${normalized},telefono.eq.${normalized}`);

  const profileIds = (profiles ?? []).map((p) => p.id as string);
  if (profileIds.length === 0) return false;

  const { data: cj } = await supabaseAdmin
    .from("convocatoria_jugadores")
    .select("id")
    .eq("partido_id", partidoId)
    .in("jugador_id", profileIds)
    .limit(1)
    .maybeSingle();
  if (cj) return true;

  const { data: dp } = await supabaseAdmin
    .from("detalles_partido")
    .select("id")
    .eq("partido_id", partidoId)
    .in("jugador_id", profileIds)
    .limit(1)
    .maybeSingle();
  if (dp) return true;

  // Convocatoria vinculada por email aunque jugador_id no esté relinked aún.
  const { data: cjByEmail } = await supabaseAdmin
    .from("convocatoria_jugadores")
    .select("id, profiles!inner(email, telefono)")
    .eq("partido_id", partidoId);
  for (const row of cjByEmail ?? []) {
    const profile = row.profiles as { email?: string; telefono?: string } | null;
    if (!profile) continue;
    const email = (profile.email ?? "").toLowerCase().trim();
    const tel = (profile.telefono ?? "").toLowerCase().trim();
    if (email === normalized || tel === normalized) return true;
  }

  return false;
}

async function resolveOrganizadorId(
  supabaseAdmin: ReturnType<typeof createClient>,
  partidoId: number,
): Promise<string | null> {
  const { data: partido } = await supabaseAdmin
    .from("partidos")
    .select("organizador_id")
    .eq("id", partidoId)
    .single();

  const orgId = partido?.organizador_id as string | null;
  if (orgId) return orgId;

  const { data: orgProfile } = await supabaseAdmin
    .from("profiles")
    .select("id")
    .in("role", ["organizer", "organizador"])
    .eq("activo", true)
    .limit(1)
    .maybeSingle();
  return (orgProfile?.id as string | null) ?? null;
}

/**
 * C4: un organizador solo puede pushear a:
 * - sí mismo
 * - jugadores de su roster (organizador_jugadores; incluye soft-leave con deuda)
 * - jugadores de sus partidos (convocatoria_jugadores / detalles_partido)
 * Cualquier UUID fuera de ese conjunto → rechazo (no se filtra en silencio).
 */
async function assertOrganizerMayNotify(
  supabaseAdmin: ReturnType<typeof createClient>,
  organizerId: string,
  requestedIds: string[],
): Promise<{ ok: true; ids: string[] } | { ok: false; rejected: string[] }> {
  const unique = [
    ...new Set(
      requestedIds
        .map((id) => String(id ?? "").trim())
        .filter((id) => id.length > 0),
    ),
  ];
  if (unique.length === 0) return { ok: true, ids: [] };

  const allowed = new Set<string>();
  if (unique.includes(organizerId)) allowed.add(organizerId);

  const pending = () => unique.filter((id) => !allowed.has(id));

  let remaining = pending();
  if (remaining.length > 0) {
    const { data: oj } = await supabaseAdmin
      .from("organizador_jugadores")
      .select("jugador_id")
      .eq("organizador_id", organizerId)
      .in("jugador_id", remaining);
    for (const row of oj ?? []) {
      const jid = row.jugador_id as string;
      if (jid) allowed.add(jid);
    }
  }

  remaining = pending();
  if (remaining.length > 0) {
    const { data: partidos } = await supabaseAdmin
      .from("partidos")
      .select("id")
      .eq("organizador_id", organizerId);
    const partidoIds = (partidos ?? []).map((p) => p.id as number);
    if (partidoIds.length > 0) {
      const { data: cj } = await supabaseAdmin
        .from("convocatoria_jugadores")
        .select("jugador_id")
        .in("partido_id", partidoIds)
        .in("jugador_id", remaining);
      for (const row of cj ?? []) {
        const jid = row.jugador_id as string;
        if (jid) allowed.add(jid);
      }

      remaining = pending();
      if (remaining.length > 0) {
        const { data: dp } = await supabaseAdmin
          .from("detalles_partido")
          .select("jugador_id")
          .in("partido_id", partidoIds)
          .in("jugador_id", remaining);
        for (const row of dp ?? []) {
          const jid = row.jugador_id as string;
          if (jid) allowed.add(jid);
        }
      }
    }
  }

  const rejected = pending();
  if (rejected.length > 0) return { ok: false, rejected };
  return { ok: true, ids: unique };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No autorizado" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const cronSecret = Deno.env.get("REMINDERS_CRON_SECRET") ??
      Deno.env.get("PURGE_CRON_SECRET") ??
      "";
    const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");

    if (!saJson) {
      return new Response(
        JSON.stringify({ error: "FIREBASE_SERVICE_ACCOUNT no configurado" }),
        {
          status: 503,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const bearer = authHeader.startsWith("Bearer ")
      ? authHeader.slice(7)
      : "";
    const isInternal =
      bearer === serviceRole ||
      (cronSecret.length > 0 && bearer === cronSecret);

    const supabaseAdmin = createClient(supabaseUrl, serviceRole);
    const bodyJson = await req.json();
    const {
      user_ids,
      title,
      body,
      data,
      player_notify_partido_id,
      player_notify_type,
      player_notify_detalle_id,
    } = bodyJson;

    // Worker / cron: omitir autorización de organizador.
    if (isInternal) {
      if (!Array.isArray(user_ids) || user_ids.length === 0) {
        return new Response(JSON.stringify({ error: "user_ids requerido" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }

      const { data: profiles } = await supabaseAdmin
        .from("profiles")
        .select("id, fcm_token")
        .in("id", user_ids);

      const withToken = (profiles ?? []).filter(
        (p) => !!((p.fcm_token as string | null) ?? "").trim(),
      );
      if (withToken.length === 0) {
        return new Response(
          JSON.stringify({ sent: 0, message: "Sin tokens FCM registrados" }),
          {
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const sa: ServiceAccount = JSON.parse(saJson);
      const accessToken = await getGoogleAccessToken(sa);
      const stringData: Record<string, string> = {};
      for (const [k, v] of Object.entries(data ?? {})) {
        stringData[k] = String(v);
      }

      const out = await sendToProfiles(
        supabaseAdmin,
        withToken as Array<{ id: string; fcm_token: string | null }>,
        accessToken,
        sa.project_id,
        title ?? "Kloovi",
        body ?? "",
        stringData,
      );

      return new Response(JSON.stringify(out), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const supabaseUser = createClient(supabaseUrl, supabaseAnon, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await supabaseUser.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "Sesión inválida" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: callerProfile } = await supabaseAdmin
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    const isOrganizer =
      callerProfile?.role === "organizer" ||
      callerProfile?.role === "organizador";

    // Cualquier usuario autenticado puede enviarse un push de prueba a sí mismo.
    const isSelfTest =
      Array.isArray(user_ids) &&
      user_ids.length === 1 &&
      user_ids[0] === user.id;

    if (!isOrganizer && !isSelfTest) {
      if (!Array.isArray(user_ids) || user_ids.length !== 1) {
        return new Response(
          JSON.stringify({ error: "Solo el organizador puede enviar push" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const notifyType = player_notify_type ?? "convocatoria_respuesta";
      const targetId = user_ids[0] as string;

      if (notifyType === "grupo_join") {
        const { data: link } = await supabaseAdmin
          .from("organizador_jugadores")
          .select("id")
          .eq("organizador_id", targetId)
          .eq("jugador_id", user.id)
          .eq("activo", true)
          .maybeSingle();

        if (!link) {
          return new Response(
            JSON.stringify({ error: "No perteneces a este grupo" }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        const { data: targetProfile } = await supabaseAdmin
          .from("profiles")
          .select("id, role, activo")
          .eq("id", targetId)
          .maybeSingle();

        const targetIsOrganizer =
          targetProfile?.role === "organizer" ||
          targetProfile?.role === "organizador";

        if (
          !targetProfile ||
          !targetIsOrganizer ||
          targetProfile.activo === false
        ) {
          return new Response(
            JSON.stringify({ error: "Destinatario no es organizador" }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      } else {
        const partidoId = Number(player_notify_partido_id);
        if (!partidoId) {
          return new Response(
            JSON.stringify({ error: "Solo el organizador puede enviar push" }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        if (notifyType === "comprobante") {
          const detalleId = Number(player_notify_detalle_id);
          if (!detalleId) {
            return new Response(
              JSON.stringify({ error: "detalle_id requerido" }),
              {
                status: 400,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              },
            );
          }

          const { data: detalle } = await supabaseAdmin
            .from("detalles_partido")
            .select("id, partido_id, jugador_id")
            .eq("id", detalleId)
            .eq("jugador_id", user.id)
            .maybeSingle();

          let comprobanteOk = !!detalle && detalle.partido_id === partidoId;

          if (!comprobanteOk && user.email) {
            const normalized = user.email.toLowerCase().trim();
            const { data: profiles } = await supabaseAdmin
              .from("profiles")
              .select("id")
              .or(`email.eq.${normalized},telefono.eq.${normalized}`);
            const profileIds = (profiles ?? []).map((p) => p.id as string);
            if (profileIds.length > 0) {
              const { data: byEmail } = await supabaseAdmin
                .from("detalles_partido")
                .select("id, partido_id")
                .eq("id", detalleId)
                .in("jugador_id", profileIds)
                .maybeSingle();
              comprobanteOk =
                !!byEmail && byEmail.partido_id === partidoId;
            }
          }

          if (!comprobanteOk) {
            return new Response(
              JSON.stringify({ error: "Comprobante no válido" }),
              {
                status: 403,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              },
            );
          }
        } else {
          const allowed = await playerBelongsToPartido(
            supabaseAdmin,
            partidoId,
            user.id,
            user.email ?? undefined,
          );

          if (!allowed) {
            return new Response(
              JSON.stringify({ error: "No perteneces a esta convocatoria" }),
              {
                status: 403,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
              },
            );
          }
        }

        const orgId = await resolveOrganizadorId(supabaseAdmin, partidoId);

        const { data: targetProfile } = await supabaseAdmin
          .from("profiles")
          .select("id, role, activo")
          .eq("id", targetId)
          .maybeSingle();

        const targetIsOrganizer =
          targetProfile?.role === "organizer" ||
          targetProfile?.role === "organizador";

        if (
          !targetProfile ||
          !targetIsOrganizer ||
          targetProfile.activo === false
        ) {
          return new Response(
            JSON.stringify({
              error: "Solo puedes notificar al organizador del encuentro",
            }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }

        if (orgId && targetId !== orgId) {
          return new Response(
            JSON.stringify({
              error: "Solo puedes notificar al organizador del encuentro",
            }),
            {
              status: 403,
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            },
          );
        }
      }
    }

    // C4: organizador no puede apuntar a UUIDs fuera de su roster/encuentros.
    if (isOrganizer && !isSelfTest) {
      if (!Array.isArray(user_ids) || user_ids.length === 0) {
        return new Response(JSON.stringify({ error: "user_ids requerido" }), {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const gate = await assertOrganizerMayNotify(
        supabaseAdmin,
        user.id,
        user_ids as string[],
      );
      if (!gate.ok) {
        return new Response(
          JSON.stringify({
            error: "Destinatarios fuera de tu grupo o encuentro",
            rejected_count: gate.rejected.length,
          }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }
    }

    if (!Array.isArray(user_ids) || user_ids.length === 0) {
      return new Response(JSON.stringify({ error: "user_ids requerido" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: profiles } = await supabaseAdmin
      .from("profiles")
      .select("id, fcm_token")
      .in("id", user_ids);

    const withToken = (profiles ?? []).filter(
      (p) => !!((p.fcm_token as string | null) ?? "").trim(),
    );

    if (withToken.length === 0) {
      return new Response(
        JSON.stringify({ sent: 0, message: "Sin tokens FCM registrados" }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const sa: ServiceAccount = JSON.parse(saJson);
    const accessToken = await getGoogleAccessToken(sa);
    const stringData: Record<string, string> = {};
    for (const [k, v] of Object.entries(data ?? {})) {
      stringData[k] = String(v);
    }

    const out = await sendToProfiles(
      supabaseAdmin,
      withToken as Array<{ id: string; fcm_token: string | null }>,
      accessToken,
      sa.project_id,
      title ?? "Kloovi",
      body ?? "",
      stringData,
    );

    return new Response(JSON.stringify(out), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error(e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
