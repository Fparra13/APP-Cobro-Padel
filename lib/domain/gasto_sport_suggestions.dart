import '../constants/conceptos_cobro.dart';
import '../constants/expense_icon.dart';
import '../core/sport_type.dart';

/// Tipo de chip sugerido al cargar gastos del encuentro.
enum GastoSuggestionKind {
  /// Mapea a `partidos.costo_cancha`.
  venue,

  /// Mapea a `partidos.costo_pelotas`.
  equipment,

  /// Gasto compartido de texto libre (costos_variables).
  freeText,
}

/// Sugerencia opcional de gasto según el deporte del encuentro.
class GastoSportSuggestion {
  final GastoSuggestionKind kind;
  final String labelKey;
  final ExpenseIconKey icon;
  final String? fixedConcepto;

  const GastoSportSuggestion._({
    required this.kind,
    required this.labelKey,
    required this.icon,
    this.fixedConcepto,
  });

  const GastoSportSuggestion.venue()
      : this._(
          kind: GastoSuggestionKind.venue,
          labelKey: 'courtLabel',
          icon: ExpenseIconKey.court,
          fixedConcepto: ConceptosCobro.cancha,
        );

  const GastoSportSuggestion.equipment()
      : this._(
          kind: GastoSuggestionKind.equipment,
          labelKey: 'ballsLabel',
          icon: ExpenseIconKey.ball,
          fixedConcepto: ConceptosCobro.pelotas,
        );

  const GastoSportSuggestion.free({
    required String labelKey,
    required ExpenseIconKey icon,
  }) : this._(
          kind: GastoSuggestionKind.freeText,
          labelKey: labelKey,
          icon: icon,
        );

  bool get isFixed => fixedConcepto != null;
}

/// Plantillas opcionales de gasto por deporte (UI only; no cambia el esquema).
class GastoSportSuggestions {
  GastoSportSuggestions._();

  /// Actividades outdoor: suelen no usar cancha ni pelotas.
  static const _outdoor = {
    SportType.running,
    SportType.cycling,
    SportType.mountainBike,
    SportType.skating,
    SportType.skate,
    SportType.surf,
    SportType.climbing,
    SportType.trekking,
  };

  /// Sala / clase / pileta: lugar sí, equipo de pelota no.
  static const _venueOnly = {
    SportType.swimming,
    SportType.boxing,
    SportType.martialArts,
    SportType.crossfit,
    SportType.fitness,
    SportType.yoga,
  };

  static bool showVenue(SportType sport) => !_outdoor.contains(sport);

  static bool showEquipment(SportType sport) =>
      !_outdoor.contains(sport) && !_venueOnly.contains(sport);

  /// Chips a mostrar arriba de la lista de gastos (orden: fijos → extras).
  static List<GastoSportSuggestion> chipsFor(SportType sport) {
    return [
      if (showVenue(sport)) const GastoSportSuggestion.venue(),
      if (showEquipment(sport)) const GastoSportSuggestion.equipment(),
      ..._extras(sport),
    ];
  }

  static List<GastoSportSuggestion> _extras(SportType sport) {
    if (_outdoor.contains(sport)) {
      return const [
        GastoSportSuggestion.free(
          labelKey: 'expenseSuggestEntryFee',
          icon: ExpenseIconKey.general,
        ),
        GastoSportSuggestion.free(
          labelKey: 'expenseSuggestTransport',
          icon: ExpenseIconKey.general,
        ),
        GastoSportSuggestion.free(
          labelKey: 'expenseSuggestSnack',
          icon: ExpenseIconKey.drink,
        ),
      ];
    }
    if (_venueOnly.contains(sport)) {
      return const [
        GastoSportSuggestion.free(
          labelKey: 'expenseSuggestDrinks',
          icon: ExpenseIconKey.drink,
        ),
        GastoSportSuggestion.free(
          labelKey: 'expenseSuggestRental',
          icon: ExpenseIconKey.general,
        ),
      ];
    }
    // Cancha / equipo (pádel, fútbol, etc.): after-match típico.
    return const [
      GastoSportSuggestion.free(
        labelKey: 'expenseSuggestAsado',
        icon: ExpenseIconKey.meat,
      ),
      GastoSportSuggestion.free(
        labelKey: 'expenseSuggestDrinks',
        icon: ExpenseIconKey.drink,
      ),
    ];
  }
}
