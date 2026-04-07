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
//
// Checkpoint 2 fix:
//   secrets.dart.example has ' ' (space) not '' (empty).
//   .trim() prevents a space from passing the isNotEmpty check.
// ─────────────────────────────────────────────────────────────────────────────
import 'secrets.dart';

class AppConfig {
  AppConfig._();

  // Read at compile time — empty string if not provided
  static const _rawUrl     = Secrets.supabaseUrl;
  static const _rawAnonKey = Secrets.supabaseAnonKey;

  // Trimmed values — guards against whitespace-only secrets.dart
  static final supabaseUrl     = _rawUrl.trim();
  static final supabaseAnonKey = _rawAnonKey.trim();

  // Sync is only enabled when keys are properly configured
  static bool get isSyncEnabled =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}