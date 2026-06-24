import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';
import '../utils/formatters.dart';

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
    final fecha = DateFormat('dd/MM/yyyy').format(pc.partido.fecha);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar partido'),
        content: Text(
          '¿Eliminar el partido del $fecha?\n'
          'Los saldos se recalcularán automáticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _repo.eliminarPartido(pc.partido.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Partido eliminado')),
        );
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de partidos'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _partidos.isEmpty
              ? const Center(child: Text('Sin partidos registrados'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _partidos.length,
                    itemBuilder: (_, i) {
                      final pc = _partidos[i];
                      final fecha =
                          DateFormat('dd/MM/yyyy').format(pc.partido.fecha);
                      final asistentes =
                          pc.detalles.where((d) => d.asistio).length;
                      final total = pc.detalles
                          .where((d) => d.asistio)
                          .fold(0.0, (s, d) => s + d.total);
                      final pendientes = pc.detalles
                          .where((d) => d.asistio && !d.pagado)
                          .length;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          title: Text(fecha),
                          subtitle: Text(
                            '$asistentes jugadores · ${formatMoney(total)}'
                            '${pendientes > 0 ? ' · $pendientes sin pagar' : ''}',
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
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: ListTile(
                                  leading: Icon(Icons.edit),
                                  title: Text('Editar'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'pdf',
                                child: ListTile(
                                  leading: Icon(Icons.picture_as_pdf),
                                  title: Text('PDF'),
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: ListTile(
                                  leading: Icon(Icons.delete, color: Colors.red),
                                  title: Text('Eliminar',
                                      style: TextStyle(color: Colors.red)),
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
                DateFormat('dd/MM/yyyy').format(pc.partido.fecha),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const Divider(),
              ...pc.detalles.where((d) => d.asistio).map(
                    (d) => ListTile(
                      dense: true,
                      title: Text(d.nombreJugador ?? ''),
                      trailing: Text(
                        d.pagado ? 'Pagó' : formatMoney(d.total),
                        style: TextStyle(
                          color: d.pagado ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
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
                        _editar(pc);
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
                        _pdfService.generarReportePartido(pc);
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
}
