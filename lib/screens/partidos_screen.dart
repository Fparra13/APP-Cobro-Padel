import 'package:flutter/material.dart';

import '../l10n/matchpay_strings.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';

class PartidosScreen extends StatefulWidget {
  const PartidosScreen({super.key});

  @override
  State<PartidosScreen> createState() => _PartidosScreenState();
}

class _PartidosScreenState extends State<PartidosScreen> {
  final _repo = PartidoRepository();
  final _pdfService = PdfService();
  List<PartidoCompleto> _partidos = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.getAll();
    final completos = <PartidoCompleto>[];
    for (final p in list) {
      final c = await _repo.getCompleto(p.id!);
      if (c != null) completos.add(c);
    }
    if (mounted) {
      setState(() {
        _partidos = completos;
        _loading = false;
      });
    }
  }

  Future<void> _editar(PartidoCompleto pc) async {
    await Navigator.pushNamed(
      context,
      '/editar-partido',
      arguments: pc.partido.id,
    );
    _load();
  }

  Future<void> _eliminar(PartidoCompleto pc) async {
    final fecha = formatFecha(pc.partido.fecha);
    final ok = await confirmarEliminarPartido(
      context,
      titulo: context.tr('deleteMatchTitle'),
      mensaje: context.tr('deleteMatchMessage', params: {'date': fecha}),
    );

    if (ok) {
      await _repo.eliminarPartido(pc.partido.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('matchDeleted'))),
        );
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('matchesHistoryTitle')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _partidos.isEmpty
              ? Center(child: Text(context.tr('noMatchesRegistered')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _partidos.length,
                    itemBuilder: (_, i) {
                      final pc = _partidos[i];
                      final fecha =
                          formatFecha(pc.partido.fecha);
                      final asistentes =
                          pc.detalles.where((d) => d.asistio).length;
                      final total = pc.detalles
                          .where((d) => d.asistio)
                          .fold(0.0, (s, d) => s + d.total);
                      final pendientes = pc.contarAsistentesConDeudaNeta();
                      final unpaid = pendientes > 0
                          ? context.tr(
                              'matchUnpaidSuffix',
                              params: {'count': '$pendientes'},
                            )
                          : '';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          title: Text(fecha),
                          subtitle: Text(
                            context.tr(
                              'matchListSubtitle',
                              params: {
                                'players': '$asistentes',
                                'amount': formatMoney(total),
                                'unpaid': unpaid,
                              },
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              switch (action) {
                                case 'edit':
                                  _editar(pc);
                                case 'pdf':
                                  _pdfService.generarReportePartido(pc);
                                case 'delete':
                                  _eliminar(pc);
                              }
                            },
                            itemBuilder: (ctx) => [
                              PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: const Icon(Icons.edit),
                                  title: Text(ctx.tr('editTooltip')),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'pdf',
                                child: ListTile(
                                  leading: const Icon(Icons.picture_as_pdf),
                                  title: Text(ctx.tr('pdfLabel')),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: const Icon(Icons.delete, color: Colors.red),
                                  title: Text(
                                    ctx.tr('deleteTooltip'),
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _showDetalle(pc),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showDetalle(PartidoCompleto pc) {
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
                formatFecha(pc.partido.fecha),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Divider(),
              ...pc.detalles.where((d) => d.asistio).map(
                    (d) {
                      final snap = pc.snapshotSaldoCobro(d);
                      final cerrado = snap != null &&
                          d.partidoCerradoNeto(snapshotSaldoAnterior: snap);
                      final pendiente = snap != null
                          ? d
                              .estadoCobro(snapshotSaldoAnterior: snap)
                              .pendienteNeto
                          : d.total;
                      return ListTile(
                      dense: true,
                      title: Text(d.nombreJugador ?? ''),
                      trailing: Text(
                        cerrado ? ctx.tr('paidVerb') : formatMoney(pendiente),
                        style: TextStyle(
                          color: cerrado ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                    },
                  ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _editar(pc);
                      },
                      icon: const Icon(Icons.edit),
                      label: Text(ctx.tr('editTooltip')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _pdfService.generarReportePartido(pc);
                      },
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(ctx.tr('pdfLabel')),
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
}
