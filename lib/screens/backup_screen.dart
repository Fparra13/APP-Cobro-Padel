import 'package:flutter/material.dart';

import '../repositories/backup_repository.dart';
import '../repositories/partido_repository.dart';
import '../services/pdf_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _backupRepo = BackupRepository();
  final _pdfService = PdfService();
  final _partidoRepo = PartidoRepository();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Respaldo y reportes')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Exportar / Importar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sin nube: respalda manualmente antes de cambiar de celular. '
                  'Puedes enviar el archivo por WhatsApp, Gmail o subirlo a Google Drive.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                _ActionTile(
                  icon: Icons.storage,
                  title: 'Exportar base de datos (.db)',
                  subtitle: 'Copia exacta de SQLite',
                  onTap: () => _run(() async {
                    final path = await _backupRepo.exportDatabase();
                    await _backupRepo.shareFile(path);
                    _showOk('Exportado: $path');
                  }),
                ),
                _ActionTile(
                  icon: Icons.data_object,
                  title: 'Exportar JSON',
                  subtitle: 'Formato legible, multiplataforma',
                  onTap: () => _run(() async {
                    final path = await _backupRepo.exportJson();
                    await _backupRepo.shareFile(path);
                    _showOk('Exportado: $path');
                  }),
                ),
                _ActionTile(
                  icon: Icons.upload_file,
                  title: 'Importar .db',
                  subtitle: 'Reemplaza la base de datos actual',
                  onTap: () => _confirmAndRun(
                    '¿Importar base de datos? Se reemplazarán todos los datos actuales.',
                    () async {
                      final ok = await _backupRepo.importDatabase();
                      _showOk(ok ? 'Importación exitosa' : 'Cancelado');
                    },
                  ),
                ),
                _ActionTile(
                  icon: Icons.upload,
                  title: 'Importar JSON',
                  subtitle: 'Restaura desde respaldo JSON',
                  onTap: () => _confirmAndRun(
                    '¿Importar JSON? Se reemplazarán todos los datos actuales.',
                    () async {
                      final ok = await _backupRepo.importJson();
                      _showOk(ok ? 'Importación exitosa' : 'Cancelado');
                    },
                  ),
                ),
                const Divider(height: 32),
                const Text(
                  'Reportes PDF',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                _ActionTile(
                  icon: Icons.picture_as_pdf,
                  title: 'Reporte de saldos',
                  subtitle: 'Genera PDF y abre menú compartir',
                  onTap: () => _run(() async {
                    final resumenes = await _partidoRepo.getResumenJugadores();
                    await _pdfService.generarReporteSaldos(resumenes);
                  }),
                ),
              ],
            ),
    );
  }

  void _showOk(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _confirmAndRun(String msg, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirmar'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (ok == true) await _run(action);
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
