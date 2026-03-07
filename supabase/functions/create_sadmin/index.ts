// Supabase Edge Function: create_sadmin
// SuperAdmin only: create staff admin Auth user + staff_admin row.

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

async function nextSadminId(): Promise<string> {
  const { data: row } = await admin
    .from('staff_admin')
    .select('sadmin_id')
    .order('sadmin_id', { ascending: false })
    .limit(1)
    .maybeSingle();

  const last = (row?.sadmin_id ?? '').toString();
  if (last.startsWith('S') && last.length >= 4) {
    const n = parseInt(last.substring(1), 10);
    if (!Number.isNaN(n)) {
      const next = n + 1;
      if (next <= 999) return `S${next.toString().padStart(3, '0')}`;
    }
  }
  return 'S001';
}

function normalizeStatus(v: string) {
  const t = (v ?? '').trim().toLowerCase();
  if (t === 'inactive') return 'Inactive';
  return 'Active';
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return bad('Method not allowed', 405);

  try {
    const jwt = getJwt(req);
    await assertSuperAdmin(jwt);

    const body = (await req.json().catch(() => ({}))) as Record<string, unknown>;

    let sadminId = String(body.sadmin_id ?? '').trim();
    const name = String(body.sadmin_name ?? '').trim();
    const email = String(body.sadmin_email ?? '').trim().toLowerCase();
    const password = String(body.sadmin_password ?? '');
    const salary = body.sadmin_salary === null || body.sadmin_salary === undefined
      ? null
      : Number(body.sadmin_salary);
    const status = normalizeStatus(String(body.sadmin_status ?? 'Active'));

    if (!name) return bad('sadmin_name is required');
    if (!email || !email.includes('@')) return bad('Invalid sadmin_email');
    if (!password || password.length < 8) return bad('Password must be at least 8 characters');

    if (!sadminId) sadminId = await nextSadminId();

    // Create auth user
    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
    });
    if (cErr || !created?.user) {
      return bad(`Auth create failed: ${cErr?.message ?? 'unknown'}`);
    }

    const authUid = created.user.id;

    // Insert staff_admin
    const { error: iErr } = await admin.from('staff_admin').insert({
      sadmin_id: sadminId,
      auth_uid: authUid,
      sadmin_name: name,
      sadmin_email: email,
      sadmin_salary: Number.isFinite(salary as number) ? salary : null,
      sadmin_status: status,
    });

    if (iErr) {
      // Cleanup auth
      try {
        await admin.auth.admin.deleteUser(authUid);
      } catch (_) {}
      return bad(`DB insert failed: ${iErr.message}`, 500);
    }

    return json({ ok: true, sadmin_id: sadminId, auth_uid: authUid });
  } catch (e) {
    return bad(e?.message ?? String(e), 401);
  }
});
