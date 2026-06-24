import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/estado_partido.dart';
import '../models/jugador.dart';
import '../repositories/convocatoria_repository.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/partido_repository.dart';
import '../services/convocatoria_message_service.dart';
import '../services/convocatoria_parser_service.dart';
import '../services/preferences_service.dart';
import '../services/share_service.dart';
import '../utils/formatters.dart';
import '../widgets/ayuda_tip.dart';
import '../widgets/confirmar_eliminar_partido_dialog.dart';

class OrganizarPartidoScreen extends StatefulWidget {
  final int? partidoId;

  const OrganizarPartidoScreen({super.key, this.partidoId});

  bool get isEditing => partidoId != null;

  @override
  State<OrganizarPartidoScreen> createState() => _OrganizarPartidoScreenState();
}

class _OrganizarPartidoScreenState extends State<OrganizarPartidoScreen> {
  final _convocatoriaRepo = ConvocatoriaRepository();
  final _jugadorRepo = JugadorRepository();
  final _partidoRepo = PartidoRepository();
  final _prefs = PreferencesService();
  final _messageService = ConvocatoriaMessageService();
  final _parserService = ConvocatoriaParserService();
  final _shareService = ShareService();

  final _recintoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  final _cuposCtrl = TextEditingController(text: '4');

  List<Jugador> _habituales = [];
  List<String> _recintosSugeridos = [];
  final Set<int> _invitados = {};
  final Map<int, EstadoConfirmacion> _estados = {};
  DateTime _fechaPartido = DateTime.now().add(const Duration(hours: 2));
  bool _loading = true;
  bool _guardando = false;
  String? _errorCarga;
  int? _partidoId;
  bool _dirty = false;
  bool _partidoConfirmado = false;

  bool get _estaGuardada => _partidoId != null;

  bool get _cuposLlenos => _confirmados >= _cuposMax;

  int get _cuposDisponibles => (_cuposMax - _confirmados).clamp(0, _cuposMax);

  int get _confirmados =>
      _invitados.where((id) => _estados[id] == EstadoConfirmacion.confirmado).length;

  int get _cuposMax {
    final n = int.tryParse(_cuposCtrl.text.trim());
    return n == null || n < 1 ? 4 : n;
  }

  @override
  void initState() {
    super.initState();
    _partidoId = widget.partidoId;
    _load();
  }

