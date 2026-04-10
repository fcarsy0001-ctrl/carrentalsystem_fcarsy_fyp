import { createClient, serve, corsHeaders, json, getJwt, mustEnv, serviceRoleKey, authUserFromJwt, isAdminOrStaff } from "./_shared.ts";

async function safeDeleteByEq(admin: ReturnType<typeof createClient>, table: string, col: string, val: string) {
  const cleanVal = (val ?? '').toString().trim();
  if (!cleanVal) return;
  try {
    const { error } = await admin.from(table).delete().eq(col, cleanVal);
    if (error) {
      const msg = (error.message ?? '').toLowerCase();
      if (
        msg.includes('does not exist') ||
        msg.includes('relation') ||
        msg.includes('column') ||
        msg.includes('schema cache')
      ) {
        return;
      }
      console.warn(`[delete_app_user] best-effort delete failed on ${table}.${col}: ${error.message}`);
    }
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

    let email = "";
    try {
      const { data } = await admin.from("app_user").select("user_email").eq("user_id", userId).limit(1).maybeSingle();
      email = (data?.user_email ?? "").toString().trim().toLowerCase();
    } catch (_) {}

    if (force) {
      const bookingIds = new Set<string>();
      try {
        const { data } = await admin.from("booking").select("booking_id").eq("user_id", userId);
        for (const row of data ?? []) {
          const bookingId = String((row as any)?.booking_id ?? '').trim();
          if (bookingId) bookingIds.add(bookingId);
        }
      } catch (_) {}
      try {
        const { data } = await admin.from("booking").select("booking_id").eq("auth_uid", authUid);
        for (const row of data ?? []) {
          const bookingId = String((row as any)?.booking_id ?? '').trim();
          if (bookingId) bookingIds.add(bookingId);
        }
      } catch (_) {}

      const bookingLinkedTables = [
        "receipt",
        "payment",
        "contract",
        "installment",
        "rental_history",
        "notification",
        "extra_charge",
      ];

      for (const bookingId of bookingIds) {
        for (const table of bookingLinkedTables) {
          await safeDeleteByEq(admin, table, "booking_id", bookingId);
        }
        await safeDeleteByEq(admin, "user_voucher", "used_booking_id", bookingId);
      }

      const userLinkedTables = [
        "receipt",
        "payment",
        "contract",
        "booking",
        "installment",
        "rental_history",
        "user_voucher",
        "driver_licenses",
        "wallet_transaction",
        "wallet_topup",
        "notification",
        "extra_charge",
        "support_ticket",
      ];
      for (const table of userLinkedTables) {
        await safeDeleteByEq(admin, table, "user_id", userId);
      }

      const authLinkedTables = [
        "receipt",
        "payment",
        "contract",
        "booking",
        "driver_licenses",
      ];
      for (const table of authLinkedTables) {
        await safeDeleteByEq(admin, table, "auth_uid", authUid);
      }

      if (email) {
        await safeDeleteByEq(admin, "verification_codes", "user_email", email);
        await safeDeleteByEq(admin, "verification_codes", "email", email);
      }
    }

    const { error: dbErr } = await admin.from("app_user").delete().eq("user_id", userId);
    if (dbErr) {
      return json({
        ok: false,
        error: `DB delete failed: ${dbErr.message}. If you still have foreign keys, keep force=true and ensure child rows are deleted first.`,
      }, 400);
    }

    const { error: authErr } = await admin.auth.admin.deleteUser(authUid);
    if (authErr) {
      return json({ ok: false, error: `Auth deleteUser failed: ${authErr.message}` }, 400);
    }

    return json({ ok: true });
  } catch (e) {
    return json({ ok: false, error: String(e?.message ?? e) }, 500);
  }
});
