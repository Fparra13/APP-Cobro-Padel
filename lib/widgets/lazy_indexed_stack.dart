import 'package:flutter/material.dart';

/// [IndexedStack] que solo construye cada pestaña la primera vez que se visita.
class LazyIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget Function()> itemBuilders;
  /// Si cambia (p. ej. deporte o idioma), se invalida la caché de pestañas.
  final Object? cacheKey;

  const LazyIndexedStack({
    super.key,
    required this.index,
    required this.itemBuilders,
    this.cacheKey,
  });

  @override
  State<LazyIndexedStack> createState() => _LazyIndexedStackState();
}

class _LazyIndexedStackState extends State<LazyIndexedStack> {
  final Set<int> _visited = {};
  final Map<int, Widget> _cache = {};
  Object? _lastCacheKey;

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _cache.clear();
      _visited.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_lastCacheKey != widget.cacheKey) {
      _cache.clear();
      _visited.clear();
      _lastCacheKey = widget.cacheKey;
    }

    _visited.add(widget.index);
    for (final i in _visited) {
      _cache.putIfAbsent(i, widget.itemBuilders[i]);
    }

    return IndexedStack(
      index: widget.index,
      children: List.generate(
        widget.itemBuilders.length,
        (i) => _cache[i] ?? const SizedBox.shrink(),
      ),
    );
  }
}
