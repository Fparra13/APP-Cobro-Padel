import 'package:flutter/material.dart';

import '../constants/conceptos_cobro.dart';
import '../core/sport_type.dart';

/// Iconos predefinidos para gastos compartidos (localizables).
enum ExpenseIconKey {
  meat('meat', Icons.outdoor_grill),
  drink('drink', Icons.local_bar),
  ball('ball', Icons.sports_baseball),
  general('general', Icons.more_horiz),
  court('court', Icons.stadium_outlined);

  const ExpenseIconKey(this.dbValue, this.defaultIcon);

  final String dbValue;
  final IconData defaultIcon;

  /// Alias retrocompatible.
  IconData get icon => defaultIcon;

  static IconData courtIconFor(SportType sport) => switch (sport) {
        SportType.football => Icons.stadium_outlined,
        SportType.padel => Icons.sports_tennis,
        SportType.tennis => Icons.sports_tennis,
        SportType.general => Icons.stadium_outlined,
      };

  /// Pelotas / equipamiento según deporte.
  static IconData ballsIconFor(SportType sport) => switch (sport) {
        SportType.football => Icons.sports_soccer,
        SportType.padel => Icons.sports_baseball,
        SportType.tennis => Icons.sports_baseball,
        SportType.general => Icons.sports_baseball,
      };

  static ExpenseIconKey fromDb(String? value) {
    if (value == null || value.isEmpty) return ExpenseIconKey.general;
    return ExpenseIconKey.values.firstWhere(
      (k) => k.dbValue == value,
      orElse: () => ExpenseIconKey.general,
    );
  }

  /// Mapea conceptos legacy a iconos.
  static ExpenseIconKey fromLegacyConcepto(String concepto) {
    return switch (concepto) {
      ConceptosCobro.asado => ExpenseIconKey.meat,
      ConceptosCobro.barraSchop => ExpenseIconKey.drink,
      ConceptosCobro.pelotas => ExpenseIconKey.ball,
      ConceptosCobro.cancha => ExpenseIconKey.court,
      ConceptosCobro.otros => ExpenseIconKey.general,
      _ => ExpenseIconKey.general,
    };
  }

  Color colorFor(ThemeData theme) {
    return switch (this) {
      ExpenseIconKey.meat => Colors.deepOrange.shade700,
      ExpenseIconKey.drink => Colors.amber.shade800,
      ExpenseIconKey.ball => Colors.lightGreen.shade800,
      ExpenseIconKey.court => theme.colorScheme.primary,
      ExpenseIconKey.general => Colors.blueGrey.shade700,
    };
  }
}
