import 'package:flutter_test/flutter_test.dart';

import 'package:matchpay/domain/convocatoria_plazo_respuesta.dart';

void main() {
  test('partido hoy en 10 h → opciones hasta 8 h (no 12)', () {
    final now = DateTime(2026, 7, 10, 10, 0);
    final partido = DateTime(2026, 7, 10, 20, 0);
    expect(
      ConvocatoriaPlazoRespuesta.opcionesPermitidas(partido, now),
      [1, 2, 4, 6, 8],
    );
    expect(ConvocatoriaPlazoRespuesta.sugerirHoras(partido, now), 8);
  });

  test('partido en ~2 h → solo 1 y 2 h (no 12)', () {
    final now = DateTime(2026, 7, 16, 20, 28);
    final partido = DateTime(2026, 7, 16, 22, 35);
    expect(
      ConvocatoriaPlazoRespuesta.opcionesPermitidas(partido, now),
      [1, 2],
    );
    expect(
      ConvocatoriaPlazoRespuesta.calcularTiempoLimite(
        enviadoEn: now,
        horasLimite: 1,
        fechaPartido: partido,
      ),
      DateTime(2026, 7, 16, 21, 28),
    );
    expect(
      ConvocatoriaPlazoRespuesta.calcularTiempoLimite(
        enviadoEn: now,
        horasLimite: 2,
        fechaPartido: partido,
      ),
      DateTime(2026, 7, 16, 22, 28),
    );
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

  test('ajustarHoras: plazo 2 h guardado con partido lejano → 24', () {
    final now = DateTime(2026, 7, 16, 18, 0);
    final partido = DateTime(2026, 7, 21, 20, 0);
    expect(
      ConvocatoriaPlazoRespuesta.ajustarHoras(2, partido, now),
      24,
    );
  });

  test('1 h → 2 h cambia el límite (now + horas)', () {
    final now = DateTime(2026, 7, 10, 20, 30);
    final partido = DateTime(2026, 7, 10, 22, 35);
    final unaHora = ConvocatoriaPlazoRespuesta.calcularTiempoLimite(
      enviadoEn: now,
      horasLimite: 1,
      fechaPartido: partido,
    );
    final dosHoras = ConvocatoriaPlazoRespuesta.calcularTiempoLimite(
      enviadoEn: now,
      horasLimite: 2,
      fechaPartido: partido,
    );
    expect(unaHora, DateTime(2026, 7, 10, 21, 30));
    expect(dosHoras, DateTime(2026, 7, 10, 22, 30));
  });
}
