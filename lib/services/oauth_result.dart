// ─────────────────────────────────────────────────────────────────────────────
// oauth_result.dart — Phase 3 (v2.7.0)
//
// OAuth state enum — single source of truth for Google Sign-In result.
// Owned by AppDataProvider via ValueNotifier<OAuthResult>.
// No screen directly subscribes to auth events — all flow through this.
// ─────────────────────────────────────────────────────────────────────────────

enum OAuthResult {
  idle,              // default — no OAuth in progress
  loading,           // browser opened, waiting for callback
  success,           // new email verified — proceed to shop details
  alreadyRegistered, // email exists in shops table — show error
  cancelled,         // user closed browser without signing in
  error,             // network or unknown error
}