  @override
  void dispose() {
    _recintoCtrl.dispose();
    _notasCtrl.dispose();
    _cuposCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final habituales = await _jugadorRepo.getAll(soloActivos: true);
      final recintos = await _partidoRepo.getRecintosRecientes();
      final ultimoRecinto = await _prefs.ultimoRecinto;

      if (_partidoId != null) {
        final conv = await _convocatoriaRepo.getCompleta(_partidoId!);
        if (conv != null) {
          _fechaPartido = conv.partido.fecha;
          _recintoCtrl.text = conv.partido.recinto ?? '';
          _notasCtrl.text = conv.partido.notas ?? '';
          _cuposCtrl.text = conv.partido.cuposMax.toString();
          _partidoConfirmado = conv.partido.esConfirmado;
          for (final entry in conv.jugadores) {
            final id = entry.jugador.id!;
            _invitados.add(id);
            _estados[id] = entry.estado;
          }
        }
      } else {
        for (final j in habituales) {
          if (j.id != null) {
            _invitados.add(j.id!);
            _estados[j.id!] = EstadoConfirmacion.invitado;
          }
        }
        if (_recintoCtrl.text.isEmpty && ultimoRecinto.isNotEmpty) {
          _recintoCtrl.text = ultimoRecinto;
        }
      }

      if (mounted) {
        setState(() {
          _habituales = habituales;
          _recintosSugeridos = recintos;
          _loading = false;
          _errorCarga = null;
          _dirty = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorCarga = e.toString();
        });
      }
    }
  }

  String _formatoFechaHora(DateTime fecha) => formatDiaCompleto(fecha);

  Future<void> _pickFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaPartido,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('es', 'CL'),
    );
    if (fecha == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_fechaPartido),
    );
    if (hora == null) return;

    setState(() {
      _fechaPartido = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        hora.hour,
        hora.minute,
      );
      _dirty = true;
    });
  }

  void _marcarDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _persistirEstadoJugador(int jugadorId) async {
    if (_partidoId == null) return;
    await _convocatoriaRepo.actualizarConfirmacion(
      partidoId: _partidoId!,
      jugadorId: jugadorId,
      estado: _estados[jugadorId] ?? EstadoConfirmacion.invitado,
    );
  }

  void _toggleInvitado(int id, bool? value) {
    setState(() {
      if (value == true) {
        _invitados.add(id);
        _estados.putIfAbsent(id, () => EstadoConfirmacion.invitado);
      } else {
        _invitados.remove(id);
        _estados.remove(id);
      }
      _dirty = true;
    });
  }

  void _seleccionarTodos(bool todos) {
    setState(() {
      if (todos) {
        for (final j in _habituales) {
          if (j.id != null) {
            _invitados.add(j.id!);
            _estados.putIfAbsent(j.id!, () => EstadoConfirmacion.invitado);
          }
        }
      } else {
        _invitados.clear();
        _estados.clear();
      }
      _dirty = true;
    });
  }

  Future<void> _ciclarEstado(int id) async {
    if (!_invitados.contains(id)) return;

    final actual = _estados[id] ?? EstadoConfirmacion.invitado;
    final siguiente = actual.siguiente();

    if (siguiente == EstadoConfirmacion.confirmado &&
        actual != EstadoConfirmacion.confirmado &&
        _cuposLlenos) {
      _mostrarError(
        'Cupos llenos ($_cuposMax/$_cuposMax). '
        'Marca a alguien como "No va" para liberar un cupo.',
      );
      return;
    }

    setState(() {
      _estados[id] = siguiente;
      _dirty = true;
    });
    if (_partidoId != null) {
      await _persistirEstadoJugador(id);
    }
  }

  Map<int, EstadoConfirmacion> _aplicarCambiosConCupo(
    Map<int, EstadoConfirmacion> cambios,
  ) {
    final aplicados = <int, EstadoConfirmacion>{};
    var disponibles = _cuposDisponibles;

    for (final entry in cambios.entries) {
      if (!_invitados.contains(entry.key)) continue;

      if (entry.value == EstadoConfirmacion.confirmado) {
        final yaConfirmado =
            _estados[entry.key] == EstadoConfirmacion.confirmado;
        if (!yaConfirmado) {
          if (disponibles <= 0) continue;
          disponibles--;
        }
      }

      _estados[entry.key] = entry.value;
      aplicados[entry.key] = entry.value;
    }

    return aplicados;
  }

  Future<bool> _guardar({bool silencioso = false}) async {
    if (_invitados.isEmpty) {
      _mostrarError('Selecciona al menos un jugador para invitar');
      return false;
    }

    setState(() => _guardando = true);
    try {
      final recinto = _recintoCtrl.text.trim();
      final notas = _notasCtrl.text.trim();

      if (_partidoId == null) {
        _partidoId = await _convocatoriaRepo.crear(
          fecha: _fechaPartido,
          recinto: recinto.isEmpty ? null : recinto,
          notas: notas.isEmpty ? null : notas,
          cuposMax: _cuposMax,
          jugadoresInvitados: _invitados.toList(),
        );
      } else {
        await _convocatoriaRepo.actualizar(
          partidoId: _partidoId!,
          fecha: _fechaPartido,
          recinto: recinto.isEmpty ? null : recinto,
          notas: notas.isEmpty ? null : notas,
          cuposMax: _cuposMax,
          jugadoresInvitados: _invitados.toList(),
          estados: Map.fromEntries(
            _invitados.map((id) => MapEntry(id, _estados[id] ?? EstadoConfirmacion.invitado)),
          ),
        );
      }

      if (recinto.isNotEmpty) {
        await _prefs.saveUltimoRecinto(recinto);
      }

      if (!silencioso && mounted) {
        setState(() => _dirty = false);
      }
      return true;
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _guardarStandby() async {
    if (!await _guardar(silencioso: true)) return;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Convocatoria en espera. Retómala desde Inicio cuando confirmen.',
        ),
        duration: Duration(seconds: 4),
      ),
    );
    Navigator.pop(context, true);
  }

  Future<bool> _confirmarSalidaSinGuardar() async {
    if (!_dirty) return true;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text(
          'Puedes dejar la convocatoria en espera y retomarla '
          'desde Inicio cuando los jugadores respondan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'descartar'),
            child: const Text('Salir sin guardar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'espera'),
            child: const Text('Dejar en espera'),
          ),
        ],
      ),
    );

    if (action == 'cancelar' || !mounted) return false;
    if (action == 'descartar') return true;
    if (action == 'espera') {
      await _guardarStandby();
      return false;
    }
    return true;
  }

  Future<void> _enviarConvocatoria() async {
    if (!await _guardar(silencioso: true)) return;

    final conv = await _convocatoriaRepo.getCompleta(_partidoId!);
    if (conv == null || !mounted) return;

    final mensaje = _messageService.construirMensaje(conv);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enviar convocatoria',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
              const SizedBox(height: 8),
              const Text(
                'Elige el grupo de WhatsApp donde están todos los jugadores.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Text(
                  mensaje,
                  style: const TextStyle(fontSize: 13, height: 1.35),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _shareService.compartirTexto(mensaje);
                },
                icon: const Icon(Icons.share),
                label: const Text('Compartir (elige grupo WhatsApp)'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _shareService.compartirWhatsApp(mensaje: mensaje);
                },
                icon: const Icon(Icons.chat),
                label: const Text('Abrir WhatsApp directo'),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: mensaje));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mensaje copiado')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copiar mensaje'),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted) return;
    final dejar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convocatoria enviada'),
        content: const Text(
          '¿Dejar en espera mientras confirman? '
          'Podrás retomarla desde Inicio en los próximos días.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir aquí'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dejar en espera'),
          ),
        ],
      ),
    );
    if (dejar == true && mounted) {
      await _guardarStandby();
    }
  }

  Future<void> _importarWhatsApp() async {
    final ctrl = TextEditingController();
    final aplicado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar confirmaciones'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pega aquí las respuestas del chat de WhatsApp. '
                'Detectamos frases como "Voy", "Confirmo", "No voy", etc.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText: 'Ej:\n✅ Voy - Juan\n❌ No voy - Pedro',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );

    if (aplicado != true || !mounted) return;

    final invitados = _habituales.where((j) => _invitados.contains(j.id)).toList();
    final resultado = _parserService.parsear(
      texto: ctrl.text,
      jugadoresInvitados: invitados,
    );

    final cambios = _aplicarCambiosConCupo(resultado.cambios);
    final omitidos = resultado.cambios.length - cambios.length;

    setState(() {});

    if (_partidoId != null && cambios.isNotEmpty) {
      await _convocatoriaRepo.aplicarConfirmaciones(
        partidoId: _partidoId!,
        cambios: cambios,
      );
    } else if (_partidoId == null) {
      _marcarDirty();
    }

    if (!mounted) return;
    final msg = StringBuffer('${cambios.length} confirmación(es) aplicada(s)');
    if (omitidos > 0) {
      msg.write('\n$omitidos omitido(s): cupos llenos ($_cuposMax)');
    }
    if (resultado.noReconocidos.isNotEmpty) {
      msg.write('\nNo reconocidos: ${resultado.noReconocidos.join(', ')}');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg.toString())),
    );
  }

  Future<void> _confirmarPartido() async {
    if (!await _guardar(silencioso: true)) return;

    if (_confirmados == 0) {
      _mostrarError('Marca al menos un jugador como confirmado');
      return;
    }

    if (!_cuposLlenos) {
      _mostrarError(
        'Necesitas $_cuposMax confirmados para cerrar el partido. '
        'Tienes $_confirmados de $_cuposMax.',
      );
      return;
    }

    if (!mounted) return;

    await _convocatoriaRepo.marcarConfirmado(_partidoId!);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Partido confirmado · $_confirmados jugadores. '
          'Registra los cobros cuando se juegue.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
    Navigator.pop(context, true);
  }

  Future<void> _registrarCobros() async {
    if (!await _guardar(silencioso: true)) return;

    final confirmados = _invitados
        .where((id) => _estados[id] == EstadoConfirmacion.confirmado)
        .toList();

    if (confirmados.isEmpty) {
      if (!mounted) return;
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sin confirmados'),
          content: const Text(
            'Nadie está marcado como confirmado. '
            '¿Registrar cobros igual seleccionando jugadores manualmente?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (continuar != true || !mounted) return;
    }

    if (!mounted) return;
    await Navigator.pushNamed(
      context,
      '/registrar-partido',
      arguments: _partidoId,
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _eliminarConvocatoria() async {
    final ok = await confirmarEliminarPartido(
      context,
      titulo: 'Eliminar convocatoria',
      mensaje: 'Vas a eliminar esta convocatoria por completo.',
      consecuencias: const [
        'Se borrará la convocatoria y la lista de confirmados.',
        'No quedará registro de este partido en la app.',
        'Esta acción es permanente y no se puede deshacer.',
      ],
    );
    if (!ok || _partidoId == null) return;

    await _convocatoriaRepo.eliminar(_partidoId!);
    if (mounted) Navigator.pop(context, true);
  }

  void _mostrarError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final salir = await _confirmarSalidaSinGuardar();
        if (!mounted) return;
        if (salir) Navigator.pop(context);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          _partidoConfirmado
              ? 'Partido confirmado'
              : _estaGuardada
                  ? 'Convocatoria en espera'
                  : widget.isEditing
                      ? 'Convocatoria'
                      : 'Organizar partido',
        ),
        actions: [
          if (_partidoId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: _eliminarConvocatoria,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorCarga != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: Colors.red.shade700),
                        const SizedBox(height: 12),
                        const Text(
                          'No se pudo cargar la convocatoria',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorCarga!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _errorCarga = null;
                            });
                            _load();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                AyudaTip(
                  texto: _partidoConfirmado
                      ? 'El grupo ya está confirmado. Cuando se juegue, '
                          'usa "Ir a cobrar" para registrar los pagos.'
                      : 'Envía la convocatoria y deja en espera mientras confirman. '
                          'Debes tener $_cuposMax confirmados para usar '
                          '"Partido confirmado".',
                ),
                const SizedBox(height: 12),
                _buildResumen(),
                const SizedBox(height: 12),
                _buildDatosPartido(),
                const SizedBox(height: 12),
                _buildAcciones(),
                const SizedBox(height: 12),
                _buildListaJugadores(),
                const SizedBox(height: 80),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_estaGuardada || _partidoConfirmado)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        _partidoConfirmado
                            ? Icons.check_circle
                            : Icons.hourglass_top,
                        size: 18,
                        color: _partidoConfirmado
                            ? Colors.green.shade700
                            : Colors.blue.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _partidoConfirmado
                              ? 'Confirmado · $_confirmados/$_cuposMax jugadores'
                              : _cuposLlenos
                                  ? 'Cupos llenos · $_confirmados/$_cuposMax'
                                  : 'En espera · $_confirmados/$_cuposMax confirmados',
                          style: TextStyle(
                            color: _partidoConfirmado
                                ? Colors.green.shade800
                                : Colors.blue.shade800,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_partidoConfirmado)
                FilledButton.icon(
                  onPressed: _registrarCobros,
                  icon: const Icon(Icons.sports_tennis_rounded),
                  label: const Text('Ir a cobrar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    minimumSize: const Size.fromHeight(48),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _guardando ? null : _guardarStandby,
                        icon: _guardando
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.pause_circle_outline),
                        label: const Text('Dejar en espera'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _cuposLlenos && !_guardando
                            ? _confirmarPartido
                            : null,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Partido confirmado'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                  ],
                ),
                if (!_partidoConfirmado && !_cuposLlenos && _confirmados > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Faltan ${_cuposMax - _confirmados} confirmado(s) '
                      'para cerrar el partido ($_confirmados/$_cuposMax).',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildResumen() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_estaGuardada || _partidoConfirmado)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _partidoConfirmado
                      ? Colors.green.shade100
                      : Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      _partidoConfirmado ? Icons.check_circle : Icons.bookmark,
                      size: 16,
                      color: _partidoConfirmado
                          ? Colors.green.shade900
                          : Colors.blue.shade900,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _partidoConfirmado
                            ? 'Partido confirmado · visible en Inicio'
                            : 'Guardada en espera · visible en Inicio',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _partidoConfirmado
                              ? Colors.green.shade900
                              : Colors.blue.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Icon(Icons.groups, color: Colors.blue.shade700, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_confirmados / $_cuposMax confirmados',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: _cuposLlenos
                              ? Colors.orange.shade900
                              : Colors.blue.shade900,
                        ),
                      ),
                      Text(
                        _cuposLlenos
                            ? 'Cupos llenos · ${_invitados.length} invitados'
                            : '${_cuposDisponibles} cupo(s) disponible(s) · '
                                '${_invitados.length} invitados',
                        style: TextStyle(color: Colors.blue.shade800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatosPartido() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Datos del partido',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Fecha y hora'),
              subtitle: Text(_formatoFechaHora(_fechaPartido)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickFecha,
            ),
            TextField(
              controller: _recintoCtrl,
              onChanged: (_) => _marcarDirty(),
              decoration: InputDecoration(
                labelText: 'Recinto',
                prefixIcon: const Icon(Icons.place),
                suffixIcon: _recintosSugeridos.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        icon: const Icon(Icons.history),
                        tooltip: 'Recintos recientes',
                        itemBuilder: (_) => _recintosSugeridos
                            .map(
                              (r) => PopupMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onSelected: (v) => setState(() => _recintoCtrl.text = v),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cuposCtrl,
              onChanged: (_) => _marcarDirty(),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Cupos máximos',
                prefixIcon: Icon(Icons.people),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notasCtrl,
              onChanged: (_) => _marcarDirty(),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                prefixIcon: Icon(Icons.notes),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcciones() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: _enviarConvocatoria,
          icon: const Icon(Icons.campaign),
          label: const Text('Enviar convocatoria'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.green.shade700,
          ),
        ),
        OutlinedButton.icon(
          onPressed: _importarWhatsApp,
          icon: const Icon(Icons.content_paste),
          label: const Text('Importar chat'),
        ),
      ],
    );
  }

  Widget _buildListaJugadores() {
    if (_habituales.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.person_add, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              const Text('Agrega jugadores habituales primero'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => Navigator.pushNamed(context, '/jugadores'),
                child: const Text('Ir a Jugadores'),
              ),
            ],
          ),
        ),
      );
    }

    final todosInvitados = _habituales.every(
      (j) => j.id != null && _invitados.contains(j.id),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Jugadores',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                TextButton(
                  onPressed: () => _seleccionarTodos(!todosInvitados),
                  child: Text(todosInvitados ? 'Desmarcar todos' : 'Seleccionar todos'),
                ),
              ],
            ),
            const Text(
              'Marca invitados. Toca el estado: pendiente → confirmado → no va. '
              'Máximo de confirmados = cupos del partido.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            ..._habituales.map((j) {
              final id = j.id!;
              final invitado = _invitados.contains(id);
              final estado = _estados[id] ?? EstadoConfirmacion.invitado;
              return CheckboxListTile(
                value: invitado,
                onChanged: (v) => _toggleInvitado(id, v),
                title: Text(j.nombre),
                subtitle: j.telefono?.trim().isNotEmpty ?? false
                    ? Text(j.telefono!)
                    : null,
                secondary: invitado
                    ? _EstadoChip(
                        estado: estado,
                        onTap: () => _ciclarEstado(id),
                      )
                    : null,
                controlAffinity: ListTileControlAffinity.leading,
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _EstadoChip extends StatelessWidget {
  final EstadoConfirmacion estado;
  final VoidCallback onTap;

  const _EstadoChip({required this.estado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (estado) {
      EstadoConfirmacion.confirmado => (
          'Confirmado',
          Colors.green.shade700,
          Icons.check_circle,
        ),
      EstadoConfirmacion.rechazado => (
          'No va',
          Colors.red.shade700,
          Icons.cancel,
        ),
      EstadoConfirmacion.invitado => (
          'Pendiente',
          Colors.orange.shade700,
          Icons.hourglass_empty,
        ),
    };

    final bgColor = switch (estado) {
      EstadoConfirmacion.confirmado => Colors.green,
      EstadoConfirmacion.rechazado => Colors.red,
      EstadoConfirmacion.invitado => Colors.orange,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: bgColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
