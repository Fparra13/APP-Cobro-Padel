import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !anonKey || !serviceKey) {
      return new Response(JSON.stringify({ error: "misconfigured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, serviceKey);

    // Antes de borrar: avisar organizadores del grupo (si había vínculo activo).
    try {
      const { data: profile } = await admin
        .from("profiles")
        .select("nombre, preferred_locale")
        .eq("id", user.id)
        .maybeSingle();
      const playerName =
        ((profile?.nombre as string | null) ?? "").trim() || "Participante";

      const { data: links } = await admin
        .from("organizador_jugadores")
        .select("organizador_id")
        .eq("jugador_id", user.id)
        .eq("activo", true);

      const orgIds = [
        ...new Set(
          (links ?? [])
            .map((r) => r.organizador_id as string | null)
            .filter((id): id is string => !!id && id.length > 0),
        ),
      ];

      if (orgIds.length > 0) {
        // Textos por locale del organizador.
        const { data: orgs } = await admin
          .from("profiles")
          .select("id, preferred_locale, fcm_token")
          .in("id", orgIds);

        const byLang = new Map<string, string[]>();
        for (const org of orgs ?? []) {
          const token = ((org.fcm_token as string | null) ?? "").trim();
          if (!token) continue;
          const lang =
            ((org.preferred_locale as string | null) ?? "es")
              .split("_")[0]
              .toLowerCase() || "es";
          byLang.set(lang, [...(byLang.get(lang) ?? []), org.id as string]);
        }

        const copy: Record<string, { title: string; body: string }> = {
          es: {
            title: "Participante eliminó su cuenta",
            body: `${playerName} eliminó su cuenta y salió de tu grupo.`,
          },
          en: {
            title: "Participant deleted their account",
            body: `${playerName} deleted their account and left your group.`,
          },
          pt: {
            title: "Participante excluiu a conta",
            body: `${playerName} excluiu a conta e saiu do seu grupo.`,
          },
        };

        for (const [lang, ids] of byLang.entries()) {
          const text = copy[lang] ?? copy.es;
          await fetch(`${supabaseUrl}/functions/v1/send-push`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${serviceKey}`,
              apikey: serviceKey,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              user_ids: ids,
              title: text.title,
              body: text.body,
              data: {
                type: "grupo_leave",
                jugador_id: user.id,
              },
            }),
          });
        }
      }
    } catch (notifyErr) {
      // No bloquear el borrado si falla el aviso.
      console.error("delete-account notify organizers", notifyErr);
    }

    const { error: purgeError } = await admin.rpc("purge_user_account_data", {
      p_user_id: user.id,
    });
    if (purgeError) {
      console.error("purge_user_account_data", purgeError);
      return new Response(
        JSON.stringify({ error: "purge_failed", detail: purgeError.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) {
      console.error("deleteUser", deleteError);
      return new Response(
        JSON.stringify({ error: "delete_failed", detail: deleteError.message }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("delete-account", e);
    return new Response(JSON.stringify({ error: "internal" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
