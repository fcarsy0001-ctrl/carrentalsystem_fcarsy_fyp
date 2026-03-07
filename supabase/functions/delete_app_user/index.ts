import { createClient, serve, corsHeaders, json, getJwt, mustEnv, serviceRoleKey, authUserFromJwt, isAdminOrStaff } from "./_shared.ts";

async function safeDeleteByEq(admin: ReturnType<typeof createClient>, table: string, col: string, val: string) {
  try {
    await admin.from(table).delete().eq(col, val);
  } catch (_) {
    // ignore (table/column might not exist)
  }
}

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
    const force = Boolean(body.force ?? true);

    if (!userId) return json({ ok: false, error: "user_id is required" }, 400);
    if (!authUid) return json({ ok: false, error: "auth_uid is required" }, 400);

    // Get email for cleanup (best effort)
    let email = "";
    try {
      const { data } = await admin.from("app_user").select("user_email").eq("user_id", userId).limit(1).maybeSingle();
      email = (data?.user_email ?? "").toString().trim().toLowerCase();
    } catch (_) {}

    if (force) {
      // Best-effort cleanup of common dependent tables in this project.
      // We ignore errors because schemas differ between teams.
      // Order matters: delete children before parent.
      await safeDeleteByEq(admin, "receipt", "user_id", userId);
      await safeDeleteByEq(admin, "payment", "user_id", userId);
      await safeDeleteByEq(admin, "contract", "user_id", userId);
      await safeDeleteByEq(admin, "booking", "user_id", userId);

      await safeDeleteByEq(admin, "user_voucher", "user_id", userId);
      await safeDeleteByEq(admin, "driver_licenses", "user_id", userId);

      // Some tables might track auth_uid instead
      await safeDeleteByEq(admin, "receipt", "auth_uid", authUid);
      await safeDeleteByEq(admin, "payment", "auth_uid", authUid);
      await safeDeleteByEq(admin, "contract", "auth_uid", authUid);
      await safeDeleteByEq(admin, "booking", "auth_uid", authUid);
      await safeDeleteByEq(admin, "driver_licenses", "auth_uid", authUid);

      if (email) {
        await safeDeleteByEq(admin, "verification_codes", "user_email", email);
        await safeDeleteByEq(admin, "verification_codes", "email", email);
      }
    }

    // Delete app_user row (may fail if FK constraints remain)
    const { error: dbErr } = await admin.from("app_user").delete().eq("user_id", userId);
    if (dbErr) {
      return json({
        ok: false,
        error: `DB delete failed: ${dbErr.message}. If you have foreign keys, enable ON DELETE CASCADE or set force=true and ensure child rows are deleted first.`,
      }, 400);
    }

    // Delete Supabase Auth user
    const { error: authErr } = await admin.auth.admin.deleteUser(authUid);
    if (authErr) {
      // If auth deletion fails, try to restore app_user? Not possible safely.
      return json({ ok: false, error: `Auth deleteUser failed: ${authErr.message}` }, 400);
    }

    return json({ ok: true });
  } catch (e) {
    return json({ ok: false, error: String(e?.message ?? e) }, 500);
  }
});
