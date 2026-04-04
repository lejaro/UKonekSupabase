import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return json(405, { error: 'Method not allowed.' });
  }

  const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? '';
  const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return json(500, { error: 'Server is not configured (Supabase keys missing).' });
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch (_) {
    return json(400, { error: 'Invalid JSON payload.' });
  }

  const email = String(payload.email ?? '').trim().toLowerCase();
  const username = String(payload.username ?? '').trim();
  const password = String(payload.password ?? '');

  if (!email || !email.includes('@')) {
    return json(400, { error: 'Valid email is required.' });
  }

  if (!username) {
    return json(400, { error: 'Username is required.' });
  }

  if (password.length < 8) {
    return json(400, { error: 'Password must be at least 8 characters.' });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: existingUsername } = await supabase
    .from('citizens')
    .select('id')
    .ilike('username', username)
    .maybeSingle();

  if (existingUsername) {
    return json(409, { error: 'Username already used, please choose another username.' });
  }

  const { data: record, error: readError } = await supabase
    .from('pending_citizen_signups')
    .select('id, profile, verified_at, consumed_at')
    .eq('email', email)
    .maybeSingle();

  if (readError || !record) {
    return json(404, { error: 'No verified OTP request found for this email.' });
  }

  if (!record.verified_at) {
    return json(403, { error: 'Please verify OTP first before creating your account.' });
  }

  if (record.consumed_at) {
    return json(409, { error: 'This OTP request was already used.' });
  }

  const profile = (record.profile ?? {}) as Record<string, unknown>;

  const adminCreateResponse = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
      apikey: SUPABASE_SERVICE_ROLE_KEY,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        role: 'citizen',
        firstname: String(profile.firstname ?? ''),
        surname: String(profile.surname ?? ''),
        middle_initial: String(profile.middle_initial ?? ''),
        date_of_birth: profile.date_of_birth ?? null,
        age: profile.age ?? null,
        contact_number: String(profile.contact_number ?? ''),
        sex: String(profile.sex ?? ''),
        complete_address: String(profile.complete_address ?? ''),
        emergency_contact_complete_name: String(profile.emergency_contact_complete_name ?? ''),
        emergency_contact_contact_number: String(profile.emergency_contact_contact_number ?? ''),
        relation: String(profile.relation ?? ''),
        username,
      },
    }),
  });

  if (!adminCreateResponse.ok) {
    const errorText = await adminCreateResponse.text();
    if (errorText.toLowerCase().includes('already')) {
      return json(409, { error: 'Email already used, please use other email.' });
    }
    return json(500, { error: 'Unable to create auth account right now.' });
  }

  const { error: consumeError } = await supabase
    .from('pending_citizen_signups')
    .update({ consumed_at: new Date().toISOString() })
    .eq('id', record.id);

  if (consumeError) {
    return json(500, { error: 'Account created but pending record cleanup failed.' });
  }

  return json(200, { ok: true });
});
