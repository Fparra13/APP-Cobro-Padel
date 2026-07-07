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
import '../models/recinto.dart';
import '../services/convocatoria_lista_espera_service.dart';
import '../services/convocatoria_message_service.dart';
import '../services/convocatoria_notificacion_service.dart';
import '../services/whatsapp_share_service.dart';
import '../services/preferences_service.dart';
import '../services/supabase_realtime_service.dart';
import '../utils/formatters.dart';
import '../utils/matchpay_context.dart';
import '../widgets/ayuda_tip.dart';
import '../core/matchpay_design_tokens.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';
import '../widgets/jugador_app_badge.dart';
import '../widgets/match_sport_picker.dart';
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

  List<Jugador> _habituales = [];
  List<Recinto> _recintosGuardados = [];
  Recinto? _recintoSeleccionado;
  final List<String> _titulares = [];
  final List<String> _listaEspera = [];
  final Map<String, EstadoConfirmacion> _estados = {};
  int _horasLimite = 24;
  DateTime _fechaPartido = DateTime.now().add(const Duration(hours: 2));
  SportType _sportType = SportType.padel;
  bool _loading = true;
  bool _guardando = false;
  String? _enviandoWhatsAppId;
  String? _errorCarga;
  int? _partidoId;
  bool _dirty = false;
  bool _partidoConfirmado = false;
  bool _convocatoriaEnviada = false;
  DateTime? _ultimoSnackPromocionAt;

  bool get _modoSeguimiento => _convocatoriaEnviada && !_partidoConfirmado;

  bool get _formularioBloqueado => _convocatoriaEnviada || _partidoConfirmado;

  bool get _puedeEditarEstados => _modoSeguimiento;

  bool get _cuposLlenos => _confirmados >= _cuposMax;

  int get _cuposDisponibles => (_cuposMax - _confirmados).clamp(0, _cuposMax);

  int get _confirmados => _titulares
      .where((id) => _estados[id] == EstadoConfirmacion.confirmado)
      .length;

  int get _pendientes => _titulares
      .where((id) => _estados[id] == EstadoConfirmacion.invitado)
      .length;

  bool get _fechaPartidoPasada => !_fechaPartido.isAfter(
        DateTime.now().subtract(Partido.convocatoriaGraceAfterMatch),
      );

  bool get _puedeRegistrarCobros =>
      _partidoConfirmado || (_convocatoriaEnviada && _fechaPartidoPasada);

  int get _enEsperaCount => _listaEspera.length;

  bool _esTitular(String id) => _titulares.contains(id);

  bool _esSuplente(String id) => _listaEspera.contains(id);

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
      final habituales = await repos.getJugadores(soloActivos: true);
      final recintosGuardados = await repos.getMisRecintos();
      final ultimoRecinto = await _prefs.ultimoRecinto;

      Recinto? recintoSel;

      if (_partidoId != null) {
        final conv = await repos.getConvocatoriaCompleta(_partidoId!);
        if (conv != null) {
          _fechaPartido = conv.partido.fecha;
          _sportType = conv.partido.sportType;
          recintoSel = _recintoDesdePartido(conv.partido, recintosGuardados);
          _notasCtrl.text = conv.partido.notas ?? '';
          _cuposCtrl.text = conv.partido.cuposMax.toString();
          _horasLimite = conv.partido.horasLimiteRespuesta;
          _partidoConfirmado = conv.partido.esConfirmado;
          _convocatoriaEnviada = conv.titulares
              .any((entry) => entry.tiempoLimite != null);
          _aplicarDesdeConvocatoria(conv);
        }
        if (!_partidoConfirmado && _convocatoriaEnviada) {
          await _listaEsperaService.sincronizar(_partidoId!);
          final actualizada = await repos.getConvocatoriaCompleta(_partidoId!);
          if (actualizada != null) {
            _aplicarDesdeConvocatoria(actualizada);
            recintoSel =
                _recintoDesdePartido(actualizada.partido, recintosGuardados);
          }
        }
      } else {
        var titularesCount = 0;
        for (final j in habituales) {
          if (j.keyId.isEmpty) continue;
          if (titularesCount < _cuposMax) {
            _titulares.add(j.keyId);
            _estados[j.keyId] = EstadoConfirmacion.invitado;
            titularesCount++;
          } else {
            _listaEspera.add(j.keyId);
            _estados[j.keyId] = EstadoConfirmacion.invitado;
          }
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
          _errorCarga = e.toString();
        });
      }
    }
  }

  void _aplicarDesdeConvocatoria(ConvocatoriaCompleta conv) {
    _titulares.clear();
    _listaEspera.clear();
    _estados.clear();
    for (final entry in conv.titulares) {
      final id = entry.jugador.keyId;
      if (id.isEmpty) continue;
      _titulares.add(id);
      _estados[id] = entry.estado;
    }
    for (final entry in conv.suplentes) {
      final id = entry.jugador.keyId;
      if (id.isEmpty) continue;
      _listaEspera.add(id);
      _estados[id] = entry.estado;
    }
    _partidoConfirmado = conv.partido.esConfirmado;
    if (!_partidoConfirmado) {
      _convocatoriaEnviada =
          conv.titulares.any((entry) => entry.tiempoLimite != null);
    }
  }

  Future<void> _sincronizarAutomatico() async {
    if (_partidoId == null || _partidoConfirmado || !_convocatoriaEnviada) {
      return;
    }
    final result = await _listaEsperaService.sincronizar(_partidoId!);
    if (!result.huboCambios || !mounted) return;
    final conv = await context.repos.getConvocatoriaCompleta(_partidoId!);
    if (conv == null || !mounted) return;
    setState(() => _aplicarDesdeConvocatoria(conv));
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
    }
  }

  String _formatoFechaHora(DateTime fecha) => formatDiaCompleto(fecha);

  Future<void> _pickFecha() async {
    if (_formularioBloqueado) return;
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaPartido,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'CL'),
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fechaPartido),
    );
    if (hora == null) return;

    setState(() {
      _fechaPartido = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );
      _dirty = true;
    });
  }

  String _nombreJugador(String id) {
    for (final j in _habituales) {
      if (j.keyId == id) return j.nombre;
    }
    return context.l10n.tr('playerDefaultName');
  }

  void _marcarDirty() {
    if (!_dirty) setState(() => _dirty = true);
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
      if (value == true) {
        if (_titulares.length >= _cuposMax) {
          _mostrarError(
            context.l10n.tr(
              'organizeMaxStartersError',
              params: {'max': '$_cuposMax'},
            ),
          );
          return;
        }
        _listaEspera.remove(id);
        if (!_titulares.contains(id)) _titulares.add(id);
        _estados.putIfAbsent(id, () => EstadoConfirmacion.invitado);
      } else {
        _titulares.remove(id);
        _estados.remove(id);
      }
      _dirty = true;
    });
  }

  void _toggleListaEspera(String id, bool? value) {
    setState(() {
      if (value == true) {
        _titulares.remove(id);
        if (!_listaEspera.contains(id)) _listaEspera.add(id);
        _estados[id] = EstadoConfirmacion.invitado;
      } else {
        _listaEspera.remove(id);
        if (!_titulares.contains(id)) _estados.remove(id);
      }
      _dirty = true;
    });
  }

  void _moverEspera(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final id = _listaEspera.removeAt(oldIndex);
      _listaEspera.insert(newIndex, id);
      _dirty = true;
    });
  }

  void _seleccionarTodosTitulares() {
    setState(() {
      _titulares.clear();
      _listaEspera.clear();
      _estados.clear();
      var count = 0;
      for (final j in _habituales) {
        if (j.keyId.isEmpty) continue;
        if (count < _cuposMax) {
          _titulares.add(j.keyId);
        } else {
          _listaEspera.add(j.keyId);
        }
        _estados[j.keyId] = EstadoConfirmacion.invitado;
        count++;
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
      _dirty = true;
    });

    if (_partidoId != null) {
      await _persistirEstadoJugador(id);
      if (siguiente == EstadoConfirmacion.rechazado ||
          actual == EstadoConfirmacion.rechazado) {
        await _sincronizarAutomatico();
      } else {
        await _autoConfirmarSiCompleto();
      }
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
          fecha: _fechaPartido,
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
        await repos.actualizarConvocatoria(
          partidoId: _partidoId!,
          fecha: _fechaPartido,
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
      }

      await _prefs.saveUltimoRecinto(recinto.nombre.trim());

      if (!silencioso && mounted) {
        setState(() => _dirty = false);
      }
      return true;
    } catch (e) {
      _mostrarError('$e');
      return false;
    } finally {
      if (actualizarGuardando && mounted) {
        setState(() => _guardando = false);
      }
    }
  }

  Future<bool> _confirmarSalidaSinGuardar() async {
    if (!_dirty) return true;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.tr('organizeExitWithoutSavingTitle')),
        content: Text(
          _convocatoriaEnviada
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
            child: Text(ctx.l10n.tr('organizeExitWithoutSaving')),
          ),
          if (!_convocatoriaEnviada)
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

      final titularesJugadores =
          _habituales.where((j) => _esTitular(j.keyId)).toList();
      await _notificaciones.notificarConvocatoriaTitulares(
        titulares: titularesJugadores,
        partidoId: _partidoId!,
        fecha: _fechaPartido,
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
    } catch (e) {
      _mostrarError(
        context.l10n.tr('organizeSendFailed', params: {'error': '$e'}),
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
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

  Future<void> _enviarConvocatoriaWhatsApp(Jugador jugador) async {
    if (jugador.tieneMatchPayApp || _partidoId == null) return;
    if (!jugador.puedeEnviarWhatsApp) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('whatsappNoNumber'))),
      );
      return;
    }

    setState(() => _enviandoWhatsAppId = jugador.keyId);
    try {
      final conv =
          await context.repos.getConvocatoriaCompleta(_partidoId!);
      if (conv == null) {
        throw Exception(context.l10n.tr('convocatoriaNotFoundSnack'));
      }
      final msg = ConvocatoriaMessageService().construirMensajePersonal(
        convocatoria: conv,
        nombreJugador: jugador.nombre,
      );
      final ok = await WhatsAppShareService.enviar(
        mensaje: msg,
        telefono: jugador.contactWhatsApp,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? context.l10n.tr('whatsappOpening')
                  : context.l10n.tr('whatsappOpenFailed'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoWhatsAppId = null);
    }
  }

  Future<void> _eliminarConvocatoria() async {
    final ok = await confirmarEliminarPartido(
      context,
      titulo: context.l10n.tr('organizeDeleteInviteTitle'),
      mensaje: context.l10n.tr('organizeDeleteInviteMessage'),
      consecuencias: [
        context.l10n.tr('organizeDeleteInviteConsequence1'),
        context.l10n.tr('organizeDeleteInviteConsequence2'),
        context.l10n.tr('organizeDeleteInviteConsequence3'),
      ],
    );
    if (!ok || _partidoId == null) return;

    await context.repos.eliminarConvocatoria(_partidoId!);
    if (mounted) Navigator.pop(context, true);
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
    return PopScope(
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
          if (_partidoId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: context.l10n.tr('deleteTooltip'),
              onPressed: _eliminarConvocatoria,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: Colors.red.shade700),
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.tr('organizeLoadFailed'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorCarga!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _errorCarga = null;
                            });
                            _load();
                          },
                          icon: const Icon(Icons.refresh),
                          label: Text(context.l10n.tr('retry')),
                        ),
                      ],
                    ),
                  ),
                )
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
                const SizedBox(height: 12),
                _buildResumen(),
                const SizedBox(height: 12),
                _buildDatosPartido(),
                const SizedBox(height: 12),
                _buildListaJugadores(),
                const SizedBox(height: 80),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_convocatoriaEnviada || _partidoConfirmado)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      _partidoConfirmado
                          ? Icons.check_circle_rounded
                          : Icons.sync_rounded,
                      size: 18,
                      color: _partidoConfirmado
                          ? MatchPayTokens.accentSuccess
                          : MatchPayTokens.accentCredit,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _partidoConfirmado
                            ? context.l10n.tr(
                                'organizeConfirmedBar',
                                params: {
                                  'confirmed': '$_confirmados',
                                  'max': '$_cuposMax',
                                },
                              )
                            : context.l10n.tr(
                                'organizeTrackingBar',
                                params: {
                                  'confirmed': '$_confirmados',
                                  'max': '$_cuposMax',
                                  'pending': '$_pendientes',
                                },
                              ),
                        style: MatchPayTokens.titleSmallStyle(
                          color: _partidoConfirmado
                              ? MatchPayTokens.accentSuccess
                              : MatchPayTokens.accentCredit,
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
            else if (_cuposLlenos)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.l10n.tr('organizeAutoConfirmInProgress'),
                  style: MatchPayTokens.titleSmallStyle(
                    color: MatchPayTokens.accentUrgent,
                  ).copyWith(fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  context.l10n.tr(
                    'organizeNeedMoreConfirmed',
                    params: {
                      'remaining': '${_cuposMax - _confirmados}',
                    },
                  ),
                  style: MatchPayTokens.bodySmallStyle(
                    color: MatchPayTokens.accentUrgent,
                  ).copyWith(fontSize: 12, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
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
          if (_modoSeguimiento || _partidoConfirmado)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _partidoConfirmado
                    ? MatchPayTokens.accentSuccessBg
                    : MatchPayTokens.accentCreditBg,
                borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
              ),
              child: Row(
                children: [
                  Icon(
                    _partidoConfirmado
                        ? Icons.check_circle_rounded
                        : Icons.campaign_rounded,
                    size: 16,
                    color: _partidoConfirmado
                        ? MatchPayTokens.accentSuccess
                        : MatchPayTokens.accentCredit,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _partidoConfirmado
                          ? context.l10n.tr('organizeBannerConfirmed')
                          : context.l10n.tr('organizeBannerSent'),
                      style: MatchPayTokens.titleSmallStyle(
                        color: _partidoConfirmado
                            ? MatchPayTokens.accentSuccess
                            : MatchPayTokens.accentCredit,
                      ).copyWith(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Icon(Icons.groups_rounded, color: palette.primary, size: 36),
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

  Widget _buildDatosPartido() {
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
              enabled: !_formularioBloqueado,
              onChanged: _formularioBloqueado
                  ? null
                  : (sport) => setState(() {
                        _sportType = sport;
                        _dirty = true;
                      }),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(context.l10n.tr('dateAndTime')),
              subtitle: Text(_formatoFechaHora(_fechaPartido)),
              trailing: _formularioBloqueado
                  ? null
                  : const Icon(Icons.chevron_right),
              onTap: _formularioBloqueado ? null : _pickFecha,
            ),
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
              onChanged: _formularioBloqueado ? null : (_) => _marcarDirty(),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: context.l10n.tr('organizeMaxSlotsLabel'),
                prefixIcon: const Icon(Icons.people),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _horasLimite,
              decoration: InputDecoration(
                labelText: context.l10n.tr('organizeResponseDeadlineLabel'),
                prefixIcon: const Icon(Icons.timer_outlined),
              ),
              items: [1, 2, 4, 8, 24]
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
              onChanged: _formularioBloqueado
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() {
                        _horasLimite = v;
                        _dirty = true;
                      });
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
    if (_habituales.isEmpty) {
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
                      context.l10n.tr(
                        'organizeStartersTitle',
                        params: {'max': '$_cuposMax'},
                      ),
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
                      : context.l10n.tr('organizeStartersHintDraft'),
                  style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 12),
                ),
                if (_modoSeguimiento) ...[
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      context.l10n.tr('organizeManualFallbackTitle'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          context.l10n.tr('organizeManualFallbackHint'),
                          style: MatchPayTokens.bodySmallStyle(
                            color: MatchPayTokens.accentUrgent,
                          ).copyWith(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                ..._habituales.map((j) {
                  final id = j.keyId;
                  if (id.isEmpty) return const SizedBox.shrink();
                  final esTitular = _esTitular(id);
                  final estado = _estados[id] ?? EstadoConfirmacion.invitado;
                  return CheckboxListTile(
                    value: esTitular,
                    onChanged: _formularioBloqueado
                        ? null
                        : (v) => _toggleTitular(id, v),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            j.nombre,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        JugadorAppBadge(jugador: j, compact: true),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (j.contactEmail != null) Text(j.contactEmail!),
                        if (esTitular &&
                            _modoSeguimiento &&
                            !j.tieneMatchPayApp) ...[
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _enviandoWhatsAppId == id
                                  ? null
                                  : () => _enviarConvocatoriaWhatsApp(j),
                              icon: _enviandoWhatsAppId == id
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.chat_outlined,
                                      size: 18,
                                      color: Color(0xFF25D366),
                                    ),
                              label: Text(
                                context.l10n.tr('sendConvocatoriaWhatsApp'),
                                style: const TextStyle(
                                  color: Color(0xFF1B8F4E),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    secondary: esTitular
                        ? _EstadoChip(
                            estado: estado,
                            onTap: _puedeEditarEstados
                                ? () => _ciclarEstado(id)
                                : () {},
                          )
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
              ],
            ),
        ),
        const SizedBox(height: 12),
        MatchPaySurfaceCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.tr('organizeWaitlistTitle'),
                style: MatchPayTokens.titleSmallStyle().copyWith(fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.tr('organizeWaitlistHint'),
                style: MatchPayTokens.bodySmallStyle().copyWith(fontSize: 12),
              ),
                const SizedBox(height: 8),
                ..._habituales.map((j) {
                  final id = j.keyId;
                  if (id.isEmpty || _esTitular(id)) {
                    return const SizedBox.shrink();
                  }
                  return CheckboxListTile(
                    value: _esSuplente(id),
                    onChanged: _formularioBloqueado
                        ? null
                        : (v) => _toggleListaEspera(id, v),
                    title: Text(j.nombre),
                    subtitle: _esSuplente(id)
                        ? Text(
                            context.l10n.tr(
                              'organizeWaitlistPriority',
                              params: {
                                'n': '${_listaEspera.indexOf(id) + 1}',
                              },
                            ),
                            style: MatchPayTokens.bodySmallStyle(
                              color: const Color(0xFF7C3AED),
                            ).copyWith(fontSize: 12),
                          )
                        : null,
                    controlAffinity: ListTileControlAffinity.leading,
                  );
                }),
                if (_listaEspera.isNotEmpty) ...[
                  const Divider(),
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorder: _formularioBloqueado ? (_, __) {} : _moverEspera,
                    children: [
                      for (var i = 0; i < _listaEspera.length; i++)
                        ListTile(
                          key: ValueKey(_listaEspera[i]),
                          leading: CircleAvatar(
                            radius: 14,
                            child: Text('${i + 1}'),
                          ),
                          title: Text(_nombreJugador(_listaEspera[i])),
                          trailing: const Icon(Icons.drag_handle),
                        ),
                    ],
                  ),
                ],
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
            ),
        ),
      ],
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final EstadoConfirmacion estado;
  final VoidCallback onTap;

  const _EstadoChip({required this.estado, required this.onTap});

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

    return MatchPayTapScale(
      onTap: onTap,
      child: Container(
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
      ),
    );
  }
}

