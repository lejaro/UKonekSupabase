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

async function sha256Hex(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function makeOtp(): string {
  const raw = crypto.getRandomValues(new Uint32Array(1))[0] % 900000;
  return String(raw + 100000);
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
  if (!email || !email.includes('@')) {
    return json(400, { error: 'Valid email is required.' });
  }

  const profile = {
    firstname: String(payload.firstname ?? '').trim(),
    surname: String(payload.surname ?? '').trim(),
    middle_initial: String(payload.middle_initial ?? '').trim(),
    date_of_birth: payload.date_of_birth,
    age: payload.age,
    contact_number: String(payload.contact_number ?? '').trim(),
    sex: String(payload.sex ?? '').trim(),
    complete_address: String(payload.complete_address ?? '').trim(),
    emergency_contact_complete_name: String(payload.emergency_contact_complete_name ?? '').trim(),
    emergency_contact_contact_number: String(payload.emergency_contact_contact_number ?? '').trim(),
    relation: String(payload.relation ?? '').trim(),
  };

  if (!profile.firstname || !profile.surname) {
    return json(400, { error: 'First name and surname are required.' });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: existingCitizen } = await supabase
    .from('citizens')
    .select('id')
    .eq('email', email)
    .maybeSingle();

  if (existingCitizen) {
    return json(409, { error: 'Email already used, please use other email.' });
  }

  const { data: existingStaff } = await supabase
    .from('staff')
    .select('id')
    .eq('email', email)
    .maybeSingle();

  if (existingStaff) {
    return json(409, { error: 'Email already used, please use other email.' });
  }

  const otpHash = await sha256Hex(makeOtp());
  const otpExpiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

  const { error: upsertError } = await supabase
    .from('pending_citizen_signups')
    .upsert(
      {
        email,
        profile,
        otp_hash: otpHash,
        otp_expires_at: otpExpiresAt,
        attempts_left: 5,
        verified_at: null,
        consumed_at: null,
      },
      { onConflict: 'email' },
    );

  if (upsertError) {
    return json(500, { error: 'Unable to store OTP request.' });
  }

  try {
    await supabase.auth.signInWithOtp({
      email,
      options: {
        shouldCreateUser: true,
        data: {
          role: 'citizen',
          firstname: profile.firstname,
          surname: profile.surname,
          middle_initial: profile.middle_initial,
          date_of_birth: profile.date_of_birth,
          age: profile.age,
          contact_number: profile.contact_number,
          sex: profile.sex,
          complete_address: profile.complete_address,
          emergency_contact_complete_name: profile.emergency_contact_complete_name,
          emergency_contact_contact_number: profile.emergency_contact_contact_number,
          relation: profile.relation,
        },
      },
    });
  } catch (_) {
    return json(500, {
      error: 'Unable to send OTP email right now. Please check Supabase Auth email settings.',
    });
  }

  return json(200, { ok: true });
});
