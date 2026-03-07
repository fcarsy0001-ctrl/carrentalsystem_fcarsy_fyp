// supabase/functions/delete_leaser/index.ts
// Deletes a leaser account COMPLETELY:
// - delete all vehicles owned by the leaser (only if no bookings exist for those vehicles)
// - delete the leaser row
// - delete the Supabase Auth user (auth.users)
// Caller must be an authenticated Admin (checked via public.admin table).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-user-jwt",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json }
  | Json[];

function jsonResponse(body: Json, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getJwt(req: Request): string {
  // Prefer explicit user JWT header, because some clients send `Authorization: Bearer <anon_key>`
  // even when authenticated. The anon key is NOT a user session JWT and will fail auth.getUser().
  const explicit = (req.headers.get("x-user-jwt") ?? "").trim();
  if (explicit) return explicit;
  const auth = req.headers.get("authorization") ?? req.headers.get("Authorization") ?? "";
  if (auth.toLowerCase().startsWith("bearer ")) return auth.slice(7).trim();
  return "";
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ ok: false, error: "Method not allowed" }, 405);

  const requestId = crypto.randomUUID();
  const log = (...args: unknown[]) => console.log(`[delete_leaser][${requestId}]`, ...args);

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
    const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    // Supabase CLI blocks secrets starting with SUPABASE_. Use SERVICE_ROLE_KEY instead.
    const SERVICE_ROLE_KEY =
      Deno.env.get("SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      "";

    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
      log("Missing SUPABASE_URL or SUPABASE_ANON_KEY");
      return jsonResponse({ ok: false, error: "Missing SUPABASE_URL or SUPABASE_ANON_KEY" }, 500);
    }
    if (!SERVICE_ROLE_KEY) {
      log("Missing SERVICE_ROLE_KEY secret");
      return jsonResponse(
        {
          ok: false,
          error:
            "Missing SERVICE_ROLE_KEY. Set it via `supabase secrets set SERVICE_ROLE_KEY=...` then redeploy.",
        },
        500,
      );
    }

    const jwt = getJwt(req);
    log("Incoming request", { hasJwt: !!jwt });

    // Client that represents the caller (uses the user's JWT from Authorization header)
    const supaUser = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: jwt ? `Bearer ${jwt}` : "" } },
      auth: { persistSession: false },
    });

    const { data: userData, error: userErr } = await supaUser.auth.getUser();
    if (userErr || !userData?.user) {
      log("Unauthorized", { userErr: userErr?.message });
      return jsonResponse({ ok: false, error: "Unauthorized (invalid or missing JWT)" }, 401);
    }
    const callerUid = userData.user.id;
    log("Caller", { callerUid });

    // Service-role client (bypasses RLS) for deletion + admin checks.
    const supaAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    });

    // Verify caller is an active/approved admin
    const { data: adminRow, error: adminErr } = await supaAdmin
      .from("admin")
      .select("admin_id, admin_role, admin_status")
      .eq("auth_uid", callerUid)
      .maybeSingle();

    if (adminErr) {
      log("Admin check failed", { adminErr: adminErr.message });
      return jsonResponse({ ok: false, error: `Admin check failed: ${adminErr.message}` }, 403);
    }
    const st = String(adminRow?.admin_status ?? "").toLowerCase().trim();
    if (!adminRow || (st !== "active" && st !== "approved")) {
      log("Forbidden (not admin)", { adminRow });
      return jsonResponse({ ok: false, error: "Forbidden: Admin access required" }, 403);
    }

    const body = await req.json().catch(() => ({}));
    const leaser_id = String((body as any)?.leaser_id ?? "").trim();
    let auth_uid = String((body as any)?.auth_uid ?? "").trim();

    log("Body", { leaser_id, hasAuthUid: !!auth_uid });

    if (!leaser_id) {
      return jsonResponse({ ok: false, error: "Missing leaser_id" }, 400);
    }

    // Validate leaser exists (and fetch user_id / email for auth_uid resolution)
    const { data: leaserRow, error: leaserErr } = await supaAdmin
      .from("leaser")
      .select("leaser_id, user_id, email")
      .eq("leaser_id", leaser_id)
      .maybeSingle();

    if (leaserErr) {
      log("Leaser lookup error", { leaserErr: leaserErr.message });
      return jsonResponse({ ok: false, error: leaserErr.message }, 500);
    }
    if (!leaserRow) {
      log("Leaser not found", { leaser_id });
      return jsonResponse({ ok: false, error: "Leaser not found" }, 404);
    }

    // Resolve auth_uid if not provided (your schema stores auth_uid in app_user, not leaser)
    if (!auth_uid) {
      if (leaserRow.user_id) {
        const { data: u } = await supaAdmin
          .from("app_user")
          .select("auth_uid")
          .eq("user_id", leaserRow.user_id)
          .maybeSingle();
        auth_uid = String((u as any)?.auth_uid ?? "").trim();
      }
      if (!auth_uid && leaserRow.email) {
        const { data: u2 } = await supaAdmin
          .from("app_user")
          .select("auth_uid")
          .ilike("user_email", String(leaserRow.email))
          .maybeSingle();
        auth_uid = String((u2 as any)?.auth_uid ?? "").trim();
      }
    }

    // LAST RESORT (dev safety net): if app_user.auth_uid is missing, try to resolve by email
    // from Supabase Auth admin API.
    if (!auth_uid && leaserRow.email) {
      const targetEmail = String(leaserRow.email).trim().toLowerCase();
      try {
        for (let page = 1; page <= 10; page++) {
          const { data: list, error: listErr } = await supaAdmin.auth.admin.listUsers({
            page,
            perPage: 200,
          });
          if (listErr) break;
          const found = (list?.users ?? []).find(
            (u: any) => String(u?.email ?? "").trim().toLowerCase() === targetEmail,
          );
          if (found?.id) {
            auth_uid = String(found.id).trim();

            // Best-effort: backfill app_user.auth_uid so future admin operations are consistent.
            try {
              if (leaserRow.user_id) {
                await supaAdmin
                  .from("app_user")
                  .update({ auth_uid })
                  .eq("user_id", leaserRow.user_id);
              }
            } catch (_) {}

            break;
          }
          if ((list?.users ?? []).length < 200) break; // no more pages
        }
      } catch (_) {
        // ignore and fall through to validation error below
      }
    }

    if (!auth_uid) {
      log("Cannot resolve auth_uid", { leaserRow });
      return jsonResponse(
        { ok: false, error: "Cannot resolve auth_uid for this leaser. Ensure app_user.auth_uid is filled." },
        422,
      );
    }

    // Collect vehicles of this leaser
    const { data: vehicles, error: vehErr } = await supaAdmin
      .from("vehicle")
      .select("vehicle_id")
      .eq("leaser_id", leaser_id);

    if (vehErr) {
      log("Vehicle lookup error", { vehErr: vehErr.message });
      return jsonResponse({ ok: false, error: vehErr.message }, 500);
    }

    const vehicleIds = (vehicles ?? []).map((v: any) => String(v.vehicle_id));
    log("Vehicles found", { count: vehicleIds.length });

    // If any bookings exist for the vehicles, refuse deletion (avoid FK breaks)
    if (vehicleIds.length > 0) {
      const { count, error: bkErr } = await supaAdmin
        .from("booking")
        .select("booking_id", { count: "exact", head: true })
        .in("vehicle_id", vehicleIds);

      if (bkErr) {
        log("Booking check error", { bkErr: bkErr.message });
        return jsonResponse({ ok: false, error: bkErr.message }, 500);
      }

      if ((count ?? 0) > 0) {
        log("Blocked by bookings", { bookings: count });
        return jsonResponse(
          {
            ok: false,
            error:
              "Cannot delete this leaser because their vehicles have bookings. Deactivate the leaser instead, or cancel/remove bookings first.",
            bookings: count,
          },
          409,
        );
      }
    }

    // Delete vehicles
    if (vehicleIds.length > 0) {
      const { error: delVehErr } = await supaAdmin
        .from("vehicle")
        .delete()
        .eq("leaser_id", leaser_id);
      if (delVehErr) {
        log("Delete vehicles failed", { delVehErr: delVehErr.message });
        return jsonResponse({ ok: false, error: delVehErr.message }, 500);
      }
    }

    // Delete leaser row
    const { error: delLeaserErr } = await supaAdmin
      .from("leaser")
      .delete()
      .eq("leaser_id", leaser_id);

    if (delLeaserErr) {
      log("Delete leaser failed", { delLeaserErr: delLeaserErr.message });
      return jsonResponse({ ok: false, error: delLeaserErr.message }, 500);
    }

    // Delete Auth user (hard requirement)
    const { error: delAuthErr } = await supaAdmin.auth.admin.deleteUser(auth_uid);

    // If already deleted, treat as ok
    if (delAuthErr && !String(delAuthErr.message).toLowerCase().includes("not found")) {
      log("Delete auth user failed", { delAuthErr: delAuthErr.message });
      return jsonResponse({ ok: false, error: `Auth delete failed: ${delAuthErr.message}` }, 500);
    }

    log("Delete success", { leaser_id, vehicles_deleted: vehicleIds.length, auth_deleted: !delAuthErr });

    return jsonResponse({
      ok: true,
      leaser_id,
      vehicles_deleted: vehicleIds.length,
      auth_deleted: !delAuthErr,
    });
  } catch (e) {
    const msg = String((e as any)?.message ?? e);
    console.log(`[delete_leaser][${requestId}]`, "Unhandled error", msg);
    return jsonResponse({ ok: false, error: msg }, 500);
  }
});
