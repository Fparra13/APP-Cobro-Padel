import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../../core/app_settings_controller.dart';
import '../../core/auth_service.dart';
import '../../core/matchpay_design_tokens.dart';
import '../../core/sport_theme.dart';
import '../../core/supabase_config.dart';
import '../../l10n/matchpay_strings.dart';
import '../../widgets/matchpay_ui.dart';
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
  bool _loadingGoogle = false;
  bool _linkEnviado = false;
  bool _mostrarEmail = false;
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
        backgroundColor: MatchPayTokens.accentError,
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
        backgroundColor: MatchPayTokens.accentSuccess,
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
      if (_loading || _loadingGoogle) return;
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
      _mostrarError(_mensajeLogin(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _entrarConGoogle() async {
    if (_loading || _loadingGoogle) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _loadingGoogle = true;
      _mensajeInline = null;
    });
    try {
      await _auth.signInWithGoogle();
      // AuthGate / auth listener navega al shell.
    } on GoogleSignInCancelledException {
      // Usuario cerró el selector: sin snackbar.
    } catch (e, st) {
      debugPrint('LoginScreen._entrarConGoogle: $e\n$st');
      if (!mounted) return;
      _mostrarError(_mensajeLogin(e));
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  String _mensajeLogin(Object e) {
    if (e is Exception) {
      final s = e.toString();
      const prefix = 'Exception: ';
      final body = s.startsWith(prefix) ? s.substring(prefix.length) : s;
      if (body.isNotEmpty &&
          !body.startsWith('Instance of') &&
          body.length < 280) {
        return body;
      }
    }
    return context.userError(e);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watch<AppSettingsController>();
    final palette = SportThemeConfig.paletteFor(settings.sport);
    final ocupado = _loading || _loadingGoogle;
    final puedeEnviar = !ocupado && _cooldownSegundos <= 0;
    final googleListo = SupabaseConfig.isGoogleSignInConfigured;

    return Scaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LoginHero(
              linkEnviado: _linkEnviado,
              palette: palette,
              title: l10n.appName,
              subtitle: _linkEnviado
                  ? l10n.tr('loginSubtitleLinkSent')
                  : l10n.tr(
                      googleListo
                          ? 'loginSubtitleGoogle'
                          : 'loginSubtitleEnterDetails',
                    ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -28),
                      child: MatchPaySurfaceCard(
                        elevated: true,
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!SupabaseConfig.isConfigured) ...[
                              MatchPayStatusBanner(
                                icon: Icons.warning_amber_rounded,
                                message: l10n.tr('loginSupabaseNotConfigured'),
                                urgent: true,
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (!_linkEnviado) ...[
                              if (googleListo) ...[
                                _buildGoogleButton(l10n, ocupado),
                                const SizedBox(height: 16),
                                _OrDivider(label: l10n.tr('loginOrEmail')),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: ocupado
                                      ? null
                                      : () => setState(
                                            () => _mostrarEmail = !_mostrarEmail,
                                          ),
                                  child: Text(
                                    _mostrarEmail
                                        ? l10n.tr('loginHideEmail')
                                        : l10n.tr('loginShowEmail'),
                                  ),
                                ),
                                if (_mostrarEmail) ...[
                                  const SizedBox(height: 8),
                                  _buildFormFields(l10n, palette, puedeEnviar),
                                ],
                              ] else ...[
                                _buildFormFields(l10n, palette, puedeEnviar),
                              ],
                            ] else ...[
                              _buildLinkSentPanel(l10n, palette),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleButton(MatchPayStrings l10n, bool ocupado) {
    return OutlinedButton(
      onPressed: ocupado || !SupabaseConfig.isConfigured ? null : _entrarConGoogle,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        backgroundColor: Colors.white,
        foregroundColor: MatchPayTokens.ink,
        side: BorderSide(color: MatchPayTokens.ink.withValues(alpha: 0.18)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MatchPayTokens.radiusButton),
        ),
      ),
      child: _loadingGoogle
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _GoogleGMark(),
                const SizedBox(width: 12),
                Text(
                  l10n.tr('loginContinueGoogle'),
                  style: MatchPayTokens.titleSmallStyle(),
                ),
              ],
            ),
    );
  }

  Widget _buildFormFields(
    MatchPayStrings l10n,
    SportThemePalette palette,
    bool puedeEnviar,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nombreCtrl,
          enabled: !_loading && !_loadingGoogle,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: l10n.tr('loginNameLabel'),
            hintText: l10n.tr('loginNameHint'),
            prefixIcon: const Icon(Icons.person_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailCtrl,
          enabled: !_loading && !_loadingGoogle,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.tr('loginEmailLabel'),
            hintText: l10n.tr('loginEmailHint'),
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusChip),
            ),
          ),
          onSubmitted: (_) {
            if (puedeEnviar) _enviarMagicLink();
          },
        ),
        if (_mensajeInline != null) ...[
          const SizedBox(height: 12),
          MatchPayStatusBanner(
            icon: Icons.error_outline,
            message: _mensajeInline!,
            urgent: true,
          ),
        ],
        const SizedBox(height: 20),
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
              : const Icon(Icons.link_rounded),
          label: Text(l10n.tr('loginSendLink')),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: palette.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusButton),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.tr('loginMagicLinkHint'),
          textAlign: TextAlign.center,
          style: MatchPayTokens.bodySmallStyle(
            color: MatchPayTokens.inkSecondary,
          ).copyWith(height: 1.4),
        ),
      ],
    );
  }

  Widget _buildLinkSentPanel(MatchPayStrings l10n, SportThemePalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: palette.cardBackground,
            borderRadius: BorderRadius.circular(MatchPayTokens.radiusCardSm),
            border: Border.all(color: palette.surfaceTint),
          ),
          child: Column(
            children: [
              Text(
                l10n.tr('loginCheckEmailTitle'),
                textAlign: TextAlign.center,
                style: MatchPayTokens.titleSmallStyle(color: palette.primaryDark),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.tr(
                  'loginCheckEmailBody',
                  params: {'email': _emailIngresado ?? ''},
                ),
                textAlign: TextAlign.center,
                style: MatchPayTokens.bodySmallStyle(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: (!_loading && !_loadingGoogle && _cooldownSegundos <= 0)
              ? _enviarMagicLink
              : null,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
          label: Text(
            _cooldownSegundos > 0
                ? l10n.tr(
                    'loginResendCooldown',
                    params: {'seconds': '$_cooldownSegundos'},
                  )
                : l10n.tr('loginResendLink'),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: palette.primary,
            side: BorderSide(color: palette.primary.withValues(alpha: 0.45)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MatchPayTokens.radiusButton),
            ),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: (_loading || _loadingGoogle)
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
    );
  }
}

class _OrDivider extends StatelessWidget {
  final String label;

  const _OrDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Divider(color: MatchPayTokens.ink.withValues(alpha: 0.12)),
    );
    return Row(
      children: [
        line,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: MatchPayTokens.bodySmallStyle(
              color: MatchPayTokens.inkSecondary,
            ),
          ),
        ),
        line,
      ],
    );
  }
}

