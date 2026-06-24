import 'package:flutter/material.dart';

import '../repositories/partido_repository.dart';
import '../services/recordatorio_service.dart';
import '../utils/formatters.dart';

class RecordatorioDeudoresSheet extends StatefulWidget {
  final List<ResumenJugador> deudores;
  final String titulo;
  final String? subtitulo;

  const RecordatorioDeudoresSheet({
    super.key,
    required this.deudores,
    this.titulo = 'Recordatorio a deudores',
    this.subtitulo,
  });

  static Future<void> show(
    BuildContext context, {
    required List<ResumenJugador> resumenes,
    String titulo = 'Recordatorio a deudores',
    String? subtitulo,
  }) {
    final deudores = resumenes.where((r) => r.saldoActual > 0).toList();
    if (deudores.isEmpty) {
      return Future.value();
    }
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RecordatorioDeudoresSheet(
        deudores: deudores,
        titulo: titulo,
        subtitulo: subtitulo,
      ),
    );
  }

  @override
  State<RecordatorioDeudoresSheet> createState() =>
      _RecordatorioDeudoresSheetState();
}

class _RecordatorioDeudoresSheetState extends State<RecordatorioDeudoresSheet> {
  final _service = RecordatorioService();
  bool _enviando = false;
  int? _enviandoJugadorId;

  int get _conWhatsApp => widget.deudores
      .where((r) => (r.jugador.telefono?.trim().isNotEmpty ?? false))
      .length;

  int get _sinWhatsApp => widget.deudores.length - _conWhatsApp;

  double get _totalDeuda =>
      widget.deudores.fold(0.0, (s, r) => s + r.saldoActual);

  Future<void> _enviarTodos() async {
    if (_conWhatsApp == 0) {
      _mostrarSnack('Ningún deudor tiene WhatsApp registrado');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.message, color: Colors.green),
        title: const Text('Enviar recordatorios'),
        content: Text(
          'Se abrirá WhatsApp $_conWhatsApp vez${_conWhatsApp == 1 ? '' : 'es'}, '
          'una por cada jugador con teléfono.\n\n'
          'Debes confirmar y enviar cada mensaje en WhatsApp.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send),
            label: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _enviando = true);
    final resultado = await _service.enviarATodos(widget.deudores);
    if (!mounted) return;

    setState(() => _enviando = false);
    _mostrarSnack(
      'Enviados: ${resultado.enviados}'
      '${resultado.sinTelefono > 0 ? ' · Sin tel: ${resultado.sinTelefono}' : ''}'
      '${resultado.errores > 0 ? ' · Errores: ${resultado.errores}' : ''}',
    );
  }

  Future<void> _enviarUno(ResumenJugador r) async {
    setState(() => _enviandoJugadorId = r.jugador.id);
    try {
      await _service.enviarIndividual(
        jugador: r.jugador,
        saldo: r.saldoActual,
      );
      if (mounted) {
        _mostrarSnack('WhatsApp abierto para ${r.jugador.nombre}');
      }
    } catch (e) {
      if (mounted) {
        _mostrarSnack('Error: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _enviandoJugadorId = null);
    }
  }

  void _mostrarSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      builder: (_, scroll) => SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.message, color: Colors.green.shade700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.titulo,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          widget.subtitulo ??
                              '${widget.deudores.length} jugadores · Total ${formatMoney(_totalDeuda)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Text(
                  _conWhatsApp > 0
                      ? 'Toca "Enviar a todos" para abrir WhatsApp con cada deudor '
                          '($_conWhatsApp con teléfono).'
                          '${_sinWhatsApp > 0 ? ' $_sinWhatsApp sin WhatsApp: edítalos en Jugadores.' : ''}'
                      : 'Nadie tiene WhatsApp. Agrega el teléfono en la pestaña Jugadores.',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: widget.deudores.length,
                itemBuilder: (_, i) {
                  final r = widget.deudores[i];
                  final tieneWa =
                      r.jugador.telefono?.trim().isNotEmpty ?? false;
                  final enviando = _enviandoJugadorId == r.jugador.id;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: tieneWa
                            ? Colors.green.shade100
                            : Colors.orange.shade100,
                        child: Icon(
                          tieneWa ? Icons.phone_android : Icons.phone_disabled,
                          color: tieneWa
                              ? Colors.green.shade700
                              : Colors.orange.shade800,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        r.jugador.nombre,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        tieneWa
                            ? 'Debe ${formatMoney(r.saldoActual)}'
                            : 'Sin WhatsApp · ${formatMoney(r.saldoActual)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tieneWa ? Colors.red.shade700 : Colors.orange.shade800,
                        ),
                      ),
                      trailing: IconButton.filledTonal(
                        icon: enviando
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.message,
                                color: tieneWa ? Colors.green : Colors.grey,
                              ),
                        tooltip: 'Enviar recordatorio',
                        onPressed: enviando || _enviando || !tieneWa
                            ? null
                            : () => _enviarUno(r),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _enviando || _conWhatsApp == 0 ? null : _enviarTodos,
                icon: _enviando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  _enviando
                      ? 'Enviando recordatorios...'
                      : 'Enviar a todos ($_conWhatsApp)',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
