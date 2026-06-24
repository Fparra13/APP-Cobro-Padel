import 'dart:io';

import 'package:flutter/material.dart';

import '../services/jugador_foto_service.dart';

class JugadorAvatar extends StatefulWidget {
  final String nombre;
  final String? fotoPath;
  final double size;
  final double borderRadius;
  final bool showBorder;
  final Color? borderColor;

  const JugadorAvatar({
    super.key,
    required this.nombre,
    this.fotoPath,
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
  File? _file;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(JugadorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fotoPath != widget.fotoPath) {
      _load();
    }
  }

  Future<void> _load() async {
    final file = await JugadorFotoService.instance.resolveFile(widget.fotoPath);
    if (mounted) setState(() => _file = file);
  }

  @override
  Widget build(BuildContext context) {
    final color = JugadorAvatar.colorDe(widget.nombre);
    final inicial = JugadorAvatar.inicialDe(widget.nombre);
    final hasPhoto = _file != null;

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
        image: hasPhoto
            ? DecorationImage(
                image: FileImage(_file!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: hasPhoto
          ? null
          : Center(
              child: Text(
                inicial,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: widget.size * 0.42,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
    );
  }
}
