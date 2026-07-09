import 'package:flutter/material.dart';

import '../core/app_repositories.dart';
import '../l10n/matchpay_strings.dart';
import '../models/recinto.dart';

/// Abre el administrador de recintos (agregar / eliminar).
Future<List<Recinto>?> showMisRecintosManager(BuildContext context) {
  return showModalBottomSheet<List<Recinto>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      minChildSize: 0.45,
      builder: (_, scroll) => MisRecintosPanel(
        scrollController: scroll,
        asSheet: true,
      ),
    ),
  );
}

/// Lista de recintos del organizador: alta y baja.
class MisRecintosPanel extends StatefulWidget {
  final ScrollController? scrollController;
  final bool asSheet;

  const MisRecintosPanel({
    super.key,
    this.scrollController,
    this.asSheet = false,
  });

  @override
  State<MisRecintosPanel> createState() => _MisRecintosPanelState();
}

class _MisRecintosPanelState extends State<MisRecintosPanel> {
  List<Recinto> _recintos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!AppRepositories.isReady) {
        throw Exception('Sin conexión');
      }
      final list = await AppRepositories.I.getMisRecintos();
      if (mounted) {
        setState(() {
          _recintos = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = context.userError(e);
        });
      }
    }
  }

  Future<void> _agregar() async {
    final creado = await showModalBottomSheet<Recinto>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const AgregarRecintoSheet(),
    );
    if (creado != null && mounted) {
      setState(() {
        _recintos = [..._recintos, creado]
          ..sort((a, b) => a.nombre.compareTo(b.nombre));
      });
    }
  }

  Future<void> _eliminar(Recinto recinto) async {
    final id = recinto.id;
    if (id == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.tr('venueDeleteTitle')),
        content: Text(
          ctx.l10n.tr(
            'venueDeleteBody',
            params: {'name': recinto.nombre},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: Text(ctx.l10n.tr('deleteTooltip')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await AppRepositories.I.eliminarRecinto(id);
      if (!mounted) return;
      setState(() {
        _recintos = _recintos.where((r) => r.id != id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tr('venueDeleted'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.userError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _abrirMapa(Recinto recinto) async {
    try {
      final ok = await recinto.location.open();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('openVenueMapError'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('openVenueMapError'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.tr('venuesSectionTitle'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            if (widget.asSheet)
              TextButton(
                onPressed: () => Navigator.pop(context, _recintos),
                child: Text(l10n.tr('close')),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.tr('venuesSectionSubtitle'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: _agregar,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: Text(l10n.tr('venueAddNew')),
        ),
        const SizedBox(height: 12),
      ],
    );

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _load, child: Text(l10n.tr('retry'))),
          ],
        ),
      );
    } else if (_recintos.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          l10n.tr('venuesEmpty'),
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    } else {
      body = Column(
        children: _recintos.map((r) {
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                r.location.hasExactLocation
                    ? Icons.place
                    : Icons.place_outlined,
                color: r.location.hasExactLocation
                    ? Colors.green.shade700
                    : Colors.grey,
              ),
              title: Text(
                r.nombre,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                r.direccion?.isNotEmpty == true
                    ? r.direccion!
                    : (r.location.hasExactLocation
                        ? l10n.tr('venueHasExactMap')
                        : l10n.tr('venueNoExactMap')),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.tr('openVenueMapTooltip'),
                    icon: const Icon(Icons.map_outlined),
                    onPressed: () => _abrirMapa(r),
                  ),
                  IconButton(
                    tooltip: l10n.tr('deleteTooltip'),
                    icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
                    onPressed: () => _eliminar(r),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    final content = Padding(
      padding: EdgeInsets.fromLTRB(widget.asSheet ? 16 : 0, 0, widget.asSheet ? 16 : 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          body,
        ],
      ),
    );

    if (widget.scrollController != null) {
      return ListView(
        controller: widget.scrollController,
        children: [content],
      );
    }
    return content;
  }
}

class AgregarRecintoSheet extends StatefulWidget {
  final String nombreInicial;

  const AgregarRecintoSheet({super.key, this.nombreInicial = ''});

  @override
  State<AgregarRecintoSheet> createState() => _AgregarRecintoSheetState();
}

class _AgregarRecintoSheetState extends State<AgregarRecintoSheet> {
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _mapsCtrl;
  late final TextEditingController _direccionCtrl;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.nombreInicial);
    _mapsCtrl = TextEditingController();
    _direccionCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _mapsCtrl.dispose();
    _direccionCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      if (!AppRepositories.isReady) {
        throw Exception('Sin conexión a Supabase');
      }
      final recinto = await AppRepositories.I.crearRecinto(
        nombre: _nombreCtrl.text,
        mapsInput: _mapsCtrl.text,
        direccion: _direccionCtrl.text.trim().isEmpty
            ? null
            : _direccionCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, recinto);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.userError(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.tr('venueAddTitle'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.tr('venueAddHelp'),
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nombreCtrl,
            decoration: InputDecoration(
              labelText: context.l10n.tr('venueLabelRequired'),
              prefixIcon: const Icon(Icons.place),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _mapsCtrl,
            decoration: InputDecoration(
              labelText: context.l10n.tr('venueMapsLinkLabel'),
              hintText: context.l10n.tr('venueMapsLinkHint'),
              prefixIcon: const Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _direccionCtrl,
            decoration: InputDecoration(
              labelText: context.l10n.tr('venueAddressOptional'),
              prefixIcon: const Icon(Icons.home_work_outlined),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(context.l10n.tr('venueSave')),
          ),
        ],
      ),
    );
  }
}
