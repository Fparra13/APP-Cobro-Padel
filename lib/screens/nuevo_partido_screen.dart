import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/conceptos_cobro.dart';
import '../models/cobro_individual_entry.dart';
import '../models/estado_pago_jugador.dart';
import '../models/jugador.dart';
import '../models/partido.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/partido_repository.dart';
import '../repositories/saldo_repository.dart';
import '../services/calculation_service.dart';
import '../services/comprobante_service.dart';
import '../services/preferences_service.dart';
import '../utils/formatters.dart';
import '../widgets/comprobante_pago_tile.dart';
import '../widgets/enviar_informes_sheet.dart';

class NuevoPartidoScreen extends StatefulWidget {
  final int? partidoId;

  const NuevoPartidoScreen({super.key, this.partidoId});

  bool get isEditing => partidoId != null;

  @override
  State<NuevoPartidoScreen> createState() => _NuevoPartidoScreenState();
}

class _NuevoPartidoScreenState extends State<NuevoPartidoScreen> {
  final _partidoRepo = PartidoRepository();
  final _jugadorRepo = JugadorRepository();
  final _saldoRepo = SaldoRepository();
  final _prefs = PreferencesService();

  final _montos = {
    for (final c in ConceptosCobro.todos) c: TextEditingController(),
  };
  final _notasCtrl = TextEditingController();
  final _recintoCtrl = TextEditingController();

  List<Jugador> _habituales = [];
  List<String> _recintosSugeridos = [];
  final Map<int, List<CobroIndividualEntry>> _cobrosIndividuales = {};
  /// Jugadores que participan en cada ítem variable (Asado, Schop, Otros).
  final Map<String, Set<int>> _participantesVariable = {};
  /// Comprobante de pago del gasto por concepto (Cancha, Pelotas, Asado, etc.).
  final Map<String, String?> _comprobantesGasto = {};
  final Set<int> _asistentes = {};
  final Map<int, EstadoPagoJugador> _pagos = {};
  final Map<int, double> _saldosSnapshot = {};
  DateTime _fechaPartido = DateTime.now();
  bool _loading = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final habituales = await _jugadorRepo.getAll(soloActivos: true);
    final recintos = await _partidoRepo.getRecintosRecientes();
    final ultimoRecinto = await _prefs.ultimoRecinto;

