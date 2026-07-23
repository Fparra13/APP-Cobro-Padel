import 'package:flutter/material.dart';

import '../constants/conceptos_cobro.dart';
import '../constants/expense_icon.dart';
import '../core/sport_type.dart';
import '../l10n/matchpay_strings.dart';
import '../models/cobro_individual_entry.dart';
import '../models/estado_pago_jugador.dart';
import '../models/jugador.dart';
import '../models/partido.dart';
import '../models/shared_expense_entry.dart';
import '../domain/gasto_compartido_logic.dart';
import '../domain/gasto_preset_logic.dart';
import '../domain/gasto_sport_suggestions.dart';
import '../domain/jugador_list_priority.dart';
import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/matchpay_design_tokens.dart';
import '../models/estado_partido.dart';
import '../services/calculation_service.dart';
import '../services/comprobante_service.dart';
import '../services/preferences_service.dart';
import '../utils/cobro_recordatorio_flow.dart';
import '../utils/formatters.dart';
import '../utils/jugador_name_filter.dart';
import '../utils/matchpay_context.dart';
import '../widgets/comprobante_pago_tile.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';
import '../widgets/expense_icon_picker.dart';
import '../widgets/match_sport_picker.dart';
import '../widgets/sport_icon.dart';

class NuevoPartidoScreen extends StatefulWidget {
  final int? partidoId;

  const NuevoPartidoScreen({super.key, this.partidoId});

  bool get isEditing => partidoId != null;

  @override
  State<NuevoPartidoScreen> createState() => _NuevoPartidoScreenState();
}

class _NuevoPartidoScreenState extends State<NuevoPartidoScreen> {
  final _prefs = PreferencesService();

  final _notasCtrl = TextEditingController();
  final _recintoCtrl = TextEditingController();
  final _jugadoresBusquedaCtrl = TextEditingController();

  final List<SharedExpenseEntry> _gastosCompartidos = [];
  int _expenseIdSeq = 0;
  SportType _sportType = SportType.padel;

