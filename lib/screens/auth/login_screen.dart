import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_settings_controller.dart';
import '../../core/auth_service.dart';
import '../../core/matchpay_design_tokens.dart';
import '../../core/supabase_config.dart';
import '../../l10n/matchpay_strings.dart';
import '../../widgets/sport_icon.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService.instance;
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _loading = false;
  bool _linkEnviado = false;
  String? _emailIngresado;
  String? _mensajeInline;
  int _cooldownSegundos = 0;
  Timer? _cooldownTimer;

  static const _cooldownTotal = 60;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  bool _esEmailValido(String email) {
    return RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(email);
  }

  MatchPayStrings get _l10n =>
      MatchPayStrings.of(context.read<AppSettingsController>().locale);

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    setState(() => _mensajeInline = mensaje);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    if (!mounted) return;
    setState(() => _mensajeInline = null);
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _iniciarCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSegundos = _cooldownTotal);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSegundos <= 1) {
        timer.cancel();
        setState(() => _cooldownSegundos = 0);
      } else {
        setState(() => _cooldownSegundos -= 1);
      }
    });
  }

  Future<void> _enviarMagicLink() async {
    try {
      if (_loading) return;
      if (_cooldownSegundos > 0) {
        _mostrarError(
          _l10n.tr(
            'loginResendCooldown',
            params: {'seconds': '$_cooldownSegundos'},
          ),
        );
        return;
      }

      FocusManager.instance.primaryFocus?.unfocus();
      final l10n = _l10n;
      final nombre = _nombreCtrl.text.trim();
      final email = _emailCtrl.text.trim().toLowerCase();

      if (nombre.isEmpty) {
        _mostrarError(l10n.tr('loginErrorEnterName'));
        return;
      }
      if (nombre.length < 2) {
        _mostrarError(l10n.tr('loginErrorNameMinLength'));
        return;
      }
      if (email.isEmpty) {
        _mostrarError(l10n.tr('loginErrorEnterEmail'));
        return;
      }
      if (!_esEmailValido(email)) {
        _mostrarError(l10n.tr('loginErrorInvalidEmail'));
        return;
      }

      setState(() {
        _loading = true;
        _mensajeInline = null;
      });

      await _auth.sendMagicLink(email, nombre: nombre);
      if (!mounted) return;
      setState(() {
        _linkEnviado = true;
        _emailIngresado = email;
        _mensajeInline = null;
      });
      _mostrarExito(l10n.tr('loginCheckEmailTitle'));
      _iniciarCooldown();
    } catch (e, st) {
      debugPrint('LoginScreen._enviarMagicLink: $e\n$st');
      if (!mounted) return;
      final msg = e is Exception
          ? e.toString().replaceFirst('Exception: ', '')
          : '$e';
      _mostrarError(msg.isEmpty ? 'No se pudo enviar el enlace.' : msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final puedeEnviar = !_loading && _cooldownSegundos <= 0;

    return Scaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SportIcon(
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _linkEnviado
                        ? l10n.tr('loginSubtitleLinkSent')
                        : l10n.tr('loginSubtitleEnterDetails'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  if (!SupabaseConfig.isConfigured) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        l10n.tr('loginSupabaseNotConfigured'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (!_linkEnviado) ...[
                    TextField(
                      controller: _nombreCtrl,
                      enabled: !_loading,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.tr('loginNameLabel'),
                        hintText: l10n.tr('loginNameHint'),
                        prefixIcon: const Icon(Icons.person_outline),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailCtrl,
                      enabled: !_loading,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: l10n.tr('loginEmailLabel'),
                        hintText: l10n.tr('loginEmailHint'),
                        prefixIcon: const Icon(Icons.email_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (puedeEnviar) _enviarMagicLink();
                      },
                    ),
                    const SizedBox(height: 24),
                    if (_mensajeInline != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _mensajeInline!,
                                style: TextStyle(
                                  color: Colors.red.shade900,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: puedeEnviar ? _enviarMagicLink : null,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.link),
                      label: Text(l10n.tr('loginSendLink')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primaryContainer
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(
                                alpha: 0.3,
                              ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.mark_email_read_outlined,
                            size: 48,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            l10n.tr('loginCheckEmailTitle'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.tr(
                              'loginCheckEmailBody',
                              params: {'email': _emailIngresado ?? ''},
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: puedeEnviar ? _enviarMagicLink : null,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _cooldownSegundos > 0
                            ? l10n.tr(
                                'loginResendCooldown',
                                params: {
                                  'seconds': '$_cooldownSegundos',
                                },
                              )
                            : l10n.tr('loginResendLink'),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _linkEnviado = false;
                                _emailIngresado = null;
                              });
                            },
                      child: Text(l10n.tr('loginChangeEmail')),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
