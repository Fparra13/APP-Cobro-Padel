/// Puente para lanzar pagos desde el home hacia [MisCobrosScreen].
///
/// Los handlers deben devolver `true` solo si iniciaron el flujo de pago
/// (p. ej. una sola cuenta con deuda). Con varias cuentas, Mis Cobros
/// solo muestra la lista y devuelve `false`.
class PlayerPayBridge {
  PlayerPayBridge._();

  static final PlayerPayBridge instance = PlayerPayBridge._();

  Future<bool> Function()? _payTotalHandler;
  Future<bool> Function()? _payOtherHandler;

  void registerPayTotalHandler(Future<bool> Function() handler) {
    _payTotalHandler = handler;
  }

  void registerPayOtherHandler(Future<bool> Function() handler) {
    _payOtherHandler = handler;
  }

  void unregisterPayTotalHandler() {
    _payTotalHandler = null;
  }

  void unregisterPayOtherHandler() {
    _payOtherHandler = null;
  }

  /// `true` si el handler inició el pago.
  Future<bool> requestPayTotal() async {
    final handler = _payTotalHandler;
    if (handler == null) return false;
    return handler();
  }

  /// `true` si el handler inició el pago.
  Future<bool> requestPayOther() async {
    final handler = _payOtherHandler;
    if (handler == null) return false;
    return handler();
  }
}