    if (widget.partidoId != null) {
      final completo = await _partidoRepo.getCompleto(widget.partidoId!);
      final historicos = await _saldoRepo.getByPartido(widget.partidoId!);

      if (completo != null) {
        _montos[ConceptosCobro.cancha]!.text =
            completo.partido.costoCancha.round().toString();
        _montos[ConceptosCobro.pelotas]!.text =
            completo.partido.costoPelotas.round().toString();
        _notasCtrl.text = completo.partido.notas ?? '';
        _recintoCtrl.text = completo.partido.recinto ?? '';
        _fechaPartido = completo.partido.fecha;

        if (completo.partido.comprobanteCancha != null) {
          _comprobantesGasto[ConceptosCobro.cancha] =
              completo.partido.comprobanteCancha;
        }
        if (completo.partido.comprobantePelotas != null) {
          _comprobantesGasto[ConceptosCobro.pelotas] =
              completo.partido.comprobantePelotas;
        }

        for (final cv in completo.costosVariables) {
          final asigs = completo.asignacionesPorCosto[cv.id] ?? [];
          if (asigs.length == 1) {
            final jugadorId = asigs.first.jugadorId;
            _cobrosIndividuales.putIfAbsent(jugadorId, () => []);
            _cobrosIndividuales[jugadorId]!.add(
              CobroIndividualEntry(
                concepto: cv.concepto,
                monto: asigs.first.monto.round().toString(),
                comprobantePath: cv.comprobantePath,
                guardado: true,
              ),
            );
            continue;
          }
          if (!ConceptosCobro.variables.contains(cv.concepto)) continue;
          final key = cv.concepto;
          _montos[key]!.text = cv.montoTotal.round().toString();
          _participantesVariable[key] =
              asigs.map((a) => a.jugadorId).toSet();
          if (cv.comprobantePath != null) {
            _comprobantesGasto[key] = cv.comprobantePath;
          }
        }

        for (final h in historicos) {
          _saldosSnapshot[h.jugadorId] = h.saldoAnterior;
        }

        for (final d in completo.detalles.where((d) => d.asistio)) {
          _asistentes.add(d.jugadorId);
          final ep = EstadoPagoJugador();
          if (d.pagado) {
            ep.tipo = TipoPago.total;
          } else if (d.montoPagado > 0) {
            ep.tipo = TipoPago.parcial;
            ep.montoParcial.text = d.montoPagado.round().toString();
          }
          _pagos[d.jugadorId] = ep;
        }

        final todos = <int, Jugador>{for (final j in habituales) j.id!: j};
        for (final id in _asistentes) {
          if (!todos.containsKey(id)) {
            final j = await _jugadorRepo.getById(id);
            if (j != null) todos[id] = j;
          }
        }

        if (mounted) {
          setState(() {
            _habituales = todos.values.toList()
              ..sort((a, b) => a.nombre.compareTo(b.nombre));
            _recintosSugeridos = recintos;
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
        if (_recintoCtrl.text.isEmpty && ultimoRecinto.isNotEmpty) {
          _recintoCtrl.text = ultimoRecinto;
        }
        _loading = false;
      });
    }
  }

  double _monto(String concepto) =>
      double.tryParse(_montos[concepto]!.text) ?? 0;

  double _saldoAnterior(Jugador j) {
    if (widget.isEditing && _saldosSnapshot.containsKey(j.id)) {
      return _saldosSnapshot[j.id!]!;
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

  double _variablesParaJugador(int jugadorId) {
    if (!_asistentes.contains(jugadorId)) return 0;
    double total = 0;
    for (final c in ConceptosCobro.variables) {
      final monto = _monto(c);
      if (monto > 0 && _participantesDe(c).contains(jugadorId)) {
        total += CalculationService.prorratear(
          monto,
          _participantesDe(c).length,
        );
      }
    }
    for (final cobro in _cobrosIndividuales[jugadorId] ?? []) {
      if (cobro.guardado) total += cobro.monto;
    }
    return total;
  }

  Set<int> _participantesDe(String concepto) {
    final set = _participantesVariable.putIfAbsent(concepto, () => {});
    set.removeWhere((id) => !_asistentes.contains(id));
    return set;
  }

  void _inicializarParticipantes(String concepto) {
    if (_monto(concepto) <= 0 || _asistentes.isEmpty) return;
    final set = _participantesDe(concepto);
    if (set.isEmpty) {
      set.addAll(_asistentes);
    }
  }

  void _toggleParticipanteVariable(String concepto, int jugadorId) {
    setState(() {
      final set = _participantesDe(concepto);
      if (set.contains(jugadorId)) {
        set.remove(jugadorId);
      } else {
        set.add(jugadorId);
      }
    });
  }

  void _setParticipantesVariable(String concepto, bool todos) {
    setState(() {
      final set = _participantesDe(concepto);
      set.clear();
      if (todos) set.addAll(_asistentes);
    });
  }

  double _prorrateoVariable(String concepto) {
    final monto = _monto(concepto);
    final n = _participantesDe(concepto).length;
    if (monto <= 0 || n == 0) return 0;
    return CalculationService.prorratear(monto, n);
  }

  double _cargoPartido(Jugador j) {
    if (!_asistentes.contains(j.id)) return 0;
    return _prorrateoCancha() +
        _prorrateoPelotas() +
        _variablesParaJugador(j.id!);
  }

  double _saldoFavorAplicado(Jugador j) =>
      CalculationService.saldoFavorAplicado(
        saldoAnterior: _saldoAnterior(j),
        cargoPartido: _cargoPartido(j),
      );

  double _totalATransferir(Jugador j) {
    if (!_asistentes.contains(j.id)) {
      return _saldoAnterior(j) > 0 ? _saldoAnterior(j) : 0;
    }
    return CalculationService.totalATransferir(
      saldoAnterior: _saldoAnterior(j),
      cargoPartido: _cargoPartido(j),
      montoPagado: _pagoDe(j.id!).montoEfectivo(_totalDebido(j)),
    );
  }

  void _autoAplicarSaldoFavor(int jugadorId) {
    final j = _habituales.firstWhere((x) => x.id == jugadorId);
    if (_totalDebido(j) <= 0) {
      _pagoDe(jugadorId).tipo = TipoPago.total;
    }
  }

  void _autoAplicarSaldoFavorTodos() {
    for (final id in _asistentes) {
      _autoAplicarSaldoFavor(id);
    }
  }

  double _totalDebido(Jugador j) {
    if (!_asistentes.contains(j.id)) return _saldoAnterior(j);
    return CalculationService.totalDebido(
      saldoAnterior: _saldoAnterior(j),
      cargoPartido: _cargoPartido(j),
    );
  }

  double _saldoRestante(Jugador j) {
    if (!_asistentes.contains(j.id)) return _saldoAnterior(j);
    final pago = _pagoDe(j.id!);
    return CalculationService.saldoDespuesPago(
      saldoAnterior: _saldoAnterior(j),
      cargoPartido: _cargoPartido(j),
      montoPagado: pago.montoEfectivo(_totalDebido(j)),
    );
  }

  EstadoPagoJugador _pagoDe(int jugadorId) =>
      _pagos.putIfAbsent(jugadorId, EstadoPagoJugador.new);

  @override
  void dispose() {
    for (final c in _montos.values) {
      c.dispose();
    }
    for (final p in _pagos.values) {
      p.dispose();
    }
    for (final lista in _cobrosIndividuales.values) {
      for (final c in lista) {
        c.dispose();
      }
    }
    _notasCtrl.dispose();
    _recintoCtrl.dispose();
    super.dispose();
  }

  void _toggleAsistente(Jugador j) {
    setState(() {
      if (_asistentes.contains(j.id)) {
        _asistentes.remove(j.id);
        _pagos.remove(j.id);
        _eliminarCobrosJugador(j.id!);
        for (final c in ConceptosCobro.variables) {
          _participantesDe(c).remove(j.id);
        }
      } else {
        _asistentes.add(j.id!);
        _autoAplicarSaldoFavor(j.id!);
      }
    });
  }

  void _eliminarCobrosJugador(int jugadorId) {
    final lista = _cobrosIndividuales.remove(jugadorId);
    if (lista != null) {
      for (final c in lista) {
        c.dispose();
      }
    }
  }

  void _agregarCobroIndividual(int jugadorId) {
    setState(() {
      _cobrosIndividuales.putIfAbsent(jugadorId, () => []);
      _cobrosIndividuales[jugadorId]!.add(CobroIndividualEntry());
    });
  }

  void _eliminarCobroIndividual(int jugadorId, CobroIndividualEntry entry) {
    setState(() {
      ComprobanteService.instance.delete(entry.comprobantePath);
      final lista = _cobrosIndividuales[jugadorId];
      lista?.remove(entry);
      entry.dispose();
      if (lista != null && lista.isEmpty) {
        _cobrosIndividuales.remove(jugadorId);
      }
    });
  }

  void _guardarCobroIndividual(int jugadorId, CobroIndividualEntry cobro) {
    if (cobro.concepto.isEmpty) {
      _showError('Indica el concepto del cobro extra');
      return;
    }
    if (cobro.monto <= 0) {
      _showError('Indica el monto del cobro extra');
      return;
    }
    setState(() => cobro.guardado = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cobro guardado: ${cobro.concepto} · ${formatMoney(cobro.monto)}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _cancelarCobroIndividual(int jugadorId, CobroIndividualEntry cobro) {
    if (!cobro.tieneDatos) {
      _eliminarCobroIndividual(jugadorId, cobro);
      return;
    }
    setState(() {
      cobro.conceptoCtrl.clear();
      cobro.montoCtrl.clear();
      if (cobro.comprobantePath != null) {
        ComprobanteService.instance.delete(cobro.comprobantePath);
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
        List<int> jugadores,
        String? comprobantePath,
      })> _costosVariables() {
    final list = <
        ({
          String concepto,
          double montoTotal,
          List<int> jugadores,
          String? comprobantePath,
        })>[];

    for (final c in ConceptosCobro.variables) {
      final monto = _monto(c);
      if (monto > 0) {
        _inicializarParticipantes(c);
        final participantes =
            _participantesDe(c).where((id) => _asistentes.contains(id)).toList();
        if (participantes.isEmpty) continue;
        list.add((
          concepto: c,
          montoTotal: monto,
          jugadores: participantes,
          comprobantePath: _comprobantesGasto[c],
        ));
      }
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
        ));
      }
    }

    return list;
  }

  void _setComprobanteGasto(String concepto, String? path) {
    setState(() {
      if (path == null) {
        _comprobantesGasto.remove(concepto);
      } else {
        _comprobantesGasto[concepto] = path;
      }
    });
  }

  void _limpiarComprobanteGasto(String concepto) {
    final path = _comprobantesGasto[concepto];
    if (path != null) {
      ComprobanteService.instance.delete(path);
      _comprobantesGasto.remove(concepto);
    }
  }

  void _onMontoGastoChanged(String concepto) {
    if (_monto(concepto) <= 0) {
      _limpiarComprobanteGasto(concepto);
    }
    setState(_autoAplicarSaldoFavorTodos);
  }

  void _setTipoPago(int jugadorId, TipoPago tipo) {
    setState(() {
      final p = _pagoDe(jugadorId);
      p.tipo = tipo;
      if (tipo == TipoPago.parcial) {
        p.montoParcial.clear();
      }
    });
  }

  void _marcarTodosPagados(bool pagaron) {
    setState(() {
      for (final id in _asistentes) {
        _pagoDe(id).tipo = pagaron ? TipoPago.total : TipoPago.ninguno;
      }
    });
  }

  Map<int, double> get _montoPagadoMap {
    final map = <int, double>{};
    for (final id in _asistentes) {
      final j = _habituales.firstWhere((x) => x.id == id);
      map[id] = _pagoDe(id).montoEfectivo(_totalDebido(j));
    }
    return map;
  }

  Future<void> _guardar() async {
    if (_asistentes.isEmpty) {
      _showError('Marca al menos un jugador asistente');
      return;
    }

    for (final id in _asistentes) {
      final j = _habituales.firstWhere((x) => x.id == id);
      final pago = _pagoDe(id);
      final total = _totalDebido(j);
      if (pago.tipo == TipoPago.parcial && total > 0) {
        final m = pago.montoEfectivo(total);
        if (m <= 0) {
          _showError('${j.nombre}: indica cuánto pagó (pago parcial)');
          return;
        }
        if (m >= total) {
          _showError(
            '${j.nombre}: el pago parcial debe ser menor al total (${formatMoney(total)})',
          );
          return;
        }
      }
      for (final cobro in _cobrosIndividuales[id] ?? []) {
        if (!cobro.guardado && cobro.tieneDatos) {
          _showError(
            '${j.nombre}: pulsa "Guardar cobro" en el cobro extra pendiente',
          );
          return;
        }
      }
    }

    for (final c in ConceptosCobro.variables) {
      if (_monto(c) <= 0) continue;
      _inicializarParticipantes(c);
      final n =
          _participantesDe(c).where((id) => _asistentes.contains(id)).length;
      if (n == 0) {
        _showError(
          'Marca quién participó en "$c" (no todos se quedan al asado/schop)',
        );
        return;
      }
    }

    setState(() => _guardando = true);

    try {
      final recinto = _recintoCtrl.text.trim();
      final partido = Partido(
        fecha: _fechaPartido,
        costoCancha: _monto(ConceptosCobro.cancha),
        costoPelotas: _monto(ConceptosCobro.pelotas),
        recinto: recinto.isEmpty ? null : recinto,
        notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
        comprobanteCancha: _monto(ConceptosCobro.cancha) > 0
            ? _comprobantesGasto[ConceptosCobro.cancha]
            : null,
        comprobantePelotas: _monto(ConceptosCobro.pelotas) > 0
            ? _comprobantesGasto[ConceptosCobro.pelotas]
            : null,
        createdAt: DateTime.now(),
      );

      if (recinto.isNotEmpty) {
        await _prefs.saveUltimoRecinto(recinto);
      }

      int partidoId;
      if (widget.isEditing) {
        await _partidoRepo.actualizarPartido(
          partidoId: widget.partidoId!,
          partido: partido,
          jugadoresAsistentes: _asistentes.toList(),
          montoPagadoPorJugador: _montoPagadoMap,
          costosVariables: _costosVariables(),
        );
        partidoId = widget.partidoId!;
      } else {
        partidoId = await _partidoRepo.guardarPartido(
          partido: partido,
          jugadoresAsistentes: _asistentes.toList(),
          montoPagadoPorJugador: _montoPagadoMap,
          costosVariables: _costosVariables(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing ? 'Partido actualizado' : 'Partido guardado',
            ),
          ),
        );
        if (mounted) {
          await EnviarInformesSheet.show(context, partidoId: partidoId);
        }
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      _showError('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Editar partido' : 'Nuevo partido'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
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
                          const SizedBox(height: 12),
                          _buildJugadoresPartido(),
                          const SizedBox(height: 12),
                          _buildItemsCobro(),
                          const SizedBox(height: 12),
                          _buildResumen(),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                    _buildSaveBar(),
                  ],
                ),
    );
  }

  Widget _buildSinJugadores() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Primero agrega jugadores habituales'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => Navigator.pushNamed(context, '/jugadores'),
            child: const Text('Ir a Jugadores'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoEdicion() {
    return Card(
      color: Colors.blue.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: const ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('Editando partido existente'),
        subtitle: Text('Los saldos se recalculan al guardar.'),
      ),
    );
  }

  Widget _buildDatosPartido() {
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
              paso: 1,
              titulo: 'Datos del partido',
              subtitulo: 'Cuándo y dónde jugaron',
              icono: Icons.event,
              color: Colors.green.shade700,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.calendar_today, color: Colors.green.shade700),
              title: const Text('Fecha y hora'),
              subtitle: Text(fechaStr),
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar),
                tooltip: 'Cambiar fecha',
                onPressed: _elegirFecha,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _recintoCtrl,
              decoration: const InputDecoration(
                labelText: 'Recinto / club',
                hintText: 'Ej: Padel UC, Club Manquehue...',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            if (_recintosSugeridos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Recientes:',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _recintosSugeridos.map((r) {
                  return ActionChip(
                    avatar: const Icon(Icons.history, size: 16),
                    label: Text(r, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      setState(() => _recintoCtrl.text = r);
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _notasCtrl,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                prefixIcon: Icon(Icons.notes),
                border: OutlineInputBorder(),
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
    final nAsistentes = _asistentes.length;
    final totalFijo = _monto(ConceptosCobro.cancha) + _monto(ConceptosCobro.pelotas);
    final totalVar = ConceptosCobro.variables
        .fold(0.0, (s, c) => s + _monto(c));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildEncabezadoSeccion(
          paso: 3,
          titulo: 'Gastos del partido',
          subtitulo: 'Cuánto costó y entre quién se reparte',
          icono: Icons.receipt_long,
          color: Colors.teal.shade700,
        ),
        const SizedBox(height: 10),
        if (_asistentes.isEmpty)
          _buildAvisoItems(
            icono: Icons.person_add_alt_1,
            color: Colors.amber.shade800,
            fondo: Colors.amber.shade50,
            borde: Colors.amber.shade200,
            titulo: 'Primero marca quién jugó',
            texto:
                'En la sección de arriba elige los asistentes. '
                'Así calculamos cuánto paga cada uno.',
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade50, Colors.green.shade50],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade100),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.teal.shade100,
                  child: Text(
                    '$nAsistentes',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    nAsistentes == 1
                        ? '1 jugador reparte los gastos del grupo'
                        : '$nAsistentes jugadores reparten los gastos del grupo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal.shade900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _buildGrupoCobro(
          titulo: 'Para todo el grupo',
          subtitulo: 'Todos los asistentes pagan lo mismo',
          icono: Icons.groups,
          color: const Color(0xFF2E7D32),
          hijos: ConceptosCobro.fijos.map(_buildTarjetaItemFijo).toList(),
        ),
        if (nAsistentes > 0 && totalFijo > 0) ...[
          const SizedBox(height: 8),
          _buildChipProrrateo(
            'Cancha ${formatMoney(_prorrateoCancha())} c/u · '
            'Pelotas ${formatMoney(_prorrateoPelotas())} c/u',
            color: Colors.green.shade700,
          ),
        ],
        const SizedBox(height: 16),
        _buildGrupoCobro(
          titulo: 'Solo quienes participaron',
          subtitulo: 'Asado, schop u otros — no todos se quedan',
          icono: Icons.restaurant,
          color: Colors.deepOrange.shade700,
          hijos: ConceptosCobro.variables.map(_buildTarjetaItemVariable).toList(),
        ),
        if (totalVar > 0 && _asistentes.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildAvisoItems(
              icono: Icons.touch_app,
              color: Colors.deepOrange.shade800,
              fondo: Colors.orange.shade50,
              borde: Colors.orange.shade200,
              titulo: 'Falta elegir participantes',
              texto: 'Marca asistentes arriba para repartir asado, schop u otros.',
            ),
          ),
        const SizedBox(height: 8),
        _buildTipCobrosExtra(),
      ],
    );
  }

  Widget _buildEncabezadoSeccion({
    required int paso,
    required String titulo,
    required String subtitulo,
    required IconData icono,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icono, color: color, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Paso $paso',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                titulo,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              Text(
                subtitulo,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
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

  Widget _buildAvisoItems({
    required IconData icono,
    required Color color,
    required Color fondo,
    required Color borde,
    required String titulo,
    required String texto,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borde),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    fontSize: 13,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  texto,
                  style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.9)),
                ),
              ],
            ),
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

