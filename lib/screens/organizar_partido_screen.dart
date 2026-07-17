import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_repositories.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import '../models/convocatoria_jugador.dart';
import '../models/estado_partido.dart';
import '../models/jugador.dart';
import '../models/partido.dart';
import '../domain/convocatoria_plazo_respuesta.dart';
import '../domain/convocatoria_cupo_logic.dart';
import '../domain/estado_partido_publico.dart';
import '../domain/jugador_list_priority.dart';
import '../domain/partido_lifecycle.dart';
import '../models/recinto.dart';
import '../services/convocatoria_comunicacion_service.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../services/convocatoria_notificacion_service.dart';
import '../services/preferences_service.dart';
import '../services/supabase_realtime_service.dart';
import '../utils/formatters.dart';
import '../utils/jugador_name_filter.dart';
import '../utils/convocatoria_organizador_actions.dart';
import '../utils/matchpay_context.dart';
import '../utils/reprogramar_convocatoria_flow.dart';
import '../widgets/convocatoria_asistencias_view.dart';
import '../widgets/convocatoria_avatar_strip.dart';
import '../widgets/convocatoria_decision_panel.dart';
import '../widgets/partido_estado_publico.dart';
import '../widgets/ayuda_tip.dart';
import '../core/matchpay_design_tokens.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/convocatoria_whatsapp_sin_app_sheet.dart';
import '../widgets/jugador_app_badge.dart';
import '../widgets/match_sport_picker.dart';
import '../widgets/friendly_error_panel.dart';
import '../widgets/mis_recintos_panel.dart';
import '../widgets/sport_icon.dart';

class OrganizarPartidoScreen extends StatefulWidget {
  final int? partidoId;

  const OrganizarPartidoScreen({super.key, this.partidoId});

  bool get isEditing => partidoId != null;

  @override
  State<OrganizarPartidoScreen> createState() => _OrganizarPartidoScreenState();
}

class _OrganizarPartidoScreenState extends State<OrganizarPartidoScreen> {
  final _prefs = PreferencesService();

  final _listaEsperaService = ConvocatoriaListaEsperaService();
  final _notificaciones = ConvocatoriaNotificacionService();

  final _notasCtrl = TextEditingController();
  final _cuposCtrl = TextEditingController(text: '4');
  final _jugadoresBusquedaCtrl = TextEditingController();

  List<Jugador> _habituales = [];
  final Set<String> _prioridadJugadorIds = {};
  final Map<String, Jugador> _jugadoresPorId = {};
  List<Recinto> _recintosGuardados = [];
  Recinto? _recintoSeleccionado;
  final List<String> _titulares = [];
  final List<String> _listaEspera = [];
  final Map<String, EstadoConfirmacion> _estados = {};
  int _horasLimite = 24;
  DateTime? _fechaPartido;
  SportType _sportType = SportType.padel;
  bool _loading = true;
  bool _guardando = false;
  String? _errorCarga;
  int? _partidoId;
  bool _dirty = false;
  bool _partidoConfirmado = false;
  bool _convocatoriaEnviada = false;
  bool _convocatoriaExpiradaAlCargar = false;
  DateTime? _ultimoSnackPromocionAt;
  ConvocatoriaCompleta? _convocatoriaCompleta;
  bool _editarSeguimiento = false;

  bool get _modoSeguimiento => _convocatoriaEnviada && !_partidoConfirmado;

  bool get _formularioBloqueado => _convocatoriaEnviada || _partidoConfirmado;

  bool get _puedeEditarEstados => _modoSeguimiento;

  bool get _puedeEditarListaEspera =>
      _convocatoriaEnviada && !_fechaPartidoPasada;

  bool get _cuposLlenos => _confirmados >= _cuposMax;

  /// La lista de espera solo se arma cuando los cupos están completos
  /// (o ya hay gente en espera cargada desde el servidor).
  bool get _mostrarListaEspera => ConvocatoriaCupoLogic.mostrarListaEspera(
        seleccionados: _titulares.length,
        cuposMax: _cuposMax,
        enEspera: _listaEspera.length,
      );

  bool get _cupoImposible {
    final completa = _convocatoriaCompleta;
    if (completa == null || !_modoSeguimiento) return false;
    return ConvocatoriaCupoLogic.cupoImposible(completa);
  }

  bool get _shouldShowEstadoSeguimiento {
    if (!_modoSeguimiento || _convocatoriaCompleta == null) return false;
    if (_cupoImposible) return false;
    final view = PartidoEstadoPublicoView.resolve(_convocatoriaCompleta!);
    return view.estado == EstadoPartidoPublico.reprogramado;
  }

  int get _cuposDisponibles => (_cuposMax - _confirmados).clamp(0, _cuposMax);

  int get _confirmados => _titulares
      .where((id) => _estados[id] == EstadoConfirmacion.confirmado)
      .length;

  int get _pendientes => _titulares
      .where((id) => _estados[id] == EstadoConfirmacion.invitado)
      .length;

  bool get _fechaPartidoPasada =>
      _fechaPartido == null || !_fechaPartido!.isAfter(DateTime.now());

  bool get _tieneFechaPartido => _fechaPartido != null;

  List<int> get _opcionesPlazo {
    if (_fechaPartido == null) {
      return ConvocatoriaPlazoRespuesta.opcionesExtendidas;
    }
    return ConvocatoriaPlazoRespuesta.opcionesPermitidas(_fechaPartido!);
  }

