import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  SupabaseClient? get _client {
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  User? get currentUser => _client?.auth.currentUser;

  bool get isLoggedIn => currentUser != null;

  bool get isOrganizer {
    final meta = currentUser?.userMetadata;
    if (meta == null) return false;
    return meta['role'] == 'organizer';
  }

  Stream<AuthState> get authStateChanges {
    final client = _client;
    if (client == null) {
      return Stream.value(const AuthState(AuthChangeEvent.initialSession, null));
    }
    return client.auth.onAuthStateChange;
  }

  Future<void> signInWithPhone(String phone) async {
    final client = _client;
    if (client == null) {
      throw Exception(
        'Supabase no configurado. Define SUPABASE_URL y SUPABASE_ANON_KEY.',
      );
    }

    await client.auth.signInWithOtp(phone: phone);
  }

  Future<AuthResponse> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final client = _client;
    if (client == null) {
      throw Exception(
        'Supabase no configurado. Define SUPABASE_URL y SUPABASE_ANON_KEY.',
      );
    }

    return client.auth.verifyOTP(
      phone: phone,
      token: otp,
      type: OtpType.sms,
    );
  }

  Future<void> signOut() async {
    await _client?.auth.signOut();
  }
}
