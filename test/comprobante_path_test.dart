import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/utils/comprobante_path.dart';

void main() {
  group('comprobante_path', () {
    test('detecta path de Storage (uuid/…)', () {
      expect(
        isCloudComprobantePath(
          '94a48fee-6382-45fd-a724-60adbfd115dd/gastos/12/1.jpg',
        ),
        isTrue,
      );
      expect(
        isCloudComprobantePath(
          '94a48fee-6382-45fd-a724-60adbfd115dd/171000.jpg',
        ),
        isTrue,
      );
    });

    test('detecta path local Documents', () {
      expect(isLocalComprobantePath('comprobantes/171000.jpg'), isTrue);
      expect(isCloudComprobantePath('comprobantes/171000.jpg'), isFalse);
    });

    test('null o vacío no son cloud', () {
      expect(isCloudComprobantePath(null), isFalse);
      expect(isCloudComprobantePath(''), isFalse);
      expect(isCloudComprobantePath('solo-nombre.jpg'), isFalse);
    });
  });
}
