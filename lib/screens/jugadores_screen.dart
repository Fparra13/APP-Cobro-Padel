import 'package:flutter/material.dart';

import '../models/jugador.dart';
import '../repositories/jugador_repository.dart';
import '../utils/formatters.dart';
import '../widgets/ayuda_tip.dart';

class JugadoresScreen extends StatefulWidget {
  const JugadoresScreen({super.key});

  @override
  State<JugadoresScreen> createState() => _JugadoresScreenState();
}

class _JugadoresScreenState extends State<JugadoresScreen> {
  final _repo = JugadorRepository();
  List<Jugador> _jugadores = [];
  bool _loading = true;

  static const _avatarColors = [
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFF00838F),
    Color(0xFFEF6C00),
    Color(0xFFC62828),
    Color(0xFF4527A0),
    Color(0xFF558B2F),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _repo.getAll();
    if (mounted) {
      setState(() {
        _jugadores = list;
        _loading = false;
      });
    }
  }

  Color _colorDe(String nombre) =>
      _avatarColors[nombre.hashCode.abs() % _avatarColors.length];

  Future<void> _showForm({Jugador? jugador}) async {
    final nombreCtrl = TextEditingController(text: jugador?.nombre ?? '');
    final telefonoCtrl = TextEditingController(text: jugador?.telefono ?? '');
    final activo = ValueNotifier(jugador?.activo ?? true);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          jugador == null ? Icons.person_add_alt_1 : Icons.edit,
          color: Theme.of(ctx).colorScheme.primary,
          size: 32,
        ),
        title: Text(jugador == null ? 'Nuevo jugador' : 'Editar jugador'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: telefonoCtrl,
              decoration: const InputDecoration(
                labelText: 'WhatsApp (opcional)',
                hintText: '56912345678',
                prefixIcon: Icon(Icons.phone_android, color: Colors.green),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: activo,
              builder: (_, value, _) => SwitchListTile(
                secondary: Icon(
                  value ? Icons.star : Icons.star_border,
                  color: value ? Colors.amber.shade700 : Colors.grey,
                ),
                title: const Text('Jugador habitual'),
                subtitle: const Text('Aparece al crear un partido'),
                value: value,
                onChanged: (v) => activo.value = v,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (nombreCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    final now = DateTime.now();
    if (jugador == null) {
      await _repo.insert(Jugador(
        nombre: nombreCtrl.text.trim(),
        activo: activo.value,
        telefono: telefonoCtrl.text.trim().isEmpty
            ? null
            : telefonoCtrl.text.trim(),
        createdAt: now,
      ));
    } else {
      await _repo.update(jugador.copyWith(
        nombre: nombreCtrl.text.trim(),
        activo: activo.value,
        telefono: telefonoCtrl.text.trim().isEmpty
            ? null
            : telefonoCtrl.text.trim(),
      ));
    }
    _load();
  }

  Future<void> _confirmDelete(Jugador j) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 36),
        title: const Text('Eliminar jugador'),
        content: Text('¿Eliminar a ${j.nombre}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('No'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.delete(j.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final activos = _jugadores.where((j) => j.activo).length;
    final conDeuda = _jugadores.where((j) => j.saldoAcumulado > 0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('👥 Jugadores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _jugadores.isEmpty
                  ? ListView(
                      children: [
                        _buildEmptyState(),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      children: [
                        _buildResumen(activos, conDeuda),
                        const SizedBox(height: 12),
                        const AyudaTip(
                          texto:
                              'Los habituales ⭐ aparecen al crear un partido. '
                              'Agrega WhatsApp para enviar informes directo.',
                        ),
                        const SizedBox(height: 12),
                        ..._jugadores.map(_buildJugadorCard),
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo jugador'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 80),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.groups_rounded,
              size: 72,
              color: Colors.green.shade700,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Sin jugadores aún',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Agrega a tu grupo de pádel para empezar\na registrar partidos y cobros.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showForm(),
            icon: const Icon(Icons.person_add),
            label: const Text('Agregar primer jugador'),
          ),
        ],
      ),
    );
  }

  Widget _buildResumen(int activos, int conDeuda) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade700, Colors.green.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade900.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ResumenChip(
            icon: Icons.people_alt_rounded,
            label: 'Total',
            value: '${_jugadores.length}',
          ),
          _ResumenChip(
            icon: Icons.star_rounded,
            label: 'Habituales',
            value: '$activos',
          ),
          _ResumenChip(
            icon: Icons.account_balance_wallet_rounded,
            label: 'Con deuda',
            value: '$conDeuda',
          ),
        ],
      ),
    );
  }

  Widget _buildJugadorCard(Jugador j) {
    final color = _colorDe(j.nombre);
    final deuda = j.saldoAcumulado > 0;
    final conFavor = j.saldoAcumulado < 0;
    final inicial = j.nombre.trim().isNotEmpty
        ? j.nombre.trim()[0].toUpperCase()
        : '?';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pushNamed(context, '/historial', arguments: j.id),
        onLongPress: () => _showForm(jugador: j),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.35),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  inicial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          j.nombre,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (j.activo) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.star_rounded,
                            size: 18, color: Colors.amber.shade700),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MiniChip(
                        icon: j.activo ? Icons.check_circle : Icons.pause_circle,
                        label: j.activo ? 'Habitual' : 'Inactivo',
                        color: j.activo ? Colors.green : Colors.grey,
                      ),
                      if (j.telefono != null && j.telefono!.isNotEmpty)
                        _MiniChip(
                          icon: Icons.phone_android,
                          label: 'WhatsApp',
                          color: Colors.teal,
                        ),
                    ],
                  ),
                  if (deuda) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Debe: ${formatMoney(j.saldoAcumulado)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ] else if (conFavor) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Saldo a favor: ${formatMoney(-j.saldoAcumulado)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      'Toca para ver ficha',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.edit_rounded, size: 22),
                  tooltip: 'Editar',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue.shade700,
                  ),
                  onPressed: () => _showForm(jugador: j),
                ),
                const SizedBox(height: 4),
                IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline_rounded, size: 22),
                  tooltip: 'Eliminar',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red.shade700,
                  ),
                  onPressed: () => _confirmDelete(j),
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ResumenChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ResumenChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 26),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final MaterialColor color;

  const _MiniChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.shade800,
            ),
          ),
        ],
      ),
    );
  }
}
