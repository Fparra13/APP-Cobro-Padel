import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/jugador_foto_service.dart';

class JugadorAvatar extends StatefulWidget {
  final String nombre;
  final String? fotoPath;
  final String? fotoUrl;
  final double size;
  final double borderRadius;
  final bool showBorder;
  final Color? borderColor;

  const JugadorAvatar({
    super.key,
    required this.nombre,
    this.fotoPath,
    this.fotoUrl,
    this.size = 52,
    this.borderRadius = 14,
    this.showBorder = false,
    this.borderColor,
  });

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

  static Color colorDe(String nombre) =>
      _avatarColors[nombre.hashCode.abs() % _avatarColors.length];

  static String inicialDe(String nombre) {
    final t = nombre.trim();
    return t.isNotEmpty ? t[0].toUpperCase() : '?';
  }

  @override
  State<JugadorAvatar> createState() => _JugadorAvatarState();
}

class _JugadorAvatarState extends State<JugadorAvatar> {
  File? _localFile;
  String? _networkUrl;
  bool _networkFailed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(JugadorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fotoPath != widget.fotoPath ||
        oldWidget.fotoUrl != widget.fotoUrl) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    _networkFailed = false;

    final localPath = await JugadorFotoService.instance.resolveFile(widget.fotoPath);
    if (generation != _loadGeneration || !mounted) return;

    final url = widget.fotoUrl?.trim();
    final hasUrl = url != null && url.isNotEmpty && url.startsWith('http');

    if (localPath != null) {
      setState(() {
        _localFile = localPath;
        _networkUrl = null;
      });
      return;
    }

    File? cachedNetwork;
    if (hasUrl) {
      cachedNetwork =
          await JugadorFotoService.instance.resolveCachedNetworkAvatar(url);
    }
    if (generation != _loadGeneration || !mounted) return;

    if (cachedNetwork != null) {
      setState(() {
        _localFile = cachedNetwork;
        _networkUrl = null;
      });
      return;
    }

    setState(() {
      _localFile = null;
      _networkUrl = hasUrl ? url : null;
    });

    if (!hasUrl) return;

    unawaited(
      JugadorFotoService.instance.cacheNetworkAvatar(url).then((file) {
        if (generation != _loadGeneration || !mounted || file == null) return;
        setState(() {
          _localFile = file;
          _networkUrl = null;
          _networkFailed = false;
        });
      }),
    );
  }

  void _onNetworkError() {
    if (mounted) setState(() => _networkFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final color = JugadorAvatar.colorDe(widget.nombre);
    final inicial = JugadorAvatar.inicialDe(widget.nombre);
    final hasLocal = _localFile != null;
    final hasNetwork = _networkUrl != null && !_networkFailed;
    final hasPhoto = hasLocal || hasNetwork;

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        gradient: hasPhoto
            ? null
            : LinearGradient(
                colors: [color, color.withValues(alpha: 0.75)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: widget.showBorder
            ? Border.all(
                color: widget.borderColor ?? Colors.white.withValues(alpha: 0.35),
                width: 2,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLocal
          ? Image.file(_localFile!, fit: BoxFit.cover)
          : hasNetwork
              ? Image.network(
                  _networkUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) {
                    _onNetworkError();
                    return _initials(inicial, color);
                  },
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: SizedBox(
                        width: widget.size * 0.35,
                        height: widget.size * 0.35,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: color,
                        ),
                      ),
                    );
                  },
                )
              : _initials(inicial, color),
    );
  }

  Widget _initials(String inicial, Color color) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        inicial,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.size * 0.42,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
