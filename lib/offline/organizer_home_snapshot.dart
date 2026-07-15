import '../models/convocatoria_jugador.dart';
import '../models/cobros_resumen.dart';
import '../models/desglose_jugador.dart';
import '../models/detalle_partido.dart';
import '../models/jugador.dart';
import '../models/mi_convocatoria.dart';
import '../repositories/partido_repository.dart';
import 'offline_snapshot_codec.dart';

/// Clave de snapshot para [HomeScreen] del organizador.
const organizerHomeSnapshotKey = 'organizer_home';

class OrganizerHomeData {
  final List<ResumenJugador> resumenes;
  final List<ConvocatoriaCompleta> convocatorias;
  final List<MiConvocatoria> misInvitaciones;
  final List<DetallePartido> pagosPorValidar;
  final List<DetallePartido> misDeudas;
  final List<PartidoCompleto> partidosJugadosRecientes;
  final List<DesgloseJugador> ultimoPartidoDesglose;
  final CobrosResumen cobrosResumen;

  const OrganizerHomeData({
    required this.resumenes,
    required this.convocatorias,
    required this.misInvitaciones,
    required this.pagosPorValidar,
    required this.misDeudas,
    required this.partidosJugadosRecientes,
    required this.ultimoPartidoDesglose,
    required this.cobrosResumen,
  });

  static const empty = OrganizerHomeData(
    resumenes: [],
    convocatorias: [],
    misInvitaciones: [],
    pagosPorValidar: [],
    misDeudas: [],
    partidosJugadosRecientes: [],
    ultimoPartidoDesglose: [],
    cobrosResumen: CobrosResumen.zero,
  );

  Map<String, dynamic> toJson() => {
        'resumenes': resumenes.map(resumenJugadorToJson).toList(),
        'convocatorias':
            convocatorias.map(convocatoriaCompletaToJson).toList(),
        'misInvitaciones': misInvitaciones.map(miConvocatoriaToJson).toList(),
        'pagosPorValidar': pagosPorValidar.map(detallePartidoToJson).toList(),
        'misDeudas': misDeudas.map(detallePartidoToJson).toList(),
        'partidosJugadosRecientes':
            partidosJugadosRecientes.map(partidoCompletoToJson).toList(),
        'ultimoPartidoDesglose':
            ultimoPartidoDesglose.map(desgloseJugadorToJson).toList(),
        'cobrosResumen': cobrosResumenToJson(cobrosResumen),
      };

  factory OrganizerHomeData.fromJson(Map<String, dynamic> json) {
    return OrganizerHomeData(
      resumenes: (json['resumenes'] as List? ?? const [])
          .map((e) => resumenJugadorFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      convocatorias: (json['convocatorias'] as List? ?? const [])
          .map((e) => convocatoriaCompletaFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      misInvitaciones: (json['misInvitaciones'] as List? ?? const [])
          .map((e) => miConvocatoriaFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      pagosPorValidar: (json['pagosPorValidar'] as List? ?? const [])
          .map((e) => detallePartidoFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      misDeudas: (json['misDeudas'] as List? ?? const [])
          .map((e) => detallePartidoFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      partidosJugadosRecientes:
          (json['partidosJugadosRecientes'] as List? ?? const [])
              .map((e) => partidoCompletoFromJson(Map<String, dynamic>.from(e)))
              .toList(),
      ultimoPartidoDesglose: (json['ultimoPartidoDesglose'] as List? ?? const [])
          .map((e) => desgloseJugadorFromJson(Map<String, dynamic>.from(e)))
          .toList(),
      cobrosResumen: cobrosResumenFromJson(
        Map<String, dynamic>.from(json['cobrosResumen'] as Map? ?? const {}),
      ),
    );
  }
}

/// Clave de snapshot para [OrganizerCobrosScreen].
const organizerCobrosSnapshotKey = 'organizer_cobros';

class OrganizerCobrosData {
  final List<ResumenJugador> resumenes;

  const OrganizerCobrosData({required this.resumenes});

  Map<String, dynamic> toJson() => {
        'resumenes': resumenes.map(resumenJugadorToJson).toList(),
      };

  factory OrganizerCobrosData.fromJson(Map<String, dynamic> json) =>
      OrganizerCobrosData(
        resumenes: (json['resumenes'] as List? ?? const [])
            .map((e) => resumenJugadorFromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Clave de snapshot para [JugadoresScreen].
const organizerJugadoresSnapshotKey = 'organizer_jugadores';

class OrganizerJugadoresData {
  final List<Jugador> jugadores;

  const OrganizerJugadoresData({required this.jugadores});

  Map<String, dynamic> toJson() => {
        'jugadores': jugadores.map(jugadorToSnapshotJson).toList(),
      };

  factory OrganizerJugadoresData.fromJson(Map<String, dynamic> json) =>
      OrganizerJugadoresData(
        jugadores: (json['jugadores'] as List? ?? const [])
            .map((e) => jugadorFromSnapshotJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Clave de snapshot para pestaña partidos de [HistorialPartidosScreen].
const organizerHistorialPartidosSnapshotKey = 'organizer_historial_partidos';

class OrganizerHistorialPartidosData {
  final List<PartidoCompleto> partidos;
  final List<ConvocatoriaCompleta> convocatorias;

  const OrganizerHistorialPartidosData({
    required this.partidos,
    required this.convocatorias,
  });

  Map<String, dynamic> toJson() => {
        'partidos': partidos.map(partidoCompletoToJson).toList(),
        'convocatorias':
            convocatorias.map(convocatoriaCompletaToJson).toList(),
      };

  factory OrganizerHistorialPartidosData.fromJson(Map<String, dynamic> json) =>
      OrganizerHistorialPartidosData(
        partidos: (json['partidos'] as List? ?? const [])
            .map((e) => partidoCompletoFromJson(Map<String, dynamic>.from(e)))
            .toList(),
        convocatorias: (json['convocatorias'] as List? ?? const [])
            .map((e) => convocatoriaCompletaFromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}
