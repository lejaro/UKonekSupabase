// Static runtime config for backendless deployment.
(() => {
  const isVercel = typeof window !== 'undefined' && (
    window.location.hostname.endsWith('vercel.app') ||
    window.location.hostname.includes('u-konek')
  );

  // On Vercel, route requests through same-origin edge proxy /api/supabase to bypass ISP/router TLS 1.3 packet filtering
  const supabaseUrl = isVercel
    ? `${window.location.origin}/api/supabase`
    : 'https://dqjxpwbsbzagbjtulhue.supabase.co';

  window.UKONEK_CONFIG = {
    SUPABASE_URL: supabaseUrl,
    DIRECT_SUPABASE_URL: 'https://dqjxpwbsbzagbjtulhue.supabase.co',
    SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxanhwd2JzYnphZ2JqdHVsaHVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTM5ODUsImV4cCI6MjA4OTgyOTk4NX0.0Gvbjf2qrcVy9VF5QCKWaHXw19rVOsOTBz9DmHWPX9g'
  };
})();
