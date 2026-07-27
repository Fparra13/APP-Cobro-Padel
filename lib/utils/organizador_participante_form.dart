import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../core/matchpay_design_tokens.dart';
import '../l10n/matchpay_strings.dart';
import '../models/jugador.dart';
import '../utils/formatters.dart';

bool _esEmailValido(String email) {
  return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
}

class _ParticipanteFormData {
  const _ParticipanteFormData({
    required this.nombre,
    required this.emailRaw,
    required this.whatsappRaw,
    required this.activo,
  });

  final String nombre;
  final String emailRaw;
  final String whatsappRaw;
  final bool activo;
}

/// Diálogo existente de alta/edición de participante (organizador).
///
/// Reutilizado desde Jugadores y desde Home A/B. Persistencia vía
/// [AppRepositories.insertJugador] / [updateJugador] (RPC crear_jugador_organizador).
Future<bool> showOrganizerParticipanteForm(
  BuildContext context, {
  Jugador? jugador,
}) async {
  // Controllers viven en el State del diálogo: dispose solo tras unmount
  // (evita dependents.isEmpty al cerrar durante la animación de salida).
  final data = await showDialog<_ParticipanteFormData>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (ctx) => _OrganizerParticipanteFormDialog(jugador: jugador),
  );

  if (data == null || !context.mounted) return false;

  final now = DateTime.now();
  final emailRaw = data.emailRaw;
  final email = emailRaw.isEmpty ? null : emailRaw.toLowerCase();
  final whatsappRaw = data.whatsappRaw;
  final whatsapp =
      whatsappRaw.isEmpty ? null : normalizeWhatsAppDigits(whatsappRaw);
  if (whatsappRaw.isNotEmpty && whatsapp == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.tr('whatsappInvalid')),
        backgroundColor: MatchPayTokens.accentError,
      ),
    );
    return false;
  }

  try {
    if (jugador == null) {
      await context.repos.insertJugador(
        Jugador(
          nombre: data.nombre,
          activo: data.activo,
          email: email,
          telefono: whatsapp,
          createdAt: now,
        ),
      );
    } else {
      await context.repos.updateJugador(
        jugador.copyWith(
          nombre: data.nombre,
          activo: data.activo,
          email: email,
          telefono: whatsapp,
          clearTelefono: whatsapp == null,
        ),
      );
    }
    if (!context.mounted) return true;
    AppRepositories.notifyDataChanged();
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          jugador == null
              ? l10n.tr('playerAdded')
              : l10n.tr(
                  'playerDataSaved',
                  params: {'name': data.nombre},
                ),
        ),
      ),
    );
    return true;
  } catch (e) {
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.userError(e)),
        backgroundColor: MatchPayTokens.accentError,
        duration: const Duration(seconds: 12),
        action: SnackBarAction(
          label: context.l10n.tr('close'),
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
    return false;
  }
}

class _OrganizerParticipanteFormDialog extends StatefulWidget {
  const _OrganizerParticipanteFormDialog({this.jugador});

  final Jugador? jugador;

  @override
  State<_OrganizerParticipanteFormDialog> createState() =>
      _OrganizerParticipanteFormDialogState();
}

class _OrganizerParticipanteFormDialogState
    extends State<_OrganizerParticipanteFormDialog> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _whatsappCtrl;
  late final ValueNotifier<bool> _activo;
  String _formError = '';

  @override
  void initState() {
    super.initState();
    final jugador = widget.jugador;
    _nombreCtrl = TextEditingController(text: jugador?.nombre ?? '');
    _emailCtrl = TextEditingController(text: jugador?.contactEmail ?? '');
    _whatsappCtrl =
        TextEditingController(text: jugador?.contactWhatsApp ?? '');
    _activo = ValueNotifier(jugador?.activo ?? true);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _whatsappCtrl.dispose();
    _activo.dispose();
    super.dispose();
  }

  void _validateAndSave() {
    final l10n = context.l10n;
    final nombre = _nombreCtrl.text.trim();
    final emailRaw = _emailCtrl.text.trim();
    if (nombre.isEmpty) {
      setState(() => _formError = l10n.tr('playerNameRequired'));
      return;
    }
    if (emailRaw.isNotEmpty && !_esEmailValido(emailRaw)) {
      setState(() => _formError = l10n.tr('emailFormatInvalid'));
      return;
    }
    Navigator.pop(
      context,
      _ParticipanteFormData(
        nombre: nombre,
        emailRaw: emailRaw,
        whatsappRaw: _whatsappCtrl.text.trim(),
        activo: _activo.value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final jugador = widget.jugador;

    return AlertDialog(
      scrollable: true,
      icon: Icon(
        jugador == null ? Icons.person_add_alt_1 : Icons.edit,
        color: Theme.of(context).colorScheme.primary,
        size: 32,
      ),
      title: Text(
        jugador == null ? l10n.tr('newPlayer') : l10n.tr('editPlayer'),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nombreCtrl,
              decoration: InputDecoration(
                labelText: l10n.tr('nameLabel'),
                prefixIcon: const Icon(Icons.badge_outlined),
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
              onSubmitted: (_) => _validateAndSave(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: l10n.tr('emailLabel'),
                hintText: l10n.tr('loginEmailHint'),
                prefixIcon: const Icon(Icons.email_outlined),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _whatsappCtrl,
              decoration: InputDecoration(
                labelText: l10n.tr('whatsappLabel'),
                hintText: l10n.tr('whatsappHint'),
                helperText: l10n.tr('whatsappHelper'),
                prefixIcon: const Icon(Icons.chat_outlined),
                border: const OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: _activo,
              builder: (_, value, _) => SwitchListTile(
                secondary: Icon(
                  value ? Icons.star : Icons.star_border,
                  color: value
                      ? MatchPayTokens.accentUrgent
                      : MatchPayTokens.inkMuted,
                ),
                title: Text(l10n.tr('regularPlayer')),
                subtitle: Text(l10n.tr('regularPlayerSubtitle')),
                value: value,
                onChanged: (v) => _activo.value = v,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (_formError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _formError,
                style: MatchPayTokens.bodySmallStyle(
                  color: MatchPayTokens.accentError,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.tr('cancel')),
        ),
        FilledButton.icon(
          onPressed: _validateAndSave,
          icon: const Icon(Icons.save),
          label: Text(l10n.tr('save')),
        ),
      ],
    );
  }
}
