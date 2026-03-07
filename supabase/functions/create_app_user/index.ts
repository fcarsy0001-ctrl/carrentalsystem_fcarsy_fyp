import { createClient, serve, corsHeaders, json, getJwt, mustEnv, serviceRoleKey, authUserFromJwt, isAdminOrStaff } from "./_shared.ts";

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
    const name = (body.user_name ?? "").toString().trim();
    const email = (body.user_email ?? "").toString().trim().toLowerCase();
    const password = (body.user_password ?? "").toString();
    const phone = (body.user_phone ?? "").toString().trim();
    const icNo = (body.user_icno ?? "").toString().trim();
    const gender = (body.user_gender ?? "Male").toString().trim();
    const role = (body.user_role ?? "User").toString().trim();
    const status = (body.user_status ?? "Active").toString().trim();
    const emailVerified = Boolean(body.email_verified ?? true);

    if (!name) return json({ ok: false, error: "user_name is required" }, 400);
    if (!email || !email.includes("@")) return json({ ok: false, error: "Invalid email" }, 400);
    if (!password || password.length < 8) return json({ ok: false, error: "Password must be at least 8 chars" }, 400);

    // Create Auth user
    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: emailVerified,
      user_metadata: { full_name: name },
    });
    if (createErr || !created?.user) {
      return json({ ok: false, error: `Auth createUser failed: ${createErr?.message ?? "unknown"}` }, 400);
    }
    const authUid = created.user.id;

    // Generate sequential user_id like U001, U002...
    async function nextUserId(): Promise<string> {
      const { data } = await admin
        .from("app_user")
        .select("user_id")
        .order("user_id", { ascending: false })
        .limit(1)
        .maybeSingle();
      const last = (data?.user_id ?? "").toString();
      const m = /^U(\d+)$/.exec(last);
      if (m) {
        const n = parseInt(m[1], 10) || 0;
        const next = n + 1;
        return `U${String(next).padStart(3, "0")}`;
      }
      return "U001";
    }

    let userId = await nextUserId();
    const baseRow: Record<string, unknown> = {
      user_id: userId,
      auth_uid: authUid,
      user_name: name,
      user_email: email,
      user_password: "***",
      user_phone: phone,
      user_icno: icNo,
      user_gender: gender,
      user_role: role,
      user_status: status,
      email_verified: emailVerified,
      driver_license_status: "Not Submitted",
    };

    // Insert app_user with retry on duplicate user_id
    for (let i = 0; i < 10; i++) {
      try {
        const { error } = await admin.from("app_user").insert(baseRow);
        if (!error) break;
        // If column doesn't exist, retry without it
        if ((error.message ?? "").includes("driver_license_status") && (error.message ?? "").includes("does not exist")) {
          delete baseRow.driver_license_status;
          const { error: e2 } = await admin.from("app_user").insert(baseRow);
          if (e2) throw e2;
          break;
        }
        // Duplicate user_id -> compute next
        if ((error.message ?? "").toLowerCase().includes("duplicate") || (error.code ?? "") === "23505") {
          userId = await nextUserId();
          baseRow.user_id = userId;
          continue;
        }
        throw error;
      } catch (e) {
        if (i === 9) {
          // Rollback: delete Auth user we just created
          try { await admin.auth.admin.deleteUser(authUid); } catch (_) {}
          throw e;
        }
      }
    }

    // Return created row (best-effort)
    const { data: userRow } = await admin
      .from("app_user")
      .select("user_id,auth_uid,user_name,user_email,user_phone,user_icno,user_gender,user_role,user_status,email_verified,driver_license_status")
      .eq("auth_uid", authUid)
      .limit(1)
      .maybeSingle();

    return json({ ok: true, user: userRow ?? { user_id: userId, auth_uid: authUid } });
  } catch (e) {
    return json({ ok: false, error: String(e?.message ?? e) }, 500);
  }
});
