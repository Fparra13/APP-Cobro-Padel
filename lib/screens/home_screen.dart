import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/convocatoria_jugador.dart';
import '../utils/formatters.dart';
import '../models/estado_pago_jugador.dart';
import '../models/jugador.dart';
import '../repositories/convocatoria_repository.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/app_navigation.dart';
import '../widgets/jugador_avatar.dart';
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
  final _convocatoriaRepo = ConvocatoriaRepository();
  final _pdfService = PdfService();

  List<ResumenJugador> _resumenes = [];
  List<Jugador> _jugadoresActivos = [];
  List<ConvocatoriaCompleta> _convocatorias = [];
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
    final convocatorias = await _convocatoriaRepo.getActivas();
    if (mounted) {
      setState(() {
        _resumenes = resumenes;
        _jugadoresActivos = activos;
        _convocatorias = convocatorias;
        _loading = false;
      });
    }
  }

  double get _totalSaldos =>
      _resumenes.fold(0.0, (sum, r) => sum + (r.saldoActual > 0 ? r.saldoActual : 0));

  int get _conDeuda => _resumenes.where((r) => r.saldoActual > 0).length;

  int get _alDia => _resumenes.where((r) => r.saldoActual <= 0).length;

  List<ResumenJugador> get _deudoresOrdenados {
    return _resumenes.where((r) => r.saldoActual > 0).toList()
      ..sort((a, b) => b.saldoActual.compareTo(a.saldoActual));
  }

  List<ResumenJugador> get _todosOrdenados {
    final copy = List<ResumenJugador>.from(_resumenes);
    copy.sort((a, b) =>
        a.jugador.nombre.toLowerCase().compareTo(b.jugador.nombre.toLowerCase()));
    return copy;
  }

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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 16),
                  QuickActionsPanel(
                    partidoRepo: _partidoRepo,
                    pdfService: _pdfService,
                    resumenes: _resumenes,
                    onRefresh: _load,
                    onNavigateTab: widget.onNavigateTab,
                  ),
                  if (_convocatorias.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildConvocatoriasActivas(),
                  ],
                  const SizedBox(height: 16),
                  _buildPlanilla(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _mostrarMenuPartido,
        elevation: 4,
        icon: const Icon(Icons.sports_tennis_rounded),
        label: const Text('Partido'),
      ),
    );
  }

  Future<void> _mostrarMenuPartido() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '¿Qué quieres hacer?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  child: Icon(Icons.campaign, color: Colors.blue.shade800),
                ),
                title: const Text('Organizar convocatoria'),
                subtitle: const Text(
                  'Confirmar jugadores antes del partido (sin cobros)',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await abrirOrganizarPartido(context);
                  _load();
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Icon(Icons.payments, color: Colors.green.shade800),
                ),
                title: const Text('Registrar partido jugado'),
                subtitle: const Text('Cobros, asistentes y pagos'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.pushNamed(context, '/nuevo-partido');
                  _load();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConvocatoriasActivas() {
    final enEspera =
        _convocatorias.where((c) => c.partido.esOrganizando).toList();
    final confirmadas =
        _convocatorias.where((c) => c.partido.esConfirmado).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_rounded, color: Colors.blue.shade800),
              const SizedBox(width: 8),
              Text(
                'Convocatorias activas',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (enEspera.isNotEmpty) ...[
            _ConvocatoriaGrupo(
              titulo: 'En espera',
              icono: Icons.hourglass_top_rounded,
              color: Colors.blue,
              cantidad: enEspera.length,
            ),
            ...enEspera.map((c) => _ConvocatoriaTile(
                  convocatoria: c,
                  onTap: () async {
                    await abrirOrganizarPartido(
                      context,
                      partidoId: c.partido.id,
                    );
                    _load();
                  },
                )),
          ],
          if (confirmadas.isNotEmpty) ...[
            if (enEspera.isNotEmpty) const SizedBox(height: 10),
            _ConvocatoriaGrupo(
              titulo: 'Confirmados',
              icono: Icons.check_circle_rounded,
              color: Colors.green,
              cantidad: confirmadas.length,
            ),
            ...confirmadas.map((c) => _ConvocatoriaTile(
                  convocatoria: c,
                  confirmado: true,
                  onTap: () async {
                    await abrirOrganizarPartido(
                      context,
                      partidoId: c.partido.id,
                    );
                    _load();
                  },
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final todosAlDia = _conDeuda == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF388E3C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.green.shade900.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todosAlDia ? '¡Grupo al día!' : 'Resumen del grupo',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      todosAlDia
                          ? 'No hay deudas pendientes'
                          : '${formatMoney(_totalSaldos)} por cobrar',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                todosAlDia
                    ? Icons.celebration_rounded
                    : Icons.account_balance_wallet_rounded,
                color: Colors.white.withValues(alpha: 0.9),
                size: 32,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _HeaderStat(
                label: 'Jugadores',
                value: '${_jugadoresActivos.length}',
                icon: Icons.people_rounded,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeaderStat(
                label: 'Con deuda',
                value: '$_conDeuda',
                icon: Icons.warning_amber_rounded,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HeaderStat(
                label: 'Al día',
                value: '$_alDia',
                icon: Icons.check_circle_rounded,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlanilla() {
    if (_resumenes.isEmpty) {
      return _HomeSeccion(
        titulo: 'Registrar pagos',
        icono: Icons.payments_rounded,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            children: [
              Icon(Icons.sports_tennis_rounded,
                  size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                'Sin datos aún',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Toca el botón Partido abajo para empezar',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    final deudores = _deudoresOrdenados;

    if (deudores.isEmpty) {
      return _HomeSeccion(
        titulo: 'Registrar pagos',
        icono: Icons.payments_rounded,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: Colors.green.shade700, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nadie debe. Todos al día.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _buildVerFichaButton(),
          ],
        ),
      );
    }

    return _HomeSeccion(
      titulo: 'Registrar pagos',
      icono: Icons.payments_rounded,
      accion: IconButton(
        icon: Icon(Icons.help_outline_rounded, color: Colors.grey.shade600),
        tooltip: 'Ayuda',
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Registrar pagos'),
              content: const Text(
                'Marca uno o más jugadores con deuda.\n\n'
                '• Varios seleccionados → pago total de cada uno\n'
                '• Un solo jugador → pago total o abono parcial',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        },
      ),
      child: Column(
        children: [
          Text(
            '${deudores.length} jugador${deudores.length == 1 ? '' : 'es'} · '
            'Total ${formatMoney(_totalSaldos)}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.red.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          ...deudores.map(_buildPlanillaFila),
          if (_planillaSeleccionados.isNotEmpty) _buildPlanillaAcciones(),
          _buildVerFichaButton(),
        ],
      ),
    );
  }

  Widget _buildVerFichaButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutlinedButton.icon(
        onPressed: _mostrarSelectorFicha,
        icon: const Icon(Icons.person_search_rounded, size: 18),
        label: const Text('Ver ficha de un jugador'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
        ),
      ),
    );
  }

  Widget _buildPlanillaFila(ResumenJugador r) {
    final saldo = r.saldoActual;
    final id = r.jugador.id!;
    final seleccionado = _planillaSeleccionados.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: seleccionado
            ? Colors.red.shade50
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _togglePlanillaSeleccion(id),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Checkbox(
                  value: seleccionado,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (_) => _togglePlanillaSeleccion(id),
                ),
                JugadorAvatar(
                  nombre: r.jugador.nombre,
                  fotoPath: r.jugador.fotoPath,
                  size: 40,
                  borderRadius: 12,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.jugador.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '${r.partidosJugados} partidos',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    formatMoney(saldo),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.red.shade800,
                    ),
                  ),
                ),
              ],
            ),
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
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
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
                inputFormatters: moneyInputFormatters,
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
        : roundMoney(parseMoney(_montoParcialController.text))
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

  void _mostrarSelectorFicha() {
    final todos = _todosOrdenados;
    if (todos.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ficha del jugador',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toca un jugador para ver su historial y saldo',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: todos.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final r = todos[i];
                  return _FichaSelectorTile(
                    resumen: r,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.pushNamed(
                        context,
                        '/historial',
                        arguments: r.jugador.id,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

}

class _HomeSeccion extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final Widget child;
  final Widget? accion;

  const _HomeSeccion({
    required this.titulo,
    required this.icono,
    required this.child,
    this.accion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icono, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (accion != null) accion!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ConvocatoriaGrupo extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final MaterialColor color;
  final int cantidad;

  const _ConvocatoriaGrupo({
    required this.titulo,
    required this.icono,
    required this.color,
    required this.cantidad,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icono, size: 16, color: color.shade700),
          const SizedBox(width: 6),
          Text(
            '$titulo ($cantidad)',
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

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final MaterialColor color;

  const _HeaderStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.shade200),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color.shade700, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color.shade900,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color.shade700,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FichaSelectorTile extends StatelessWidget {
  final ResumenJugador resumen;
  final VoidCallback onTap;

  const _FichaSelectorTile({
    required this.resumen,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final saldo = resumen.saldoActual;
    final deuda = saldo > 0;
    final conFavor = saldo < 0;

    final (estado, estadoColor, monto) = switch ((deuda, conFavor)) {
      (true, _) => ('Debe', Colors.red, formatMoney(saldo)),
      (_, true) => ('A favor', Colors.blue, formatMoney(-saldo)),
      _ => ('Al día', Colors.green, '—'),
    };

    return Material(
      color: Colors.grey.shade50,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              JugadorAvatar(
                nombre: resumen.jugador.nombre,
                fotoPath: resumen.jugador.fotoPath,
                size: 44,
                borderRadius: 12,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resumen.jugador.nombre,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${resumen.partidosJugados} partidos · Toca para abrir ficha',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: estadoColor.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: estadoColor.shade200),
                    ),
                    child: Text(
                      estado,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: estadoColor.shade800,
                      ),
                    ),
                  ),
                  if (deuda || conFavor) ...[
                    const SizedBox(height: 4),
                    Text(
                      monto,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: estadoColor.shade800,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConvocatoriaTile extends StatelessWidget {
  final ConvocatoriaCompleta convocatoria;
  final bool confirmado;
  final VoidCallback onTap;

  const _ConvocatoriaTile({
    required this.convocatoria,
    required this.onTap,
    this.confirmado = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = convocatoria;
    final fecha = formatDiaCorto(c.partido.fecha);
    final pendientes = c.invitados - c.confirmados - c.rechazados;

    return Material(
      color: confirmado ? Colors.green.shade50 : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: confirmado
                      ? Colors.green.shade100
                      : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  confirmado ? Icons.check_circle_rounded : Icons.campaign_rounded,
                  color: confirmado
                      ? Colors.green.shade800
                      : Colors.blue.shade800,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fecha,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${c.partido.recinto ?? 'Sin recinto'} · '
                      '${c.confirmados}/${c.partido.cuposMax} confirmados'
                      '${!confirmado && pendientes > 0 ? ' · $pendientes pend.' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
