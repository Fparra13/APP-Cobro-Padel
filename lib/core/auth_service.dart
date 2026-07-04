import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fcm_service.dart';
import 'supabase_config.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  StreamSubscription<AuthState>? _authSubscription;

  /// Deep link de retorno tras magic link (debe coincidir con AndroidManifest).
  static const magicLinkRedirect = SupabaseConfig.authRedirectUrl;

  SupabaseClient? get _client {
    if (!SupabaseConfig.isConfigured) return null;
    return Supabase.instance.client;
  }

  User? get currentUser => _client?.auth.currentUser;

  bool get isLoggedIn => currentUser != null;

  String? _profileRole;

  /// Rol desde `profiles` (fuente de verdad con RLS).
  bool get isOrganizer =>
      _profileRole == 'organizer' || _profileRole == 'organizador';

  String? get profileRole => _profileRole;

  /// Jugador se convierte en organizador (misma cuenta; habilita crear partidos).
  Future<void> becomeOrganizer() async {
    final client = _client;
    final uid = currentUser?.id;
    if (client == null || uid == null) {
      throw Exception('Sesión requerida');
    }
    await client.from('profiles').update({
      'role': 'organizer',
    }).eq('id', uid);
    _profileRole = 'organizer';
  }

  /// Recarga rol desde `profiles`. Devuelve true si la lectura a BD fue exitosa.
  Future<bool> refreshProfile() async {
    final client = _client;
    final uid = currentUser?.id;
    if (client == null || uid == null) {
      _profileRole = null;
      return false;
    }
    try {
      final row = await client
          .from('profiles')
          .select('role')
          .eq('id', uid)
          .maybeSingle();
      if (row != null) {
        _profileRole = row['role'] as String? ?? 'jugador';
        return true;
      }
      final meta = currentUser?.userMetadata;
      _profileRole = meta?['role'] as String?;
      return false;
    } catch (_) {
      final meta = currentUser?.userMetadata;
      _profileRole = meta?['role'] as String?;
      return false;
    }
  }

  Stream<AuthState> get authStateChanges {
    final client = _client;
    if (client == null) {
      return Stream.value(const AuthState(AuthChangeEvent.initialSession, null));
    }
    return client.auth.onAuthStateChange;
  }

  /// Escucha sesión tras magic link. [AuthGate] reacciona al mismo stream
  /// y muestra [MainShell] cuando hay sesión activa.
  void initializeAuthListener({VoidCallback? onSignedIn}) {
    _authSubscription?.cancel();
    final client = _client;
    if (client == null) return;

    _authSubscription = client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && data.session != null) {
        refreshProfile();
        onSignedIn?.call();
      }
    });
  }

  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  /// Envía magic link al email. El usuario abre el enlace y vuelve a la app.
  Future<void> sendMagicLink(
    String email, {
    String? nombre,
  }) async {
    final client = _client;
    if (client == null) {
      throw Exception(
        'Supabase no configurado. Define SUPABASE_URL y SUPABASE_ANON_KEY.',
      );
    }

    final data = <String, dynamic>{};
    final nombreTrim = nombre?.trim();
    if (nombreTrim != null && nombreTrim.isNotEmpty) {
      data['nombre'] = nombreTrim;
    }

    try {
      await client.auth
          .signInWithOtp(
            email: email.trim().toLowerCase(),
            shouldCreateUser: true,
            emailRedirectTo: magicLinkRedirect,
            data: data.isEmpty ? null : data,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
              'Sin respuesta del servidor. Revisa tu conexión a internet e intenta de nuevo.',
            ),
          );
    } on AuthException catch (e) {
      throw Exception(mapAuthError(e));
    }
  }

  /// Mensajes legibles para errores de Supabase Auth.
  static String mapAuthError(AuthException e) {
    final code = e.code ?? '';
    final status = e.statusCode;
    final msg = e.message.trim();
    if (code == 'over_email_send_rate_limit' ||
        status == 429 ||
        status == '429') {
      return 'Demasiados intentos de envío. Espera unos minutos (hasta 1 hora) '
          'y vuelve a intentar, o revisa si ya tienes un enlace en tu correo '
          'o carpeta de spam.';
    }
    if (code == 'email_address_invalid') {
      return 'Correo inválido. Verifica que esté bien escrito.';
    }
    if (code == 'signup_disabled') {
      return 'El registro está deshabilitado. Contacta al organizador.';
    }
    if (code == 'unexpected_failure' ||
        msg.toLowerCase().contains('database error saving new user')) {
      return 'No se pudo crear tu cuenta con este email. '
          'Si el organizador ya te registró en la lista de jugadores, '
          'pide que ejecute la actualización SQL 016 en Supabase e intenta de nuevo. '
          'Si persiste, prueba con el mismo email en unos minutos.';
    }
    if (msg.isNotEmpty) return msg;
    return 'No se pudo enviar el enlace. Intenta de nuevo más tarde.';
  }

  /// Actualiza el nombre del perfil del usuario en sesión.
  Future<void> updateMyNombre(String nombre) async {
    final client = _client;
    final uid = currentUser?.id;
    if (client == null || uid == null) {
      throw Exception('Sesión requerida');
    }
    final trimmed = nombre.trim();
    if (trimmed.isEmpty) {
      throw Exception('El nombre no puede estar vacío');
    }
    await client.from('profiles').update({'nombre': trimmed}).eq('id', uid);
  }

  Future<void> signOut() async {
    await FcmService.instance.clearTokenOnLogout();
    await _client?.auth.signOut();
  }
}
