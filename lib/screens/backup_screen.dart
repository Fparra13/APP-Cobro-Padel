import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/nav_shell_layout.dart';
import '../services/pdf_service.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/shimmer_loading.dart';

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
              dataActionErrorMessage(
                context.l10n,
                e,
                fallback: (err) => context.l10n.tr(
                  'backupError',
                  params: {'error': '$err'},
                ),
              ),
            ),
            backgroundColor: MatchPayTokens.accentError,
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
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(
        title: Text(
          cloud ? l10n.tr('backupCloudTitle') : l10n.tr('backupLocalTitle'),
        ),
      ),
      body: _busy
          ? const _BackupShimmer()
          : ListView(
              padding: NavShellScope.listPadding(context, left: 16, top: 16),
              children: [
                if (cloud) ...[
                  MatchPayStatusBanner(
                    icon: Icons.cloud_done_rounded,
                    message: l10n.tr('backupSupabaseBody'),
                    urgent: false,
                  ),
                  const SizedBox(height: 8),
                  MatchPaySurfaceCard(
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: MatchPayTokens.accentCreditBg,
                            borderRadius: BorderRadius.circular(
                              MatchPayTokens.radiusChip,
                            ),
                          ),
                          child: const Icon(
                            Icons.cloud_sync_rounded,
                            color: MatchPayTokens.accentCredit,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.tr('backupSupabaseTitle'),
                            style: MatchPayTokens.titleSmallStyle(
                              color: MatchPayTokens.accentCredit,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  MatchPaySectionHeader(
                    title: l10n.tr('backupExportImportTitle'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.tr('backupOfflineHint'),
                    style: MatchPayTokens.bodySmallStyle(),
                  ),
                  const SizedBox(height: 16),
                  _ActionTile(
                    icon: Icons.storage_rounded,
                    iconColor: MatchPayTokens.accentCredit,
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
                  _ActionTile(
                    icon: Icons.data_object_rounded,
                    iconColor: MatchPayTokens.accentSuccess,
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
                    icon: Icons.upload_file_rounded,
                    iconColor: MatchPayTokens.accentUrgent,
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
                    icon: Icons.upload_rounded,
                    iconColor: MatchPayTokens.accentUrgent,
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
                  const SizedBox(height: 24),
                ],
                if (cloud) const SizedBox(height: 16),
                MatchPaySectionHeader(title: l10n.tr('backupPdfReportsTitle')),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.picture_as_pdf_rounded,
                  iconColor: MatchPayTokens.accentError,
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

  Future<void> _confirmAndRun(
    String msg,
    Future<void> Function() action,
  ) async {
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
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MatchPayTapScale(
        onTap: onTap,
        child: MatchPaySurfaceCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(MatchPayTokens.radiusChip),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: MatchPayTokens.titleSmallStyle()),
                    const SizedBox(height: 2),
                    Text(subtitle, style: MatchPayTokens.bodySmallStyle()),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: MatchPayTokens.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupShimmer extends StatelessWidget {
  const _BackupShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: NavShellScope.listPadding(context, left: 16, top: 16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        ShimmerLoading(
          height: 72,
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
        ),
        const SizedBox(height: 16),
        ShimmerLoading(
          height: 14,
          width: 160,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 10),
        ...List.generate(
          3,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ShimmerLoading(
              height: 76,
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusCard),
            ),
          ),
        ),
      ],
    );
  }
}
