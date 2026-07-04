import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/nav_shell_layout.dart';
import '../services/pdf_service.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final _pdfService = PdfService();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.tr('backupError', params: {'error': '$e'}),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cloud = context.repos.isCloud;
    return ShellTabScaffold(
      appBar: AppBar(
        title: Text(
          cloud ? l10n.tr('backupCloudTitle') : l10n.tr('backupLocalTitle'),
        ),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: NavShellScope.listPadding(context),
              children: [
                if (cloud)
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.cloud_done,
                                  color: Colors.blue.shade800),
                              const SizedBox(width: 8),
                              Text(
                                l10n.tr('backupSupabaseTitle'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.tr('backupSupabaseBody'),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Text(
                    l10n.tr('backupExportImportTitle'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.tr('backupOfflineHint'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  _ActionTile(
                    icon: Icons.storage,
                    title: l10n.tr('backupExportDbTitle'),
                    subtitle: l10n.tr('backupExportDbSubtitle'),
                    onTap: () => _run(() async {
                      final backup = context.repos.backup;
                      final path = await backup.exportDatabase();
                      await backup.shareFile(path);
                      _showOk(
                        l10n.tr('backupExported', params: {'path': path}),
                      );
                    }),
                  ),
                ],
                if (!cloud) ...[
                  _ActionTile(
                    icon: Icons.data_object,
                    title: l10n.tr('backupExportJsonTitle'),
                    subtitle: l10n.tr('backupExportJsonSubtitle'),
                    onTap: () => _run(() async {
                      final backup = context.repos.backup;
                      final path = await backup.exportJson();
                      await backup.shareFile(path);
                      _showOk(
                        l10n.tr('backupExported', params: {'path': path}),
                      );
                    }),
                  ),
                  _ActionTile(
                    icon: Icons.upload_file,
                    title: l10n.tr('backupImportDbTitle'),
                    subtitle: l10n.tr('backupImportDbSubtitle'),
                    onTap: () => _confirmAndRun(
                      l10n.tr('backupImportDbConfirm'),
                      () async {
                        final ok = await context.repos.backup.importDatabase();
                        _showOk(
                          ok
                              ? l10n.tr('backupImportSuccess')
                              : l10n.tr('backupCanceled'),
                        );
                      },
                    ),
                  ),
                  _ActionTile(
                    icon: Icons.upload,
                    title: l10n.tr('backupImportJsonTitle'),
                    subtitle: l10n.tr('backupImportJsonSubtitle'),
                    onTap: () => _confirmAndRun(
                      l10n.tr('backupImportJsonConfirm'),
                      () async {
                        final ok = await context.repos.backup.importJson();
                        _showOk(
                          ok
                              ? l10n.tr('backupImportSuccess')
                              : l10n.tr('backupCanceled'),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 32),
                ],
                if (cloud) const SizedBox(height: 16),
                Text(
                  l10n.tr('backupPdfReportsTitle'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                _ActionTile(
                  icon: Icons.picture_as_pdf,
                  title: l10n.tr('backupBalanceReportTitle'),
                  subtitle: l10n.tr('backupBalanceReportSubtitle'),
                  onTap: () => _run(() async {
                    final resumenes = await context.repos.getResumenJugadores();
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
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.tr('confirm')),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.tr('continueBtn')),
          ),
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
