import 'package:flutter_test/flutter_test.dart';

import 'package:matchpay/domain/convocatoria_plazo_respuesta.dart';

void main() {
  test('partido hoy en 10 h → plazos cortos hasta 4 h', () {
    final now = DateTime(2026, 7, 10, 10, 0);
    final partido = DateTime(2026, 7, 10, 20, 0);
    expect(
      ConvocatoriaPlazoRespuesta.opcionesPermitidas(partido, now),
      [1, 2, 4],
    );
    expect(ConvocatoriaPlazoRespuesta.sugerirHoras(partido, now), 4);
  });

  test('partido en 23 h → plazos cortos hasta 12 h', () {
    final now = DateTime(2026, 7, 10, 21, 0);
    final partido = DateTime(2026, 7, 11, 20, 0);
    expect(
      ConvocatoriaPlazoRespuesta.opcionesPermitidas(partido, now),
      [1, 2, 4, 6, 8, 12],
    );
  });

  test('sábado → lunes (>24 h) → plazos extendidos sin 1–2 h', () {
    final now = DateTime(2026, 7, 11, 10, 0); // sábado
    final partido = DateTime(2026, 7, 13, 20, 0); // lunes
    expect(ConvocatoriaPlazoRespuesta.partidoLejano(partido, now), isTrue);
    expect(
      ConvocatoriaPlazoRespuesta.opcionesPermitidas(partido, now),
      [8, 12, 24],
    );
    expect(ConvocatoriaPlazoRespuesta.sugerirHoras(partido, now), 24);
  });

  test('tiempo límite no supera 6 h antes del partido', () {
    final now = DateTime(2026, 7, 10, 14, 0);
    final partido = DateTime(2026, 7, 10, 20, 0);
    final limite = ConvocatoriaPlazoRespuesta.calcularTiempoLimite(
      enviadoEn: now,
      horasLimite: 24,
      fechaPartido: partido,
    );
    expect(limite, DateTime(2026, 7, 10, 14, 0));
  });
}
