import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import 'recordatorio_deudores_sheet.dart';

class QuickActionsPanel extends StatelessWidget {
  final PartidoRepository partidoRepo;
  final PdfService pdfService;
  final List<ResumenJugador> resumenes;
  final VoidCallback onRefresh;
  final void Function(int tabIndex)? onNavigateTab;

  const QuickActionsPanel({
    super.key,
    required this.partidoRepo,
    required this.pdfService,
    required this.resumenes,
    required this.onRefresh,
    this.onNavigateTab,
  });

  int get _conDeuda => resumenes.where((r) => r.saldoActual > 0).length;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Acceso rápido',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuickActionChip(
                  icon: Icons.sports_tennis,
                  label: 'Nuevo partido',
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () async {
                    await Navigator.pushNamed(context, '/nuevo-partido');
                    onRefresh();
                  },
                ),
                _QuickActionChip(
                  icon: Icons.picture_as_pdf,
                  label: 'PDF saldos',
                  color: Colors.deepOrange,
                  onTap: () async {
                    await pdfService.generarReporteSaldos(resumenes);
                  },
                ),
                _QuickActionChip(
                  icon: Icons.history,
                  label: 'Último partido',
                  color: Colors.blue,
                  onTap: () => _abrirUltimoPartido(context),
                ),
                if (_conDeuda > 0) ...[
                  _QuickActionChip(
                    icon: Icons.message,
                    label: 'Recordar deudores',
                    color: Colors.green.shade700,
                    onTap: () => RecordatorioDeudoresSheet.show(
                      context,
                      resumenes: resumenes,
                    ),
                  ),
                  _QuickActionChip(
                    icon: Icons.warning_amber,
                    label: 'Ver deudores ($_conDeuda)',
                    color: Colors.red.shade700,
                    onTap: () => _mostrarDeudores(context),
                  ),
                ],
                _QuickActionChip(
                  icon: Icons.person_add,
                  label: 'Jugadores',
                  color: Colors.teal,
                  onTap: () {
                    onNavigateTab?.call(1);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirUltimoPartido(BuildContext context) async {
    final ultimo = await partidoRepo.getUltimoPartido();
    if (!context.mounted) return;

    if (ultimo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aún no hay partidos registrados')),
      );
      return;
    }

    final fecha = DateFormat('dd/MM/yyyy').format(ultimo.partido.fecha);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Último partido — $fecha',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const Divider(),
              ...ultimo.detalles.where((d) => d.asistio).map(
                    (d) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.nombreJugador ?? ''),
                      trailing: Text(
                        d.pagado ? 'Pagó ✓' : formatMoney(d.total),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: d.pagado ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(
                          context,
                          '/editar-partido',
                          arguments: ultimo.partido.id,
                        ).then((_) => onRefresh());
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        pdfService.generarReportePartido(ultimo);
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostrarDeudores(BuildContext context) {
    final deudores = resumenes.where((r) => r.saldoActual > 0).toList();
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Jugadores con deuda',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
            ...deudores.map(
              (r) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red.shade100,
                  child: Text(
                    r.jugador.nombre[0].toUpperCase(),
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
                title: Text(r.jugador.nombre),
                subtitle: r.jugador.telefono?.trim().isNotEmpty ?? false
                    ? Text('WhatsApp: ${r.jugador.telefono}')
                    : const Text(
                        'Sin WhatsApp',
                        style: TextStyle(color: Colors.orange),
                      ),
                trailing: Text(
                  formatMoney(r.saldoActual),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  RecordatorioDeudoresSheet.show(
                    context,
                    resumenes: resumenes,
                  );
                },
                icon: const Icon(Icons.message),
                label: const Text('Enviar recordatorio WhatsApp'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}
