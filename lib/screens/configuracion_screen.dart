import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/app_settings_controller.dart';
import '../core/auth_service.dart';
import '../models/jugador.dart';
import '../services/notification_service.dart';
import '../services/preferences_service.dart';
import '../widgets/app_mode_switch_panel.dart';
import '../widgets/jugador_avatar.dart';
import '../widgets/matchpay_preferences_panel.dart';
import '../widgets/mis_recintos_panel.dart';
import '../l10n/matchpay_strings.dart';
import '../utils/matchpay_context.dart';
import '../utils/nav_shell_layout.dart';
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
  final _bancoCtrl = TextEditingController();
  final _cuentaCtrl = TextEditingController();
  final _rutCtrl = TextEditingController();

  bool _loading = true;
  bool _isOrganizer = true;
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
    await AuthService.instance.refreshProfile();
    _isOrganizer = AuthService.instance.isOrganizer;

    final uid = AuthService.instance.currentUser?.id;
    if (uid != null && context.mounted) {
      try {
        final perfil = await context.repos.getJugador(uid);
        _perfil = perfil;
        _nombrePerfilCtrl.text = perfil?.nombre ?? '';
      } catch (_) {}
    }

    if (_isOrganizer) {
      _titularCtrl.text = await _prefs.titularNombre;
      _bancoCtrl.text = await _prefs.bancoNombre;
      _cuentaCtrl.text = await _prefs.cuentaNumero;
      _rutCtrl.text = await _prefs.titularRut;

      _recordatorioActivo = await _prefs.recordatorioActivo;
      _recordatorioDias = await _prefs.recordatorioDias;
      final hora = await _prefs.recordatorioHora;
      final minuto = await _prefs.recordatorioMinuto;
      _recordatorioHora = TimeOfDay(hour: hora, minute: minuto);
    }

    _permisosOk = await NotificationService.instance.arePermissionsGranted();

    if (mounted) setState(() => _loading = false);
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
            content: Text('$e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _saveBancarios() async {
    await _prefs.saveDatosBancarios(
      titular: _titularCtrl.text.trim(),
      banco: _bancoCtrl.text.trim(),
      cuenta: _cuentaCtrl.text.trim(),
      rut: _rutCtrl.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('configBankDataSaved'))),
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
    final ok = await NotificationService.instance.requestPermissions();
    setState(() => _permisosOk = ok);
    if (mounted) {
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
    _bancoCtrl.dispose();
    _cuentaCtrl.dispose();
    _rutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Herramientas de admin solo en modo organizador (no en vista jugador).
    final enModoOrganizador =
        _isOrganizer && context.watchSettings().showOrganizerShell;

    return ShellTabScaffold(
      appBar: AppBar(title: Text(l10n.configScreenTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: NavShellScope.listPadding(context),
              children: [
                MatchPayPreferencesPanel(showSport: enModoOrganizador),
                if (_isOrganizer) ...[
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 16),
                  const AppModeSwitchPanel(),
                ],
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 16),
                if (AuthService.instance.isLoggedIn) ...[
                  _buildSeccionPerfil(),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 16),
                ],
                if (!_isOrganizer && AuthService.instance.isLoggedIn) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: Text(context.l10n.tr('becomeOrganizerCardTitle')),
                    subtitle: Text(context.l10n.tr('becomeOrganizerSoftSub')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      try {
                        await AuthService.instance.becomeOrganizer();
                        if (!mounted) return;
                        await context.switchAppUiMode(AppUiMode.organizer);
                        if (!mounted) return;
                        setState(() => _isOrganizer = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.tr('becomeOrganizerDone')),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$e'),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 16),
                ],
                if (enModoOrganizador) ...[
                  const MisRecintosPanel(),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 16),
                  _buildSeccionRecordatorios(),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    l10n.tr('configBankDataTitle'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _titularCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.tr('configAccountHolderLabel'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _rutCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.tr('configRutLabel'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bancoCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.tr('configBankLabel'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _cuentaCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.tr('configAccountNumberLabel'),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _saveBancarios,
                    icon: const Icon(Icons.save),
                    label: Text(l10n.tr('configSaveBankData')),
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),
                ] else ...[
                  _buildSeccionJugador(),
                  const SizedBox(height: 28),
                  const Divider(),
                  const SizedBox(height: 16),
                ],
                if (AuthService.instance.isLoggedIn) ...[
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
