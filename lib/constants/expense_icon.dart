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
        SportType.padel ||
        SportType.tennis ||
        SportType.beachTennis ||
        SportType.pickleball =>
          Icons.sports_tennis,
        SportType.futevolei || SportType.volleyball => Icons.sports_volleyball,
        SportType.golf => Icons.golf_course,
        SportType.swimming => Icons.pool,
        SportType.climbing || SportType.trekking => Icons.terrain,
        _ => Icons.stadium_outlined,
      };

  /// Pelotas / equipamiento según deporte.
  static IconData ballsIconFor(SportType sport) => switch (sport) {
        SportType.football || SportType.futevolei => Icons.sports_soccer,
        SportType.basketball => Icons.sports_basketball,
        SportType.volleyball => Icons.sports_volleyball,
        SportType.baseball => Icons.sports_baseball,
        SportType.padel ||
        SportType.tennis ||
        SportType.beachTennis ||
        SportType.pickleball ||
        SportType.tableTennis ||
        SportType.badminton =>
          Icons.sports_baseball,
        _ => Icons.sports_baseball,
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