  DateTime get _sugerenciaInicialPicker {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1, 20, 0);
  }

  void _ajustarPlazoTrasCambioFecha({bool primeraVez = false}) {
    if (_fechaPartido == null) return;
    _horasLimite = primeraVez
        ? ConvocatoriaPlazoRespuesta.sugerirHoras(_fechaPartido!)
        : ConvocatoriaPlazoRespuesta.ajustarHoras(
            _horasLimite,
            _fechaPartido!,
          );
  }

  bool get _mostrarResumenConvocatoria =>
      _convocatoriaEnviada || _partidoConfirmado;

  bool get _puedeRegistrarCobros =>
      _fechaPartido != null &&
      PartidoLifecycle.puedeRegistrarGastosDesdeOrganizar(
        partido: Partido(
          fecha: _fechaPartido!,
          estado: _partidoConfirmado
              ? EstadoPartido.confirmado
              : EstadoPartido.organizando,
          createdAt: DateTime.now(),
        ),
        convocatoriaEnviada: _convocatoriaEnviada,
      );

  int get _enEsperaCount => _listaEspera.length;

  List<Jugador> get _titularesSinApp => _titulares
      .map(_jugadorPorId)
      .whereType<Jugador>()
      .where((j) => !j.tieneMatchPayApp)
      .toList();

  void _indexarJugadores(Iterable<Jugador> jugadores) {
    for (final j in jugadores) {
      if (j.keyId.isNotEmpty) _jugadoresPorId[j.keyId] = j;
    }
  }

  Jugador? _jugadorPorId(String id) => _jugadoresPorId[id];

  List<ConvocatoriaJugadorEntry> _titularesConvocatoriaEntries() {
    final partidoId = _partidoId ?? 0;
    return _titulares
        .map((id) {
          final jugador = _jugadorPorId(id);
          if (jugador == null) return null;
          return ConvocatoriaJugadorEntry(
            partidoId: partidoId,
            jugador: jugador,
            estado: _estados[id] ?? EstadoConfirmacion.invitado,
          );
        })
        .whereType<ConvocatoriaJugadorEntry>()
        .toList();
  }

  List<Jugador> _jugadoresTitularesEnPantalla() {
    final puedeSeleccionar =
        !_formularioBloqueado || _puedeEditarListaEspera;
    final base = puedeSeleccionar
        ? _habituales.where((j) => j.keyId.isNotEmpty)
        : _titulares.map(_jugadorPorId).whereType<Jugador>();
    final ordered = sortJugadoresParaConvocatoria(
      jugadores: base,
      invitadosIds: _titulares,
      esperaIds: _listaEspera,
      priorityIds: _prioridadJugadorIds,
    );
    return filterJugadoresByName(ordered, _jugadoresBusquedaCtrl.text);
  }

  bool _esTitular(String id) => _titulares.contains(id);

  bool _esSuplente(String id) => _listaEspera.contains(id);

  bool _estaSeleccionado(String id) => _esTitular(id) || _esSuplente(id);

  int get _cuposMax {
    final n = int.tryParse(_cuposCtrl.text.trim());
    return n == null || n < 1 ? 4 : n;
  }

  @override
  void initState() {
    super.initState();
    _partidoId = widget.partidoId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load().then((_) {
        if (mounted) _suscribirRealtime();
      });
    });
  }

  void _suscribirRealtime() {
    if (_partidoId == null || !mounted) return;
    final repos = AppRepositories.isReady
        ? AppRepositories.I
        : context.repos;
    if (!repos.isCloud) return;
    SupabaseRealtimeService.instance.subscribeConvocatoria(
      partidoId: _partidoId!,
      onChange: _recargarDesdeSupabase,
    );
  }

  Future<void> _recargarDesdeSupabase() async {
    if (_partidoId == null || !mounted || !_convocatoriaEnviada) return;
    await _sincronizarAutomatico();
    final conv = await context.repos.getConvocatoriaCompleta(_partidoId!);
    if (conv == null || !mounted) return;
    setState(() {
      _aplicarDesdeConvocatoria(conv);
      _partidoConfirmado = conv.partido.esConfirmado;
    });
  }

  @override
  void dispose() {
    SupabaseRealtimeService.instance.unsubscribeConvocatoria();
    _notasCtrl.dispose();
    _cuposCtrl.dispose();
    _jugadoresBusquedaCtrl.dispose();
    super.dispose();
  }

  Recinto? _recintoDesdePartido(Partido partido, List<Recinto> guardados) {
    if (partido.recintoId != null) {
      for (final r in guardados) {
        if (r.id == partido.recintoId) return r;
      }
    }
    final nombre = partido.recinto?.trim();
    if (nombre == null || nombre.isEmpty) return null;
    for (final r in guardados) {
      if (r.nombre.toLowerCase() == nombre.toLowerCase()) return r;
    }
    final mapsUrl = partido.recintoMapsUrl?.trim() ?? '';
    return Recinto(
      id: partido.recintoId,
      nombre: nombre,
      mapsUrl: mapsUrl,
      lat: partido.recintoLat,
      lng: partido.recintoLng,
      createdAt: partido.createdAt,
    );
  }

  Future<void> _load() async {
    try {
      final repos = AppRepositories.isReady
          ? AppRepositories.I
          : context.repos;
      final habituales = await repos.getJugadores(
        soloActivos: true,
        incluirUsuarioActual: true,
      );
      _jugadoresPorId.clear();
      _indexarJugadores(habituales);
      final recintosGuardados = await repos.getMisRecintos();
      final ultimoRecinto = await _prefs.ultimoRecinto;

      Recinto? recintoSel;

      if (_partidoId != null) {
        final conv = await repos.getConvocatoriaCompleta(_partidoId!);
        if (conv == null) {
          if (mounted) {
            setState(() {
              _loading = false;
              _errorCarga = context.l10n.tr('convocatoriaLoadUnavailable');
            });
          }
          return;
        }
        _fechaPartido = conv.partido.fecha;
        _sportType = conv.partido.sportType;
        recintoSel = _recintoDesdePartido(conv.partido, recintosGuardados);
        _notasCtrl.text = conv.partido.notas ?? '';
        _cuposCtrl.text = conv.partido.cuposMax.toString();
        _horasLimite = conv.partido.horasLimiteRespuesta;
        // Ajusta a opciones válidas para la fecha (evita crash del dropdown
        // si el partido quedó lejano y el plazo guardado era 1–2 h).
        _ajustarPlazoTrasCambioFecha();
        _partidoConfirmado = conv.partido.esConfirmado;
        _convocatoriaExpiradaAlCargar =
            PartidoLifecycle.convocatoriaExpirada(conv.partido);
        _convocatoriaEnviada =
            conv.titulares.any((entry) => entry.tiempoLimite != null);
        _aplicarDesdeConvocatoria(conv);
        if (!_partidoConfirmado && _convocatoriaEnviada) {
          await _listaEsperaService.sincronizar(_partidoId!);
          final actualizada = await repos.getConvocatoriaCompleta(_partidoId!);
          if (actualizada != null) {
            _aplicarDesdeConvocatoria(actualizada);
            recintoSel =
                _recintoDesdePartido(actualizada.partido, recintosGuardados);
          }
        }
        try {
          final ultimo = await repos.getUltimoPartido();
          if (ultimo != null) {
            _prioridadJugadorIds
              ..clear()
              ..addAll({
                for (final d in ultimo.detalles)
                  if (d.asistio) d.jugadorKeyId,
              });
          }
        } catch (_) {}
      } else {
        Set<String> prioridad = {};
        try {
          final ultimo = await repos.getUltimoPartido();
          if (ultimo != null) {
            prioridad = {
              for (final d in ultimo.detalles)
                if (d.asistio) d.jugadorKeyId,
            };
          }
        } catch (_) {}
        _prioridadJugadorIds
          ..clear()
          ..addAll(prioridad);

        final ordenados = sortJugadoresByPriority(
          jugadores: habituales,
          priorityIds: prioridad,
        );
        var titularesCount = 0;
        for (final j in ordenados) {
          if (j.keyId.isEmpty) continue;
          if (titularesCount >= _cuposMax) break;
          _titulares.add(j.keyId);
          _estados[j.keyId] = EstadoConfirmacion.invitado;
          titularesCount++;
        }
        if (ultimoRecinto.isNotEmpty) {
          for (final r in recintosGuardados) {
            if (r.nombre.toLowerCase() == ultimoRecinto.toLowerCase()) {
              recintoSel = r;
              break;
            }
          }
        }
        if (mounted) {
          _sportType = context.readSettings().sport;
        }
      }

      if (mounted) {
        setState(() {
          _habituales = habituales;
          _recintosGuardados = recintosGuardados;
          _recintoSeleccionado = recintoSel;
          _loading = false;
          _errorCarga = null;
          _dirty = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorCarga = context.userError(e);
        });
      }
    }
  }

  void _aplicarDesdeConvocatoria(ConvocatoriaCompleta conv) {
    _convocatoriaCompleta = conv;
    _titulares.clear();
    _listaEspera.clear();
    _estados.clear();
    for (final entry in conv.titulares) {
      final id = entry.jugador.keyId;
      if (id.isEmpty) continue;
      _titulares.add(id);
      _estados[id] = entry.estado;
      _jugadoresPorId[id] = entry.jugador;
    }
    for (final entry in conv.suplentes) {
      final id = entry.jugador.keyId;
      if (id.isEmpty) continue;
      _listaEspera.add(id);
      _estados[id] = entry.estado;
      _jugadoresPorId[id] = entry.jugador;
    }
    _partidoConfirmado = conv.partido.esConfirmado;
    if (!_partidoConfirmado) {
      _convocatoriaEnviada =
          conv.titulares.any((entry) => entry.tiempoLimite != null);
    }
  }

  Future<void> _sincronizarAutomatico() async {
    if (_partidoId == null || !_convocatoriaEnviada) {
      return;
    }
    final result = await _listaEsperaService.sincronizar(_partidoId!);
    if (!result.huboCambios || !mounted) return;
    final conv = await context.repos.getConvocatoriaCompleta(_partidoId!);
    if (conv == null || !mounted) return;
    setState(() {
      _aplicarDesdeConvocatoria(conv);
    });
    if (result.autoConfirmado && mounted) {
      setState(() => _partidoConfirmado = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('organizeAutoConfirmedSnack')),
        ),
      );
    } else if (result.promovidos > 0) {
      final now = DateTime.now();
      final puedeMostrar = _ultimoSnackPromocionAt == null ||
          now.difference(_ultimoSnackPromocionAt!) >
              const Duration(seconds: 45);
      if (puedeMostrar) {
        _ultimoSnackPromocionAt = now;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.tr(
                'organizePromotedFromWaitlist',
                params: {'count': '${result.promovidos}'},
              ),
            ),
          ),
        );
      }
      final sinAppPromovidos = result.invitadosPromovidos
          .where((j) => !j.tieneMatchPayApp && j.puedeEnviarWhatsApp)
          .toList();
      if (sinAppPromovidos.isNotEmpty && mounted) {
        await ConvocatoriaWhatsAppSinAppSheet.show(
          context,
          partidoId: _partidoId!,
          jugadores: sinAppPromovidos,
          estados: Map.from(_estados),
        );
      }
    }
  }

  String _formatoFechaHora(DateTime? fecha) =>
      fecha == null ? '' : formatDiaCompleto(fecha);

  Future<void> _pickFecha() async {
    if (_formularioBloqueado) return;
    final sugerida = _fechaPartido ?? _sugerenciaInicialPicker;
    final now = DateTime.now();
    final initialDate = sugerida.isAfter(now)
        ? sugerida
        : DateTime(now.year, now.month, now.day);

    final fecha = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      locale: Localizations.localeOf(context),
      helpText: context.l10n.tr('reprogramPickDateTitle'),
    );
    if (fecha == null || !mounted) return;

    final horaInicial = _fechaPartido != null
        ? TimeOfDay.fromDateTime(_fechaPartido!)
        : const TimeOfDay(hour: 20, minute: 0);

    final hora = await showTimePicker(
      context: context,
      initialTime: horaInicial,
      helpText: context.l10n.tr('reprogramPickTimeTitle'),
    );
    if (hora == null || !mounted) return;

    final nueva = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
      hora.hour,
      hora.minute,
    );
    if (!nueva.isAfter(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.tr('organizerCycleRescheduleFutureError'),
            ),
          ),
        );
      }
      return;
    }

    final primeraVez = _fechaPartido == null;
    setState(() {
      _fechaPartido = nueva;
      _ajustarPlazoTrasCambioFecha(primeraVez: primeraVez);
      _dirty = true;
    });
  }

  String _nombreJugador(String id) =>
      _jugadorPorId(id)?.nombre ?? context.l10n.tr('playerDefaultName');

  void _marcarDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _onCuposChanged(String _) {
    setState(() {
      _dirty = true;
      final max = _cuposMax;
      // Al bajar cupos, deselecciona el excedente (no va a espera solo:
      // la espera se arma marcando personas de más a propósito).
      while (_titulares.length > max) {
        final id = _titulares.removeLast();
        _listaEspera.remove(id);
        _estados.remove(id);
      }
    });
  }

  Future<void> _persistirEstadoJugador(String jugadorId) async {
    if (_partidoId == null) return;
    await context.repos.actualizarConfirmacion(
      partidoId: _partidoId!,
      jugadorId: jugadorId,
      estado: _estados[jugadorId] ?? EstadoConfirmacion.invitado,
    );
  }

  List<ConvocatoriaJugadorInput> _buildJugadoresInput() {
    final inputs = <ConvocatoriaJugadorInput>[];
    for (final id in _titulares) {
      inputs.add(ConvocatoriaJugadorInput(
        jugadorId: id,
        esSuplente: false,
        estado: _estados[id] ?? EstadoConfirmacion.invitado,
      ));
    }
    for (var i = 0; i < _listaEspera.length; i++) {
      final id = _listaEspera[i];
      inputs.add(ConvocatoriaJugadorInput(
        jugadorId: id,
        esSuplente: true,
        ordenEspera: i + 1,
        estado: _estados[id] ?? EstadoConfirmacion.invitado,
      ));
    }
    return inputs;
  }

  void _toggleTitular(String id, bool? value) {
    setState(() {
      if (_formularioBloqueado) {
        // Tras enviar: los invitados quedan fijos; solo se puede
        // agregar/quitar gente de la lista de espera.
        if (_esTitular(id)) return;
        if (value == true) {
          if (!_listaEspera.contains(id)) _listaEspera.add(id);
          _estados.putIfAbsent(id, () => EstadoConfirmacion.invitado);
        } else {
          _listaEspera.remove(id);
          _estados.remove(id);
        }
        _dirty = true;
      } else if (value == true) {
        if (_esTitular(id) || _esSuplente(id)) return;
        if (_titulares.length < _cuposMax) {
          _listaEspera.remove(id);
          _titulares.add(id);
        } else {
          // Cupos de invitación llenos → pasa a lista de espera.
          if (!_listaEspera.contains(id)) _listaEspera.add(id);
        }
        _estados.putIfAbsent(id, () => EstadoConfirmacion.invitado);
        _dirty = true;
      } else {
        _titulares.remove(id);
        _listaEspera.remove(id);
        _estados.remove(id);
        _dirty = true;
      }
    });
    if (_formularioBloqueado &&
        _partidoId != null &&
        _convocatoriaEnviada) {
      unawaited(_guardar(silencioso: true, actualizarGuardando: false));
    }
  }

  void _moverEspera(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final id = _listaEspera.removeAt(oldIndex);
      _listaEspera.insert(newIndex, id);
      _dirty = true;
    });
    if (_puedeEditarListaEspera && _partidoId != null) {
      unawaited(_persistirOrdenListaEspera());
    }
  }

  Future<void> _persistirOrdenListaEspera() async {
    if (_partidoId == null || _listaEspera.isEmpty) return;
    try {
      await context.repos.actualizarOrdenListaEspera(
        partidoId: _partidoId!,
        jugadorIdsEnOrden: List.from(_listaEspera),
      );
      if (mounted) setState(() => _dirty = false);
    } catch (e) {
      if (mounted) _mostrarError(context.userError(e));
    }
  }

  Future<void> _quitarDeListaEspera(String id) async {
    setState(() {
      _listaEspera.remove(id);
      _estados.remove(id);
      _dirty = true;
    });
    if (_partidoId != null && _convocatoriaEnviada) {
      await _guardar(silencioso: true, actualizarGuardando: false);
    }
  }

  void _seleccionarTodosTitulares() {
    setState(() {
      _titulares.clear();
      _estados.removeWhere((id, _) => !_listaEspera.contains(id));
      var count = 0;
      // Con filtro activo: prioriza los visibles; si no, toda la lista.
      final fuente = _jugadoresTitularesEnPantalla();
      for (final j in fuente) {
        if (j.keyId.isEmpty) continue;
        if (count < _cuposMax) {
          _titulares.add(j.keyId);
          _listaEspera.remove(j.keyId);
          _estados[j.keyId] = EstadoConfirmacion.invitado;
          count++;
        }
      }
      _dirty = true;
    });
  }

  void _limpiarSeleccion() {
    setState(() {
      _titulares.clear();
      _listaEspera.clear();
      _estados.clear();
      _dirty = true;
    });
  }

  Future<void> _autoConfirmarSiCompleto() async {
    if (_partidoId == null || _partidoConfirmado || !_convocatoriaEnviada) {
      return;
    }
    if (_confirmados < _cuposMax) return;

    await context.repos.marcarConvocatoriaConfirmada(_partidoId!);
    if (!mounted) return;
    setState(() => _partidoConfirmado = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.tr('organizeAutoConfirmedSnack')),
      ),
    );
  }

  Future<void> _ciclarEstado(String id) async {
    if (!_puedeEditarEstados || !_esTitular(id)) return;
    if (_jugadorPorId(id)?.tieneMatchPayApp == true) return;

    final actual = _estados[id] ?? EstadoConfirmacion.invitado;
    final siguiente = actual.siguiente();

    if (siguiente == EstadoConfirmacion.confirmado &&
        actual != EstadoConfirmacion.confirmado &&
        _cuposLlenos) {
      _mostrarError(
        context.l10n.tr(
          'organizeSlotsFullError',
          params: {'max': '$_cuposMax'},
        ),
      );
      return;
    }

    setState(() {
      _estados[id] = siguiente;
    });

    if (_partidoId != null) {
      await _persistirEstadoJugador(id);
      if (siguiente == EstadoConfirmacion.rechazado ||
          actual == EstadoConfirmacion.rechazado) {
        await _sincronizarAutomatico();
      } else {
        await _autoConfirmarSiCompleto();
      }
    } else {
      _marcarDirty();
    }
  }

  Future<bool> _guardar({
    bool silencioso = false,
    bool actualizarGuardando = true,
  }) async {
    if (_titulares.isEmpty && _listaEspera.isEmpty) {
      _mostrarError(context.l10n.tr('organizeSelectStarterOrSub'));
      return false;
    }
    if (_titulares.length < _cuposMax) {
      _mostrarError(
        context.l10n.tr(
          'organizeNominateStartersError',
          params: {
            'max': '$_cuposMax',
            'current': '${_titulares.length}',
          },
        ),
      );
      return false;
    }
    if (_titulares.length > _cuposMax) {
      _mostrarError(
        context.l10n.tr(
          'organizeMaxStartersShort',
          params: {'max': '$_cuposMax'},
        ),
      );
      return false;
    }

    if (_fechaPartido == null) {
      _mostrarError(context.l10n.tr('organizeMatchDateRequired'));
      return false;
    }
    if (!_fechaPartido!.isAfter(DateTime.now())) {
      _mostrarError(context.l10n.tr('organizeMatchDateMustBeFuture'));
      return false;
    }

    final recinto = _recintoSeleccionado;
    if (recinto == null || recinto.nombre.trim().isEmpty) {
      _mostrarError(context.l10n.tr('venueRequiredError'));
      return false;
    }
    if (!recinto.location.hasExactLocation) {
      _mostrarError(context.l10n.tr('venueMapsRequiredError'));
      return false;
    }

    if (context.repos.isCloud) {
      final sinId = _titulares.where((id) => id.isEmpty).toList();
      if (sinId.isNotEmpty) {
        _mostrarError(context.l10n.tr('organizeStartersNoProfileError'));
        return false;
      }
    }

    if (actualizarGuardando) setState(() => _guardando = true);
    try {
      final notas = _notasCtrl.text.trim();
      final jugadores = _buildJugadoresInput();

      final repos = context.repos;
      if (_partidoId == null) {
        _partidoId = await repos.crearConvocatoria(
          fecha: _fechaPartido!,
          recinto: recinto.nombre.trim(),
          recintoId: recinto.id,
          recintoMapsUrl: recinto.mapsUrl,
          recintoLat: recinto.lat,
          recintoLng: recinto.lng,
          notas: notas.isEmpty ? null : notas,
          cuposMax: _cuposMax,
          horasLimiteRespuesta: _horasLimite,
          jugadores: jugadores,
          sportType: _sportType,
        );
      } else {
        final partidoId = _partidoId!;
        final reabrirConvocatoria = _convocatoriaExpiradaAlCargar &&
            _fechaPartido!.isAfter(DateTime.now());
        if (reabrirConvocatoria) {
          await repos.reprogramarConvocatoria(
            partidoId: partidoId,
            nuevaFecha: _fechaPartido!,
          );
          final fresh = await repos.getConvocatoriaCompleta(partidoId);
          if (fresh != null && mounted) {
            final result = await ConvocatoriaComunicacionService()
                .avisarReprogramacion(fresh);
            if (result.sinApp.isNotEmpty && mounted) {
              final estados = {
                for (final e in fresh.titulares)
                  e.jugador.keyId: e.estado,
              };
              await ConvocatoriaWhatsAppSinAppSheet.show(
                context,
                partidoId: partidoId,
                jugadores: result.sinApp,
                estados: estados,
              );
            }
          }
        }
        await repos.actualizarConvocatoria(
          partidoId: partidoId,
          fecha: _fechaPartido!,
          recinto: recinto.nombre.trim(),
          recintoId: recinto.id,
          recintoMapsUrl: recinto.mapsUrl,
          recintoLat: recinto.lat,
          recintoLng: recinto.lng,
          notas: notas.isEmpty ? null : notas,
          cuposMax: _cuposMax,
          horasLimiteRespuesta: _horasLimite,
          jugadores: jugadores,
          sportType: _sportType,
        );
        if (_convocatoriaEnviada && mounted) {
          final fresh = await repos.getConvocatoriaCompleta(partidoId);
          if (fresh != null && mounted) {
            setState(() => _aplicarDesdeConvocatoria(fresh));
          }
        }
      }

      await _prefs.saveUltimoRecinto(recinto.nombre.trim());

      if (!silencioso && mounted) {
        setState(() => _dirty = false);
      } else if (silencioso && mounted && _dirty) {
        // Auto-guardado en seguimiento: no dejar dirty colgado.
        setState(() => _dirty = false);
      }
      return true;
    } catch (e) {
      _mostrarError(context.userError(e));
      return false;
    } finally {
      if (actualizarGuardando && mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  Future<bool> _confirmarSalidaSinGuardar() async {
    if (!_dirty) return true;

    final enviada = _convocatoriaEnviada;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          enviada
              ? ctx.l10n.tr('organizeExitConfirmTitle')
              : ctx.l10n.tr('organizeExitWithoutSavingTitle'),
        ),
        content: Text(
          enviada
              ? ctx.l10n.tr('organizeExitStatesSavedBody')
              : ctx.l10n.tr('organizeExitDraftBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            child: Text(ctx.l10n.tr('organizeKeepEditing')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'descartar'),
            child: Text(
              enviada
                  ? ctx.l10n.tr('organizeExitConfirmAction')
                  : ctx.l10n.tr('organizeExitWithoutSaving'),
            ),
          ),
          if (!enviada)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'borrador'),
              child: Text(ctx.l10n.tr('organizeSaveDraft')),
            ),
        ],
      ),
    );

    if (action == 'cancelar' || !mounted) return false;
    if (action == 'descartar') return true;
    if (action == 'borrador') {
      if (!await _guardar(silencioso: true)) return false;
      if (mounted) Navigator.pop(context, true);
      return false;
    }
    return false;
  }

  Future<void> _enviarConvocatoria() async {
    if (_convocatoriaEnviada || _partidoConfirmado) {
      _mostrarError(
        _partidoConfirmado
            ? context.l10n.tr('organizeMatchAlreadyConfirmed')
            : context.l10n.tr('organizeInviteAlreadySent'),
      );
      return;
    }

    if (_titulares.isEmpty) {
      _mostrarError(context.l10n.tr('organizeSelectAtLeastOneStarter'));
      return;
    }

    final recinto = _recintoSeleccionado;
    if (recinto == null || recinto.nombre.trim().isEmpty) {
      _mostrarError(context.l10n.tr('venueRequiredError'));
      return;
    }
    if (!recinto.location.hasExactLocation) {
      _mostrarError(context.l10n.tr('venueMapsRequiredError'));
      return;
    }

    setState(() => _guardando = true);
    try {
      if (!await _guardar(silencioso: true, actualizarGuardando: false)) {
        return;
      }

      await context.repos.activarTiemposLimiteConvocatoria(
        partidoId: _partidoId!,
        horasLimite: _horasLimite,
      );

      final titularesJugadores = _titulares
          .map(_jugadorPorId)
          .whereType<Jugador>()
          .toList();
      await _notificaciones.notificarConvocatoriaTitulares(
        titulares: titularesJugadores,
        partidoId: _partidoId!,
        fecha: _fechaPartido!,
        horasLimite: _horasLimite,
        recinto: recinto.nombre.trim(),
        sportType: _sportType,
      );

      if (!mounted) return;
      setState(() {
        _convocatoriaEnviada = true;
        _dirty = false;
      });
      _suscribirRealtime();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('organizeInviteSentSnack'))),
      );
      if (_titularesSinApp.isNotEmpty) {
        await ConvocatoriaWhatsAppSinAppSheet.show(
          context,
          partidoId: _partidoId!,
          jugadores: _titularesSinApp,
          estados: Map.from(_estados),
        );
      }
    } catch (e) {
      _mostrarError(context.userError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _mostrarWhatsAppSinAppSheet() async {
    if (_partidoId == null || _titularesSinApp.isEmpty) return;
    await ConvocatoriaWhatsAppSinAppSheet.show(
      context,
      partidoId: _partidoId!,
      jugadores: _titularesSinApp,
      estados: Map.from(_estados),
    );
  }

  void _salirTrasCancelar() {
    if (!mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  Future<void> _registrarCobros() async {
    final confirmados = _titulares
        .where((id) => _estados[id] == EstadoConfirmacion.confirmado)
        .toList();

    if (confirmados.isEmpty) {
      if (!mounted) return;
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.tr('organizeNoConfirmedTitle')),
          content: Text(ctx.l10n.tr('organizeNoConfirmedBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.tr('continueBtn')),
            ),
          ],
        ),
      );
      if (continuar != true || !mounted) return;
    }

    if (!mounted) return;
    await Navigator.pushNamed(
      context,
      '/registrar-partido',
      arguments: _partidoId,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _eliminarConvocatoria() async {
    if (_partidoId == null) return;
    final ok = await confirmarYEliminarConvocatoria(
      context,
      partidoId: _partidoId!,
      convocatoria: _convocatoriaCompleta,
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _abrirMapaRecinto() async {
    final recinto = _recintoSeleccionado;
    if (recinto == null) {
      _mostrarError(context.l10n.tr('venueRequiredError'));
      return;
    }
    try {
      final ok = await recinto.location.open();
      if (!ok && mounted) {
        _mostrarError(context.l10n.tr('openVenueMapError'));
      }
    } catch (_) {
      if (mounted) _mostrarError(context.l10n.tr('openVenueMapError'));
    }
  }

  Future<void> _administrarRecintos() async {
    final actualizados = await showMisRecintosManager(context);
    if (!mounted) return;
    final list = actualizados ?? await AppRepositories.I.getMisRecintos();
    setState(() {
      _recintosGuardados = list;
      if (_recintoSeleccionado != null) {
        final id = _recintoSeleccionado!.id;
        Recinto? still;
        for (final r in list) {
          if (r.id == id) {
            still = r;
            break;
          }
        }
        _recintoSeleccionado = still;
        if (still == null) _marcarDirty();
      }
    });
  }

  Future<void> _elegirRecintoGuardado() async {
    if (_recintosGuardados.isEmpty) {
      await _administrarRecintos();
      return;
    }
    final elegido = await showModalBottomSheet<Recinto>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                ctx.l10n.tr('venuePickHint'),
                style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 13),
              ),
            ),
            ..._recintosGuardados.map(
              (r) => ListTile(
                leading: Icon(
                  r.location.hasExactLocation
                      ? Icons.place
                      : Icons.place_outlined,
                  color: r.location.hasExactLocation
                      ? MatchPayTokens.accentSuccess
                      : MatchPayTokens.inkMuted,
                ),
                title: Text(r.nombre),
                subtitle: Text(
                  r.direccion?.isNotEmpty == true
                      ? r.direccion!
                      : (r.location.hasExactLocation
                          ? ctx.l10n.tr('venueHasExactMap')
                          : ctx.l10n.tr('venueNoExactMap')),
                ),
                selected: _recintoSeleccionado?.id == r.id,
                onTap: () => Navigator.pop(ctx, r),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || elegido == null) return;
    setState(() {
      _recintoSeleccionado = elegido;
      _marcarDirty();
    });
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themed = context.readSettings().themeForSport(_sportType);
    return Theme(
      data: themed,
      child: PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final salir = await _confirmarSalidaSinGuardar();
        if (!mounted) return;
        if (salir) Navigator.pop(context);
      },
      child: Scaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: themed.colorScheme.primary,
        foregroundColor: Colors.white,
        title: Text(
          _partidoConfirmado
              ? context.l10n.tr('organizeMatchConfirmedTitle')
              : _modoSeguimiento
                  ? context.l10n.tr('organizeTrackingTitle')
                  : widget.isEditing
                      ? context.l10n.tr('convocatoriaTitle')
                      : context.l10n.tr('organizeTitle'),
        ),
        actions: [
          if (_modoSeguimiento)
            IconButton(
              icon: Icon(
                _editarSeguimiento
                    ? Icons.fact_check_outlined
                    : Icons.edit_outlined,
              ),
              tooltip: _editarSeguimiento
                  ? context.l10n.tr('organizeTrackingTitle')
                  : context.l10n.tr('asistenciasEditDetails'),
              onPressed: () => setState(
                () => _editarSeguimiento = !_editarSeguimiento,
              ),
            ),
          if (_partidoId != null)
            IconButton(
              icon: Icon(
                _confirmados > 0
                    ? Icons.event_busy_outlined
                    : Icons.delete_outline,
              ),
              tooltip: _confirmados > 0
                  ? context.l10n.tr('organizerCycleAtRiskCancel')
                  : context.l10n.tr('deleteTooltip'),
              onPressed: _eliminarConvocatoria,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga != null
              ? Column(
                  children: [
                    Expanded(
                      child: FriendlyErrorPanel(
                        message: _errorCarga!,
                        onRetry: () {
                          setState(() {
                            _loading = true;
                            _errorCarga = null;
                          });
                          _load();
                        },
                      ),
                    ),
                    if (_partidoId != null)
                      SafeArea(
                        minimum: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _eliminarConvocatoria,
                            icon: Icon(
                              _confirmados > 0
                                  ? Icons.event_busy_outlined
                                  : Icons.delete_outline_rounded,
                            ),
                            label: Text(
                              context.l10n.tr(
                                _confirmados > 0
                                    ? 'organizerCycleAtRiskCancel'
                                    : 'organizerCycleDeleteConvocatoria',
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              : _modoSeguimiento && !_editarSeguimiento
                  ? _buildAsistenciasBody()
                  : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                AyudaTip(
                  texto: _fechaPartidoPasada && _convocatoriaEnviada
                      ? context.l10n.tr('organizePastDateBanner')
                      : _partidoConfirmado
                          ? context.l10n.tr('organizeHelpConfirmed')
                          : _modoSeguimiento
                              ? context.l10n.tr('organizeHelpTracking')
                              : context.l10n.tr('organizeHelpDraft'),
                ),
                if (_modoSeguimiento && _editarSeguimiento) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _editarSeguimiento = false),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(context.l10n.tr('organizeTrackingTitle')),
                    ),
                  ),
                ],
                if (_convocatoriaEnviada && _convocatoriaCompleta != null) ...[
                  if (_shouldShowEstadoSeguimiento) ...[
                    const SizedBox(height: 12),
                    MatchPaySurfaceCard(
                      padding: const EdgeInsets.all(14),
                      child: PartidoEstadoPublicoMessage(
                        view: PartidoEstadoPublicoView.resolve(
                          _convocatoriaCompleta!,
                        ),
                        fechaPartido: _convocatoriaCompleta!.partido.fecha,
                        showBody: true,
                      ),
                    ),
                  ],
                ],
                if (_cupoImposible && _partidoId != null && !_modoSeguimiento) ...[
                  const SizedBox(height: 12),
                  ConvocatoriaDecisionPanel(
                    partidoId: _partidoId,
                    onCompleted: () {
                      if (mounted) unawaited(_load());
                    },
                    onCancelSuccess: _salirTrasCancelar,
                  ),
                ],
                const SizedBox(height: 12),
                _buildFechaHoraHero(),
                if (_mostrarResumenConvocatoria) ...[
                  const SizedBox(height: 12),
                  _buildResumen(),
                ],
                const SizedBox(height: 12),
                _buildDatosPartido(),
                const SizedBox(height: 12),
                _buildListaJugadores(),
                const SizedBox(height: 80),
              ],
            ),
      bottomNavigationBar: _errorCarga != null
          ? null
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_partidoConfirmado)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: MatchPayTokens.accentSuccess,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.l10n.tr(
                          'organizeConfirmedBar',
                          params: {
                            'confirmed': '$_confirmados',
                            'max': '$_cuposMax',
                          },
                        ),
                        style: MatchPayTokens.titleSmallStyle(
                          color: MatchPayTokens.accentSuccess,
                        ).copyWith(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            if (_puedeRegistrarCobros)
              FilledButton.icon(
                onPressed: _registrarCobros,
                icon: SportIcon(size: 20),
                label: Text(context.l10n.tr('goToCharges')),
                style: FilledButton.styleFrom(
                  backgroundColor: MatchPayTokens.accentSuccess,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(MatchPayTokens.radiusButton),
                  ),
                ),
              )
            else if (!_convocatoriaEnviada)
              FilledButton.icon(
                onPressed: _guardando ? null : _enviarConvocatoria,
                icon: _guardando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.campaign_rounded),
                label: Text(context.l10n.tr('sendConvocatoria')),
                style: FilledButton.styleFrom(
                  backgroundColor: context.sportPalette.primary,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(MatchPayTokens.radiusButton),
                  ),
                ),
              )
            else if (_partidoConfirmado && !_puedeRegistrarCobros)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.l10n.tr(
                    'organizeChargesAfterMatch',
                    params: {'when': _formatoFechaHora(_fechaPartido)},
                  ),
                  style: MatchPayTokens.bodySmallStyle(
                    color: MatchPayTokens.inkMuted,
                  ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              )
            else if (_modoSeguimiento) ...[
              if (_cupoImposible && _partidoId != null)
                ConvocatoriaDecisionPanel(
                  showHeader: false,
                  partidoId: _partidoId,
                  onCompleted: () {
                    if (mounted) unawaited(_load());
                  },
                  onCancelSuccess: _salirTrasCancelar,
                )
              else ...[
                FilledButton.icon(
                  onPressed: _pendientes > 0 ? _recordarPendientesAsistencias : null,
                  icon: const Icon(Icons.campaign_rounded),
                  label: Text(context.l10n.tr('asistenciasRemindPending')),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.sportPalette.primary,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(MatchPayTokens.radiusButton),
                    ),
                  ),
                ),
                if (_titularesSinApp.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _mostrarWhatsAppSinAppSheet,
                    icon: const Icon(
                      Icons.chat_outlined,
                      color: Color(0xFF25D366),
                    ),
                    label: Text(context.l10n.tr('organizeWhatsAppNoAppButton')),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: const Color(0xFF1B8F4E),
                      side: const BorderSide(color: Color(0xFF25D366)),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(MatchPayTokens.radiusButton),
                      ),
                    ),
                  ),
                ],
                if (_cuposLlenos)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      context.l10n.tr('organizeAutoConfirmInProgress'),
                      style: MatchPayTokens.titleSmallStyle(
                        color: MatchPayTokens.accentUrgent,
                      ).copyWith(fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ],
            ],
          ),
        ),
      ),
    ),
    ),
    );
  }

  Widget _buildAsistenciasBody() {
    final fecha = _fechaPartido ?? DateTime.now();
    final recinto = _recintoSeleccionado?.nombre.trim() ??
        (_convocatoriaCompleta?.partido.recinto ?? '').trim();
    final titulares = _titulares
        .map((id) {
          final j = _jugadorPorId(id);
          if (j == null) return null;
          return ConvocatoriaAsistenciaItem(
            jugador: j,
            estado: _estados[id] ?? EstadoConfirmacion.invitado,
          );
        })
        .whereType<ConvocatoriaAsistenciaItem>()
        .toList();
    final suplentes = _listaEspera
        .map((id) {
          final j = _jugadorPorId(id);
          if (j == null) return null;
          return ConvocatoriaAsistenciaItem(
            jugador: j,
            estado: _estados[id] ?? EstadoConfirmacion.invitado,
            esSuplente: true,
          );
        })
        .whereType<ConvocatoriaAsistenciaItem>()
        .toList();

    Widget? banner;
    if (_cupoImposible && _partidoId != null) {
      banner = ConvocatoriaDecisionPanel(
        partidoId: _partidoId,
        onCompleted: () {
          if (mounted) unawaited(_load());
        },
        onCancelSuccess: _salirTrasCancelar,
      );
    } else if (_shouldShowEstadoSeguimiento && _convocatoriaCompleta != null) {
      banner = MatchPaySurfaceCard(
        padding: const EdgeInsets.all(14),
        child: PartidoEstadoPublicoMessage(
          view: PartidoEstadoPublicoView.resolve(_convocatoriaCompleta!),
          fechaPartido: _convocatoriaCompleta!.partido.fecha,
          showBody: true,
        ),
      );
    }

    return ConvocatoriaAsistenciasView(
      fecha: fecha,
      recinto: recinto,
      sportType: _sportType,
      cuposMax: _cuposMax,
      statusLabel: context.l10n.tr('asistenciasStatusInProgress'),
      titulares: titulares,
      suplentes: suplentes,
      topBanner: banner,
      onCycleEstado: _puedeEditarEstados
          ? (id) {
              unawaited(_ciclarEstado(id));
            }
          : null,
    );
  }

  Future<void> _recordarPendientesAsistencias() async {
    final conv = _convocatoriaCompleta;
    if (conv == null) return;
    await ReprogramarConvocatoriaFlow.recordarPendientes(
      context,
      convocatoria: conv,
    );
  }

  Widget _buildFechaHoraHero() {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final fecha = _fechaPartido;
    final bloqueado = _formularioBloqueado;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: bloqueado ? null : _pickFecha,
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: fecha == null
                  ? [
                      MatchPayTokens.accentCredit.withValues(alpha: 0.14),
                      MatchPayTokens.accentCredit.withValues(alpha: 0.06),
                    ]
                  : [
                      palette.primary.withValues(alpha: 0.16),
                      palette.primary.withValues(alpha: 0.06),
                    ],
            ),
            border: Border.all(
              color: fecha == null
                  ? MatchPayTokens.accentCredit.withValues(alpha: 0.45)
                  : palette.primary.withValues(alpha: 0.35),
              width: fecha == null ? 1.5 : 1,
            ),
            boxShadow: MatchPayTokens.shadowCard(elevated: fecha != null),
          ),
          padding: const EdgeInsets.all(18),
          child: fecha == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: MatchPayTokens.accentCredit
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.event_rounded,
                            color: MatchPayTokens.accentCredit,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.tr('organizePickMatchWhenTitle'),
                                style: MatchPayTokens.titleMediumStyle(
                                  color: MatchPayTokens.accentCredit,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.tr('organizePickMatchWhenSubtitle'),
                                style: MatchPayTokens.bodySmallStyle(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!bloqueado) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _pickFecha,
                        icon: const Icon(Icons.calendar_month_rounded),
                        label: Text(l10n.tr('organizePickMatchWhenAction')),
                        style: FilledButton.styleFrom(
                          backgroundColor: MatchPayTokens.accentCredit,
                          minimumSize: const Size.fromHeight(44),
                        ),
                      ),
                    ],
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.tr('dateAndTime').toUpperCase(),
                      style: MatchPayTokens.sectionLabelStyle(
                        color: palette.primary,
                      ).copyWith(letterSpacing: 0.8),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      formatDiaCompleto(fecha),
                      style: MatchPayTokens.titleMediumStyle(
                        color: palette.primaryDark,
                      ).copyWith(
                        fontSize: bloqueado ? 22 : 20,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatEnCuanto(fecha),
                      style: MatchPayTokens.bodySmallStyle(
                        color: MatchPayTokens.inkSecondary,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (bloqueado &&
                        _recintoSeleccionado?.nombre.trim().isNotEmpty ==
                            true) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 16,
                            color: palette.primaryDark.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _recintoSeleccionado!.nombre.trim(),
                              style: MatchPayTokens.bodySmallStyle(
                                color: palette.primaryDark,
                              ).copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (!bloqueado) ...[
                      const SizedBox(height: 10),
                      Text(
                        l10n.tr('organizePickMatchWhenChange'),
                        style: MatchPayTokens.bodySmallStyle(
                          color: palette.primary,
                        ).copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildResumen() {
    final palette = context.sportPalette;
    return MatchPaySurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_partidoConfirmado)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: MatchPayTokens.accentSuccessBg,
                borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: MatchPayTokens.accentSuccess,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      context.l10n.tr('organizeBannerConfirmed'),
                      style: MatchPayTokens.titleSmallStyle(
                        color: MatchPayTokens.accentSuccess,
                      ).copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          if (_modoSeguimiento) ...[
            Text(
              context.l10n.tr('organizeTrackingSectionTitle'),
              style: MatchPayTokens.sectionLabelStyle(
                color: palette.primary,
              ).copyWith(letterSpacing: 0.6),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ConvocatoriaAvatarStrip(
                titulares: _titularesConvocatoriaEntries(),
                cuposMax: _cuposMax,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.tr(
                        'organizeSummaryCounts',
                        params: {
                          'confirmed': '$_confirmados',
                          'max': '$_cuposMax',
                          'pending': '$_pendientes',
                          'waiting': '$_enEsperaCount',
                        },
                      ),
                      style: MatchPayTokens.titleMediumStyle(
                        color: _cuposLlenos
                            ? MatchPayTokens.accentUrgent
                            : palette.primaryDark,
                      ),
                    ),
                    Text(
                      _cuposLlenos
                          ? context.l10n.tr(
                              'organizeSummarySlotsFull',
                              params: {'starters': '${_titulares.length}'},
                            )
                          : context.l10n.tr(
                              'organizeSummarySlotsAvailable',
                              params: {
                                'available': '$_cuposDisponibles',
                                'starters': '${_titulares.length}',
                                'subs': '$_enEsperaCount',
                              },
                            ),
                      style: MatchPayTokens.bodySmallStyle(
                        color: palette.primaryDark,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _buildPlazoHelperText() {
    final fecha = _fechaPartido;
    if (fecha == null) return null;
    final l10n = context.l10n;
    final limite = ConvocatoriaPlazoRespuesta.calcularTiempoLimite(
      enviadoEn: DateTime.now(),
      horasLimite: _horasLimite,
      fechaPartido: fecha,
    );
    final deadline = formatFechaHora(limite);
    final recortado = ConvocatoriaPlazoRespuesta.plazoRecortadoPorPartido(
      horasLimite: _horasLimite,
      fechaPartido: fecha,
    );
    if (recortado) {
      return l10n.tr(
        'organizeResponseDeadlineCapped',
        params: {'deadline': deadline},
      );
    }
    return l10n.tr(
      'organizeResponseDeadlineHint',
      params: {'deadline': deadline},
    );
  }

  Widget _buildDatosPartido() {
    if (_formularioBloqueado) {
      final recinto = _recintoSeleccionado;
      return MatchPaySurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.tr('matchDetailsTitle'),
              style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 15),
            ),
            const SizedBox(height: 12),
            SportChargeChip(sport: _sportType),
            if (recinto != null) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.place_outlined,
                    size: 20,
                    color: context.sportPalette.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recinto.nombre,
                          style: MatchPayTokens.titleSmallStyle().copyWith(
                            fontSize: 14,
                          ),
                        ),
                        if (recinto.location.hasExactLocation) ...[
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await recinto.location.open();
                            },
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: Text(
                              context.l10n.tr('openExactVenueMap'),
                            ),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    return MatchPaySurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.tr('matchDetailsTitle'),
            style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 15),
          ),
            const SizedBox(height: 12),
          MatchSportPicker(
            value: _sportType,
            onChanged: (sport) => setState(() {
              _sportType = sport;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 12),
            InputDecorator(
              decoration: InputDecoration(
                labelText: context.l10n.tr('venueLabelRequired'),
                prefixIcon: const Icon(Icons.place),
                border: const OutlineInputBorder(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _recintoSeleccionado?.nombre ??
                        context.l10n.tr('venuePickHint'),
                    style: TextStyle(
                      fontWeight: _recintoSeleccionado == null
                          ? FontWeight.normal
                          : FontWeight.w600,
                      color: _recintoSeleccionado == null
                          ? MatchPayTokens.inkMuted
                          : null,
                    ),
                  ),
                  if (_recintoSeleccionado != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _recintoSeleccionado!.location.hasExactLocation
                          ? context.l10n.tr('venueHasExactMap')
                          : context.l10n.tr('venueNoExactMap'),
                      style: MatchPayTokens.bodySmallStyle(
                        color: _recintoSeleccionado!.location.hasExactLocation
                            ? MatchPayTokens.accentSuccess
                            : MatchPayTokens.accentUrgent,
                      ).copyWith(fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (!_formularioBloqueado)
                        FilledButton.tonalIcon(
                          onPressed: _elegirRecintoGuardado,
                          icon: const Icon(Icons.list_alt, size: 18),
                          label: Text(
                            _recintosGuardados.isEmpty
                                ? context.l10n.tr('venueManageInSettings')
                                : context.l10n.tr('venueChooseSaved'),
                          ),
                        ),
                      if (!_formularioBloqueado)
                        TextButton(
                          onPressed: _administrarRecintos,
                          child: Text(context.l10n.tr('venueManageShort')),
                        ),
                      OutlinedButton.icon(
                        onPressed: _recintoSeleccionado == null
                            ? null
                            : _abrirMapaRecinto,
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: Text(context.l10n.tr('openVenueMapTooltip')),
                      ),
                    ],
                  ),
                  if (!_formularioBloqueado && _recintosGuardados.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        context.l10n.tr('venueOrganizeEmptyHint'),
                        style: MatchPayTokens.bodySmallStyle(
                          color: MatchPayTokens.accentUrgent,
                        ).copyWith(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cuposCtrl,
              readOnly: _formularioBloqueado,
              onChanged: _formularioBloqueado ? null : _onCuposChanged,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: context.l10n.tr('organizeMaxSlotsLabel'),
                prefixIcon: const Icon(Icons.people),
              ),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final opciones = _opcionesPlazo;
                assert(opciones.isNotEmpty);
                final valor = opciones.contains(_horasLimite)
                    ? _horasLimite
                    : opciones.last;
                if (valor != _horasLimite) {
                  // Sync diferido: evita value fuera de items (assert Flutter).
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (_horasLimite != valor) {
                      setState(() => _horasLimite = valor);
                    }
                  });
                }
                return DropdownButtonFormField<int>(
                  key: ValueKey('plazo-${opciones.join('-')}'),
                  value: valor,
                  decoration: InputDecoration(
                    labelText:
                        context.l10n.tr('organizeResponseDeadlineLabel'),
                    prefixIcon: const Icon(Icons.timer_outlined),
                    helperText: _fechaPartido == null
                        ? context.l10n
                            .tr('organizeResponseDeadlineNeedDate')
                        : _buildPlazoHelperText(),
                    helperMaxLines: 2,
                  ),
                  items: opciones
                      .map(
                        (h) => DropdownMenuItem(
                          value: h,
                          child: Text(
                            context.l10n.tr(
                              'organizeHoursCount',
                              params: {'n': '$h'},
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _formularioBloqueado || _fechaPartido == null
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            _horasLimite = v;
                            _dirty = true;
                          });
                        },
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notasCtrl,
              readOnly: _formularioBloqueado,
              onChanged: _formularioBloqueado ? null : (_) => _marcarDirty(),
              maxLines: 2,
              decoration: InputDecoration(
                labelText: context.l10n.tr('notesOptionalLabel'),
                prefixIcon: const Icon(Icons.notes),
              ),
            ),
          ],
        ),
    );
  }

  Widget _buildListaJugadores() {
    if (_habituales.isEmpty && _titulares.isEmpty) {
      return MatchPaySurfaceCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.person_add_rounded,
                size: 48, color: MatchPayTokens.inkMuted),
            const SizedBox(height: 8),
            Text(
              context.l10n.tr('organizeAddRegularPlayersFirst'),
              style: MatchPayTokens.bodySmallStyle(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pushNamed(context, '/jugadores'),
              child: Text(context.l10n.tr('navPlayers')),
            ),
          ],
        ),
      );
    }

    final sinSeleccion =
        _titulares.isEmpty && _listaEspera.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MatchPaySurfaceCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.tr('organizeStartersTitle'),
                      style: MatchPayTokens.titleSmallStyle().copyWith(
                        fontSize: 15,
                      ),
                    ),
                  ),
                    TextButton(
                      onPressed: _formularioBloqueado ? null : _seleccionarTodosTitulares,
                      child: Text(context.l10n.tr('organizeAutoSelect')),
                    ),
                    TextButton(
                      onPressed: _formularioBloqueado ? null : _limpiarSeleccion,
                      child: Text(context.l10n.tr('organizeClearSelection')),
                    ),
                  ],
                ),
                Text(
                  _modoSeguimiento
                      ? context.l10n.tr('organizeStartersHintTracking')
                      : context.l10n.tr(
                          'organizeStartersHintDraft',
                          params: {'max': '$_cuposMax'},
                        ),
                  style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _jugadoresBusquedaCtrl,
                  enabled: !_formularioBloqueado || _modoSeguimiento,
                  decoration: InputDecoration(
                    hintText: context.l10n.tr('organizeSearchHint'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _jugadoresBusquedaCtrl.text.trim().isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _jugadoresBusquedaCtrl.clear();
                              setState(() {});
                            },
                          ),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                ..._jugadoresTitularesEnPantalla().map((j) {
                  final id = j.keyId;
                  final seleccionado = _formularioBloqueado && !_puedeEditarListaEspera
                      ? _esTitular(id)
                      : _estaSeleccionado(id);
                  final enEspera = _esSuplente(id);
                  final esInvitado = _esTitular(id);
                  final estado = _estados[id] ?? EstadoConfirmacion.invitado;
                  final puedeToggle =
                      !_formularioBloqueado || _puedeEditarListaEspera;
                  return CheckboxListTile(
                    value: seleccionado,
                    onChanged: puedeToggle ? (v) => _toggleTitular(id, v) : null,
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            j.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (enEspera) ...[
                          const SizedBox(width: 6),
                          Text(
                            context.l10n.tr('organizeWaitlistBadge'),
                            style: MatchPayTokens.bodySmallStyle(
                              color: const Color(0xFF7C3AED),
                            ).copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        JugadorAppBadge(jugador: j, compact: true),
                      ],
                    ),
                    secondary: esInvitado
                        ? _EstadoChip(
                            estado: estado,
                            onTap: _puedeEditarEstados && !j.tieneMatchPayApp
                                ? () => _ciclarEstado(id)
                                : null,
                            tooltip: j.tieneMatchPayApp && _puedeEditarEstados
                                ? context.l10n.tr('organizeStatusRespondInApp')
                                : null,
                          )
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
              ],
            ),
        ),
        const SizedBox(height: 12),
        if (_mostrarListaEspera)
          MatchPaySurfaceCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tr('organizeWaitlistTitle'),
                  style:
                      MatchPayTokens.titleSmallStyle().copyWith(fontSize: 15),
                ),
                const SizedBox(height: 4),
                Text(
                  context.l10n.tr('organizeWaitlistHint'),
                  style:
                      MatchPayTokens.bodySmallStyle().copyWith(fontSize: 12),
                ),
                if (_puedeEditarListaEspera) ...[
                  const SizedBox(height: 6),
                  Text(
                    context.l10n.tr('organizeWaitlistHintTracking'),
                    style: MatchPayTokens.bodySmallStyle(
                      color: MatchPayTokens.accentCredit,
                    ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
                if (_listaEspera.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      context.l10n.tr('organizeWaitlistEmpty'),
                      style: MatchPayTokens.bodySmallStyle(
                        color: MatchPayTokens.inkMuted,
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 8),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder:
                        (!_formularioBloqueado || _puedeEditarListaEspera)
                            ? _moverEspera
                            : (_, __) {},
                    children: [
                      for (var i = 0; i < _listaEspera.length; i++)
                        ListTile(
                          key: ValueKey(_listaEspera[i]),
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: const Color(0xFF7C3AED)
                                .withValues(alpha: 0.15),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Color(0xFF7C3AED),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(_nombreJugador(_listaEspera[i])),
                          subtitle: Text(
                            context.l10n.tr(
                              'organizeWaitlistPriority',
                              params: {'n': '${i + 1}'},
                            ),
                            style: MatchPayTokens.bodySmallStyle(
                              color: const Color(0xFF7C3AED),
                            ).copyWith(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_formularioBloqueado ||
                                  _puedeEditarListaEspera)
                                IconButton(
                                  icon: Icon(
                                    Icons.remove_circle_outline,
                                    color: Colors.red.shade400,
                                    size: 22,
                                  ),
                                  tooltip: context.l10n
                                      .tr('organizeWaitlistRemove'),
                                  onPressed: () =>
                                      _quitarDeListaEspera(_listaEspera[i]),
                                ),
                              const Icon(Icons.drag_handle),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        if (sinSeleccion)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              context.l10n.tr('organizeSelectStartersAndSubs'),
              style: MatchPayTokens.bodySmallStyle(
                color: MatchPayTokens.accentUrgent,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final EstadoConfirmacion estado;
  final VoidCallback? onTap;
  final String? tooltip;

  const _EstadoChip({
    required this.estado,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (estado) {
      EstadoConfirmacion.confirmado => (
          context.l10n.tr('statusConfirmed'),
          MatchPayTokens.accentSuccess,
          Icons.check_circle_rounded,
        ),
      EstadoConfirmacion.rechazado => (
          context.l10n.tr('statusDeclined'),
          MatchPayTokens.accentError,
          Icons.cancel_rounded,
        ),
      EstadoConfirmacion.noRespondio => (
          context.l10n.tr('statusNoResponse'),
          MatchPayTokens.inkMuted,
          Icons.timer_off_rounded,
        ),
      EstadoConfirmacion.invitado => (
          context.l10n.tr('statusPending'),
          MatchPayTokens.accentUrgent,
          Icons.hourglass_empty_rounded,
        ),
    };

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: MatchPayTokens.titleSmallStyle(color: color).copyWith(
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

    Widget child = chip;
    if (onTap != null) {
      child = MatchPayTapScale(onTap: onTap, child: chip);
    }
    if (tooltip != null) {
      child = Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

