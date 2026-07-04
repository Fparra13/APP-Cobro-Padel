import '../core/supabase_parse.dart';

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
    bool clearFoto = false,
    DateTime? createdAt,
  }) {
    return Jugador(
      id: id ?? this.id,
      supabaseId: supabaseId ?? this.supabaseId,
      nombre: nombre ?? this.nombre,
      activo: activo ?? this.activo,
      saldoAcumulado: saldoAcumulado ?? this.saldoAcumulado,
      email: email ?? this.email,
      telefono: telefono ?? this.telefono,
      fotoPath: clearFoto ? null : (fotoPath ?? this.fotoPath),
      fotoUrl: clearFoto ? null : (fotoUrl ?? this.fotoUrl),
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
      activo: SupabaseParse.toBool(map['activo']),
      saldoAcumulado: SupabaseParse.toDouble(map['saldo_acumulado']),
      email: SupabaseParse.toStringOrNull(map['email'])?.toLowerCase(),
      telefono: SupabaseParse.toStringOrNull(map['telefono']),
      fotoUrl: SupabaseParse.toStringOrNull(map['foto_url']),
      createdAt: SupabaseParse.toDateTime(map['created_at']),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    final map = <String, dynamic>{
      'nombre': nombre,
      'activo': activo,
      'saldo_acumulado': saldoAcumulado,
    };
    final id = supabaseId;
    if (id != null && id.isNotEmpty) map['id'] = id;
    final mail = contactEmail;
    if (mail != null) map['email'] = mail;
    final tel = telefono?.trim();
    if (tel != null && tel.isNotEmpty) map['telefono'] = tel;
    final foto = fotoUrl?.trim();
    if (foto != null && foto.isNotEmpty) map['foto_url'] = foto;
    return map;
  }
}
