import 'package:flutter_test/flutter_test.dart';
import 'package:matchpay/constants/conceptos_cobro.dart';
import 'package:matchpay/constants/expense_icon.dart';
import 'package:matchpay/core/sport_type.dart';
import 'package:matchpay/domain/gasto_sport_suggestions.dart';

void main() {
  test('pádel: cancha + pelotas + asado/bebidas', () {
    final chips = GastoSportSuggestions.chipsFor(SportType.padel);
    expect(chips.map((c) => c.kind), [
      GastoSuggestionKind.venue,
      GastoSuggestionKind.equipment,
      GastoSuggestionKind.freeText,
      GastoSuggestionKind.freeText,
    ]);
    expect(chips[0].fixedConcepto, ConceptosCobro.cancha);
    expect(chips[1].fixedConcepto, ConceptosCobro.pelotas);
    expect(chips[2].labelKey, 'expenseSuggestAsado');
    expect(chips[2].icon, ExpenseIconKey.meat);
    expect(chips[3].labelKey, 'expenseSuggestDrinks');
  });

  test('running: sin cancha/pelotas; inscripción/transporte/snack', () {
    final chips = GastoSportSuggestions.chipsFor(SportType.running);
    expect(GastoSportSuggestions.showVenue(SportType.running), isFalse);
    expect(GastoSportSuggestions.showEquipment(SportType.running), isFalse);
    expect(chips.every((c) => c.kind == GastoSuggestionKind.freeText), isTrue);
    expect(chips.map((c) => c.labelKey), [
      'expenseSuggestEntryFee',
      'expenseSuggestTransport',
      'expenseSuggestSnack',
    ]);
  });

  test('yoga: sala sí, pelotas no', () {
    expect(GastoSportSuggestions.showVenue(SportType.yoga), isTrue);
    expect(GastoSportSuggestions.showEquipment(SportType.yoga), isFalse);
    final chips = GastoSportSuggestions.chipsFor(SportType.yoga);
    expect(chips.first.kind, GastoSuggestionKind.venue);
    expect(
      chips.where((c) => c.kind == GastoSuggestionKind.equipment),
      isEmpty,
    );
    expect(
      chips.where((c) => c.kind == GastoSuggestionKind.freeText).map((c) => c.labelKey),
      ['expenseSuggestDrinks', 'expenseSuggestRental'],
    );
  });

  test('fútbol y natación cubren los grupos esperados', () {
    expect(GastoSportSuggestions.showEquipment(SportType.football), isTrue);
    expect(GastoSportSuggestions.showEquipment(SportType.swimming), isFalse);
    expect(GastoSportSuggestions.showVenue(SportType.swimming), isTrue);
  });
}
