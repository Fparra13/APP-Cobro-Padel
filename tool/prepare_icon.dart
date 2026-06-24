import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() {
  const input = 'assets/icon/app_icon_raw.png';
  const output = 'assets/icon/app_icon_square.png';
  const size = 1024;
  final bg = img.ColorRgba8(25, 118, 210, 255);

  final source = img.decodePng(File(input).readAsBytesSync());
  if (source == null) {
    stderr.writeln('No se pudo leer $input');
    exit(1);
  }

  // Escala para cubrir un cuadrado y recorta el centro.
  final side = math.min(source.width, source.height);
  var working = source;
  if (source.width != source.height) {
    final scale = size / side;
    final targetW = (source.width * scale).round();
    final targetH = (source.height * scale).round();
    working = img.copyResize(source, width: targetW, height: targetH);
    final cropSide = math.min(working.width, working.height);
    final left = (working.width - cropSide) ~/ 2;
    final top = (working.height - cropSide) ~/ 2;
    working = img.copyCrop(
      working,
      x: left,
      y: top,
      width: cropSide,
      height: cropSide,
    );
  }

  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: bg);
  final resized = img.copyResize(working, width: size, height: size);
  img.compositeImage(canvas, resized);

  File(output).writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Generado: $output (${size}x$size)');
}