  Widget _buildTipCobrosExtra() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '¿Un jugador pagó algo solo para él? Usa '
              '"Cobro extra" en su fila más abajo (raqueta, multa, etc.).',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  ({IconData icon, Color color}) _estiloConcepto(String concepto) {
    return switch (concepto) {
      ConceptosCobro.cancha => (
          icon: Icons.sports_tennis,
          color: const Color(0xFF2E7D32),
        ),
      ConceptosCobro.pelotas => (
          icon: Icons.sports_baseball,
          color: Colors.lightGreen.shade800,
        ),
      ConceptosCobro.asado => (
          icon: Icons.outdoor_grill,
          color: Colors.deepOrange.shade700,
        ),
      ConceptosCobro.barraSchop => (
          icon: Icons.local_bar,
          color: Colors.amber.shade800,
        ),
      ConceptosCobro.otros => (
          icon: Icons.more_horiz,
          color: Colors.blueGrey.shade700,
        ),
      _ => (icon: Icons.payments, color: Colors.grey.shade700),
    };
  }

  Widget _buildTarjetaItemFijo(String concepto) {
    final monto = _monto(concepto);
    final estilo = _estiloConcepto(concepto);
    final prorrateo = concepto == ConceptosCobro.cancha
        ? _prorrateoCancha()
        : _prorrateoPelotas();

    return _buildTarjetaItemBase(
      concepto: concepto,
      estilo: estilo,
      monto: monto,
      badge: monto > 0 && _asistentes.isNotEmpty
          ? '${formatMoney(prorrateo)} c/u · ${_asistentes.length} jugadores'
          : monto > 0
              ? 'Ingresa asistentes para calcular c/u'
              : null,
      badgeColor: estilo.color,
      extra: monto > 0
          ? ComprobantePagoTile(
              comprobantePath: _comprobantesGasto[concepto],
              onChanged: (path) => _setComprobanteGasto(concepto, path),
              compact: true,
            )
          : null,
      onMontoChanged: () => _onMontoGastoChanged(concepto),
    );
  }