/// Marca "G" de Google sin dependencias de assets.
class _GoogleGMark extends StatelessWidget {
  const _GoogleGMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Simplificado: círculo azul con G blanca (identificable, no logo oficial exacto).
    paint.color = const Color(0xFF4285F4);
    canvas.drawCircle(Offset(cx, cy), r, paint);
    final tp = TextPainter(
      text: const TextSpan(
        text: 'G',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoginHero extends StatelessWidget {
  final bool linkEnviado;
  final SportThemePalette palette;
  final String title;
  final String subtitle;

  const _LoginHero({
    required this.linkEnviado,
    required this.palette,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.primary, palette.primaryDark],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(MatchPayTokens.radiusCard),
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: linkEnviado
                ? _LoginLottie(
                    key: const ValueKey('sent'),
                    asset: 'assets/lottie/login_email_sent.json',
                    palette: palette,
                  )
                : _LoginTrophy(key: const ValueKey('welcome')),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: MatchPayTokens.displayStyle(color: Colors.white).copyWith(
              fontSize: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: MatchPayTokens.bodySmallStyle(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginTrophy extends StatelessWidget {
  const _LoginTrophy({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.emoji_events_rounded,
            size: 52,
            color: Color(0xFFFFD54F),
          ),
        ),
      ),
    );
  }
}

class _LoginLottie extends StatelessWidget {
  final String asset;
  final SportThemePalette palette;

  const _LoginLottie({
    super.key,
    required this.asset,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: Lottie.asset(
        asset,
        repeat: true,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => Center(
          child: SportEmoji(
            sport: context.read<AppSettingsController>().sport,
            size: 72,
          ),
        ),
      ),
    );
  }
}
