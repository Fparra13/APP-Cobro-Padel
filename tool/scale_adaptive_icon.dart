import 'dart:io';

import 'package:image/image.dart' as img;

/// Escala el icono para llenar la máscara circular de Android.
void main() {
  const source = 'assets/icon/Icono APP Padel Cobro.png';
  const output = 'assets/icon/app_icon_full.png';
  /// Escala fija: el diseño original es un cuadrado redondeado ~82% del canvas.
  const coverScale = 1.24;
  final bg = img.ColorRgba8(30, 126, 200, 255);

  final bytes = File(source).readAsBytesSync();
  final image = img.decodePng(bytes);
  if (image == null) {
    stderr.writeln('No se pudo leer $source');
    exit(1);
  }

  final size = image.width;
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: bg);

  final newSize = (size * coverScale).round();
  final resized = img.copyResize(image, width: newSize, height: newSize);
  final offset = (size - newSize) ~/ 2;
  img.compositeImage(canvas, resized, dstX: offset, dstY: offset);

  File(output).writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Generado: $output (escala ${coverScale}x)');
}
