import '../core/supabase_parse.dart';
import '../utils/formatters.dart';

class Jugador {
  final int? id;
  /// UUID en Supabase (`profiles.id`). Null en SQLite local.
  final String? supabaseId;
  final String nombre;
  final bool activo;
  final double saldoAcumulado;
  final String? email;
  /// Legacy local / campo deprecado en Supabase.
  final String? telefono;
  final String? fotoPath;
  /// URL pública en Supabase Storage.
  final String? fotoUrl;
  /// Token FCM: indica que el jugador abrió la app y recibe push.
  final String? fcmToken;
  final DateTime createdAt;

  const Jugador({
    this.id,
    this.supabaseId,
    required this.nombre,
    this.activo = true,
    this.saldoAcumulado = 0,
    this.email,
    this.telefono,
    this.fotoPath,
    this.fotoUrl,
    this.fcmToken,
    required this.createdAt,
  });

  /// Identificador principal según origen (Supabase o SQLite).
  String? get remoteId => supabaseId;

  /// Email de contacto (campo dedicado o legacy en telefono).
  String? get contactEmail {
    final e = email?.trim();
    if (e != null && e.isNotEmpty) return e.toLowerCase();
    final t = telefono?.trim();
    if (t != null && t.contains('@')) return t.toLowerCase();
    return null;
  }

  /// WhatsApp / teléfono móvil (no confundir con email legacy en telefono).
  String? get contactWhatsApp {
    final t = telefono?.trim();
    if (t == null || t.isEmpty || t.contains('@')) return null;
    return t;
  }

  /// Perfil vinculado a Supabase (puede tener o no la app instalada).
  bool get tienePerfilRemoto => supabaseId != null && supabaseId!.isNotEmpty;

  /// App instalada y registrada para notificaciones push.
  bool get tieneMatchPayApp =>
      fcmToken != null && fcmToken!.trim().isNotEmpty;

  bool get puedeEnviarWhatsApp =>
      normalizeWhatsAppDigits(contactWhatsApp) != null;

  /// Clave estable para mapas, rutas y repositorios unificados.
  String get keyId => supabaseId ?? id?.toString() ?? '';

  bool get isRemote => supabaseId != null;

  Jugador copyWith({
    int? id,
    String? supabaseId,
    String? nombre,
    bool? activo,
    double? saldoAcumulado,
    String? email,
    String? telefono,
    String? fotoPath,
    String? fotoUrl,
    String? fcmToken,
    bool clearFoto = false,
    bool clearTelefono = false,
    bool clearEmail = false,
    bool clearFcmToken = false,
    DateTime? createdAt,
  }) {
    return Jugador(
      id: id ?? this.id,
      supabaseId: supabaseId ?? this.supabaseId,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      saldoAcumulado: saldoAcumulado ?? this.saldoAcumulado,
      email: clearEmail ? null : (email ?? this.email),
      telefono: clearTelefono ? null : (telefono ?? this.telefono),
      fotoPath: clearFoto ? null : (fotoPath ?? this.fotoPath),
      fotoUrl: clearFoto ? null : (fotoUrl ?? this.fotoUrl),
      fcmToken: clearFcmToken ? null : (fcmToken ?? this.fcmToken),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'nombre': nombre,
        'activo': activo ? 1 : 0,
        'saldo_acumulado': saldoAcumulado,
        'email': email ?? contactEmail,
        'telefono': telefono,
        'foto_path': fotoPath,
        'created_at': createdAt.toIso8601String(),
      };

  factory Jugador.fromMap(Map<String, dynamic> map) => Jugador(
        id: map['id'] as int?,
        nombre: map['nombre'] as String,
        activo: (map['activo'] as int? ?? 1) == 1,
        saldoAcumulado: (map['saldo_acumulado'] as num?)?.toDouble() ?? 0,
        email: map['email'] as String?,
        telefono: map['telefono'] as String?,
        fotoPath: map['foto_path'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  factory Jugador.fromSupabaseMap(Map<String, dynamic> map) {
    return Jugador(
      supabaseId: SupabaseParse.toStringOrNull(map['id']),
      nombre: SupabaseParse.asString(map['nombre'], fallback: 'Sin nombre'),
      // Roster RPC expone perfil_activo; profiles usa activo.
      activo: SupabaseParse.toBool(map['activo'] ?? map['perfil_activo']),
      // Saldo de la cuenta con ESTE organizador (organizador_jugadores), no global.
      saldoAcumulado: SupabaseParse.toDouble(map['saldo_acumulado']),
      email: SupabaseParse.toStringOrNull(map['email'])?.toLowerCase(),
      telefono: SupabaseParse.toStringOrNull(map['telefono']),
      fotoUrl: SupabaseParse.toStringOrNull(map['foto_url']),
      fcmToken: SupabaseParse.toStringOrNull(map['fcm_token']),
      createdAt: SupabaseParse.toDateTime(map['created_at']),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    // No enviar saldo_acumulado a profiles: el SSOT vive en organizador_jugadores.
    final map = <String, dynamic>{
      'nombre': nombre,
      'activo': activo,
    };
    final id = supabaseId;
    if (id != null && id.isNotEmpty) map['id'] = id;
    map['email'] = contactEmail;
    final tel = telefono?.trim();
    map['telefono'] = (tel != null && tel.isNotEmpty) ? tel : null;
    final foto = fotoUrl?.trim();
    if (foto != null && foto.isNotEmpty) map['foto_url'] = foto;
    return map;
  }
}
