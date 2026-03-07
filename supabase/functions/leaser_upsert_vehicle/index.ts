import { createClient, serve, corsHeaders, json, getJwt, mustEnv, serviceRoleKey, authUserFromJwt } from "./_shared.ts";

function norm(s: unknown): string {
  return (s ?? "").toString().trim();
}

function statusApproved(raw: string): boolean {
  const s = raw.trim().toLowerCase();
  return s === "approved" || s === "active" || s.includes("approve");
}

function statusDisabled(raw: string): boolean {
  const s = raw.trim().toLowerCase();
  return s === "inactive" || s === "disabled" || s.includes("deactiv");
}

async function resolveApprovedLeaserId(
  admin: ReturnType<typeof createClient>,
  authUid: string,
  email: string,
): Promise<string> {
  const emailNorm = norm(email).toLowerCase();

  // 1) app_user lookup (auth_uid first; fallback by email for legacy rows)
  let au: any = null;

  const byUid = await admin
    .from("app_user")
    .select("user_id,user_role,user_status,auth_uid,user_email")
    .eq("auth_uid", authUid)
    .limit(1)
    .maybeSingle();

  au = byUid.data ?? null;

  if (!au && emailNorm) {
    const byEmail = await admin
      .from("app_user")
      .select("user_id,user_role,user_status,auth_uid,user_email")
      .ilike("user_email", emailNorm)
      .limit(1)
      .maybeSingle();
    au = byEmail.data ?? null;

    // Self-heal: link auth_uid once for legacy users (best-effort)
    const userIdFix = norm(au?.user_id);
    const hasAuthUid = norm(au?.auth_uid);
    if (userIdFix && !hasAuthUid) {
      try {
        await admin.from("app_user").update({ auth_uid: authUid }).eq("user_id", userIdFix);
      } catch (_) {}
    }
  }

  const userId = norm(au?.user_id);
  const role = norm(au?.user_role).toLowerCase();
  const uStatus = norm(au?.user_status).toLowerCase();

  if (uStatus && uStatus !== "active") throw new Error("User is inactive.");

  // 2) leaser by user_id (latest)
  if (userId) {
    const { data: lr } = await admin
      .from("leaser")
      .select("*")
      .eq("user_id", userId)
      .order("leaser_id", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (lr) {
      const leaserId = norm(lr.leaser_id);
      const st = norm(lr.leaser_status ?? lr.status ?? "");
      const acc = norm(lr.leaser_account_status ?? "");
      if (!leaserId) throw new Error("Leaser ID missing.");
      if (statusDisabled(acc) || statusDisabled(st)) throw new Error("Leaser account is disabled.");
      if (!statusApproved(st)) throw new Error("Leaser is not approved yet.");
      return leaserId;
    }
  }

  // 3) fallback leaser by email (legacy data where app_user linkage is missing)
  if (emailNorm) {
    const { data: lr2 } = await admin
      .from("leaser")
      .select("*")
      .ilike("email", emailNorm)
      .order("leaser_id", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (lr2) {
      const leaserId = norm(lr2.leaser_id);
      const st = norm(lr2.leaser_status ?? lr2.status ?? "");
      const acc = norm(lr2.leaser_account_status ?? "");
      if (!leaserId) throw new Error("Leaser ID missing.");
      if (statusDisabled(acc) || statusDisabled(st)) throw new Error("Leaser account is disabled.");
      if (!statusApproved(st)) throw new Error("Leaser is not approved yet.");
      return leaserId;
    }
  }

  // 4) Role says leaser -> treat as not approved, never silently fall back
  if (role === "leaser") throw new Error("Leaser row not found / not approved.");

  throw new Error("Not a leaser.");
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

    const leaserId = await resolveApprovedLeaserId(admin, caller.id, caller.email ?? "");

    const body = await req.json().catch(() => ({}));
    const isEdit = Boolean(body.is_edit ?? false);
    const vehicleId = norm(body.vehicle_id);
    const payloadIn = body.payload ?? {};

    if (!vehicleId) return json({ ok: false, error: "vehicle_id is required" }, 400);
    if (typeof payloadIn !== "object" || payloadIn === null) return json({ ok: false, error: "payload must be an object" }, 400);

    // Clean payload: never allow client to change leaser_id in server-side operation
    const payload: Record<string, unknown> = { ...(payloadIn as Record<string, unknown>) };
    payload.leaser_id = leaserId;

    if (isEdit) {
      // Ensure ownership
      const { data: existing } = await admin
        .from("vehicle")
        .select("vehicle_id,leaser_id")
        .eq("vehicle_id", vehicleId)
        .limit(1)
        .maybeSingle();

      if (!existing) return json({ ok: false, error: "Vehicle not found" }, 404);
      if (norm(existing.leaser_id) !== leaserId) return json({ ok: false, error: "Forbidden (not your vehicle)" }, 403);

      const { data: updated, error } = await admin
        .from("vehicle")
        .update(payload)
        .eq("vehicle_id", vehicleId)
        .select("*")
        .maybeSingle();

      if (error) return json({ ok: false, error: `Update failed: ${error.message}` }, 400);
      return json({ ok: true, vehicle: updated ?? { vehicle_id: vehicleId } });
    } else {
      const insertRow: Record<string, unknown> = { vehicle_id: vehicleId, ...payload };
      const { data: inserted, error } = await admin
        .from("vehicle")
        .insert(insertRow)
        .select("*")
        .maybeSingle();

      if (error) return json({ ok: false, error: `Insert failed: ${error.message}` }, 400);
      return json({ ok: true, vehicle: inserted ?? { vehicle_id: vehicleId } });
    }
  } catch (e) {
    return json({ ok: false, error: String(e?.message ?? e) }, 500);
  }
});
