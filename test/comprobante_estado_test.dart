import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/models/comprobante_estado.dart';
import 'package:matchpay/models/detalle_partido.dart';

DetallePartido _detalle({
  String? url,
  bool? validado,
  ComprobanteEstado? estado,
  double? declarado,
  bool pagado = false,
}) {
  return DetallePartido(
    partidoId: 1,
    total: 10000,
    pagado: pagado,
    comprobanteUrl: url,
    comprobanteValidado: validado,
    comprobanteEstado: estado,
    montoPagoDeclarado: declarado,
  );
}

void main() {
  group('comprobantePendienteValidacion / histórico', () {
    test('en_revision es pendiente aunque tenga URL', () {
      final d = _detalle(
        url: 'uuid/file.jpg',
        estado: ComprobanteEstado.enRevision,
        declarado: 5000,
      );
      expect(d.comprobantePendienteValidacion, isTrue);
      expect(d.comprobanteEsHistorico, isFalse);
    });

    test('aprobado con URL no es pendiente (histórico)', () {
      final d = _detalle(
        url: 'uuid/file.jpg',
        validado: true,
        estado: ComprobanteEstado.aprobado,
      );
      expect(d.comprobantePendienteValidacion, isFalse);
      expect(d.comprobanteEsHistorico, isTrue);
    });

    test('rechazado con URL no vuelve a la cola', () {
      final d = _detalle(
        url: 'uuid/file.jpg',
        validado: false,
        estado: ComprobanteEstado.rechazado,
      );
      expect(d.comprobantePendienteValidacion, isFalse);
      expect(d.comprobanteEsHistorico, isTrue);
    });

    test('legacy: URL + no validado → en revisión', () {
      final d = _detalle(url: 'uuid/file.jpg', validado: false);
      expect(d.comprobantePendienteValidacion, isTrue);
    });

    test('legacy: validado true → no pendiente', () {
      final d = _detalle(url: null, validado: true);
      expect(d.comprobantePendienteValidacion, isFalse);
      expect(d.comprobanteEsHistorico, isFalse);
    });
  });
}
