import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/estado_pago_jugador.dart';
import '../models/jugador.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/deuda_chart_widget.dart';
import '../widgets/quick_actions_panel.dart';

class HomeScreen extends StatefulWidget {
  final void Function(int tabIndex)? onNavigateTab;

  const HomeScreen({super.key, this.onNavigateTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _partidoRepo = PartidoRepository();
  final _jugadorRepo = JugadorRepository();
  final _pdfService = PdfService();

  List<ResumenJugador> _resumenes = [];
  List<Jugador> _jugadoresActivos = [];
  bool _loading = true;
  final Set<int> _planillaSeleccionados = {};
  TipoPago _tipoPagoPlanilla = TipoPago.total;
  final _montoParcialController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _montoParcialController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final resumenes = await _partidoRepo.getResumenJugadores();
    final activos = await _jugadorRepo.getAll(soloActivos: true);
    if (mounted) {
      setState(() {
        _resumenes = resumenes;
        _jugadoresActivos = activos;
        _loading = false;
      });
    }
  }

  double get _totalSaldos =>
      _resumenes.fold(0.0, (sum, r) => sum + (r.saldoActual > 0 ? r.saldoActual : 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        title: const Text('🎾 Pádel Cobro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 12),
                  const AyudaTip(
                    texto:
                        'Flujo rápido: agrega jugadores → Nuevo partido → '
                        'marca asistentes y pagos → envía informes. '
                        'En la planilla registras abonos posteriores.',
                  ),
                  const SizedBox(height: 12),
                  QuickActionsPanel(
                    partidoRepo: _partidoRepo,
                    pdfService: _pdfService,
                    resumenes: _resumenes,
                    onRefresh: _load,
                    onNavigateTab: widget.onNavigateTab,
                  ),
                  const SizedBox(height: 12),
                  _buildQuickStats(),
                  const SizedBox(height: 12),
                  DeudaChartWidget(resumenes: _resumenes),
                  const SizedBox(height: 12),
                  _buildPlanilla(),
                  const SizedBox(height: 12),
                  _buildHabituales(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.pushNamed(context, '/nuevo-partido');
          _load();
        },
        icon: const Icon(Icons.sports_tennis),
        label: const Text('Nuevo partido'),
      ),
    );
  }

  Widget _buildHeader() {
    final conDeuda = _resumenes.where((r) => r.saldoActual > 0).length;
    final conFavor = _resumenes.where((r) => r.saldoActual < 0).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2E7D32),
            const Color(0xFF43A047),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade900.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '🎾 Pádel Cobro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            conDeuda > 0
                ? '💰 $conDeuda jugador${conDeuda == 1 ? '' : 'es'} con deuda · Total ${formatMoney(_totalSaldos)}'
                : conFavor > 0
                    ? '💙 $conFavor con saldo a favor · Resto al día'
                    : '✅ ¡Todos al día! Sin deudas pendientes',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _StatChip(
              label: 'Jugadores',
              value: '${_jugadoresActivos.length}',
              icon: Icons.people,
            ),
            _StatChip(
              label: 'Total por cobrar',
              value: formatMoney(_totalSaldos),
              icon: Icons.payments,
              highlight: _totalSaldos > 0,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanilla() {
    if (_resumenes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.table_chart, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Sin datos aún.\nAgrega jugadores y registra tu primer partido.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Planilla de saldos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                const AyudaTip(
                  texto:
                      'Marca jugadores con deuda para registrar pagos. '
                      'Varios seleccionados = pago total de cada uno. '
                      'Un solo jugador: pago total o abono (puede ser mayor a la deuda).',
                ),
              ],
            ),
          ),
          ..._resumenes.map((r) => _buildPlanillaFila(r)),
          if (_planillaSeleccionados.isNotEmpty) _buildPlanillaAcciones(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextButton.icon(
              onPressed: () => _mostrarHistorialJugador(),
              icon: const Icon(Icons.history, size: 18),
              label: const Text('Ver historial de un jugador'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanillaFila(ResumenJugador r) {
    final saldo = r.saldoActual;
    final deuda = tieneDeuda(saldo);
    final conFavor = tieneSaldoAFavor(saldo);
    final id = r.jugador.id!;
    final seleccionado = _planillaSeleccionados.contains(id);

    return Material(
      color: seleccionado
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25)
          : null,
      child: InkWell(
        onTap: deuda
            ? () => _togglePlanillaSeleccion(id)
            : () => _mostrarHistorialJugador(jugadorId: id),
        onLongPress: () => _mostrarHistorialJugador(jugadorId: id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Checkbox(
                value: seleccionado,
                onChanged: deuda
                    ? (_) => _togglePlanillaSeleccion(id)
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.jugador.nombre,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${r.partidosJugados} partidos',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    conFavor
                        ? 'A favor: ${formatMoney(-saldo)}'
                        : formatMoney(saldo),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorSaldo(saldo),
                    ),
                  ),
                  Chip(
                    label: Text(
                      conFavor
                          ? 'Saldo a favor'
                          : deuda
                              ? 'Debe'
                              : 'Al día',
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: conFavor
                        ? Colors.blue.shade50
                        : deuda
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanillaAcciones() {
    final seleccionados = _resumenes
        .where((r) => _planillaSeleccionados.contains(r.jugador.id))
        .toList();
    final conDeuda =
        seleccionados.where((r) => r.saldoActual > 0).toList();
    final uno = conDeuda.length == 1 ? conDeuda.first : null;
    final totalAbono =
        conDeuda.fold(0.0, (s, r) => s + r.saldoActual);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${conDeuda.length} jugador${conDeuda.length == 1 ? '' : 'es'} seleccionado${conDeuda.length == 1 ? '' : 's'}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (conDeuda.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Los seleccionados ya están al día.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            )
          else if (uno != null) ...[
            const SizedBox(height: 10),
            Text(
              '${uno.jugador.nombre} · Saldo ${formatMoney(uno.saldoActual)}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 10),
            SegmentedButton<TipoPago>(
              segments: const [
                ButtonSegment(
                  value: TipoPago.total,
                  label: Text('Pago total', style: TextStyle(fontSize: 12)),
                  icon: Icon(Icons.check_circle, size: 16),
                ),
                ButtonSegment(
                  value: TipoPago.parcial,
                  label: Text('Abono', style: TextStyle(fontSize: 12)),
                  icon: Icon(Icons.savings_outlined, size: 16),
                ),
              ],
              selected: {_tipoPagoPlanilla},
              onSelectionChanged: (s) {
                setState(() {
                  _tipoPagoPlanilla = s.first;
                  if (s.first == TipoPago.parcial) {
                    _montoParcialController.clear();
                  }
                });
              },
            ),
            if (_tipoPagoPlanilla == TipoPago.parcial) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _montoParcialController,
                decoration: InputDecoration(
                  labelText: 'Monto del abono',
                  hintText: '0',
                  helperText:
                      'Puede ser mayor a la deuda para dejar saldo a favor',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  suffixText: 'debe ${formatMoney(uno.saldoActual)}',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _registrarPagoUnJugador(uno),
              icon: const Icon(Icons.payments),
              label: Text(
                _tipoPagoPlanilla == TipoPago.total
                    ? 'Registrar pago total'
                    : 'Registrar abono',
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Se registrará el pago total de cada jugador '
              '(${formatMoney(totalAbono)} en total).',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _registrarPagoMultiple(conDeuda),
              icon: const Icon(Icons.done_all),
              label: Text('Registrar pago total (${conDeuda.length})'),
            ),
          ],
          TextButton(
            onPressed: () {
              setState(() {
                _planillaSeleccionados.clear();
                _tipoPagoPlanilla = TipoPago.total;
                _montoParcialController.clear();
              });
            },
            child: const Text('Cancelar selección'),
          ),
        ],
      ),
    );
  }

  void _togglePlanillaSeleccion(int jugadorId) {
    setState(() {
      if (_planillaSeleccionados.contains(jugadorId)) {
        _planillaSeleccionados.remove(jugadorId);
      } else {
        _planillaSeleccionados.add(jugadorId);
      }
      _tipoPagoPlanilla = TipoPago.total;
      _montoParcialController.clear();
    });
  }

  Future<void> _registrarPagoUnJugador(ResumenJugador resumen) async {
    final saldo = resumen.saldoActual;
    final monto = _tipoPagoPlanilla == TipoPago.total
        ? saldo
        : roundMoney(double.tryParse(_montoParcialController.text) ?? 0)
            .toDouble();

    if (monto <= 0) {
      _mostrarError('Ingresa un monto mayor a 0');
      return;
    }

    final concepto = monto > saldo
        ? 'Abono con saldo a favor'
        : monto == saldo
            ? 'Abono total'
            : 'Abono parcial';

    await _partidoRepo.registrarAbono(
      jugadorId: resumen.jugador.id!,
      monto: monto,
      concepto: concepto,
    );

    if (mounted) {
      setState(() {
        _planillaSeleccionados.clear();
        _tipoPagoPlanilla = TipoPago.total;
        _montoParcialController.clear();
      });
      final excedente = monto > saldo ? monto - saldo : 0.0;
      final msg = excedente > 0
          ? 'Abono ${formatMoney(monto)} · Saldo a favor: ${formatMoney(excedente)} · ${resumen.jugador.nombre}'
          : monto >= saldo
              ? 'Deuda saldada · ${resumen.jugador.nombre}'
              : 'Abono ${formatMoney(monto)} · Queda ${formatMoney(saldo - monto)} · ${resumen.jugador.nombre}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
      _load();
    }
  }

  Future<void> _registrarPagoMultiple(List<ResumenJugador> jugadores) async {
    for (final r in jugadores) {
      await _partidoRepo.registrarAbono(
        jugadorId: r.jugador.id!,
        monto: r.saldoActual,
        concepto: 'Abono total',
      );
    }

    if (mounted) {
      setState(() => _planillaSeleccionados.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Pago total registrado para ${jugadores.length} jugadores',
          ),
        ),
      );
      _load();
    }
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  void _mostrarHistorialJugador({int? jugadorId}) {
    if (jugadorId != null) {
      Navigator.pushNamed(context, '/historial', arguments: jugadorId);
      return;
    }

    final conDeuda = _resumenes.where((r) => r.saldoActual >= 0).toList();
    if (conDeuda.isEmpty) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Historial de jugador',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ...conDeuda.map(
              (r) => ListTile(
                title: Text(r.jugador.nombre),
                subtitle: Text('Saldo: ${formatMoney(r.saldoActual)}'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushNamed(
                    context,
                    '/historial',
                    arguments: r.jugador.id,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabituales() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Jugadores habituales (${_jugadoresActivos.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _jugadoresActivos
                  .map((j) => Chip(
                        label: Text(j.nombre),
                        avatar: j.saldoAcumulado > 0
                            ? CircleAvatar(
                                backgroundColor: Colors.red.shade100,
                                child: Text(
                                  '!',
                                  style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            : null,
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: highlight ? Colors.red.shade700 : null),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: highlight ? Colors.red.shade700 : null,
              ),
        ),
      ],
    );
  }
}
