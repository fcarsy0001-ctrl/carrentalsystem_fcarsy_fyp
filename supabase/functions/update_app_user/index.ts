import { createClient, serve, corsHeaders, json, getJwt, mustEnv, serviceRoleKey, authUserFromJwt, isAdminOrStaff } from "./_shared.ts";

const ALLOWED_KEYS = new Set([
  "user_name",
  "user_phone",
  "user_icno",
  "user_gender",
  "user_status",
  "email_verified",
]);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = mustEnv("SUPABASE_URL");
    const anonKey = mustEnv("SUPABASE_ANON_KEY");
    const srk = serviceRoleKey();
    if (!srk) throw new Error("Missing SERVICE_ROLE_KEY secret. Set it in Supabase Edge Function secrets.");

    const jwt = getJwt(req);
    if (!jwt) return json({ ok: false, error: "Missing Authorization token" }, 401);

    const caller = await authUserFromJwt(supabaseUrl, anonKey, jwt);

    const admin = createClient(supabaseUrl, srk);
    const allowed = await isAdminOrStaff(admin, caller.id);
    if (!allowed) return json({ ok: false, error: "Forbidden (admin/staff only)" }, 403);

    const body = await req.json().catch(() => ({}));
    const userId = (body.user_id ?? "").toString().trim();
    const authUid = (body.auth_uid ?? "").toString().trim();
    const payloadIn = body.payload ?? {};
    if (!userId) return json({ ok: false, error: "user_id is required" }, 400);
    if (!authUid) return json({ ok: false, error: "auth_uid is required" }, 400);
    if (typeof payloadIn !== "object" || payloadIn === null) return json({ ok: false, error: "payload must be an object" }, 400);

    const payload: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(payloadIn)) {
      if (ALLOWED_KEYS.has(k)) payload[k] = v;
    }
    if (Object.keys(payload).length === 0) return json({ ok: false, error: "No valid fields to update" }, 400);

    const { data: updated, error } = await admin
      .from("app_user")
      .update(payload)
      .eq("user_id", userId)
      .select("user_id,auth_uid,user_name,user_email,user_phone,user_icno,user_gender,user_role,user_status,email_verified,driver_license_status")
      .maybeSingle();

    if (error) return json({ ok: false, error: `DB update failed: ${error.message}` }, 400);
    if (!updated) return json({ ok: false, error: "Update failed (no row updated)" }, 400);

    // Keep Supabase Auth email confirmation in sync (best effort).
    if (payload.email_verified === true) {
      try {
        await admin.auth.admin.updateUserById(authUid, { email_confirm: true });
      } catch (_) {}
    }

    return json({ ok: true, user: updated });
  } catch (e) {
    return json({ ok: false, error: String(e?.message ?? e) }, 500);
  }
});
