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
) {
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
            notification: { channel_id: "convocatorias" },
          },
        },
      }),
    },
  );

  if (!res.ok) {
    const err = await res.text();
    console.error(`FCM error for token ${token.slice(0, 8)}…: ${err}`);
  }
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

    const supabaseAdmin = createClient(supabaseUrl, serviceRole);
    const { data: callerProfile } = await supabaseAdmin
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

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

    const isOrganizer =
      callerProfile?.role === "organizer" ||
      callerProfile?.role === "organizador";

    if (!isOrganizer) {
      const partidoId = Number(player_notify_partido_id);
      if (!partidoId || !Array.isArray(user_ids) || user_ids.length !== 1) {
        return new Response(
          JSON.stringify({ error: "Solo el organizador puede enviar push" }),
          {
            status: 403,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        );
      }

      const notifyType = player_notify_type ?? "convocatoria_respuesta";

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
      const targetId = user_ids[0] as string;

      const { data: targetProfile } = await supabaseAdmin
        .from("profiles")
        .select("id, role, activo")
        .eq("id", targetId)
        .maybeSingle();

      const targetIsOrganizer =
        targetProfile?.role === "organizer" ||
        targetProfile?.role === "organizador";

      if (!targetProfile || !targetIsOrganizer || targetProfile.activo === false) {
        return new Response(
          JSON.stringify({
            error: "Solo puedes notificar al organizador del partido",
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
            error: "Solo puedes notificar al organizador del partido",
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

    const tokens = (profiles ?? [])
      .map((p) => p.fcm_token as string | null)
      .filter((t): t is string => !!t && t.length > 0);

    if (tokens.length === 0) {
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

    let sent = 0;
    for (const token of tokens) {
      await sendFcm(
        accessToken,
        sa.project_id,
        token,
        title ?? "MatchPay",
        body ?? "",
        stringData,
      );
      sent++;
    }

    return new Response(JSON.stringify({ sent }), {
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
