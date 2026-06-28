import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth_service.dart';
import '../../core/supabase_config.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _auth = AuthService.instance;
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _loading = false;
  bool _otpEnviado = false;
  String? _telefonoCompleto;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String _normalizarTelefono(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('56') && digits.length >= 11) {
      return '+$digits';
    }
    if (digits.length == 9 && digits.startsWith('9')) {
      return '+56$digits';
    }
    if (digits.length == 8) {
      return '+569$digits';
    }
    if (digits.isNotEmpty && !input.startsWith('+')) {
      return '+$digits';
    }
    return input.startsWith('+') ? input : '+56$digits';
  }

  void _mostrarError(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  void _mostrarExito(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensaje)),
    );
  }

  Future<void> _enviarCodigo() async {
    final raw = _phoneCtrl.text.trim();
    if (raw.isEmpty) {
      _mostrarError('Ingresa tu número de teléfono');
      return;
    }

    final phone = _normalizarTelefono(raw);
    if (phone.length < 12) {
      _mostrarError('Número inválido. Ejemplo: 912345678');
      return;
    }

    setState(() => _loading = true);
    try {
      await _auth.signInWithPhone(phone);
      if (!mounted) return;
      setState(() {
        _otpEnviado = true;
        _telefonoCompleto = phone;
      });
      _mostrarExito('Código enviado a $phone');
    } catch (e) {
      _mostrarError('No se pudo enviar el código: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verificarCodigo() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _mostrarError('El código debe tener 6 dígitos');
      return;
    }

    final phone = _telefonoCompleto;
    if (phone == null) {
      _mostrarError('Primero envía el código a tu teléfono');
      return;
    }

    setState(() => _loading = true);
    try {
      await _auth.verifyOtp(phone: phone, otp: otp);
      _mostrarExito('¡Bienvenido!');
    } catch (e) {
      _mostrarError('Código incorrecto o expirado: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.sports_tennis_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pádel Cobro',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Inicia sesión con tu número de WhatsApp',
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
                        'Supabase no está configurado. Compila con '
                        '--dart-define=SUPABASE_URL=... y '
                        '--dart-define=SUPABASE_ANON_KEY=...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  TextField(
                    controller: _phoneCtrl,
                    enabled: !_otpEnviado && !_loading,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Teléfono',
                      hintText: '912345678',
                      prefixText: '+56 ',
                      prefixIcon: Icon(Icons.phone_android),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_otpEnviado) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _otpCtrl,
                      enabled: !_loading,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Código SMS',
                        hintText: '000000',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _verificarCodigo(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (!_otpEnviado)
                    FilledButton.icon(
                      onPressed: _loading ? null : _enviarCodigo,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.sms_outlined),
                      label: const Text('Enviar código'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: _loading ? null : _verificarCodigo,
                      icon: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.verified_outlined),
                      label: const Text('Verificar'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _otpEnviado = false;
                                _otpCtrl.clear();
                                _telefonoCompleto = null;
                              });
                            },
                      child: const Text('Cambiar número'),
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
