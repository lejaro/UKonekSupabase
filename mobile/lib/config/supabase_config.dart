/// Supabase configuration — centralizes connection details.
///
/// Values can be overridden at build time via `--dart-define`:
/// ```bash
/// flutter run \
///   --dart-define=SUPABASE_URL=https://your-project.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=your-anon-key
/// ```
///
/// If no overrides are provided, the production defaults are used.
class SupabaseConfig {
  SupabaseConfig._();

  /// Supabase project URL.
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dqjxpwbsbzagbjtulhue.supabase.co',
  );

  /// Supabase anonymous (public) API key.
  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRxanhwd2JzYnphZ2JqdHVsaHVlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQyNTM5ODUsImV4cCI6MjA4OTgyOTk4NX0.0Gvbjf2qrcVy9VF5QCKWaHXw19rVOsOTBz9DmHWPX9g',
  );
}