  Widget _buildTarjetaItemVariable(String concepto) {
    final monto = _monto(concepto);
    final estilo = _estiloConcepto(concepto);
    final participantes = _participantesDe(concepto);
    final asistentesList =
        _habituales.where((j) => _asistentes.contains(j.id)).toList();
    final n = participantes.length;
    final prorrateo = _prorrateoVariable(concepto);

    return _buildTarjetaItemBase(
      concepto: concepto,
      estilo: estilo,
      monto: monto,
      badge: monto > 0 && n > 0
          ? '${formatMoney(prorrateo)} c/u · $n participan'
          : monto > 0 && _asistentes.isNotEmpty
              ? 'Marca quién participó'
              : null,
      badgeColor: Colors.deepOrange.shade700,
      onMontoChanged: () {
        _inicializarParticipantes(concepto);
        _onMontoGastoChanged(concepto);
      },
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (monto > 0) ...[
            const SizedBox(height: 8),
            ComprobantePagoTile(
              comprobantePath: _comprobantesGasto[concepto],
              onChanged: (path) => _setComprobanteGasto(concepto, path),
              compact: true,
            ),
          ],
          if (monto > 0 && _asistentes.isNotEmpty) ...[
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
                      Icon(Icons.people, size: 16, color: Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Text(
                        '¿Quién se quedó? ($n)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => _setParticipantesVariable(concepto, true),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Todos', style: TextStyle(fontSize: 11)),
                      ),
                      TextButton(
                        onPressed: () => _setParticipantesVariable(concepto, false),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Ninguno', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: asistentesList.map((j) {
                      final sel = participantes.contains(j.id);
                      return FilterChip(
                        avatar: sel
                            ? Icon(Icons.check, size: 14, color: Colors.orange.shade900)
                            : null,
                        label: Text(j.nombre, style: const TextStyle(fontSize: 12)),
                        selected: sel,
                        onSelected: (_) =>
                            _toggleParticipanteVariable(concepto, j.id!),
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
    );
  }

  Widget _buildTarjetaItemBase({
    required String concepto,
    required ({IconData icon, Color color}) estilo,
    required double monto,
    required VoidCallback onMontoChanged,
    String? badge,
    Color? badgeColor,
    Widget? extra,
  }) {
    final activo = monto > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: activo
              ? estilo.color.withValues(alpha: 0.45)
              : Colors.grey.shade200,
          width: activo ? 1.5 : 1,
        ),
        boxShadow: activo
            ? [
                BoxShadow(
                  color: estilo.color.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: estilo.color.withValues(alpha: activo ? 0.1 : 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: estilo.color.withValues(alpha: 0.15),
                  child: Icon(estilo.icon, color: estilo.color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        concepto,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: estilo.color,
                        ),
                      ),
                      Text(
                        ConceptosCobro.ayudaUi(concepto),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _montos[concepto],
                  decoration: InputDecoration(
                    labelText: 'Monto total',
                    hintText: '0',
                    prefixText: '\$ ',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: estilo.color, width: 2),
                    ),
                    isDense: true,
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => onMontoChanged(),
                ),
                if (badge != null) ...[
                  const SizedBox(height: 8),
                  _buildChipProrrateo(badge, color: badgeColor ?? estilo.color),
                ],
                if (extra != null) extra,
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildJugadoresPartido() {
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
              paso: 2,
              titulo: 'Jugadores y pagos',
              subtitulo: 'Marca quién jugó y cuánto pagó',
              icono: Icons.people,
              color: Colors.indigo.shade700,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '1) Marca asistentes · 2) Indica si pagaron total, parcial o nada · '
                '3) Define los gastos en el paso siguiente',
                style: TextStyle(fontSize: 12, color: Colors.indigo.shade900),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.group, size: 18),
                  label: const Text('Todos jugaron'),
                  onPressed: () => setState(() {
                    _asistentes.addAll(_habituales.map((x) => x.id!));
                    for (final c in ConceptosCobro.variables) {
                      if (_monto(c) > 0) {
                        _participantesVariable[c] = Set.from(_asistentes);
                      }
                    }
                  }),
                ),
                ActionChip(
                  avatar: const Icon(Icons.payments, size: 18),
                  label: const Text('Pago total todos'),
                  onPressed: _asistentes.isEmpty
                      ? null
                      : () => _marcarTodosPagados(true),
                ),
                ActionChip(
                  label: const Text('Sin pagos'),
                  onPressed: _asistentes.isEmpty
                      ? null
                      : () => _marcarTodosPagados(false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._habituales.map((j) => _buildFilaJugador(j)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilaJugador(Jugador j) {
    final asistio = _asistentes.contains(j.id);
    final saldoAnt = _saldoAnterior(j);
    final totalDeb = asistio ? _totalDebido(j) : saldoAnt;
    final pago = asistio ? _pagoDe(j.id!) : null;
    final restante = asistio ? _saldoRestante(j) : saldoAnt;
    final favorAplicado = asistio ? _saldoFavorAplicado(j) : 0.0;
    final aTransferir = asistio
        ? _totalATransferir(j)
        : (saldoAnt > 0 ? saldoAnt : 0.0);

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j.nombre,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (saldoAnt > 0)
                        Text(
                          'Deuda anterior: ${formatMoney(saldoAnt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.red.shade700,
                          ),
                        ),
                      if (saldoAnt < 0)
                        Text(
                          'Saldo a favor: ${formatMoney(-saldoAnt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                if (asistio)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'A transferir: ${formatMoney(aTransferir)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (favorAplicado > 0)
                        Text(
                          '−${formatMoney(favorAplicado)} saldo a favor',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (asistio && favorAplicado > 0) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Se aplicará ${formatMoney(favorAplicado)} de saldo a favor '
                        'al cobro de este partido.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (asistio && pago != null) ...[
              const SizedBox(height: 8),
              SegmentedButton<TipoPago>(
                segments: const [
                  ButtonSegment(
                    value: TipoPago.ninguno,
                    label: Text('Sin pago', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.close, size: 16),
                  ),
                  ButtonSegment(
                    value: TipoPago.total,
                    label: Text('Total', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.check_circle, size: 16),
                  ),
                  ButtonSegment(
                    value: TipoPago.parcial,
                    label: Text('Parcial', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.pie_chart, size: 16),
                  ),
                ],
                selected: {pago.tipo},
                onSelectionChanged: (s) => _setTipoPago(j.id!, s.first),
              ),
              if (pago.tipo == TipoPago.parcial) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: pago.montoParcial,
                  decoration: InputDecoration(
                    labelText: 'Monto que pagó ${j.nombre}',
                    hintText: '0',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixText: 'de ${formatMoney(totalDeb)}',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                _textoEstadoPago(pago, totalDeb, restante, j),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: restante <= 0
                      ? Colors.green.shade700
                      : pago.tipo == TipoPago.parcial
                          ? Colors.orange.shade800
                          : Colors.red.shade700,
                ),
              ),
              _buildCobrosIndividuales(j),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCobrosIndividuales(Jugador j) {
    final cobros = _cobrosIndividuales[j.id!] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.add_circle_outline, size: 16, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Text(
              'Cobros extra individuales',
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
          'Completa concepto y monto, luego pulsa Guardar cobro.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 6),
        ...cobros.map((c) => _buildFilaCobroIndividual(j.id!, c)),
        TextButton.icon(
          onPressed: () => _agregarCobroIndividual(j.id!),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Agregar cobro extra'),
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Widget _buildFilaCobroIndividual(int jugadorId, CobroIndividualEntry cobro) {
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
                      'Comprobante adjunto',
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
              tooltip: 'Editar cobro',
              onPressed: () => _editarCobroIndividual(cobro),
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade700, size: 20),
              tooltip: 'Quitar cobro',
              onPressed: () => _eliminarCobroIndividual(jugadorId, cobro),
            ),
          ],
        ),
      );
    }

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
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: cobro.conceptoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Concepto',
                    hintText: 'Ej: Raqueta',
                    border: OutlineInputBorder(),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: cobro.montoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Monto',
                    hintText: '0',
                    border: OutlineInputBorder(),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) {
                    if (cobro.monto <= 0 && cobro.comprobantePath != null) {
                      ComprobanteService.instance.delete(cobro.comprobantePath);
                      cobro.comprobantePath = null;
                    }
                    setState(() {});
                  },
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                tooltip: 'Quitar cobro',
                onPressed: () => _eliminarCobroIndividual(jugadorId, cobro),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: ConceptosCobro.sugerenciasIndividuales.map((s) {
              return ActionChip(
                label: Text(s, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  setState(() => cobro.conceptoCtrl.text = s);
                },
              );
            }).toList(),
          ),
          if (cobro.monto > 0) ...[
            const SizedBox(height: 6),
            ComprobantePagoTile(
              comprobantePath: cobro.comprobantePath,
              onChanged: (path) => setState(() => cobro.comprobantePath = path),
              compact: true,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _cancelarCobroIndividual(jugadorId, cobro),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Cancelar', style: TextStyle(fontSize: 12)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _guardarCobroIndividual(jugadorId, cobro),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Guardar cobro', style: TextStyle(fontSize: 12)),
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
    final favor = _saldoFavorAplicado(j);
    if (restante < 0) {
      return '✓ Cubierto · Saldo a favor: ${formatMoney(-restante)}';
    }
    if (totalDeb <= 0 && pago.tipo == TipoPago.total) {
      if (favor > 0) {
        return '✓ Cubierto con saldo a favor (${formatMoney(favor)})';
      }
      return '✓ Al día — sin transferencia';
    }
    switch (pago.tipo) {
      case TipoPago.total:
        return '✓ A transferir: ${formatMoney(totalDeb > 0 ? totalDeb : 0)}';
      case TipoPago.parcial:
        final m = pago.montoEfectivo(totalDeb);
        return 'Pagó ${formatMoney(m)} · Queda: ${formatMoney(restante > 0 ? restante : 0)}';
      case TipoPago.ninguno:
        return 'A transferir: ${formatMoney(restante > 0 ? restante : 0)}';
    }
  }

  Widget _buildResumen() {
    final asistentesList =
        _habituales.where((j) => _asistentes.contains(j.id)).toList();
    if (asistentesList.isEmpty) return const SizedBox.shrink();

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
              paso: 4,
              titulo: 'Resumen final',
              subtitulo: 'Revisa antes de guardar',
              icono: Icons.summarize,
              color: Colors.purple.shade700,
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...asistentesList.map((j) {
              final pago = _pagoDe(j.id!);
              final totalDeb = _totalDebido(j);
              final restante = _saldoRestante(j);
              final aTransferir = _totalATransferir(j);
              String estado;
              Color color;
              if (restante <= 0) {
                estado = restante < 0
                    ? 'SALDO A FAVOR ${formatMoney(-restante)}'
                    : 'AL DÍA';
                color = Colors.green.shade700;
              } else if (pago.tipo == TipoPago.total) {
                estado = 'TRANSFIERE ${formatMoney(aTransferir)}';
                color = Colors.green.shade700;
              } else if (pago.tipo == TipoPago.parcial) {
                estado =
                    'Parcial ${formatMoney(pago.montoEfectivo(totalDeb))} · Debe ${formatMoney(restante)}';
                color = Colors.orange.shade800;
              } else {
                estado = 'Debe ${formatMoney(restante)}';
                color = Colors.red.shade700;
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(j.nombre)),
                    Flexible(
                      child: Text(
                        estado,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveBar() {
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
          onPressed: _guardando ? null : _guardar,
          icon: _guardando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save),
          label: Text(_guardando ? 'Guardando...' : 'Guardar partido'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
