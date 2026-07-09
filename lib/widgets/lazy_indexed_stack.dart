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

  void _invalidateCacheIfNeeded() {
    if (_lastCacheKey != widget.cacheKey) {
      _cache.clear();
      _visited.clear();
      _lastCacheKey = widget.cacheKey;
    }
  }

  @override
  void didUpdateWidget(LazyIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheKey != widget.cacheKey) {
      _invalidateCacheIfNeeded();
    }
  }

  Widget _childForIndex(int i) {
    return _cache.putIfAbsent(i, widget.itemBuilders[i]);
  }

  @override
  Widget build(BuildContext context) {
    _invalidateCacheIfNeeded();
    _visited.add(widget.index);

    return IndexedStack(
      index: widget.index,
      sizing: StackFit.expand,
      children: List.generate(widget.itemBuilders.length, (i) {
        if (!_visited.contains(i)) {
          return const SizedBox.shrink();
        }
        final child = RepaintBoundary(child: _childForIndex(i));
        return TickerMode(
          enabled: i == widget.index,
          child: child,
        );
      }),
    );
  }
}
