import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/deuda_partido_anterior.dart';
import '../models/jugador.dart';
import '../models/saldo_historico.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/partido_repository.dart';
import '../repositories/saldo_repository.dart';
import '../services/share_service.dart';
import '../utils/formatters.dart';

class HistorialScreen extends StatefulWidget {
  final int jugadorId;

  const HistorialScreen({super.key, required this.jugadorId});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final _saldoRepo = SaldoRepository();
  final _jugadorRepo = JugadorRepository();
  final _partidoRepo = PartidoRepository();
  final _shareService = ShareService();

  Jugador? _jugador;
  List<SaldoHistorico> _historial = [];
  List<DeudaPartidoAnterior> _pendientes = [];
  int _partidosJugados = 0;
  int _partidosPagados = 0;
  double _totalAbonos = 0;
  double _totalCargos = 0;
  _FiltroHistorial _filtro = _FiltroHistorial.todos;
  bool _loading = true;

  static const _avatarColors = [
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFEF6C00),
    Color(0xFFC62828),
    Color(0xFF4527A0),
    Color(0xFF558B2F),
  ];

  static const _meses = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final jugador = await _jugadorRepo.getById(widget.jugadorId);
    final historial = await _saldoRepo.getByJugador(widget.jugadorId);
    final pendientes =
        await _partidoRepo.getPartidosPendientesJugador(widget.jugadorId);
    final resumen =
        await _partidoRepo.getResumenPartidosJugador(widget.jugadorId);

    final totalAbonos =
        historial.fold(0.0, (s, h) => s + h.abono);
    final totalCargos =
        historial.fold(0.0, (s, h) => s + h.cargoPartido);

    if (mounted) {
      setState(() {
        _jugador = jugador;
        _historial = historial;
        _pendientes = pendientes;
        _partidosJugados = resumen.partidosJugados;
        _partidosPagados = resumen.partidosPagados;
        _totalAbonos = totalAbonos;
        _totalCargos = totalCargos;
        _loading = false;
      });
    }
  }

  List<SaldoHistorico> get _historialFiltrado {
    return _historial.where((h) {
      switch (_filtro) {
        case _FiltroHistorial.todos:
          return true;
        case _FiltroHistorial.cargos:
          return h.cargoPartido > 0;
        case _FiltroHistorial.abonos:
          return h.abono > 0;
      }
    }).toList();
  }

  Map<String, List<SaldoHistorico>> get _historialPorMes {
    final map = <String, List<SaldoHistorico>>{};
    for (final h in _historialFiltrado) {
      final key = '${h.fecha.year}-${h.fecha.month.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(h);
    }
    return map;
  }

  Color _colorDe(String nombre) =>
      _avatarColors[nombre.hashCode.abs() % _avatarColors.length];

  String _etiquetaMes(String key) {
    final parts = key.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    return '${_meses[month - 1]} $year';
  }

  _MovimientoTipo _tipoDe(SaldoHistorico h) {
    if (h.abono > 0 && h.cargoPartido == 0) return _MovimientoTipo.abono;
    if (h.cargoPartido > 0 && h.abono == 0) return _MovimientoTipo.cargo;
    if (h.abono > 0 && h.cargoPartido > 0) return _MovimientoTipo.mixto;
    return _MovimientoTipo.otro;
  }

  Future<void> _registrarPago() async {
    final jugador = _jugador;
    if (jugador == null || jugador.saldoAcumulado <= 0) return;

    final saldo = jugador.saldoAcumulado;
    final montoCtrl = TextEditingController();
    var pagoTotal = true;

    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Registrar pago',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  jugador.nombre,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          color: Colors.red.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Deuda actual: ${formatMoney(saldo)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Pago total')),
                    ButtonSegment(value: false, label: Text('Abono')),
                  ],
                  selected: {pagoTotal},
                  onSelectionChanged: (s) {
                    setModal(() {
                      pagoTotal = s.first;
                      if (pagoTotal) montoCtrl.clear();
                    });
                  },
                ),
                if (!pagoTotal) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: montoCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Monto del abono',
                      prefixIcon: const Icon(Icons.payments_outlined),
                      helperText:
                          'Puede ser mayor a la deuda para dejar saldo a favor',
                      suffixText: 'debe ${formatMoney(saldo)}',
                    ),
                    autofocus: true,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    pagoTotal
                        ? 'Confirmar ${formatMoney(saldo)}'
                        : 'Confirmar abono',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmado != true || !mounted) return;

    final monto = pagoTotal
        ? saldo
        : roundMoney(double.tryParse(montoCtrl.text) ?? 0).toDouble();

    if (monto <= 0) {
      _mostrarSnack('Ingresa un monto mayor a 0', esError: true);
      return;
    }

    final concepto = monto > saldo
        ? 'Abono con saldo a favor'
        : pagoTotal
            ? 'Abono total'
            : 'Abono parcial';

    await _partidoRepo.registrarAbono(
      jugadorId: jugador.id!,
      monto: monto,
      concepto: concepto,
    );

    if (mounted) {
      final excedente = monto > saldo ? monto - saldo : 0.0;
      final msg = excedente > 0
          ? 'Abono ${formatMoney(monto)} · Saldo a favor: ${formatMoney(excedente)}'
          : monto >= saldo
              ? 'Deuda saldada'
              : 'Abono ${formatMoney(monto)} · Queda ${formatMoney(saldo - monto)}';
      _mostrarSnack(msg);
      _load();
    }
  }

  Future<void> _enviarWhatsApp() async {
    final jugador = _jugador;
    if (jugador == null) return;

    final tel = jugador.telefono?.trim() ?? '';
    if (tel.isEmpty) {
      _mostrarSnack('Este jugador no tiene WhatsApp registrado', esError: true);
      return;
    }

    final buffer = StringBuffer()
      ..writeln('Hola ${jugador.nombre} 👋')
      ..writeln()
      ..writeln('Te escribo por el saldo del grupo de pádel.');

    if (jugador.saldoAcumulado > 0) {
      buffer
        ..writeln('Tu deuda actual es ${formatMoney(jugador.saldoAcumulado)}.')
        ..writeln();
      if (_pendientes.isNotEmpty) {
        buffer.writeln('Partidos pendientes:');
        for (final p in _pendientes) {
          final fecha = DateFormat('dd/MM/yyyy').format(p.fecha);
          final lugar = p.recinto?.trim().isNotEmpty == true
              ? ' · ${p.recinto}'
              : '';
          buffer.writeln('• $fecha$lugar: ${formatMoney(p.montoPendiente)}');
        }
        buffer.writeln();
      }
      buffer.writeln('¿Nos puedes transferir cuando puedas? ¡Gracias! 🎾');
    } else if (jugador.saldoAcumulado < 0) {
      buffer.writeln(
        'Tienes saldo a favor de ${formatMoney(-jugador.saldoAcumulado)}. '
        'Se descontará en tu próximo partido. 🎾',
      );
    } else {
      buffer.writeln('¡Estás al día con los pagos! 🎾');
    }

    try {
      await _shareService.compartirWhatsApp(
        mensaje: buffer.toString(),
        telefono: tel,
      );
    } catch (_) {
      if (mounted) {
        _mostrarSnack('No se pudo abrir WhatsApp', esError: true);
      }
    }
  }

  void _mostrarSnack(String msg, {bool esError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: esError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jugador = _jugador;
    final nombre = jugador?.nombre ?? '';
    final saldo = jugador?.saldoAcumulado ?? 0;
    final alDia = saldo <= 0;
    final conFavor = saldo < 0;
    final color = _colorDe(nombre);
    final inicial =
        nombre.trim().isNotEmpty ? nombre.trim()[0].toUpperCase() : '?';
    final mesesOrdenados = _historialPorMes.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha del jugador'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildFicha(jugador, color, inicial, alDia, conFavor, saldo)),
                  SliverToBoxAdapter(child: _buildEstadisticas(alDia, conFavor)),
                  if (_pendientes.isNotEmpty)
                    SliverToBoxAdapter(child: _buildPendientes()),
                  SliverToBoxAdapter(child: _buildAcciones(alDia, conFavor)),
                  SliverToBoxAdapter(child: _buildFiltros()),
                  if (_historialFiltrado.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyHistorial(),
                    )
                  else
                    ...mesesOrdenados.expand((mesKey) {
                      final items = _historialPorMes[mesKey]!;
                      return [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              _etiquetaMes(mesKey),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => _buildMovimientoCard(
                              items[i],
                              esUltimo: i == items.length - 1,
                            ),
                            childCount: items.length,
                          ),
                        ),
                      ];
                    }),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
    );
  }

  Widget _buildFicha(
    Jugador? jugador,
    Color color,
    String inicial,
    bool alDia,
    bool conFavor,
    double saldo,
  ) {
    final nombre = jugador?.nombre ?? '';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color, color.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      inicial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (jugador?.activo ?? false)
                            _ChipFicha(
                              icon: Icons.star_rounded,
                              label: 'Habitual',
                              color: Colors.amber.shade300,
                            ),
                          _ChipFicha(
                            icon: conFavor
                                ? Icons.savings_rounded
                                : alDia
                                    ? Icons.check_circle_rounded
                                    : Icons.warning_amber_rounded,
                            label: conFavor
                                ? 'Saldo a favor'
                                : alDia
                                    ? 'Al día'
                                    : 'Con deuda',
                            color: Colors.white,
                          ),
                          if (jugador?.telefono?.trim().isNotEmpty ?? false)
                            _ChipFicha(
                              icon: Icons.phone_android,
                              label: 'WhatsApp',
                              color: Colors.white,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  conFavor
                      ? 'Saldo a favor'
                      : alDia
                          ? 'Saldo actual'
                          : 'Deuda pendiente',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  conFavor ? formatMoney(-saldo) : formatMoney(saldo),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: colorSaldo(saldo),
                  ),
                ),
                if (!alDia && _pendientes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_pendientes.length} partido${_pendientes.length == 1 ? '' : 's'} sin pagar',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticas(bool alDia, bool conFavor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.sports_tennis_rounded,
              label: 'Partidos',
              value: '$_partidosJugados',
              subtitulo: '$_partidosPagados pagados',
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.arrow_upward_rounded,
              label: 'Cargos',
              value: formatMoney(_totalCargos),
              subtitulo: 'Total generado',
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatCard(
              icon: Icons.arrow_downward_rounded,
              label: 'Abonos',
              value: formatMoney(_totalAbonos),
              subtitulo: conFavor ? 'Crédito disponible' : alDia ? 'Al día' : 'Pagado',
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendientes() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        elevation: 0,
        color: Colors.orange.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.orange.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.pending_actions_rounded,
                      color: Colors.orange.shade800, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Partidos pendientes',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ..._pendientes.map((p) {
                final fecha = DateFormat('dd/MM/yyyy').format(p.fecha);
                final lugar = p.recinto?.trim().isNotEmpty == true
                    ? ' · ${p.recinto}'
                    : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 8, color: Colors.orange.shade600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$fecha$lugar',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                      Text(
                        formatMoney(p.montoPendiente),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcciones(bool alDia, bool conFavor) {
    final tieneWhatsApp = _jugador?.telefono?.trim().isNotEmpty ?? false;
    final puedePagar = !alDia && !conFavor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          if (puedePagar)
            Expanded(
              child: FilledButton.icon(
                onPressed: _registrarPago,
                icon: const Icon(Icons.payments_rounded),
                label: const Text('Registrar pago'),
              ),
            ),
          if (puedePagar && tieneWhatsApp) const SizedBox(width: 8),
          if (tieneWhatsApp)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enviarWhatsApp,
                icon: const Icon(Icons.chat_rounded, color: Colors.green),
                label: Text(puedePagar ? 'Recordar' : 'WhatsApp'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Historial de movimientos',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _FiltroHistorial.values.map((f) {
                final selected = _filtro == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(f.label),
                    selected: selected,
                    onSelected: (_) => setState(() => _filtro = f),
                    avatar: Icon(
                      f.icono,
                      size: 18,
                      color: selected ? Colors.white : Colors.grey.shade700,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistorial() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_rounded,
              size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            _filtro == _FiltroHistorial.todos
                ? 'Sin movimientos aún'
                : 'Sin movimientos de este tipo',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Los cargos de partidos y abonos\naparecerán aquí automáticamente.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMovimientoCard(SaldoHistorico h, {required bool esUltimo}) {
    final tipo = _tipoDe(h);
    final fecha = DateFormat('dd/MM · HH:mm').format(h.fecha);
    final delta = h.abono > 0 && h.cargoPartido == 0
        ? h.abono
        : h.cargoPartido > 0 && h.abono == 0
            ? h.cargoPartido
            : 0.0;
    final esIngreso = h.abono > 0 && h.cargoPartido == 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, esUltimo ? 4 : 0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: tipo.color,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: tipo.color.withValues(alpha: 0.4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  if (!esUltimo)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: Colors.grey.shade300,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: tipo.color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(tipo.icono, color: tipo.color, size: 22),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  h.concepto,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  fecha,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (delta != 0)
                            Text(
                              '${esIngreso ? '-' : '+'}${formatMoney(delta)}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: esIngreso
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                        ],
                      ),
                      if (h.cargoPartido > 0 && h.abono > 0) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            _MontoBadge(
                              icon: Icons.arrow_upward_rounded,
                              label: 'Cargo',
                              monto: h.cargoPartido,
                              color: Colors.red,
                            ),
                            _MontoBadge(
                              icon: Icons.arrow_downward_rounded,
                              label: 'Abono',
                              monto: h.abono,
                              color: Colors.green,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Saldo después',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              formatMoney(h.saldoNuevo),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorSaldo(h.saldoNuevo),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _FiltroHistorial {
  todos('Todos', Icons.list_alt_rounded),
  cargos('Partidos', Icons.sports_tennis_rounded),
  abonos('Abonos', Icons.savings_rounded);

  final String label;
  final IconData icono;

  const _FiltroHistorial(this.label, this.icono);
}

enum _MovimientoTipo {
  abono(Icons.savings_rounded, Color(0xFF2E7D32)),
  cargo(Icons.sports_tennis_rounded, Color(0xFFC62828)),
  mixto(Icons.swap_horiz_rounded, Color(0xFFEF6C00)),
  otro(Icons.receipt_rounded, Color(0xFF546E7A));

  final IconData icono;
  final Color color;

  const _MovimientoTipo(this.icono, this.color);
}

class _ChipFicha extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _ChipFicha({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitulo;
  final MaterialColor color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitulo,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color.shade700),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.shade800),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color.shade900,
            ),
          ),
          Text(
            subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: color.shade700),
          ),
        ],
      ),
    );
  }
}

class _MontoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final double monto;
  final MaterialColor color;

  const _MontoBadge({
    required this.icon,
    required this.label,
    required this.monto,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            '$label: ${formatMoney(monto)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
