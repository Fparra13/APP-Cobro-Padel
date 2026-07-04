import 'package:flutter/material.dart';

/// Deportes soportados por MatchPay.
enum SportType {
  padel('padel', 'Pádel', Icons.sports_tennis),
  football('football', 'Fútbol', Icons.sports_soccer),
  tennis('tennis', 'Tenis', Icons.sports_tennis),
  general('general', 'General', Icons.emoji_events_outlined);

  const SportType(this.dbValue, this.labelEs, this.icon);

  final String dbValue;
  final String labelEs;
  final IconData icon;

  static SportType fromDb(String? value) {
    if (value == null || value.isEmpty) return SportType.padel;
    return SportType.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => SportType.general,
    );
  }

  String labelForLang(String lang) {
    return switch (lang) {
      'en' => switch (this) {
          SportType.padel => 'Padel',
          SportType.football => 'Football',
          SportType.tennis => 'Tennis',
          SportType.general => 'General',
        },
      'pt' => switch (this) {
          SportType.padel => 'Padel',
          SportType.football => 'Futebol',
          SportType.tennis => 'Tênis',
          SportType.general => 'Geral',
        },
      _ => labelEs,
    };
  }
}
