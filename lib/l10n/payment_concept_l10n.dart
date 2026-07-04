import 'translation_maps.dart';

/// Traduce conceptos de movimiento guardados en BD (a menudo en español)
/// al idioma activo de la app.
class PaymentConceptL10n {
  PaymentConceptL10n._();

  static const _knownKeys = [
    'paymentConceptWithCredit',
    'paymentConceptFull',
    'paymentConceptPartial',
    'historicalAccumulatedDebt',
    'historicalPartialPayment',
    'historicalMatchPaid',
    'historicalMatchCoveredByCredit',
    'historicalManualPayment',
    'historicalPaymentValidatedOrganizer',
    'historicalPartialValidatedOrganizer',
    'historicalMovement',
  ];

  static const _langs = ['es', 'en', 'pt'];

  /// Textos antiguos en BD (antes de renombrar conceptos).
  static const _legacyToKey = {
    'Deuda acumulada': 'historicalAccumulatedDebt',
    'Accumulated debt': 'historicalAccumulatedDebt',
    'Dívida acumulada': 'historicalAccumulatedDebt',
    'Pago validado por organizador': 'historicalPaymentValidatedOrganizer',
    'Payment validated by organizer': 'historicalPaymentValidatedOrganizer',
    'Pagamento validado pelo organizador':
        'historicalPaymentValidatedOrganizer',
    'Abono validado por organizador': 'historicalPartialValidatedOrganizer',
    'Partial payment validated by organizer':
        'historicalPartialValidatedOrganizer',
    'Pagamento parcial validado pelo organizador':
        'historicalPartialValidatedOrganizer',
    'Abono manual': 'historicalManualPayment',
    'Manual payment': 'historicalManualPayment',
    'Pagamento manual': 'historicalManualPayment',
  };

  static String translate(String stored, String languageCode) {
    final trimmed = stored.trim();
    if (trimmed.isEmpty) return stored;

    final legacyKey = _legacyToKey[trimmed];
    if (legacyKey != null) {
      return TranslationMaps.lookup(languageCode, legacyKey);
    }

    for (final key in _knownKeys) {
      for (final lang in _langs) {
        if (TranslationMaps.lookup(lang, key) == trimmed) {
          return TranslationMaps.lookup(languageCode, key);
        }
      }
    }
    return stored;
  }
}
