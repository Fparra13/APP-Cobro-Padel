import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_repositories.dart';
import '../core/auth_service.dart';
import '../core/crashlytics_bootstrap.dart';
import '../core/firebase_config.dart';
import '../core/legal_urls.dart';
import '../models/jugador.dart';
import '../models/cobro_recordatorio_prefs.dart';
import '../core/matchpay_design_tokens.dart';
import '../services/fcm_service.dart';
import '../services/notification_service.dart';
import '../services/push_notification_service.dart';
import '../services/preferences_service.dart';
import '../utils/cobro_recordatorio_flow.dart';
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
  int _recordatorioDiasPrimer = 3;
  int _recordatorioFrecuencia = 7;
  TimeOfDay _recordatorioHora = const TimeOfDay(hour: 10, minute: 0);
  String _recordatorioTimezone = 'America/Santiago';
  bool? _permisosOk;
  Jugador? _perfil;

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

        final prefsRemote =
            await CobroRecordatorioPrefsLoader.loadAndMigrateIfNeeded();
        _recordatorioActivo = prefsRemote.activo;
        _recordatorioDiasPrimer =
            CobroRecordatorioPrefs.normalizePrimer(prefsRemote.diasPrimer);
        _recordatorioFrecuencia =
            CobroRecordatorioPrefs.normalizeFrecuencia(prefsRemote.frecuenciaDias);
        _recordatorioHora = TimeOfDay(
          hour: prefsRemote.horaLocal.hour,
          minute: prefsRemote.horaLocal.minute,
        );
        _recordatorioTimezone = prefsRemote.timezone;
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
    if (!AppRepositories.isReady) return;
    final tz = await CobroRecordatorioPrefsLoader.deviceTimezone();
    final prefs = CobroRecordatorioPrefs(
      activo: _recordatorioActivo,
      diasPrimer: _recordatorioDiasPrimer,
      frecuenciaDias: _recordatorioFrecuencia,
      horaLocal: TimeOfDayLike(
        hour: _recordatorioHora.hour,
        minute: _recordatorioHora.minute,
      ),
      timezone: tz,
      exists: true,
    );
    try {
      final saved = await AppRepositories.I.upsertCobroRecordatorioPrefs(prefs);
      if (!mounted) return;
      setState(() {
        _recordatorioTimezone = saved.timezone;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('configRemindersSaved'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dataActionErrorMessage(context.l10n, e)),
          backgroundColor: Colors.red.shade700,
        ),
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
      final sync = await FcmService.instance.syncTokenToProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sync == FcmSyncResult.synced
                ? context.l10n.tr('configNotificationsAlreadyGranted')
                : context.l10n.tr('configPushRegisterFailed'),
          ),
          backgroundColor:
              sync == FcmSyncResult.synced ? null : Colors.orange.shade800,
        ),
      );
      return;
    }

    final ok = await NotificationService.instance.requestPermissions();
    if (!mounted) return;
    setState(() => _permisosOk = ok);
    FcmSyncResult? sync;
    if (ok) {
      sync = await FcmService.instance.syncTokenToProfile();
    }
    if (!mounted) return;
    final msg = !ok
        ? context.l10n.tr('configNotificationsDenied')
        : sync == FcmSyncResult.synced
            ? context.l10n.tr('configNotificationsGranted')
            : context.l10n.tr('configPushRegisterFailed');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            ok && sync != FcmSyncResult.synced ? Colors.orange.shade800 : null,
      ),
    );
  }

  Future<void> _probarNotificacion() async {
    final ok = await NotificationService.instance.requestPermissions();
    final enabled =
        await NotificationService.instance.arePermissionsGranted();
    if ((!ok || !enabled) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('configNotificationsBlocked')),
          backgroundColor: Colors.red.shade700,
        ),
      );
      setState(() => _permisosOk = false);
      return;
    }
    if (!mounted) return;
    setState(() => _permisosOk = true);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('configPushRegistering'))),
    );

    // QA: captura initializeApp/getToken en release (appLog no imprime ahí).
    await FcmService.instance.runQaDiagnostics();

    // Sin forceReinit: no tumbar un Firebase ya OK solo para re-probar.
    final sync = await FcmService.instance.syncTokenToProfile();
    // Local: prueba canal/permisos. Remoto: prueba FCM de punta a punta.
    await NotificationService.instance.showTestNotification();
    final stillEnabled =
        await NotificationService.instance.arePermissionsGranted();
    final uid = AuthService.instance.currentUser?.id;
    PushSendResult? remote;
    if (uid != null && uid.isNotEmpty && mounted) {
      final l10n = context.l10n;
      remote = await PushNotificationService.instance.enviarPruebaAMiMismo(
        userId: uid,
        title: l10n.tr('configPushRemoteTestTitle'),
        body: l10n.tr('configPushRemoteTestBody'),
      );
    }
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    if (!stillEnabled) {
      setState(() => _permisosOk = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('configNotificationsBlocked')),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    if (remote != null && remote.ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('configPushRemoteSent')),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else if (sync == FcmSyncResult.synced) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            remote == null
                ? context.l10n.tr('configPushRegisteredCheckTray')
                : context.l10n.tr('configPushRemoteFailed'),
          ),
          backgroundColor:
              remote == null ? Colors.green.shade700 : Colors.orange.shade800,
        ),
      );
    } else if (await FcmService.instance.profileHasFcmToken()) {
      // Token ya en servidor (push puede seguir llegando) aunque el re-sync falle.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            remote != null && !remote.ok
                ? context.l10n.tr('configPushRemoteFailed')
                : context.l10n.tr('configPushAlreadyActive'),
          ),
          backgroundColor: remote != null && !remote.ok
              ? Colors.orange.shade800
              : Colors.green.shade700,
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.tr('configPushRegisterFailed')),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    }
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
    final uid = AuthService.instance.currentUser?.id;
    if (uid == null) return;
    final perfil = _perfil ??
        Jugador(
          supabaseId: uid,
          nombre: _nombrePerfilCtrl.text.trim().isNotEmpty
              ? _nombrePerfilCtrl.text.trim()
              : (AuthService.instance.currentUser?.email ?? 'Usuario'),
          email: AuthService.instance.currentUser?.email,
          createdAt: DateTime.now(),
        );
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
                onTap: AuthService.instance.currentUser == null
                    ? null
                    : _cambiarFotoPerfil,
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
                onPressed: AuthService.instance.currentUser == null
                    ? null
                    : _cambiarFotoPerfil,
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
              labelText: l10n.tr('configFirstReminder'),
              border: const OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: CobroRecordatorioPrefs.normalizePrimer(
                  _recordatorioDiasPrimer,
                ),
                items: CobroRecordatorioPrefs.primerOpciones
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(
                          l10n.tr(
                            d == 1
                                ? 'configDaysAfterOne'
                                : 'configDaysAfter',
                            params: {'days': '$d'},
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (d) async {
                  if (d == null) return;
                  setState(() => _recordatorioDiasPrimer = d);
                  await _saveRecordatorio();
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: InputDecoration(
              labelText: l10n.tr('configReminderFrequency'),
              border: const OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                isExpanded: true,
                value: CobroRecordatorioPrefs.normalizeFrecuencia(
                  _recordatorioFrecuencia,
                ),
                items: CobroRecordatorioPrefs.frecuenciaOpciones
                    .map(
                      (d) => DropdownMenuItem(
                        value: d,
                        child: Text(
                          l10n.tr(
                            'configFrequencyEveryDays',
                            params: {'days': '$d'},
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (d) async {
                  if (d == null) return;
                  setState(() => _recordatorioFrecuencia = d);
                  await _saveRecordatorio();
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tr('configRemindersHelpExample'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.tr('configDailyReminderTime')),
            subtitle: Text(
              '${_recordatorioHora.format(context)} · $_recordatorioTimezone',
            ),
            trailing: const Icon(Icons.schedule),
            onTap: _elegirHora,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
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


  Future<void> _eliminarCuenta() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.tr('deleteAccountConfirmTitle')),
        content: Text(l10n.tr('deleteAccountConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.tr('deleteAccountConfirmAction')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await AuthService.instance.deleteAccount();
      AppRepositories.clear();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('deleteAccountSuccess'))),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('deleteAccountError'))),
      );
    }
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

        if (AuthService.instance.isLoggedIn)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_forever_outlined, color: Colors.red.shade700),
            title: Text(
              l10n.tr('deleteAccount'),
              style: TextStyle(color: Colors.red.shade700),
            ),
            subtitle: Text(l10n.tr('deleteAccountSubtitle')),
            onTap: _eliminarCuenta,
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_permisosOk != true)
              OutlinedButton.icon(
                onPressed: _solicitarPermisos,
                icon: const Icon(Icons.notifications_active),
                label: Text(l10n.tr('configEnableNotifications')),
              ),
            OutlinedButton.icon(
              onPressed: _probarNotificacion,
              icon: const Icon(Icons.notifications_none),
              label: Text(l10n.tr('test')),
            ),
          ],
        ),
      ],
    );
  }
}
