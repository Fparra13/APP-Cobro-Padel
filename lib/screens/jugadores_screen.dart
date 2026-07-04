import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/jugador.dart';
import '../services/jugador_foto_service.dart';
import '../utils/formatters.dart';
import '../widgets/ayuda_tip.dart';
import '../utils/nav_shell_layout.dart';
import '../widgets/jugador_avatar.dart';
import 'estadisticas_jugadores_screen.dart';

class JugadoresScreen extends StatefulWidget {
  const JugadoresScreen({super.key});

  @override
  State<JugadoresScreen> createState() => _JugadoresScreenState();
}

class _JugadoresScreenState extends State<JugadoresScreen> {
  final _fotoService = JugadorFotoService.instance;
  List<Jugador> _jugadores = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await context.repos.getJugadores();
    if (mounted) {
      setState(() {
        _jugadores = list;
        _loading = false;
      });
    }
  }

  Future<void> _showForm({Jugador? jugador}) async {
    final nombreCtrl = TextEditingController(text: jugador?.nombre ?? '');
    final emailCtrl = TextEditingController(text: jugador?.contactEmail ?? '');
    final activo = ValueNotifier(jugador?.activo ?? true);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
        icon: Icon(
          jugador == null ? Icons.person_add_alt_1 : Icons.edit,
          color: Theme.of(ctx).colorScheme.primary,
          size: 32,
        ),
        title: Text(jugador == null ? l10n.tr('newPlayer') : l10n.tr('editPlayer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: InputDecoration(
                labelText: l10n.tr('nameLabel'),
                prefixIcon: const Icon(Icons.badge_outlined),
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
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
            ValueListenableBuilder(
              valueListenable: activo,
              builder: (_, value, _) => SwitchListTile(
                secondary: Icon(
                  value ? Icons.star : Icons.star_border,
                  color: value ? Colors.amber.shade700 : Colors.grey,
                ),
                title: Text(l10n.tr('regularPlayer')),
                subtitle: Text(l10n.tr('regularPlayerSubtitle')),
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
            child: Text(l10n.tr('cancel')),
          ),
          FilledButton.icon(
            onPressed: () {
              if (nombreCtrl.text.trim().isEmpty) return;
              if (emailCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.save),
            label: Text(l10n.tr('save')),
          ),
        ],
      );
      },
    );

    if (saved != true || !mounted) return;

    final now = DateTime.now();
    final email = emailCtrl.text.trim().toLowerCase();
    try {
      if (jugador == null) {
        await context.repos.insertJugador(Jugador(
          nombre: nombreCtrl.text.trim(),
          activo: activo.value,
          email: email,
          createdAt: now,
        ));
      } else {
        await context.repos.updateJugador(jugador.copyWith(
          nombre: nombreCtrl.text.trim(),
          activo: activo.value,
          email: email,
        ));
      }
      if (mounted) {
        _load();
        final l10n = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              jugador == null
                  ? l10n.tr('playerAdded')
                  : l10n.tr(
                      'playerDataSaved',
                      params: {'name': nombreCtrl.text.trim()},
                    ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 12),
            action: SnackBarAction(
              label: context.l10n.tr('close'),
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(Jugador j) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) {
        final l10n = c.l10n;
        return AlertDialog(
        icon: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 36),
        title: Text(l10n.tr('deletePlayerTitle')),
        content: Text(l10n.tr('deletePlayerMessage', params: {'name': j.nombre})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.tr('no')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.tr('yesDelete')),
          ),
        ],
      );
      },
    );
    if (confirm == true) {
      await _fotoService.delete(j.fotoPath);
      await context.repos.deleteJugador(j.keyId);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activos = _jugadores.where((j) => j.activo).length;
    final conDeuda = _jugadores.where((j) => j.saldoAcumulado > 0).length;

    return ShellTabScaffold(
      appBar: AppBar(
        title: Text('👥 ${l10n.tr('playersScreenTitle')}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: l10n.tr('statsTooltip'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const EstadisticasJugadoresScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.tr('refreshTooltip'),
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
                      padding: NavShellScope.listPadding(
                        context,
                        left: 12,
                        top: 12,
                        right: 12,
                      ),
                      children: [
                        _buildResumen(activos, conDeuda),
                        const SizedBox(height: 12),
                        AyudaTip(texto: l10n.tr('playersHelpTip')),
                        const SizedBox(height: 12),
                        ..._jugadores.map(_buildJugadorCard),
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.person_add),
        label: Text(l10n.tr('newPlayer')),
      ),
    );
  }

  Widget _buildEmptyState() {
    final l10n = context.l10n;

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
            l10n.tr('playersEmptyTitle'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.tr('playersEmptySubtitle'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showForm(),
            icon: const Icon(Icons.person_add),
            label: Text(l10n.tr('addFirstPlayer')),
          ),
        ],
      ),
    );
  }

  Widget _buildResumen(int activos, int conDeuda) {
    final l10n = context.l10n;

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
            label: l10n.tr('total'),
            value: '${_jugadores.length}',
          ),
          _ResumenChip(
            icon: Icons.star_rounded,
            label: l10n.tr('regulars'),
            value: '$activos',
          ),
          _ResumenChip(
            icon: Icons.account_balance_wallet_rounded,
            label: l10n.tr('withDebt'),
            value: '$conDeuda',
          ),
        ],
      ),
    );
  }

  Widget _buildJugadorCard(Jugador j) {
    final l10n = context.l10n;
    final deuda = j.saldoAcumulado > 0;
    final conFavor = j.saldoAcumulado < 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pushNamed(context, '/historial', arguments: j.keyId),
        onLongPress: () => _showForm(jugador: j),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
          children: [
            JugadorAvatar(
              nombre: j.nombre,
              fotoPath: j.fotoPath,
              fotoUrl: j.fotoUrl,
              size: 52,
              borderRadius: 14,
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
                        label: j.activo ? l10n.tr('statusRegular') : l10n.tr('statusInactive'),
                        color: j.activo ? Colors.green : Colors.grey,
                      ),
                      if (j.contactEmail != null)
                        _MiniChip(
                          icon: Icons.email_outlined,
                          label: j.contactEmail!,
                          color: Colors.teal,
                        ),
                    ],
                  ),
                  if (deuda) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${l10n.tr('statusOwes')}: ${formatMoney(j.saldoAcumulado)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ] else if (conFavor) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${l10n.tr('statusCredit')}: ${formatMoney(-j.saldoAcumulado)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.tr('tapToViewProfile'),
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
                  tooltip: l10n.tr('editTooltip'),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.blue.shade50,
                    foregroundColor: Colors.blue.shade700,
                  ),
                  onPressed: () => _showForm(jugador: j),
                ),
                const SizedBox(height: 4),
                IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline_rounded, size: 22),
                  tooltip: l10n.tr('deleteTooltip'),
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
