import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const config = window.UKONEK_CONFIG || {};
const supabaseUrl = String(config.SUPABASE_URL || '').trim();
const supabaseAnonKey = String(config.SUPABASE_ANON_KEY || '').trim();

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Missing Supabase runtime config. Update frontend/web/js/runtime-config.js');
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey);
