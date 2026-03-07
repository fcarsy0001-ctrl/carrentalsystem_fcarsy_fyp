// Shared helpers for Supabase Edge Functions (Deno).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.43.4";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-user-jwt",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getJwt(req: Request): string | null {
  const auth = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (auth && auth.toLowerCase().startsWith("bearer ")) return auth.slice(7).trim();
  const x = req.headers.get("x-user-jwt");
  return x?.trim() || null;
}

function mustEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing environment variable: ${name}`);
  return v;
}

function serviceRoleKey(): string {
  // Supabase CLI blocks secrets starting with SUPABASE_. Use SERVICE_ROLE_KEY.
  return Deno.env.get("SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

async function authUserFromJwt(supabaseUrl: string, anonKey: string, jwt: string) {
  const authed = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data, error } = await authed.auth.getUser();
  if (error || !data?.user) throw new Error("Invalid/expired session token.");
  return data.user;
}

async function isAdminOrStaff(admin: ReturnType<typeof createClient>, authUid: string): Promise<boolean> {
  // admin table (super admin or normal admin)
  try {
    const { data } = await admin
      .from("admin")
      .select("admin_id,admin_status")
      .eq("auth_uid", authUid)
      .limit(1)
      .maybeSingle();
    const st = (data?.admin_status ?? "").toString().trim().toLowerCase();
    if (data && st === "active") return true;
  } catch (_) {}

  // staff_admin table
  try {
    const { data } = await admin
      .from("staff_admin")
      .select("sadmin_id,sadmin_status")
      .eq("auth_uid", authUid)
      .limit(1)
      .maybeSingle();
    const st = (data?.sadmin_status ?? "").toString().trim().toLowerCase();
    if (data && st === "active") return true;
  } catch (_) {}

  return false;
}

export { createClient, serve, corsHeaders, json, getJwt, mustEnv, serviceRoleKey, authUserFromJwt, isAdminOrStaff };
