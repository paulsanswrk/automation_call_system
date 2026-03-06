import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;

  /// Sign in with Google OAuth via Supabase.
  /// On Android this opens the system browser for the OAuth flow.
  static Future<bool> signInWithGoogle() async {
    final res = await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'com.act.trading://login-callback/',
    );
    return res;
  }

  /// Sign out of the current Supabase session.
  static Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// Current authenticated user (or null).
  static User? get currentUser => _client.auth.currentUser;

  /// Current session (or null).
  static Session? get currentSession => _client.auth.currentSession;
}
