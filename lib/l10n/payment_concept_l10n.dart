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
  /// Conceptos fijos del partido guardados en español en BD.
  static const _chargeConceptToKey = {
    'Cancha': 'courtLabel',
    'Pelotas': 'ballsLabel',
  };

  static const _legacyToKey = {
    'Deuda acumulada': 'historicalAccumulatedDebt',
    'Accumulated debt': 'historicalAccumulatedDebt',
    'Dívida acumulada': 'historicalAccumulatedDebt',
    'Pendiente acumulado': 'historicalAccumulatedDebt',
    'Accumulated pending': 'historicalAccumulatedDebt',
    'Pendência acumulada': 'historicalAccumulatedDebt',
    'Cobro de encuentro': 'historicalAccumulatedDebt',
    'Aporte del encuentro': 'historicalAccumulatedDebt',
    // Conceptos de encuentro (antes “Partido …”) guardados en historial.
    'Partido pagado': 'historicalMatchPaid',
    'Encuentro pagado': 'historicalMatchPaid',
    'Session paid': 'historicalMatchPaid',
    'Encontro pago': 'historicalMatchPaid',
    'Encuentro al día': 'historicalMatchPaid',
    'Gathering settled': 'historicalMatchPaid',
    'Encontro em dia': 'historicalMatchPaid',
    'Partido cubierto con saldo a favor': 'historicalMatchCoveredByCredit',
    'Pago parcial': 'historicalPartialPayment',
    'Partial payment': 'historicalPartialPayment',
    'Pagamento parcial': 'historicalPartialPayment',
    'Aporte parcial': 'historicalPartialPayment',
    'Partial contribution': 'historicalPartialPayment',
    'Contribuição parcial': 'historicalPartialPayment',
    'Pago validado por organizador': 'historicalPaymentValidatedOrganizer',
    'Payment validated by organizer': 'historicalPaymentValidatedOrganizer',
    'Pagamento validado pelo organizador':
        'historicalPaymentValidatedOrganizer',
    'Aporte validado por organizador': 'historicalPaymentValidatedOrganizer',
    'Abono validado por organizador': 'historicalPartialValidatedOrganizer',
    'Partial payment validated by organizer':
        'historicalPartialValidatedOrganizer',
    'Pagamento parcial validado pelo organizador':
        'historicalPartialValidatedOrganizer',
    'Abono manual': 'historicalManualPayment',
    'Manual payment': 'historicalManualPayment',
    'Pagamento manual': 'historicalManualPayment',
    'Pago registrado manualmente': 'historicalManualPayment',
  };

  static String translate(String stored, String languageCode) {
    final trimmed = stored.trim();
    if (trimmed.isEmpty) return stored;

    final chargeKey = _chargeConceptToKey[trimmed];
    if (chargeKey != null) {
      return TranslationMaps.lookup(languageCode, chargeKey);
    }

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
