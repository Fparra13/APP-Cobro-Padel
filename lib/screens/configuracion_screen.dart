import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/crashlytics_bootstrap.dart';
import '../core/firebase_config.dart';
import '../core/legal_urls.dart';
import '../models/jugador.dart';
import '../core/matchpay_design_tokens.dart';
import '../services/notification_service.dart';
import '../services/preferences_service.dart';
import '../widgets/app_mode_switch_panel.dart';
import '../widgets/codigo_grupo_organizador_card.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/matchpay_preferences_panel.dart';
import '../widgets/matchpay_ui.dart';
import '../widgets/mis_recintos_panel.dart';
import '../widgets/unirse_grupo_sheet.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
import '../utils/organizer_subscription_flow.dart';
import '../utils/perfil_foto.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _prefs = PreferencesService();
  final _nombrePerfilCtrl = TextEditingController();
  final _titularCtrl = TextEditingController();
  final _pagoDetalleCtrl = TextEditingController();
  final _pagoNotaCtrl = TextEditingController();

  bool _loading = true;
  bool _isOrganizer = false;
  bool _recordatorioActivo = false;
  int _recordatorioDias = 3;
  TimeOfDay _recordatorioHora = const TimeOfDay(hour: 10, minute: 0);
  bool? _permisosOk;
  Jugador? _perfil;

  static const _opcionesDias = [1, 2, 3, 5, 7, 10, 14, 21, 30];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await AuthService.instance.refreshProfile();
      _isOrganizer = AuthService.instance.isOrganizer;

      final uid = AuthService.instance.currentUser?.id;
      if (uid != null && mounted) {
        try {
          final perfil = await context.repos.getJugador(uid);
          _perfil = perfil;
          _nombrePerfilCtrl.text = perfil?.nombre ?? '';
        } catch (_) {}
      }

      if (_isOrganizer) {
        final pago = await _prefs.datosPago;
        _titularCtrl.text = pago.titular;
        _pagoDetalleCtrl.text = pago.detalle;
        _pagoNotaCtrl.text = pago.nota;

        final uidOrg = AuthService.instance.currentUser?.id;
        if (uidOrg != null && AppRepositories.isReady && mounted) {
          final repos = context.repos;
          try {
            final remote = await repos.getDatosPagoOrganizador(uidOrg);
            if (!mounted) return;
            if (remote != null && remote.pago.tieneDatos) {
              _titularCtrl.text = remote.pago.titular;
              _pagoDetalleCtrl.text = remote.pago.detalle;
              _pagoNotaCtrl.text = remote.pago.nota;
            } else if (pago.tieneDatos) {
              // Primera vez: sube lo que había en el teléfono.
              await repos.guardarDatosPagoOrganizador(
                titular: pago.titular,
                detalle: pago.detalle,
                nota: pago.nota,
              );
            }
          } catch (_) {}
        }

        _recordatorioActivo = await _prefs.recordatorioActivo;
        _recordatorioDias = await _prefs.recordatorioDias;
        final hora = await _prefs.recordatorioHora;
        final minuto = await _prefs.recordatorioMinuto;
        _recordatorioHora = TimeOfDay(hour: hora, minute: minuto);
      }

      _permisosOk = await NotificationService.instance.arePermissionsGranted();
    } catch (_) {
      // Preferencias locales / permisos: no bloquear la pantalla en blanco.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePerfil() async {
    final nombre = _nombrePerfilCtrl.text.trim();
    if (nombre.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.tr('loginErrorNameMinLength')),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
      return;
    }
    try {
      await AuthService.instance.updateMyNombre(nombre);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('configNameUpdated'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.userError(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _confirmBecomeOrganizer() async {
    await openOrganizerSubscriptionFlow(context);
  }

  Future<void> _saveBancarios() async {
    final titular = _titularCtrl.text.trim();
    final detalle = _pagoDetalleCtrl.text.trim();
    final nota = _pagoNotaCtrl.text.trim();
    await _prefs.saveDatosPago(
      titular: titular,
      detalle: detalle,
      nota: nota,
    );
    try {
      if (AppRepositories.isReady && mounted) {
        final repos = context.repos;
        await repos.guardarDatosPagoOrganizador(
          titular: titular,
          detalle: detalle,
          nota: nota,
        );
      }
    } catch (_) {
      // Prefs locales ya guardados; el sync remoto puede reintentarse.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('configPaymentInfoSaved'))),
      );
    }
  }

  Future<void> _saveRecordatorio() async {
    await _prefs.saveRecordatorio(
      activo: _recordatorioActivo,
      dias: _recordatorioDias,
      hora: _recordatorioHora.hour,
      minuto: _recordatorioHora.minute,
    );
    await NotificationService.instance.syncSchedule();
    if (_recordatorioActivo) {
      await NotificationService.instance.checkAndNotifyIfNeeded();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('configRemindersSaved'))),
      );
    }
  }

  Future<void> _toggleRecordatorio(bool value) async {
    if (value) {
      final ok = await NotificationService.instance.requestPermissions();
      _permisosOk = ok;
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.tr('configEnableNotificationsInSettings'),
            ),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }
    setState(() => _recordatorioActivo = value);
    await _saveRecordatorio();
  }

  Future<void> _solicitarPermisos() async {
    final already =
        await NotificationService.instance.arePermissionsGranted();
    if (already) {
      if (!mounted) return;
      setState(() => _permisosOk = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('configNotificationsAlreadyGranted')),
        ),
      );
      return;
    }

    final ok = await NotificationService.instance.requestPermissions();
    if (!mounted) return;
    setState(() => _permisosOk = ok);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.l10n.tr('configNotificationsGranted')
              : context.l10n.tr('configNotificationsDenied'),
        ),
      ),
    );
  }

  Future<void> _probarNotificacion() async {
    final ok = await NotificationService.instance.requestPermissions();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('configGrantNotificationFirst')),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    await NotificationService.instance.showTestNotification();
  }

  Future<void> _elegirHora() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _recordatorioHora,
      helpText: context.l10n.tr('configDailyReminderTime'),
    );
    if (hora == null) return;
    setState(() => _recordatorioHora = hora);
    await _saveRecordatorio();
  }

  @override
  void dispose() {
    _nombrePerfilCtrl.dispose();
    _titularCtrl.dispose();
    _pagoDetalleCtrl.dispose();
    _pagoNotaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Herramientas de admin solo en modo organizador (no en vista jugador).
    final enModoOrganizador =
        _isOrganizer && context.watchSettings().showOrganizerShell;

    return ShellTabScaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      appBar: AppBar(title: Text(l10n.configScreenTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: NavShellScope.listPadding(context),
              children: [
                // 1. Identidad
                if (AuthService.instance.isLoggedIn) ...[
                  _buildSeccionPerfil(),
                  _configDivider(),
                ],

                // 2. Vista diaria (organizador ↔ jugador)
                if (_isOrganizer) ...[
                  const AppModeSwitchPanel(),
                  _configDivider(),
                ],

                // Código de grupo / unirse a grupos
                if (AuthService.instance.isLoggedIn) ...[
                  if (enModoOrganizador) ...[
                    const CodigoGrupoOrganizadorCard(),
                    _configDivider(),
                  ],
                  // También como jugador (o dual): unirse a otros grupos
                  if (!enModoOrganizador || _isOrganizer) ...[
                    MatchPaySurfaceCard(
                      onTap: () async {
                        final result = await UnirseGrupoSheet.show(context);
                        if (!context.mounted || result == null) return;
                        final msg = result.yaEstaba
                            ? l10n.tr(
                                'groupCodeJoinAlready',
                                params: {'name': result.nombre},
                              )
                            : l10n.tr(
                                'groupCodeJoinSuccess',
                                params: {'name': result.nombre},
                              );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg)),
                        );
                        if (!context.mounted) return;
                        await UnirseGrupoSheet.maybeShowCuentaAdicionalInfo(
                          context,
                          result,
                        );
                      },
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: context.sportPalette.primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.group_add_rounded,
                              color: context.sportPalette.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.tr('groupCodeJoinTitle'),
                                  style: MatchPayTokens.titleSmallStyle(),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  l10n.tr('groupCodeJoinSubtitle'),
                                  style: MatchPayTokens.bodySmallStyle(),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                    _configDivider(),
                  ],
                ],

                // 3. Preferencias regionales + deporte
                MatchPayPreferencesPanel(showSport: enModoOrganizador),
                _configDivider(),

                // 4. Cobros: cómo pagarme + recordatorios
                if (enModoOrganizador) ...[
                  _buildSeccionPago(l10n),
                  _configDivider(),
                  _buildSeccionRecordatorios(),
                  _configDivider(),
                  // 5. Lugares y respaldo (menos frecuente)
                  const MisRecintosPanel(),
                  _configDivider(),
                  _buildEntradaBackup(l10n),
                  _configDivider(),
                ] else ...[
                  if (AuthService.instance.isLoggedIn) ...[
                    MatchPaySurfaceCard(
                      onTap: _confirmBecomeOrganizer,
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: context.sportPalette.primary
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.groups_rounded,
                              color: context.sportPalette.primaryDark,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.tr('becomeOrganizerCardTitle'),
                                  style: MatchPayTokens.titleSmallStyle(),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  context.l10n.tr('becomeOrganizerSoftSub'),
                                  style: MatchPayTokens.bodySmallStyle(),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: context.sportPalette.primary,
                          ),
                        ],
                      ),
                    ),
                    _configDivider(),
                  ],
                  _buildSeccionJugador(),
                  _configDivider(),
                ],

                // 6. Legal y cuenta
                _buildSeccionLegal(),
                if (kDebugMode && FirebaseConfig.isConfigured) ...[
                  _configDivider(),
                  _buildSeccionCrashlyticsTest(),
                ],
                if (AuthService.instance.isLoggedIn) ...[
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () async {
                      AppRepositories.clear();
                      await AuthService.instance.signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: Text(l10n.tr('signOut')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _configDivider() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Divider(height: 1),
      );

  Widget _buildEntradaBackup(MatchPayStrings l10n) {
    return MatchPaySurfaceCard(
      onTap: () => Navigator.pushNamed(context, '/backup'),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.sportPalette.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.cloud_outlined,
              color: context.sportPalette.primaryDark,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.navCloud,
                  style: MatchPayTokens.titleSmallStyle(),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.tr('configOpenBackupSubtitle'),
                  style: MatchPayTokens.bodySmallStyle(),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: context.sportPalette.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionPago(MatchPayStrings l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MatchPaySectionHeader(title: l10n.tr('configPaymentInfoTitle')),
        const SizedBox(height: 8),
        Text(
          l10n.tr('configPaymentInfoHint'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _titularCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.tr('configPaymentNameLabel'),
            hintText: l10n.tr('configPaymentNameHint'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pagoDetalleCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.tr('configPaymentDetailLabel'),
            hintText: l10n.tr('configPaymentDetailHint'),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pagoNotaCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: l10n.tr('configPaymentNoteLabel'),
            hintText: l10n.tr('configPaymentNoteHint'),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _saveBancarios,
          icon: const Icon(Icons.save),
          label: Text(l10n.tr('configSavePaymentInfo')),
        ),
      ],
    );
  }

  Future<void> _cambiarFotoPerfil() async {
    final perfil = _perfil;
    if (perfil == null) return;
    await editarFotoPerfil(
      context,
      jugador: perfil,
      onDone: () {
        if (mounted) _load();
      },
    );
  }

  Widget _buildSeccionPerfil() {
    final l10n = context.l10n;
    final email = AuthService.instance.currentUser?.email ?? '';
    final rol = l10n.tr(_isOrganizer ? 'roleOrganizer' : 'rolePlayer');
    final nombre = _nombrePerfilCtrl.text.trim().isNotEmpty
        ? _nombrePerfilCtrl.text.trim()
        : l10n.tr('playerDefaultName');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.person, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              l10n.tr('configMyProfile'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.tr('configProfileVisibilityHint'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              InkWell(
                onTap: _perfil == null ? null : _cambiarFotoPerfil,
                borderRadius: BorderRadius.circular(40),
                child: Stack(
                  children: [
                    JugadorAvatar(
                      nombre: nombre,
                      fotoUrl: _perfil?.fotoUrl,
                      fotoPath: _perfil?.fotoPath,
                      size: 80,
                      borderRadius: 40,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _perfil == null ? null : _cambiarFotoPerfil,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(l10n.tr('configChangePhoto')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _nombrePerfilCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: l10n.tr('nameLabel'),
            prefixIcon: const Icon(Icons.badge_outlined),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: InputDecoration(
            labelText: l10n.tr('emailLabel'),
            prefixIcon: const Icon(Icons.email_outlined),
            border: const OutlineInputBorder(),
          ),
          child: Text(email, style: TextStyle(color: Colors.grey.shade800)),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.tr('configRoleLabel', params: {'role': rol}),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _savePerfil,
          icon: const Icon(Icons.save),
          label: Text(l10n.tr('configSaveName')),
        ),
      ],
    );
  }

  Widget _buildSeccionRecordatorios() {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              l10n.tr('configPaymentRemindersTitle'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.tr('configPaymentRemindersBody'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.tr('configEnableReminders')),
          subtitle: Text(
            _permisosOk == true
                ? l10n.tr('configNotificationsAllowed')
                : _permisosOk == false
                    ? l10n.tr('configPermissionsPending')
                    : l10n.tr('configCheckingPermissions'),
            style: TextStyle(
              fontSize: 12,
              color: _permisosOk == true
                  ? Colors.green.shade700
                  : Colors.orange.shade800,
            ),
          ),
          value: _recordatorioActivo,
          onChanged: _toggleRecordatorio,
        ),
        if (_recordatorioActivo) ...[
          const SizedBox(height: 8),
          InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.tr('configNotifyAfter'),
              border: const OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: _opcionesDias.contains(_recordatorioDias)
                    ? _recordatorioDias
                    : 3,
                items: _opcionesDias
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(
                          l10n.tr('configDaysUnpaid', params: {'days': '$d'}),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (d) async {
                  if (d == null) return;
                  setState(() => _recordatorioDias = d);
                  await _saveRecordatorio();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.tr('configDailyReminderTime')),
            subtitle: Text(_recordatorioHora.format(context)),
            trailing: const Icon(Icons.schedule),
            onTap: _elegirHora,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Solo pedir permisos si aún faltan; si ya están OK, basta Probar.
            if (_permisosOk != true)
              OutlinedButton.icon(
                onPressed: _solicitarPermisos,
                icon: const Icon(Icons.security, size: 18),
                label: Text(l10n.tr('permissions')),
              ),
            OutlinedButton.icon(
              onPressed: _probarNotificacion,
              icon: const Icon(Icons.notifications_none, size: 18),
              label: Text(l10n.tr('test')),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _abrirPoliticaPrivacidad() async {
    final uri = Uri.parse(LegalUrls.privacyPolicy);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildSeccionLegal() {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.gavel_outlined, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              l10n.tr('legalSectionTitle'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(l10n.tr('privacyPolicy')),
          trailing: const Icon(Icons.open_in_new, size: 18),
          onTap: _abrirPoliticaPrivacidad,
        ),
      ],
    );
  }

  /// Solo debug: Paso 3 de la guía oficial de Crashlytics.
  Widget _buildSeccionCrashlyticsTest() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.bug_report_outlined, color: Colors.orange.shade800),
            const SizedBox(width: 8),
            const Text(
              'Crashlytics (debug)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Fuerza una excepción de prueba para ver el informe en Firebase Console. '
          'Después reinicia la app.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => CrashlyticsBootstrap.forceTestException(),
          icon: const Icon(Icons.warning_amber_rounded, size: 18),
          label: const Text('Throw Test Exception'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange.shade900,
            minimumSize: const Size.fromHeight(44),
          ),
        ),
      ],
    );
  }

  Widget _buildSeccionJugador() {
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.notifications_outlined, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              l10n.tr('configNotificationsTitle'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.tr('configPlayerNotificationsBody'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            _permisosOk == true ? Icons.check_circle : Icons.warning_amber,
            color: _permisosOk == true
                ? Colors.green.shade700
                : Colors.orange.shade800,
          ),
          title: Text(
            _permisosOk == true
                ? l10n.tr('configNotificationsActive')
                : l10n.tr('configNotificationsDisabled'),
          ),
          subtitle: Text(
            _permisosOk == true
                ? l10n.tr('configPlayerNotificationsActiveHint')
                : l10n.tr('configPlayerNotificationsInactiveHint'),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _solicitarPermisos,
          icon: const Icon(Icons.notifications_active),
          label: Text(l10n.tr('configEnableNotifications')),
        ),
      ],
    );
  }
}
