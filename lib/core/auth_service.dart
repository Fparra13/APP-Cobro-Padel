import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/fcm_service.dart';
import '../offline/offline_snapshot_store.dart';
import 'subscription_service.dart';
import 'supabase_config.dart';
import '../utils/app_log.dart';

/// Usuario cerró el sheet de Google sin completar.
class GoogleSignInCancelledException implements Exception {
  const GoogleSignInCancelledException();
}

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
  bool _accesoIlimitado = false;
  String? _profileEmail;

  /// Generación de carga de perfil. Se incrementa al iniciar cada
  /// [refreshProfile] y al mutar el rol en cliente ([becomeOrganizer], logout).
  /// Así un refresh iniciado antes de promover no puede pisar el estado nuevo.
  int _profileEpoch = 0;

  static bool isOrganizerRole(String? role) =>
      role == 'organizer' || role == 'organizador';

  /// Rol desde `profiles` (fuente de verdad con RLS).
  bool get isOrganizer => isOrganizerRole(_profileRole);

  String? get profileRole => _profileRole;

  /// Founder/staff: sin trial ni paywall (columna `acceso_ilimitado`).
  bool get hasUnlimitedAccess => _accesoIlimitado;

  String? get profileEmail => _profileEmail;

  void _invalidateProfileLoads() {
    _profileEpoch++;
  }

  /// Jugador se convierte en organizador (misma cuenta; habilita crear partidos).
  /// No es Pro: solo permiso RLS / shell organizador.
  Future<void> becomeOrganizer() async {
    final client = _client;
    final uid = currentUser?.id;
    if (client == null || uid == null) {
      throw Exception('Sesión requerida');
    }
    await client.rpc('promover_a_organizador');
    // Invalida refreshes en vuelo que aún leyeron role=jugador.
    _invalidateProfileLoads();
    _profileRole = 'organizer';
  }

  /// Recarga rol y entitlements desde `profiles`.
  /// Devuelve true si la lectura a BD fue exitosa y se aplicó (no estaba stale).
  Future<bool> refreshProfile() async {
    final epoch = ++_profileEpoch;
    final client = _client;
    final uid = currentUser?.id;
    if (client == null || uid == null) {
      if (epoch != _profileEpoch) return _profileRole != null;
      _profileRole = null;
      _accesoIlimitado = false;
      _profileEmail = null;
      SubscriptionService.instance.clearProfileEntitlements();
      return false;
    }
    final authEmail = currentUser?.email?.trim().toLowerCase();
    try {
      Map<String, dynamic>? row;
      try {
        row = await client
            .from('profiles')
            .select('role, email, acceso_ilimitado')
            .eq('id', uid)
            .maybeSingle();
      } catch (_) {
        // Migración 047 aún no aplicada.
        row = await client
            .from('profiles')
            .select('role, email')
            .eq('id', uid)
            .maybeSingle();
      }
      // Otra refresh o becomeOrganizer ganó mientras esperábamos la red.
      if (epoch != _profileEpoch) {
        return isOrganizerRole(_profileRole) || _profileRole != null;
      }
      if (row != null) {
        _profileRole = row['role'] as String? ?? 'jugador';
        _accesoIlimitado = row['acceso_ilimitado'] == true;
        final rowEmail = (row['email'] as String?)?.trim().toLowerCase();
        _profileEmail =
            (rowEmail != null && rowEmail.isNotEmpty) ? rowEmail : authEmail;
        SubscriptionService.instance.syncFromProfile(
          accesoIlimitado: _accesoIlimitado,
          email: _profileEmail,
        );
        return true;
      }
      // Sin fila en profiles: no inferir organizador desde metadata de auth.
      _profileRole = 'jugador';
      _accesoIlimitado = false;
      _profileEmail = authEmail;
      SubscriptionService.instance.syncFromProfile(
        accesoIlimitado: false,
        email: _profileEmail,
      );
      return false;
    } catch (_) {
      if (epoch != _profileEpoch) {
        return isOrganizerRole(_profileRole) || _profileRole != null;
      }
      // Mantener rol previo si ya se cargó; si no, asumir jugador (nunca organizer).
      _profileRole ??= 'jugador';
      _profileEmail ??= authEmail;
      SubscriptionService.instance.syncFromProfile(
        accesoIlimitado: _accesoIlimitado,
        email: _profileEmail,
      );
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

  bool _googleInitialized = false;

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    if (!SupabaseConfig.isGoogleSignInConfigured) {
      throw Exception(
        'Google Sign-In no configurado. Define GOOGLE_WEB_CLIENT_ID '
        '(y GOOGLE_IOS_CLIENT_ID en iOS).',
      );
    }
    await GoogleSignIn.instance.initialize(
      serverClientId: SupabaseConfig.googleWebClientId,
      clientId: defaultTargetPlatform == TargetPlatform.iOS &&
              SupabaseConfig.googleIosClientId.isNotEmpty
          ? SupabaseConfig.googleIosClientId
          : null,
    );
    _googleInitialized = true;
  }

  /// Login nativo con Google → sesión Supabase vía ID token.
  Future<void> signInWithGoogle() async {
    final client = _client;
    if (client == null) {
      throw Exception(
        'Supabase no configurado. Define SUPABASE_URL y SUPABASE_ANON_KEY.',
      );
    }

    try {
      await _ensureGoogleInitialized();
      const scopes = ['email', 'profile'];
      final googleUser = await GoogleSignIn.instance.authenticate(
        scopeHint: scopes,
      );

      final authorization =
          await googleUser.authorizationClient.authorizationForScopes(scopes) ??
              await googleUser.authorizationClient.authorizeScopes(scopes);

      final idToken = googleUser.authentication.idToken;
      if (idToken == null) {
        throw Exception('No se recibió ID token de Google. Revisa la config OAuth.');
      }

      await client.auth
          .signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
            accessToken: authorization.accessToken,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception(
              'Sin respuesta del servidor. Revisa tu conexión e intenta de nuevo.',
            ),
          );

      await refreshProfile();
      await _syncNombreDesdeGoogle(googleUser.displayName);
    } on GoogleSignInCancelledException {
      rethrow;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw const GoogleSignInCancelledException();
      }
      throw Exception(mapGoogleSignInError(e));
    } on AuthException catch (e) {
      throw Exception(mapAuthError(e));
    }
  }

  /// Si el perfil quedó genérico, usa el nombre de la cuenta Google.
  Future<void> _syncNombreDesdeGoogle(String? displayName) async {
    final trimmed = displayName?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    final client = _client;
    final uid = currentUser?.id;
    if (client == null || uid == null) return;
    try {
      final row = await client
          .from('profiles')
          .select('nombre')
          .eq('id', uid)
          .maybeSingle();
      final actual = (row?['nombre'] as String?)?.trim() ?? '';
      final emailLocal =
          (currentUser?.email ?? '').split('@').first.trim().toLowerCase();
      final esGenerico = actual.isEmpty ||
          actual.toLowerCase() == 'sin nombre' ||
          (emailLocal.isNotEmpty && actual.toLowerCase() == emailLocal);
      if (esGenerico) {
        await client.from('profiles').update({'nombre': trimmed}).eq('id', uid);
      }
    } catch (e) {
      appLog('AuthService._syncNombreDesdeGoogle: $e');
    }
  }

  static String mapGoogleSignInError(GoogleSignInException e) {
    final desc = e.description?.trim() ?? '';
    final lower = desc.toLowerCase();
    // ApiException 10 = DEVELOPER_ERROR: package/SHA-1 no registrado en Google.
    if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
        lower.contains('10:') ||
        lower.contains('developer_error') ||
        lower.contains('api_exception: 10')) {
      return 'Google Sign-In: falta el SHA-1 de esta APK en Firebase '
          '(Project settings → tu app Android → Add fingerprint).';
    }
    switch (e.code) {
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Google Sign-In no está disponible en este dispositivo.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'No se pudo mostrar el selector de cuenta Google.';
      default:
        if (desc.isNotEmpty) return desc;
        return 'No se pudo iniciar sesión con Google. Intenta de nuevo.';
    }
  }

  /// Mensajes legibles para errores de Supabase Auth.
  static String mapAuthError(AuthException e) {
    final code = e.code ?? '';
    final status = e.statusCode;
    final msg = e.message.trim();
    if (code == 'over_email_send_rate_limit' ||
        status == '429' ||
        '$status' == '429') {
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
          'Si el organizador ya te registró en la lista de participantes, '
          'pide que ejecute la actualización SQL 016 en Supabase e intenta de nuevo. '
          'Si persiste, prueba con el mismo email en unos minutos.';
    }
    if (msg.toLowerCase().contains('provider is not enabled') ||
        msg.toLowerCase().contains('unsupported provider')) {
      return 'Google no está habilitado en Supabase. Actívalo en Authentication → Providers.';
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
    final uid = currentUser?.id;
    await FcmService.instance.clearTokenOnLogout();
    if (_googleInitialized) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        appLog('AuthService.signOut Google: $e');
      }
    }
    await _client?.auth.signOut();
    _clearCachedProfile();
    SubscriptionService.instance.clearProfileEntitlements();
    if (uid != null) {
      await OfflineSnapshotStore.clearForUser(uid);
    }
  }

  void _clearCachedProfile() {
    _invalidateProfileLoads();
    _profileRole = null;
    _accesoIlimitado = false;
    _profileEmail = null;
  }

  /// Elimina la cuenta del usuario autenticado (Edge Function + Auth Admin).
  Future<void> deleteAccount() async {
    final client = _client;
    final uid = currentUser?.id;
    if (client == null || uid == null) {
      throw Exception('Sesión requerida');
    }

    final response = await client.functions.invoke('delete-account');
    if (response.status != 200) {
      throw Exception(
        'delete_account_failed:${response.status}:${response.data}',
      );
    }

    await SubscriptionService.instance.setProActive(false);
    _clearCachedProfile();
    SubscriptionService.instance.clearProfileEntitlements();
    await OfflineSnapshotStore.clearForUser(uid);

    try {
      await client.auth.signOut();
    } catch (_) {
      // La sesión puede quedar inválida tras borrar el usuario Auth.
    }
  }
}
