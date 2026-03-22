// ─────────────────────────────────────────────────────────────────────────────
// app_config.dart
//
// Reads keys injected via --dart-define at build time.
// Keys are NEVER in source code or git.
//
// Usage in launch.json:
//   "args": [
//     "--dart-define=SUPABASE_URL=https://jbkbwqprwbkqoduwghjp.supabase.co",
//     "--dart-define=SUPABASE_ANON_KEY=eyJhbGci..."
//   ]
//
// For release APK:
//   flutter build apk --release
//     --dart-define=SUPABASE_URL=https://jbkbwqprwbkqoduwghjp.supabase.co
//     --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
// ─────────────────────────────────────────────────────────────────────────────
import 'secrets.dart';

class AppConfig {
  AppConfig._();

  // Read at compile time — empty string if not provided
  static const supabaseUrl     = Secrets.supabaseUrl;
  static const supabaseAnonKey = Secrets.supabaseAnonKey;


  // Sync is only enabled when keys are properly configured
  static bool get isSyncEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}