  List<Jugador> _habituales = [];
  List<String> _recintosSugeridos = [];
  final Map<String, List<CobroIndividualEntry>> _cobrosIndividuales = {};
  final Set<String> _asistentes = {};
  final Map<String, EstadoPagoJugador> _pagos = {};
  final Map<String, double> _saldosSnapshot = {};
  /// Jugadores a fijar arriba (último encuentro o confirmados).
  final Set<String> _prioridadJugadorIds = {};
  JugadorPrioritySource _prioridadFuente = JugadorPrioritySource.none;
  DateTime _fechaPartido = DateTime.now();
  bool _loading = true;
  bool _guardando = false;
  bool _esOrganizando = false;
  /// Lista de jugadores expandida; colapsada muestra chips de seleccionados.
  bool _jugadoresExpandido = true;
  DateTime? _createdAtOriginal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadData();
    });
  }

  String _nuevoExpenseId() => 'exp_${_expenseIdSeq++}';

  void _agregarGastoCompartido({
    String label = '',
    ExpenseIconKey icon = ExpenseIconKey.general,
  }) {
    setState(() {
      final blankIndex =
          _gastosCompartidos.indexWhere((g) => !g.tieneDatos);
      if (label.isNotEmpty && blankIndex >= 0) {
        // Rellenar la fila vacía en vez de apilar otra debajo.
        final blank = _gastosCompartidos[blankIndex];
        blank.labelCtrl.text = label;
        blank.iconKey = icon;
        return;
      }
      if (label.isEmpty && blankIndex >= 0) {
        // Ya hay un gasto en blanco; no crear otro vacío.
        return;
      }
      _gastosCompartidos.add(
        SharedExpenseEntry(id: _nuevoExpenseId(), label: label, iconKey: icon),
      );
    });
  }

  /// Preset opcional (Cancha / Pelotas) → gasto compartido canónico.
  void _agregarPresetGasto(String concepto) {
    final existing = GastoPresetLogic.findPreset(_gastosCompartidos, concepto);
    if (existing != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('expensePresetAlreadyAdded'))),
      );
      return;
    }
    _agregarGastoCompartido(
      label: concepto,
      icon: GastoPresetLogic.iconForPreset(concepto),
    );
  }

  /// Chip sugerido según deporte (fijo o texto libre).
  void _agregarSugerenciaGasto(GastoSportSuggestion suggestion) {
    final fixed = suggestion.fixedConcepto;
    if (fixed != null) {
      _agregarPresetGasto(fixed);
      return;
    }
    final label = context.l10n.tr(suggestion.labelKey);
    final exists = _gastosCompartidos.any(
      (g) => g.label.toLowerCase() == label.toLowerCase(),
    );
    if (exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('expensePresetAlreadyAdded'))),
      );
      return;
    }
    _agregarGastoCompartido(label: label, icon: suggestion.icon);
  }

  void _eliminarGastoCompartido(SharedExpenseEntry entry) {
    setState(() {
      if (entry.comprobantePath != null) {
        ComprobanteService.instance.deleteAny(entry.comprobantePath);
      }
      entry.dispose();
      _gastosCompartidos.remove(entry);
    });
  }

  Set<String> _participantesDeGasto(SharedExpenseEntry entry) {
    entry.participantes.removeWhere((id) => !_asistentes.contains(id));
    return entry.participantes;
  }

  Set<String> _participantesRepartoGasto(SharedExpenseEntry entry) =>
      GastoCompartidoLogic.participantesReparto(
        participantesExplicitos: _participantesDeGasto(entry),
        asistentes: _asistentes,
        repartoEntreTodos: entry.repartoEntreTodos,
        sinParticipantesExplicito: entry.sinParticipantesExplicito,
        monto: entry.monto,
      );

  Future<void> _loadData() async {
    try {
      final repos = AppRepositories.isReady
          ? AppRepositories.I
          : context.repos;
      final habituales = await repos.getJugadores(
        soloActivos: true,
        incluirUsuarioActual: true,
      );
      final recintos = await repos.getRecintosRecientes();
      final ultimoRecinto = await _prefs.ultimoRecinto;

      if (widget.partidoId != null) {
        await _loadPartidoExistente(
          repos: repos,
          habituales: habituales,
          recintos: recintos,
        );
        return;
      }

      Set<String> prioridad = {};
      try {
        final ultimo = await repos.getUltimoPartido();
        if (ultimo != null) {
          prioridad = {
            for (final d in ultimo.detalles)
              if (d.asistio) d.jugadorKeyId,
          };
        }
      } catch (_) {
        // Sin último encuentro: lista normal.
      }

      if (mounted) {
        setState(() {
          _habituales = habituales;
          _recintosSugeridos = recintos;
          _sportType = context.readSettings().sport;
          _prioridadJugadorIds
            ..clear()
            ..addAll(prioridad);
          _prioridadFuente = prioridad.isEmpty
              ? JugadorPrioritySource.none
              : JugadorPrioritySource.lastMatch;
          if (_recintoCtrl.text.isEmpty && ultimoRecinto.isNotEmpty) {
            _recintoCtrl.text = ultimoRecinto;
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.userError(e)),
            backgroundColor: Colors.red.shade700,
            action: SnackBarAction(
              label: context.tr('retry'),
              textColor: Colors.white,
              onPressed: () {
                setState(() => _loading = true);
                _loadData();
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadPartidoExistente({
    required AppRepositories repos,
    required List<Jugador> habituales,
    required List<String> recintos,
  }) async {
    if (widget.partidoId != null) {
      final completo = await repos.getPartidoCompleto(widget.partidoId!);

      if (completo != null && completo.partido.esConvocatoriaPendiente) {
        final conv = await repos.getConvocatoriaCompleta(widget.partidoId!);
        if (conv != null) {
          _esOrganizando = true;
          _createdAtOriginal = conv.partido.createdAt;
          _notasCtrl.text = conv.partido.notas ?? '';
          _recintoCtrl.text = conv.partido.recinto ?? '';
          _fechaPartido = conv.partido.fecha;
          _sportType = conv.partido.sportType;

          final confirmados = conv.jugadores
              .where((e) => e.estado == EstadoConfirmacion.confirmado)
              .map((e) => e.jugador.keyId)
              .toSet();

          if (confirmados.isNotEmpty) {
            _asistentes.addAll(confirmados);
          } else {
            for (final e in conv.jugadores) {
              if (e.estado != EstadoConfirmacion.rechazado) {
                _asistentes.add(e.jugador.keyId);
              }
            }
          }

          for (final id in _asistentes) {
            _pagos[id] = EstadoPagoJugador();
          }

          final todos = <String, Jugador>{for (final j in habituales) j.keyId: j};
          for (final e in conv.jugadores) {
            todos[e.jugador.keyId] = e.jugador;
          }

          final prioridad = confirmados.isNotEmpty
              ? confirmados
              : _asistentes.toSet();

          if (mounted) {
            setState(() {
              _habituales = todos.values.toList()
                ..sort((a, b) => a.nombre.compareTo(b.nombre));
              _recintosSugeridos = recintos;
              _prioridadJugadorIds
                ..clear()
                ..addAll(prioridad);
              _prioridadFuente = prioridad.isEmpty
                  ? JugadorPrioritySource.none
                  : JugadorPrioritySource.convocatoriaConfirmed;
              // Ya hay confirmados: colapsar para no alargar la pantalla.
              _jugadoresExpandido = _asistentes.length <= 6;
              _loading = false;
            });
          }
          return;
        }
      }

      final historicos = await repos.getSaldosByPartido(widget.partidoId!);

      if (completo != null) {
        _notasCtrl.text = completo.partido.notas ?? '';
        _recintoCtrl.text = completo.partido.recinto ?? '';
        _fechaPartido = completo.partido.fecha;
        _sportType = completo.partido.sportType;

        if (completo.partido.costoCancha > 0) {
          _gastosCompartidos.add(
            SharedExpenseEntry(
              id: _nuevoExpenseId(),
              label: ConceptosCobro.cancha,
              monto: formatMoneyField(completo.partido.costoCancha),
              iconKey: ExpenseIconKey.court,
              comprobantePath: completo.partido.comprobanteCancha,
              repartoEntreTodos: true,
            ),
          );
        }
        if (completo.partido.costoPelotas > 0) {
          _gastosCompartidos.add(
            SharedExpenseEntry(
              id: _nuevoExpenseId(),
              label: ConceptosCobro.pelotas,
              monto: formatMoneyField(completo.partido.costoPelotas),
              iconKey: ExpenseIconKey.ball,
              comprobantePath: completo.partido.comprobantePelotas,
              repartoEntreTodos: true,
            ),
          );
        }

        for (final cv in completo.costosVariables) {
          final asigs = completo.asignacionesPorCosto[cv.id] ?? [];
          if (asigs.length == 1) {
            final jugadorId = asigs.first.jugadorKeyId;
            _cobrosIndividuales.putIfAbsent(jugadorId, () => []);
            _cobrosIndividuales[jugadorId]!.add(
              CobroIndividualEntry(
                concepto: cv.concepto,
                monto: formatMoneyField(asigs.first.monto),
                comprobantePath: cv.comprobantePath,
                guardado: true,
              ),
            );
            continue;
          }
          if (ConceptosCobro.esFijo(cv.concepto)) continue;
          final icon = cv.iconKey != null
              ? ExpenseIconKey.fromDb(cv.iconKey)
              : ExpenseIconKey.fromLegacyConcepto(cv.concepto);
          _gastosCompartidos.add(
            SharedExpenseEntry(
              id: _nuevoExpenseId(),
              label: cv.concepto,
              monto: formatMoneyField(cv.montoTotal),
              iconKey: icon,
              participantes: asigs.map((a) => a.jugadorKeyId).toSet(),
              comprobantePath: cv.comprobantePath,
              repartoEntreTodos: false,
              sinParticipantesExplicito: false,
            ),
          );
        }

        for (final h in historicos) {
          _saldosSnapshot[h.jugadorKeyId] = h.saldoAnterior;
        }

        for (final d in completo.detalles.where((d) => d.asistio)) {
          _asistentes.add(d.jugadorKeyId);
          final ep = EstadoPagoJugador();
          final snap = _saldosSnapshot[d.jugadorKeyId];
          if (snap != null &&
              d.partidoCerradoNeto(snapshotSaldoAnterior: snap)) {
            ep.tipo = TipoPago.total;
          } else if (d.montoPagado > 0) {
            ep.tipo = TipoPago.parcial;
            ep.montoParcial.text = formatMoneyField(d.montoPagado);
            ep.abonoConfirmado = true;
          }
          _pagos[d.jugadorKeyId] = ep;
        }

        final todos = <String, Jugador>{for (final j in habituales) j.keyId: j};
        final orgId = AuthService.instance.currentUser?.id;
        for (final id in _asistentes) {
          if (!todos.containsKey(id)) {
            final j = await repos.getJugador(id, organizadorId: orgId);
            if (j != null) todos[id] = j;
          }
        }

        if (mounted) {
          setState(() {
            _habituales = todos.values.toList()
              ..sort((a, b) => a.nombre.compareTo(b.nombre));
            _recintosSugeridos = recintos;
            _jugadoresExpandido = _asistentes.length <= 6;
            _loading = false;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _habituales = habituales;
        _recintosSugeridos = recintos;
        _sportType = context.readSettings().sport;
        _loading = false;
      });
    }
  }

  double _monto(String concepto) =>
      GastoPresetLogic.montoPreset(_gastosCompartidos, concepto);

  Listenable get _gastosMontosListenable => Listenable.merge([
        for (final g in _gastosCompartidos) g.montoCtrl,
      ]);

  double _saldoAnterior(Jugador j) {
    if (widget.isEditing && _saldosSnapshot.containsKey(j.keyId)) {
      return _saldosSnapshot[j.keyId]!;
    }
    return j.saldoAcumulado;
  }

  double _prorrateoCancha() => CalculationService.prorrateoCancha(
        costoCancha: _monto(ConceptosCobro.cancha),
        cantidadAsistentes: _asistentes.length,
      );

  double _prorrateoPelotas() => CalculationService.prorrateoPelotas(
        costoPelotas: _monto(ConceptosCobro.pelotas),
        cantidadAsistentes: _asistentes.length,
      );

  double _variablesParaJugador(String jugadorId) {
    if (!_asistentes.contains(jugadorId)) return 0;
    double total = 0;
    for (final gasto in _gastosCompartidos) {
      final monto = gasto.monto;
      if (monto <= 0) continue;
      if (GastoPresetLogic.isFixedPreset(gasto.label)) continue;
      final participantes = _participantesRepartoGasto(gasto);
      total += GastoCompartidoLogic.cuotaJugador(
        montoTotal: monto,
        participantes: participantes,
        jugadorId: jugadorId,
      );
    }
    for (final cobro in _cobrosIndividuales[jugadorId] ?? []) {
      if (cobro.guardado) total += cobro.monto;
    }
    return total;
  }

  void _toggleParticipanteGasto(SharedExpenseEntry entry, String jugadorId) {
    setState(() {
      if (entry.repartoEntreTodos) {
        entry.participantes
          ..clear()
          ..addAll(_asistentes);
        entry.repartoEntreTodos = false;
      }
      entry.sinParticipantesExplicito = false;
      final set = _participantesDeGasto(entry);
      if (set.contains(jugadorId)) {
        set.remove(jugadorId);
      } else {
        set.add(jugadorId);
      }
    });
  }

  void _setParticipantesGasto(SharedExpenseEntry entry, bool todos) {
    setState(() {
      final set = _participantesDeGasto(entry);
      set.clear();
      entry.repartoEntreTodos = todos;
      entry.sinParticipantesExplicito = !todos;
    });
  }

  double _prorrateoGasto(SharedExpenseEntry entry) {
    final monto = entry.monto;
    final participantes = _participantesRepartoGasto(entry);
    if (monto <= 0 || participantes.isEmpty) return 0;
    return CalculationService.prorratear(monto, participantes.length);
  }

  double _cargoPartido(Jugador j) {
    if (!_asistentes.contains(j.keyId)) return 0;
    return CalculationService.cargoPartido(
      prorrateoFijo: _prorrateoCancha() + _prorrateoPelotas(),
      totalVariables: _variablesParaJugador(j.keyId),
    );
  }

  double _saldoFavorAplicado(Jugador j) =>
      CalculationService.saldoFavorAplicado(
        saldoAnterior: _saldoAnterior(j),
        cargoPartido: _cargoPartido(j),
      );

  double _netoAPagarPartido(Jugador j) {
    if (!_asistentes.contains(j.keyId)) return 0;
    return CalculationService.netoAPagarPartido(
      saldoAnterior: _saldoAnterior(j),
      cargoPartido: _cargoPartido(j),
    );
  }

  double _saldoRestante(Jugador j) {
    if (!_asistentes.contains(j.keyId)) return _saldoAnterior(j);
    final pago = _pagoDe(j.keyId);
    return CalculationService.saldoDespuesPagoPartido(
      saldoAnterior: _saldoAnterior(j),
      cargoPartido: _cargoPartido(j),
      montoPagado: pago.montoEfectivo(_netoAPagarPartido(j)),
    );
  }

  double _pendientePartido(Jugador j) {
    if (!_asistentes.contains(j.keyId)) return 0;
    final pago = _pagoDe(j.keyId);
    return CalculationService.pendientePartido(
      saldoAnterior: _saldoAnterior(j),
      cargoPartido: _cargoPartido(j),
      montoPagado: pago.montoEfectivo(_netoAPagarPartido(j)),
    );
  }

  EstadoPagoJugador _pagoDe(String jugadorId) =>
      _pagos.putIfAbsent(jugadorId, EstadoPagoJugador.new);

  @override
  void dispose() {
    for (final p in _pagos.values) {
      p.dispose();
    }
    for (final lista in _cobrosIndividuales.values) {
      for (final c in lista) {
        c.dispose();
      }
    }
    for (final g in _gastosCompartidos) {
      g.dispose();
    }
    _notasCtrl.dispose();
    _recintoCtrl.dispose();
    _jugadoresBusquedaCtrl.dispose();
    super.dispose();
  }

  void _toggleAsistente(Jugador j) {
    setState(() {
      if (_asistentes.contains(j.keyId)) {
        _asistentes.remove(j.keyId);
        _pagos.remove(j.keyId);
        _eliminarCobrosJugador(j.keyId);
        for (final g in _gastosCompartidos) {
          g.participantes.remove(j.keyId);
        }
      } else {
        _asistentes.add(j.keyId);
      }
    });
  }

  void _eliminarCobrosJugador(String jugadorId) {
    final lista = _cobrosIndividuales.remove(jugadorId);
    if (lista != null) {
      for (final c in lista) {
        c.dispose();
      }
    }
  }

  void _agregarCobroIndividual(String jugadorId) {
    setState(() {
      _cobrosIndividuales.putIfAbsent(jugadorId, () => []);
      _cobrosIndividuales[jugadorId]!.add(CobroIndividualEntry());
    });
  }

  void _eliminarCobroIndividual(String jugadorId, CobroIndividualEntry entry) {
    setState(() {
      ComprobanteService.instance.deleteAny(entry.comprobantePath);
      final lista = _cobrosIndividuales[jugadorId];
      lista?.remove(entry);
      entry.dispose();
      if (lista != null && lista.isEmpty) {
        _cobrosIndividuales.remove(jugadorId);
      }
    });
  }

  void _guardarCobroIndividual(String jugadorId, CobroIndividualEntry cobro) {
    final l10n = context.l10n;
    if (cobro.concepto.isEmpty) {
      _showError(l10n.tr('errorExtraChargeConcept'));
      return;
    }
    if (cobro.monto <= 0) {
      _showError(l10n.tr('errorExtraChargeAmount'));
      return;
    }
    setState(() => cobro.guardado = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.tr('snackChargeSaved', params: {
            'concept': cobro.concepto,
            'amount': formatMoney(cobro.monto),
          }),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _cancelarCobroIndividual(String jugadorId, CobroIndividualEntry cobro) {
    if (!cobro.tieneDatos) {
      _eliminarCobroIndividual(jugadorId, cobro);
      return;
    }
    setState(() {
      cobro.conceptoCtrl.clear();
      cobro.montoCtrl.clear();
      if (cobro.comprobantePath != null) {
        ComprobanteService.instance.deleteAny(cobro.comprobantePath);
        cobro.comprobantePath = null;
      }
    });
    _eliminarCobroIndividual(jugadorId, cobro);
  }

  void _editarCobroIndividual(CobroIndividualEntry cobro) {
    setState(() => cobro.guardado = false);
  }

  List<
      ({
        String concepto,
        double montoTotal,
        List<String> jugadores,
        String? comprobantePath,
        String? iconKey,
      })> _costosVariables() {
    final list = <
        ({
          String concepto,
          double montoTotal,
          List<String> jugadores,
          String? comprobantePath,
          String? iconKey,
        })>[];

    for (final gasto in GastoPresetLogic.sharedForVariables(_gastosCompartidos)) {
      final participantes = _participantesRepartoGasto(gasto).toList();
      if (participantes.isEmpty) continue;
      list.add((
        concepto: gasto.label,
        montoTotal: gasto.monto,
        jugadores: participantes,
        comprobantePath: gasto.comprobantePath,
        iconKey: gasto.iconKey.dbValue,
      ));
    }

    for (final jugadorId in _asistentes) {
      for (final cobro in _cobrosIndividuales[jugadorId] ?? []) {
        if (!cobro.guardado || cobro.monto <= 0 || cobro.concepto.isEmpty) {
          continue;
        }
        list.add((
          concepto: cobro.concepto,
          montoTotal: cobro.monto,
          jugadores: [jugadorId],
          comprobantePath: cobro.comprobantePath,
          iconKey: null,
        ));
      }
    }

    return list;
  }

  void _setTipoPago(String jugadorId, TipoPago tipo) {
    setState(() {
      final p = _pagoDe(jugadorId);
      p.tipo = tipo;
      p.abonoConfirmado = false;
      if (tipo == TipoPago.parcial) {
        p.montoParcial.clear();
      }
    });
  }

  void _confirmarAbonoJugador(Jugador j) {
    final l10n = context.l10n;
    final pago = _pagoDe(j.keyId);
    final m = roundMoney(parseMoney(pago.montoParcial.text)).toDouble();
    if (m <= 0) {
      _showError(l10n.tr('errorPlayerPartialAmount', params: {'name': j.nombre}));
      return;
    }

    setState(() => pago.abonoConfirmado = true);

    final restante = CalculationService.saldoDespuesPagoPartido(
      saldoAnterior: _saldoAnterior(j),
      cargoPartido: _cargoPartido(j),
      montoPagado: m,
    );

    final msg = restante < 0
        ? l10n.tr('snackPaymentWithCredit', params: {
            'amount': formatMoney(m),
            'credit': formatMoney(-restante),
            'name': j.nombre,
          })
        : restante == 0
            ? l10n.tr('snackDebtCleared', params: {'name': j.nombre})
            : l10n.tr('snackPartialPayment', params: {
                'amount': formatMoney(m),
                'remaining': formatMoney(restante),
                'name': j.nombre,
              });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green.shade700),
    );
  }

  void _editarAbonoJugador(String jugadorId) {
    setState(() => _pagoDe(jugadorId).abonoConfirmado = false);
  }

  void _marcarTodosPagados(bool pagaron) {
    setState(() {
      for (final id in _asistentes) {
        final p = _pagoDe(id);
        p.tipo = pagaron ? TipoPago.total : TipoPago.ninguno;
        p.abonoConfirmado = false;
      }
    });
  }

  Map<String, double> get _montoPagadoMap {
    final map = <String, double>{};
    for (final id in _asistentes) {
      Jugador? j;
      for (final x in _habituales) {
        if (x.keyId == id) {
          j = x;
          break;
        }
      }
      if (j == null) continue;
      map[id] = _pagoDe(id).montoEfectivo(_netoAPagarPartido(j));
    }
    return map;
  }

  Future<void> _confirmarYGuardar() async {
    if (_guardando) return;
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('confirmSaveMatchTitle')),
        content: Text(
          _esOrganizando
              ? l10n.tr('confirmSaveChargesBody')
              : l10n.tr('confirmSaveMatchBody'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              _esOrganizando
                  ? l10n.tr('confirmCharges')
                  : l10n.tr('saveMatch'),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _guardar();
  }

  Future<void> _guardar() async {
    final l10n = context.l10n;
    if (_asistentes.isEmpty) {
      _showError(l10n.tr('errorMarkAtLeastOnePlayer'));
      return;
    }

    for (final id in _asistentes) {
      Jugador? j;
      for (final x in _habituales) {
        if (x.keyId == id) {
          j = x;
          break;
        }
      }
      if (j == null) {
        _showError(l10n.tr('errorMarkAtLeastOnePlayer'));
        return;
      }
      final pago = _pagoDe(id);
      final total = _netoAPagarPartido(j);
      if (pago.tipo == TipoPago.parcial && total > 0) {
        final m = parseMoney(pago.montoParcial.text);
        if (m <= 0) {
          _showError(l10n.tr('errorPlayerPartialAmount', params: {'name': j.nombre}));
          return;
        }
        if (!pago.abonoConfirmado) {
          _showError(l10n.tr('errorConfirmPartialFirst', params: {'name': j.nombre}));
          return;
        }
      }
      for (final cobro in _cobrosIndividuales[id] ?? []) {
        if (!cobro.guardado && cobro.tieneDatos) {
          _showError(
            l10n.tr('errorSaveExtraChargeFirst', params: {'name': j.nombre}),
          );
          return;
        }
      }
    }

    for (final gasto in _gastosCompartidos) {
      if (gasto.monto <= 0) continue;
      if (gasto.label.trim().isEmpty) {
        _showError(l10n.tr('errorSharedExpenseName'));
        return;
      }
      // Cancha/Pelotas siempre se reparte entre asistentes (columnas fijas).
      if (GastoPresetLogic.isFixedPreset(gasto.label)) continue;
      final n = _participantesRepartoGasto(gasto).length;
      if (n == 0) {
        _showError(
          l10n.tr('errorMarkParticipants', params: {'label': gasto.label}),
        );
        return;
      }
    }

    setState(() => _guardando = true);

    try {
      final repos = context.repos;
      final recinto = _recintoCtrl.text.trim();
      final sportType = _sportType;
      final partido = Partido(
        fecha: _fechaPartido,
        costoCancha: _monto(ConceptosCobro.cancha),
        costoPelotas: _monto(ConceptosCobro.pelotas),
        recinto: recinto.isEmpty ? null : recinto,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
        comprobanteCancha: GastoPresetLogic.comprobantePreset(
          _gastosCompartidos,
          ConceptosCobro.cancha,
        ),
        comprobantePelotas: GastoPresetLogic.comprobantePreset(
          _gastosCompartidos,
          ConceptosCobro.pelotas,
        ),
        sportType: sportType,
        createdAt: _createdAtOriginal ?? DateTime.now(),
      );

      if (recinto.isNotEmpty) {
        await _prefs.saveUltimoRecinto(recinto);
      }

      final costos = _costosVariables()
          .map(
            (cv) => (
              concepto: cv.concepto,
              montoTotal: cv.montoTotal,
              jugadores: cv.jugadores,
              comprobantePath: cv.comprobantePath,
              comprobanteUrl: cv.comprobantePath,
              iconKey: cv.iconKey,
            ),
          )
          .toList();
      int? partidoIdRecordatorios;
      if (_esOrganizando && widget.partidoId != null) {
        await repos.completarPartidoOrganizado(
          partidoId: widget.partidoId!,
          partido: partido,
          jugadoresAsistentes: _asistentes.toList(),
          montoPagadoPorJugador: _montoPagadoMap,
          costosVariables: costos,
        );
        partidoIdRecordatorios = widget.partidoId;
      } else if (widget.isEditing) {
        await repos.actualizarPartido(
          partidoId: widget.partidoId!,
          partido: partido,
          jugadoresAsistentes: _asistentes.toList(),
          montoPagadoPorJugador: _montoPagadoMap,
          costosVariables: costos,
        );
      } else {
        partidoIdRecordatorios = await repos.guardarPartido(
          partido: partido,
          jugadoresAsistentes: _asistentes.toList(),
          montoPagadoPorJugador: _montoPagadoMap,
          costosVariables: costos,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _esOrganizando
                ? l10n.tr('matchRegisteredWithCharges')
                : widget.isEditing
                    ? l10n.tr('matchUpdated')
                    : l10n.tr('matchSaved'),
          ),
        ),
      );
      if (partidoIdRecordatorios != null) {
        await CobroRecordatorioPartidoFlow.preguntarTrasRegistrarCobros(
          context,
          partidoId: partidoIdRecordatorios,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showError(context.userError(e));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  Future<void> _eliminarPartido() async {
    final id = widget.partidoId;
    if (id == null) return;

    final fecha = formatFecha(_fechaPartido);
    final l10n = context.l10n;
    final ok = await confirmarEliminarPartido(
      context,
      titulo: l10n.tr('deleteMatchTitle'),
      mensaje: l10n.tr('deleteMatchMessage', params: {'date': fecha}),
    );
    if (!ok || !mounted) return;

    await context.repos.eliminarPartido(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('matchDeleted'))),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themed = context.readSettings().themeForSport(_sportType);
    return Theme(
      data: themed,
      child: Scaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(
        backgroundColor: themed.colorScheme.primary,
        foregroundColor: Colors.white,
        title: Text(
          _esOrganizando
              ? l10n.tr('chargeMatchTitle')
              : widget.isEditing
                  ? l10n.tr('editMatchTitle')
                  : l10n.tr('newMatchTitle'),
        ),
        actions: [
          if (widget.isEditing && !_esOrganizando)
            IconButton(
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: l10n.tr('deleteMatchTitle'),
              onPressed: _eliminarPartido,
            ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _habituales.isEmpty
              ? _buildSinJugadores()
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        children: [
                          if (widget.isEditing) _buildInfoEdicion(),
                          _buildDatosPartido(),
                          if (_esOrganizando) ...[
                            const SizedBox(height: 12),
                            _buildBannerCobro(),
                          ],
                          if (context.repos.isCloud && _esOrganizando) ...[
                            const SizedBox(height: 12),
                            Card(
                              color: Colors.blue.shade50,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    Icon(Icons.cloud_sync,
                                        color: Colors.blue.shade800),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        l10n.tr('collaborativeModeHint'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          _buildJugadoresPartido(),
                          const SizedBox(height: 12),
                          _buildItemsCobro(),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    _buildSaveBar(),
                  ],
                ),
    ),
    );
  }

  Widget _buildSinJugadores() {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.tr('addPlayersFirst')),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/jugadores'),
            child: Text(l10n.tr('goToPlayers')),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerCobro() {
    final l10n = context.l10n;
    final fechaStr =
        '${_fechaPartido.day}/${_fechaPartido.month}/${_fechaPartido.year} · '
        '${_fechaPartido.hour.toString().padLeft(2, '0')}:'
        '${_fechaPartido.minute.toString().padLeft(2, '0')}';
    final recinto = _recintoCtrl.text.trim();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade50, Colors.teal.shade50],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: context.sportPalette.surfaceTint,
            child: SportIcon(color: context.sportPrimaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.tr('matchConfirmedLine', params: {
                    'players': _asistentes.length == 1
                        ? l10n.tr('onePlayer')
                        : l10n.tr('matchPlayersCount', params: {
                            'count': '${_asistentes.length}',
                          }),
                  }),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  recinto.isNotEmpty ? '$fechaStr · $recinto' : fechaStr,
                  style: TextStyle(fontSize: 12, color: Colors.green.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoEdicion() {
    final l10n = context.l10n;
    return Card(
      color: Colors.blue.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text(l10n.tr('editingExistingMatch')),
        subtitle: Text(l10n.tr('balancesRecalcOnSave')),
      ),
    );
  }

  Widget _buildDatosPartido() {
    final l10n = context.l10n;
    final fechaStr =
        '${_fechaPartido.day}/${_fechaPartido.month}/${_fechaPartido.year} '
        '${_fechaPartido.hour.toString().padLeft(2, '0')}:'
        '${_fechaPartido.minute.toString().padLeft(2, '0')}';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildEncabezadoSeccion(
              titulo: l10n.tr('matchDetailsTitle'),
              icono: Icons.event,
              color: context.sportPrimary,
            ),
            const SizedBox(height: 16),
            MatchSportPicker(
              value: _sportType,
              onChanged: (sport) => setState(() => _sportType = sport),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.calendar_today, color: context.sportPrimary),
              title: Text(l10n.tr('dateAndTime')),
              subtitle: Text(fechaStr),
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar),
                tooltip: l10n.tr('changeDate'),
                onPressed: _elegirFecha,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _recintoCtrl,
              decoration: InputDecoration(
                labelText: l10n.tr('venueClubLabel'),
                hintText: l10n.tr('venueHint'),
                prefixIcon: const Icon(Icons.location_on_outlined),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _recintosSugeridos.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: l10n.tr('recentVenues'),
                        icon: Icon(
                          Icons.history_rounded,
                          color: Colors.grey.shade600,
                        ),
                        onSelected: (r) =>
                            setState(() => _recintoCtrl.text = r),
                        itemBuilder: (ctx) => _recintosSugeridos
                            .map(
                              (r) => PopupMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                      ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notasCtrl,
              decoration: InputDecoration(
                labelText: l10n.tr('notesOptionalLabel'),
                prefixIcon: const Icon(Icons.notes),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaPartido,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fechaPartido),
    );
    if (!mounted) return;

    setState(() {
      _fechaPartido = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora?.hour ?? _fechaPartido.hour,
        hora?.minute ?? _fechaPartido.minute,
      );
    });
  }

  Widget _buildItemsCobro() {
    final l10n = context.l10n;
    final nAsistentes = _asistentes.length;
    final suggestions = GastoSportSuggestions.chipsFor(_sportType);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEncabezadoSeccion(
              titulo: l10n.tr('matchExpensesTitle'),
              subtitulo: l10n.tr('enterExpensesHint'),
              icono: Icons.receipt_long,
              color: Colors.teal.shade700,
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                l10n.tr('expensePresetsHint'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in suggestions)
                    _buildSuggestionChip(s, l10n),
                ],
              ),
            ],
            // Slot fijo: evita remount del TextField al aparecer el chip.
            ListenableBuilder(
              listenable: _gastosMontosListenable,
              builder: (context, _) {
                final totalFijo = _monto(ConceptosCobro.cancha) +
                    _monto(ConceptosCobro.pelotas);
                if (nAsistentes <= 0 || totalFijo <= 0) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildChipProrrateo(
                    l10n.tr('courtAndBallsPerPerson', params: {
                      'court': formatMoney(_prorrateoCancha()),
                      'balls': formatMoney(_prorrateoPelotas()),
                    }),
                    color: Colors.green.shade700,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildGrupoCobro(
              titulo: l10n.groupExpensesTitle,
              subtitulo: l10n.groupExpensesSubtitle,
              icono: Icons.playlist_add_check_rounded,
              color: Colors.deepOrange.shade700,
              hijos: [
                ..._gastosCompartidos.map(_buildTarjetaGastoCompartido),
                OutlinedButton.icon(
                  onPressed: _agregarGastoCompartido,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addExpense),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionChip(
    GastoSportSuggestion suggestion,
    MatchPayStrings l10n,
  ) {
    final alreadyAdded = switch (suggestion.kind) {
      GastoSuggestionKind.venue =>
        GastoPresetLogic.findPreset(_gastosCompartidos, ConceptosCobro.cancha) !=
            null,
      GastoSuggestionKind.equipment =>
        GastoPresetLogic.findPreset(
              _gastosCompartidos,
              ConceptosCobro.pelotas,
            ) !=
            null,
      GastoSuggestionKind.freeText => _gastosCompartidos.any(
          (g) =>
              g.label.toLowerCase() ==
              l10n.tr(suggestion.labelKey).toLowerCase(),
        ),
    };
    final color = switch (suggestion.kind) {
      GastoSuggestionKind.venue => const Color(0xFF2E7D32),
      GastoSuggestionKind.equipment => Colors.lightGreen.shade800,
      GastoSuggestionKind.freeText => Colors.deepOrange.shade700,
    };
    final avatarIcon = switch (suggestion.kind) {
      GastoSuggestionKind.venue => sportVenueIcon(_sportType),
      GastoSuggestionKind.equipment => sportBallsIcon(_sportType),
      GastoSuggestionKind.freeText => suggestion.icon.icon,
    };

    return ActionChip(
      avatar: Icon(
        avatarIcon,
        size: 18,
        color: alreadyAdded ? Colors.grey : color,
      ),
      label: Text(l10n.tr(suggestion.labelKey)),
      onPressed:
          alreadyAdded ? null : () => _agregarSugerenciaGasto(suggestion),
    );
  }

  Widget _buildEncabezadoSeccion({
    required String titulo,
    String? subtitulo,
    required IconData icono,
    required Color color,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icono, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              if (subtitulo != null && subtitulo.isNotEmpty)
                Text(
                  subtitulo,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildGrupoCobro({
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color color,
    required List<Widget> hijos,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        color: color.withValues(alpha: 0.04),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(icono, color: color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: color,
                        ),
                      ),
                      Text(
                        subtitulo,
                        style: TextStyle(
                          fontSize: 11,
                          color: color.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            child: Column(children: hijos),
          ),
        ],
      ),
    );
  }

  Widget _buildChipProrrateo(String texto, {required Color color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetaGastoCompartido(SharedExpenseEntry entry) {
    final theme = Theme.of(context);
    final color = entry.iconKey.colorFor(theme);
    final esPreset = GastoPresetLogic.isFixedPreset(entry.label);
    final l10n = context.l10n;

    // Cabecera + campos fijos: se pasan como [child] del ListenableBuilder para
    // que el TextField de monto no se remonte al escribir (mantiene el foco).
    final camposEstables = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ExpenseIconPicker(
              selected: entry.iconKey,
              onSelected: esPreset
                  ? null
                  : (k) => setState(() => entry.iconKey = k),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red.shade400,
              onPressed: () => _eliminarGastoCompartido(entry),
              tooltip: l10n.tr('deleteTooltip'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (esPreset)
          InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.tr('expensePresetLabel'),
              prefixIcon: Icon(entry.iconKey.icon, color: color),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(
              l10n.translateConcept(entry.label),
              style: const TextStyle(fontSize: 16),
            ),
          )
        else
          TextField(
            controller: entry.labelCtrl,
            decoration: InputDecoration(
              labelText: l10n.expenseLabelHint,
              prefixIcon: Icon(entry.iconKey.icon, color: color),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
        const SizedBox(height: 8),
        TextField(
          controller: entry.montoCtrl,
          decoration: InputDecoration(
            labelText: l10n.tr('totalAmountLabel'),
            prefixIcon: const Icon(Icons.payments),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: moneyInputFormatters,
          onChanged: (_) {
            // Sin setState: el ListenableBuilder reacciona al controller.
            if (entry.monto <= 0 && entry.comprobantePath != null) {
              ComprobanteService.instance.deleteAny(entry.comprobantePath);
              entry.comprobantePath = null;
            }
            if (entry.monto <= 0) {
              entry.repartoEntreTodos = true;
              entry.sinParticipantesExplicito = false;
              entry.participantes.clear();
            }
          },
          onEditingComplete: () => setState(() {}),
        ),
      ],
    );

    return ListenableBuilder(
      key: ValueKey('gasto-${entry.id}'),
      listenable: entry.montoCtrl,
      builder: (context, child) {
        final monto = entry.monto;
        final participantes = esPreset
            ? _asistentes
            : _participantesRepartoGasto(entry);
        final asistentesList =
            _habituales.where((j) => _asistentes.contains(j.keyId)).toList();
        final n = participantes.length;
        final prorrateo = esPreset
            ? (n > 0 ? monto / n : 0.0)
            : _prorrateoGasto(entry);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: monto > 0
                  ? color.withValues(alpha: 0.45)
                  : Colors.grey.shade200,
              width: monto > 0 ? 1.5 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                child!,
                if (monto > 0 && n > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      esPreset
                          ? l10n.tr('perPersonWithCount', params: {
                              'amount': formatMoney(prorrateo),
                              'count': '$n',
                            })
                          : l10n.tr('perPersonParticipants', params: {
                              'amount': formatMoney(prorrateo),
                              'count': '$n',
                            }),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                if (monto > 0 && esPreset && _asistentes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.tr('enterAttendeesToCalcPerPerson'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                if (monto > 0) ...[
                  const SizedBox(height: 8),
                  ComprobantePagoTile(
                    comprobantePath: entry.comprobantePath,
                    onChanged: (path) =>
                        setState(() => entry.comprobantePath = path),
                    compact: true,
                  ),
                ],
                if (monto > 0 && _asistentes.isNotEmpty && !esPreset) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.orange.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.people,
                              size: 16,
                              color: Colors.orange.shade800,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              l10n.tr(
                                'whoParticipated',
                                params: {'count': '$n'},
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade900,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () =>
                                  _setParticipantesGasto(entry, true),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: Text(
                                l10n.tr('all'),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  _setParticipantesGasto(entry, false),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              child: Text(
                                l10n.tr('none'),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: asistentesList.map((j) {
                            final sel = participantes.contains(j.keyId);
                            return FilterChip(
                              avatar: sel
                                  ? Icon(
                                      Icons.check,
                                      size: 14,
                                      color: Colors.orange.shade900,
                                    )
                                  : null,
                              label: Text(
                                j.nombre,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: sel,
                              onSelected: (_) =>
                                  _toggleParticipanteGasto(entry, j.keyId),
                              selectedColor: Colors.orange.shade100,
                              checkmarkColor: Colors.orange.shade900,
                              backgroundColor: Colors.grey.shade50,
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
      child: camposEstables,
    );
  }

  void _toggleJugadoresExpandido() {
    setState(() => _jugadoresExpandido = !_jugadoresExpandido);
  }

  void _seleccionarTodosJugaron() {
    setState(() {
      _asistentes.addAll(_habituales.map((x) => x.keyId));
      for (final g in _gastosCompartidos) {
        if (g.monto > 0) {
          g.repartoEntreTodos = true;
          g.sinParticipantesExplicito = false;
          g.participantes.clear();
        }
      }
      // Con muchos jugadores, colapsar deja la pantalla legible.
      if (_asistentes.length > 6) _jugadoresExpandido = false;
    });
  }

  void _limpiarAsistentes() {
    setState(() {
      for (final id in _asistentes.toList()) {
        _pagos.remove(id)?.dispose();
        _eliminarCobrosJugador(id);
        for (final g in _gastosCompartidos) {
          g.participantes.remove(id);
        }
      }
      _asistentes.clear();
    });
  }

  void _seleccionarJugadoresVisibles(Iterable<Jugador> visibles) {
    setState(() {
      for (final j in visibles) {
        if (_asistentes.add(j.keyId)) {
          _pagos.putIfAbsent(j.keyId, EstadoPagoJugador.new);
        }
      }
      if (_asistentes.length > 6) _jugadoresExpandido = false;
    });
  }

  Widget _buildJugadoresPartido() {
    final l10n = context.l10n;
    final color = Colors.indigo.shade700;
    final query = _jugadoresBusquedaCtrl.text;
    final jugadoresOrdenados = sortJugadoresByPriority(
      jugadores: _habituales,
      priorityIds: _prioridadJugadorIds,
      selectedIds: _asistentes,
    );
    final jugadoresVisibles = filterJugadoresByName(jugadoresOrdenados, query);
    final seleccionados = jugadoresOrdenados
        .where((j) => _asistentes.contains(j.keyId))
        .toList();
    final nSel = seleccionados.length;
    final nTotal = _habituales.length;
    final filtroActivo = query.trim().isNotEmpty;
    final prioridadEnRoster = [
      for (final j in _habituales)
        if (_prioridadJugadorIds.contains(j.keyId)) j,
    ];
    final prioridadPendiente = [
      for (final j in prioridadEnRoster)
        if (!_asistentes.contains(j.keyId)) j,
    ];
    final mostrarSecciones =
        !filtroActivo && _prioridadFuente != JugadorPrioritySource.none;
    final partes = mostrarSecciones
        ? splitJugadoresByPriority(
            ordered: jugadoresVisibles,
            priorityIds: _prioridadJugadorIds,
          )
        : (priority: const <Jugador>[], rest: jugadoresVisibles);
    final conteo = nSel == 0
        ? l10n.tr('playersNoneSelected', params: {'total': '$nTotal'})
        : l10n.tr('playersSelectedCount', params: {
            'count': '$nSel',
            'total': '$nTotal',
          });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _toggleJugadoresExpandido,
              borderRadius: BorderRadius.circular(12),
              child: _buildEncabezadoSeccion(
                titulo: context.repos.isCloud
                    ? l10n.tr('confirmedPlayersTitle')
                    : l10n.tr('playersAndPaymentsTitle'),
                subtitulo: conteo,
                icono: Icons.people,
                color: color,
                trailing: Icon(
                  _jugadoresExpandido
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: color,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!_jugadoresExpandido)
              _buildJugadoresColapsado(seleccionados)
            else ...[
              TextField(
                controller: _jugadoresBusquedaCtrl,
                decoration: InputDecoration(
                  hintText: l10n.tr('playersSearchHint'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: query.trim().isEmpty
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
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (prioridadPendiente.isNotEmpty)
                    ActionChip(
                      avatar: const Icon(Icons.history, size: 18),
                      label: Text(
                        l10n.tr(
                          _prioridadFuente ==
                                  JugadorPrioritySource.convocatoriaConfirmed
                              ? 'playersSelectPriorityConfirmed'
                              : 'playersSelectPriority',
                          params: {'count': '${prioridadPendiente.length}'},
                        ),
                      ),
                      onPressed: () =>
                          _seleccionarJugadoresVisibles(prioridadPendiente),
                    ),
                  if (filtroActivo && jugadoresVisibles.isNotEmpty)
                    ActionChip(
                      avatar: const Icon(Icons.playlist_add_check, size: 18),
                      label: Text(
                        l10n.tr(
                          'playersSelectFiltered',
                          params: {'count': '${jugadoresVisibles.length}'},
                        ),
                      ),
                      onPressed: () =>
                          _seleccionarJugadoresVisibles(jugadoresVisibles),
                    )
                  else if (nTotal <= 20)
                    ActionChip(
                      avatar: const Icon(Icons.group, size: 18),
                      label: Text(l10n.tr('allPlayed')),
                      onPressed: _seleccionarTodosJugaron,
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.clear_all, size: 18),
                    label: Text(l10n.tr('playersClearSelection')),
                    onPressed: nSel == 0 ? null : _limpiarAsistentes,
                  ),
                  if (!context.repos.isCloud) ...[
                    ActionChip(
                      avatar: const Icon(Icons.payments, size: 18),
                      label: Text(l10n.tr('payAllFull')),
                      onPressed: _asistentes.isEmpty
                          ? null
                          : () => _marcarTodosPagados(true),
                    ),
                    ActionChip(
                      label: Text(l10n.tr('noPayments')),
                      onPressed: _asistentes.isEmpty
                          ? null
                          : () => _marcarTodosPagados(false),
                    ),
                  ],
                ],
              ),
              if (filtroActivo) ...[
                const SizedBox(height: 6),
                Text(
                  l10n.tr('playersSelectFilteredHint'),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
              const SizedBox(height: 8),
              if (jugadoresVisibles.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l10n.tr('playersNoneSelected', params: {'total': '0'}),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              else if (mostrarSecciones) ...[
                if (partes.priority.isNotEmpty) ...[
                  _buildJugadoresSeccionTitulo(
                    _prioridadFuente ==
                            JugadorPrioritySource.convocatoriaConfirmed
                        ? l10n.tr('playersPriorityConfirmed')
                        : l10n.tr('playersPriorityLastMatch'),
                    color,
                  ),
                  ...partes.priority.map((j) => _buildFilaJugador(j)),
                ],
                if (partes.rest.isNotEmpty) ...[
                  if (partes.priority.isNotEmpty)
                    _buildJugadoresSeccionTitulo(
                      l10n.tr('playersPriorityRest'),
                      Colors.grey.shade700,
                    ),
                  ...partes.rest.map((j) => _buildFilaJugador(j)),
                ],
              ] else
                ...jugadoresVisibles.map((j) => _buildFilaJugador(j)),
              if (nTotal > 6) ...[
                const SizedBox(height: 4),
                Center(
                  child: TextButton.icon(
                    onPressed: () =>
                        setState(() => _jugadoresExpandido = false),
                    icon: const Icon(Icons.unfold_less, size: 18),
                    label: Text(l10n.tr('playersCollapseList')),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildJugadoresSeccionTitulo(String titulo, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Text(
        titulo,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildJugadoresColapsado(List<Jugador> seleccionados) {
    final l10n = context.l10n;
    const maxChips = 8;

    return Material(
      color: Colors.indigo.shade50,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _toggleJugadoresExpandido,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (seleccionados.isEmpty)
                Row(
                  children: [
                    Icon(Icons.person_add_alt_1_outlined,
                        size: 20, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.tr('playersTapToSelect'),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.indigo.shade900,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.indigo.shade400),
                  ],
                )
              else ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final j in seleccionados.take(maxChips))
                      Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          j.nombre,
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: Colors.white,
                        side: BorderSide(color: Colors.indigo.shade100),
                        padding: EdgeInsets.zero,
                      ),
                    if (seleccionados.length > maxChips)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          '+${seleccionados.length - maxChips}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade800,
                          ),
                        ),
                        backgroundColor: Colors.indigo.shade100,
                        side: BorderSide.none,
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.tr('playersTapToEditList'),
                  style: TextStyle(fontSize: 12, color: Colors.indigo.shade700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilaJugador(Jugador j) {
    final l10n = context.l10n;
    final asistio = _asistentes.contains(j.keyId);
    final totalDeb = asistio ? _netoAPagarPartido(j) : 0.0;
    final pago = asistio ? _pagoDe(j.keyId) : null;
    final restante = asistio ? _saldoRestante(j) : 0.0;
    final aTransferir = asistio ? _pendientePartido(j) : 0.0;
    // En nube el pago lo declara el jugador; aquí solo se marca asistencia.
    final modoNube = context.repos.isCloud;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: asistio ? null : Colors.grey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: asistio,
                  onChanged: (_) => _toggleAsistente(j),
                ),
                Expanded(
                  child: Text(
                    j.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (asistio && !modoNube && !_esOrganizando)
                  Text(
                    l10n.tr('toTransfer', params: {
                      'amount': formatMoney(aTransferir),
                    }),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.end,
                  ),
              ],
            ),
            if (asistio && pago != null && !modoNube && !_esOrganizando) ...[
              const SizedBox(height: 8),
              SegmentedButton<TipoPago>(
                segments: [
                  ButtonSegment(
                    value: TipoPago.ninguno,
                    label: Text(l10n.tr('noPayment'), style: const TextStyle(fontSize: 11)),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                  ButtonSegment(
                    value: TipoPago.total,
                    label: Text(l10n.tr('homePayFull'), style: const TextStyle(fontSize: 11)),
                    icon: const Icon(Icons.check_circle, size: 16),
                  ),
                  ButtonSegment(
                    value: TipoPago.parcial,
                    label: Text(l10n.tr('homePartialPayment'), style: const TextStyle(fontSize: 11)),
                    icon: const Icon(Icons.savings_outlined, size: 16),
                  ),
                ],
                selected: {pago.tipo},
                onSelectionChanged: (s) => _setTipoPago(j.keyId, s.first),
              ),
              if (pago.tipo == TipoPago.parcial) ...[
                const SizedBox(height: 8),
                if (pago.abonoConfirmado) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _textoEstadoPago(pago, totalDeb, restante, j),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _editarAbonoJugador(j.keyId),
                          child: Text(l10n.tr('editTooltip')),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: pago.montoParcial,
                    decoration: InputDecoration(
                      labelText: l10n.tr('homePartialAmountLabel'),
                      hintText: '0',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      helperText: l10n.tr('homePartialAmountHelper'),
                      helperMaxLines: 2,
                      suffixText: l10n.tr('homeOwesSuffix', params: {
                        'amount': formatMoney(totalDeb),
                      }),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: moneyInputFormatters,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _confirmarAbonoJugador(j),
                    icon: const Icon(Icons.savings_outlined, size: 18),
                    label: Text(l10n.tr('confirmPartialPayment')),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
              ],
              if (pago.tipo != TipoPago.parcial) ...[
                const SizedBox(height: 6),
                Text(
                  _textoEstadoPago(pago, totalDeb, restante, j),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: restante <= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ],
              _buildCobrosIndividuales(j),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCobrosIndividuales(Jugador j) {
    final l10n = context.l10n;
    final cobros = _cobrosIndividuales[j.keyId] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.add_circle_outline, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Text(
              l10n.tr('individualExtraChargesTitle'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          l10n.tr('individualChargeInstructions'),
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        ...cobros.map((c) => _buildFilaCobroIndividual(j.keyId, c)),
        TextButton.icon(
          onPressed: () => _agregarCobroIndividual(j.keyId),
          icon: const Icon(Icons.add, size: 18),
          label: Text(l10n.tr('addExtraCharge')),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildFilaCobroIndividual(String jugadorId, CobroIndividualEntry cobro) {
    final l10n = context.l10n;
    if (cobro.guardado) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cobro.concepto,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    formatMoney(cobro.monto),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (cobro.comprobantePath != null)
                    Text(
                      l10n.tr('receiptAttached'),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green.shade700,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: l10n.tr('editChargeTooltip'),
              onPressed: () => _editarCobroIndividual(cobro),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 20),
              tooltip: l10n.tr('removeChargeTooltip'),
              onPressed: () => _eliminarCobroIndividual(jugadorId, cobro),
            ),
          ],
        ),
      );
    }

    final filaCampos = Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: cobro.conceptoCtrl,
            decoration: InputDecoration(
              labelText: l10n.tr('conceptLabel'),
              hintText: l10n.tr('conceptHintRaqueta'),
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
            ),
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: cobro.montoCtrl,
            decoration: InputDecoration(
              labelText: l10n.tr('amountLabel'),
              hintText: '0',
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: moneyInputFormatters,
            onChanged: (_) {
              if (cobro.monto <= 0 && cobro.comprobantePath != null) {
                ComprobanteService.instance.deleteAny(cobro.comprobantePath);
                cobro.comprobantePath = null;
              }
            },
          ),
        ),
        IconButton(
          icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
          tooltip: l10n.tr('removeChargeTooltip'),
          onPressed: () => _eliminarCobroIndividual(jugadorId, cobro),
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          filaCampos,
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: _extraSuggestions().map((s) {
              return ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  cobro.conceptoCtrl.text = s;
                },
              );
            }).toList(),
          ),
          ListenableBuilder(
            listenable: cobro.montoCtrl,
            builder: (context, _) {
              if (cobro.monto <= 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ComprobantePagoTile(
                  comprobantePath: cobro.comprobantePath,
                  onChanged: (path) =>
                      setState(() => cobro.comprobantePath = path),
                  compact: true,
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _cancelarCobroIndividual(jugadorId, cobro),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(
                    l10n.tr('cancel'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _guardarCobroIndividual(jugadorId, cobro),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    l10n.tr('saveCharge'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _textoEstadoPago(
    EstadoPagoJugador pago,
    double totalDeb,
    double restante,
    Jugador j,
  ) {
    final l10n = context.l10n;
    final favor = _saldoFavorAplicado(j);
    if (restante < 0) {
      return l10n.tr('statusCoveredWithCredit', params: {
        'amount': formatMoney(-restante),
      });
    }
    if (totalDeb <= 0 && pago.tipo == TipoPago.total) {
      if (favor > 0) {
        return l10n.tr('statusCoveredWithCreditApplied', params: {
          'amount': formatMoney(favor),
        });
      }
      return l10n.tr('statusUpToDateNoTransfer');
    }
    switch (pago.tipo) {
      case TipoPago.total:
        return l10n.tr('statusToTransfer', params: {
          'amount': formatMoney(totalDeb > 0 ? totalDeb : 0),
        });
      case TipoPago.parcial:
        final m = pago.montoEfectivo(totalDeb);
        if (restante < 0) {
          return l10n.tr('statusPartialWithCredit', params: {
            'paid': formatMoney(m),
            'credit': formatMoney(-restante),
          });
        }
        return l10n.tr('statusPartialRemaining', params: {
          'paid': formatMoney(m),
          'remaining': formatMoney(restante > 0 ? restante : 0),
        });
      case TipoPago.ninguno:
        return l10n.tr('statusOwesTransfer', params: {
          'amount': formatMoney(restante > 0 ? restante : 0),
        });
    }
  }

  Widget _buildSaveBar() {
    final l10n = context.l10n;
    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: FilledButton.icon(
          onPressed: _guardando ? null : _confirmarYGuardar,
          icon: _guardando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save),
          label: Text(
            _guardando
                ? l10n.tr('saving')
                : _esOrganizando
                    ? l10n.tr('confirmCharges')
                    : l10n.tr('saveMatch'),
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  List<String> _extraSuggestions() {
    final l10n = context.l10n;
    return [
      l10n.tr('extraSuggestionRaqueta'),
      l10n.tr('extraSuggestionDrinks'),
      l10n.tr('extraSuggestionFine'),
      l10n.tr('extraSuggestionOther'),
    ];
  }
}
