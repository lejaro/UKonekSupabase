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
  const otp = String(payload.otp ?? '').trim();

  if (!email || !email.includes('@')) {
    return json(400, { error: 'Valid email is required.' });
  }

  if (!otp) {
    return json(400, { error: 'OTP is required.' });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: record, error: readError } = await supabase
    .from('pending_citizen_signups')
    .select('id, otp_hash, otp_expires_at, attempts_left, consumed_at')
    .eq('email', email)
    .maybeSingle();

  if (readError || !record) {
    return json(404, { error: 'No pending OTP request found for this email.' });
  }

  if (record.consumed_at) {
    return json(409, { error: 'This OTP request was already used.' });
  }

  const now = Date.now();
  const expires = new Date(record.otp_expires_at).getTime();
  if (!Number.isFinite(expires) || now > expires) {
    return json(403, { error: 'OTP expired. Please request a new OTP.' });
  }

  if ((record.attempts_left ?? 0) <= 0) {
    return json(429, { error: 'Too many wrong OTP attempts. Please request a new OTP.' });
  }

  const otpHash = await sha256Hex(otp);
  if (otpHash !== record.otp_hash) {
    const nextAttempts = Math.max(0, (record.attempts_left ?? 0) - 1);
    await supabase
      .from('pending_citizen_signups')
      .update({ attempts_left: nextAttempts })
      .eq('id', record.id);

    return json(400, {
      error: nextAttempts > 0
        ? `Incorrect OTP. ${nextAttempts} attempt(s) left.`
        : 'Too many wrong OTP attempts. Please request a new OTP.',
    });
  }

  const { error: updateError } = await supabase
    .from('pending_citizen_signups')
    .update({ verified_at: new Date().toISOString() })
    .eq('id', record.id);

  if (updateError) {
    return json(500, { error: 'Unable to mark OTP as verified.' });
  }

  return json(200, { ok: true });
});
