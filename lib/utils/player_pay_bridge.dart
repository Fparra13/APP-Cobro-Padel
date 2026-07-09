/// Puente para lanzar pagos desde el home hacia [MisCobrosScreen].
class PlayerPayBridge {
  PlayerPayBridge._();

  static final PlayerPayBridge instance = PlayerPayBridge._();

  Future<void> Function()? _payTotalHandler;
  Future<void> Function()? _payOtherHandler;

  void registerPayTotalHandler(Future<void> Function() handler) {
    _payTotalHandler = handler;
  }

  void registerPayOtherHandler(Future<void> Function() handler) {
    _payOtherHandler = handler;
  }

  void unregisterPayTotalHandler() {
    _payTotalHandler = null;
  }

  void unregisterPayOtherHandler() {
    _payOtherHandler = null;
  }

  /// `true` si había pantalla de cobros registrada y se inició el flujo.
  Future<bool> requestPayTotal() async {
    final handler = _payTotalHandler;
    if (handler == null) return false;
    await handler();
    return true;
  }

  /// `true` si había pantalla de cobros registrada y se inició el flujo.
  Future<bool> requestPayOther() async {
    final handler = _payOtherHandler;
    if (handler == null) return false;
    await handler();
    return true;
  }
}
