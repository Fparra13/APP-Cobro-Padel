import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../services/preferences_service.dart';

class ConfiguracionScreen extends StatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  State<ConfiguracionScreen> createState() => _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends State<ConfiguracionScreen> {
  final _prefs = PreferencesService();
  final _titularCtrl = TextEditingController();
  final _bancoCtrl = TextEditingController();
  final _cuentaCtrl = TextEditingController();
  final _rutCtrl = TextEditingController();

  bool _loading = true;
  bool _recordatorioActivo = false;
  int _recordatorioDias = 3;
  TimeOfDay _recordatorioHora = const TimeOfDay(hour: 10, minute: 0);
  bool? _permisosOk;

  static const _opcionesDias = [1, 2, 3, 5, 7, 10, 14, 21, 30];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _titularCtrl.text = await _prefs.titularNombre;
    _bancoCtrl.text = await _prefs.bancoNombre;
    _cuentaCtrl.text = await _prefs.cuentaNumero;
    _rutCtrl.text = await _prefs.titularRut;

    _recordatorioActivo = await _prefs.recordatorioActivo;
    _recordatorioDias = await _prefs.recordatorioDias;
    final hora = await _prefs.recordatorioHora;
    final minuto = await _prefs.recordatorioMinuto;
    _recordatorioHora = TimeOfDay(hour: hora, minute: minuto);
    _permisosOk = await NotificationService.instance.arePermissionsGranted();

    if (mounted) setState(() => _loading = false);
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
        const SnackBar(content: Text('Datos bancarios guardados')),
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
        const SnackBar(content: Text('Recordatorios guardados')),
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
            content: const Text(
              'Activa las notificaciones en ajustes del teléfono',
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
                ? 'Permisos de notificación concedidos'
                : 'Permisos denegados. Actívalos en Ajustes del teléfono.',
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
          content: const Text('Primero concede permisos de notificación'),
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
      helpText: 'Hora del recordatorio diario',
    );
    if (hora == null) return;
    setState(() => _recordatorioHora = hora);
    await _saveRecordatorio();
  }

  @override
  void dispose() {
    _titularCtrl.dispose();
    _bancoCtrl.dispose();
    _cuentaCtrl.dispose();
    _rutCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSeccionRecordatorios(),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Datos bancarios (para reportes PDF)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titularCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre titular',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _rutCtrl,
                  decoration: const InputDecoration(
                    labelText: 'RUT',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bancoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Banco',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _cuentaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Número de cuenta',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _saveBancarios,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar datos bancarios'),
                ),
              ],
            ),
    );
  }

  Widget _buildSeccionRecordatorios() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.notifications_active, color: Colors.green.shade700),
            const SizedBox(width: 8),
            const Text(
              'Recordatorios de cobro',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Te avisamos cuando hay jugadores que no han pagado después de '
          'los días que definas. Al tocar la notificación puedes enviar '
          'recordatorios por WhatsApp.',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Activar recordatorios'),
          subtitle: Text(
            _permisosOk == true
                ? 'Notificaciones permitidas'
                : _permisosOk == false
                    ? 'Permisos pendientes'
                    : 'Verificando permisos...',
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
            decoration: const InputDecoration(
              labelText: 'Avisar después de',
              border: OutlineInputBorder(),
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
                          d == 1 ? '1 día sin pagar' : '$d días sin pagar',
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
            title: const Text('Hora del aviso diario'),
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
              label: const Text('Permisos'),
            ),
            OutlinedButton.icon(
              onPressed: _probarNotificacion,
              icon: const Icon(Icons.notifications_none, size: 18),
              label: const Text('Probar'),
            ),
          ],
        ),
      ],
    );
  }
}
