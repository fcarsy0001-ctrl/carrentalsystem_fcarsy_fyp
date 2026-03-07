// Supabase Edge Function: set_staff_password
// SuperAdmin only: set staff admin password via Supabase Admin API.

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-user-jwt',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function bad(message: string, status = 400) {
  return json({ ok: false, error: message }, status);
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

function env(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

const supabaseUrl = env('SUPABASE_URL');
const serviceKey = env('SUPABASE_SERVICE_ROLE_KEY');
const admin = createClient(supabaseUrl, serviceKey);

async function assertSuperAdmin(jwt: string) {
  if (!jwt) throw new Error('Missing Authorization token');
  const { data: u, error: uErr } = await admin.auth.getUser(jwt);
  if (uErr || !u?.user) throw new Error('Invalid/expired session token');

  const { data: rows } = await admin
    .from('admin')
    .select('admin_id')
    .eq('auth_uid', u.user.id)
    .eq('admin_status', 'Active')
    .limit(1);
  if (rows && rows.length > 0) return;
  throw new Error('Access denied');
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return bad('Method not allowed', 405);

  try {
    const jwt = getJwt(req);
    await assertSuperAdmin(jwt);

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;
    const authUid = String(body.auth_uid ?? '').trim();
    const newPassword = String(body.new_password ?? '');

    if (!authUid) return bad('auth_uid is required');
    if (!newPassword || newPassword.length < 8) return bad('new_password must be at least 8 characters');

    const { error } = await admin.auth.admin.updateUserById(authUid, {
      password: newPassword,
    });

    if (error) return bad(`Update failed: ${error.message}`, 500);

    return json({ ok: true });
  } catch (e) {
    return bad(e?.message ?? String(e), 401);
  }
});
