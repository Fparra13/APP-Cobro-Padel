import 'package:flutter/material.dart';

/// Deportes soportados por Kloovi (identidad visual; la lógica es neutra).
///
/// `dbValue` se persiste en `partidos.sport_type` / preferencias.
/// Valores desconocidos en DB caen en [other].
enum SportType {
  football('football', 'Fútbol', Icons.sports_soccer, '⚽'),
  padel('padel', 'Pádel', Icons.sports_tennis, '🎾'),
  tennis('tennis', 'Tenis', Icons.sports_tennis, '🎾'),
  beachTennis('beach_tennis', 'Tenis playa', Icons.beach_access, '🏖️'),
  pickleball('pickleball', 'Pickleball', Icons.sports_tennis, '🏓'),
  futevolei('futevolei', 'Futevôlei', Icons.sports_volleyball, '🏐'),
  basketball('basketball', 'Básquetbol', Icons.sports_basketball, '🏀'),
  volleyball('volleyball', 'Vóleibol', Icons.sports_volleyball, '🏐'),
  rugby('rugby', 'Rugby', Icons.sports_rugby, '🏉'),
  hockey('hockey', 'Hockey', Icons.sports_hockey, '🏒'),
  baseball('baseball', 'Béisbol', Icons.sports_baseball, '⚾'),
  running('running', 'Running', Icons.directions_run, '🏃'),
  cycling('cycling', 'Ciclismo', Icons.directions_bike, '🚴'),
  mountainBike('mountain_bike', 'Mountain Bike', Icons.pedal_bike, '🚵'),
  swimming('swimming', 'Natación', Icons.pool, '🏊'),
  skating('skating', 'Patinaje', Icons.ice_skating, '🛼'),
  skate('skate', 'Skate', Icons.skateboarding, '🛹'),
  surf('surf', 'Surf', Icons.surfing, '🏄'),
  climbing('climbing', 'Escalada', Icons.terrain, '🧗'),
  trekking('trekking', 'Trekking', Icons.hiking, '🥾'),
  boxing('boxing', 'Boxeo', Icons.sports_mma, '🥊'),
  martialArts('martial_arts', 'Artes marciales', Icons.sports_martial_arts, '🥋'),
  crossfit('crossfit', 'CrossFit', Icons.fitness_center, '💪'),
  fitness('fitness', 'Fitness', Icons.fitness_center, '🏋️'),
  yoga('yoga', 'Yoga', Icons.self_improvement, '🧘'),
  golf('golf', 'Golf', Icons.golf_course, '⛳'),
  tableTennis('table_tennis', 'Ping pong', Icons.sports_tennis, '🏓'),
  badminton('badminton', 'Bádminton', Icons.sports_tennis, '🏸'),
  /// Multideporte / no listado (antes `general` en DB).
  other('general', 'Otro', Icons.emoji_events_outlined, '⭐');

  const SportType(this.dbValue, this.labelEs, this.icon, this.emoji);

  final String dbValue;
  final String labelEs;
  final IconData icon;
  final String emoji;

  /// Alias retrocompatible con código que usaba [SportType.general].
  static const SportType general = SportType.other;

  /// Deportes destacados en pickers (el resto va en «Ver más»).
  /// Preferir [CountrySportCatalog.featuredFor] con el país del usuario.
  static const List<SportType> featured = [
    SportType.football,
    SportType.padel,
    SportType.tennis,
    SportType.beachTennis,
    SportType.pickleball,
    SportType.futevolei,
    SportType.running,
    SportType.basketball,
    SportType.other,
  ];

  static SportType fromDb(String? value) {
    if (value == null || value.isEmpty) return SportType.padel;
    // Compat: 'general' → other
    return SportType.values.firstWhere(
      (s) => s.dbValue == value,
      orElse: () => SportType.other,
    );
  }

  String labelForLang(String lang) {
    final map = switch (lang) {
      'en' => _labelsEn,
      'pt' => _labelsPt,
      _ => null,
    };
    final fromMap = map?[this];
    if (fromMap != null && fromMap.isNotEmpty) return fromMap;
    return labelEs;
  }

  static const _labelsEn = <SportType, String>{
    SportType.football: 'Football',
    SportType.padel: 'Padel',
    SportType.tennis: 'Tennis',
    SportType.beachTennis: 'Beach tennis',
    SportType.pickleball: 'Pickleball',
    SportType.futevolei: 'Footvolley',
    SportType.basketball: 'Basketball',
    SportType.volleyball: 'Volleyball',
    SportType.rugby: 'Rugby',
    SportType.hockey: 'Hockey',
    SportType.baseball: 'Baseball',
    SportType.running: 'Running',
    SportType.cycling: 'Cycling',
    SportType.mountainBike: 'Mountain bike',
    SportType.swimming: 'Swimming',
    SportType.skating: 'Skating',
    SportType.skate: 'Skate',
    SportType.surf: 'Surf',
    SportType.climbing: 'Climbing',
    SportType.trekking: 'Trekking',
    SportType.boxing: 'Boxing',
    SportType.martialArts: 'Martial arts',
    SportType.crossfit: 'CrossFit',
    SportType.fitness: 'Fitness',
    SportType.yoga: 'Yoga',
    SportType.golf: 'Golf',
    SportType.tableTennis: 'Table tennis',
    SportType.badminton: 'Badminton',
    SportType.other: 'Other',
  };

  static const _labelsPt = <SportType, String>{
    SportType.football: 'Futebol',
    SportType.padel: 'Padel',
    SportType.tennis: 'Tênis',
    SportType.beachTennis: 'Beach tennis',
    SportType.pickleball: 'Pickleball',
    SportType.futevolei: 'Futevôlei',
    SportType.basketball: 'Basquete',
    SportType.volleyball: 'Vôlei',
    SportType.rugby: 'Rúgbi',
    SportType.hockey: 'Hóquei',
    SportType.baseball: 'Beisebol',
    SportType.running: 'Corrida',
    SportType.cycling: 'Ciclismo',
    SportType.mountainBike: 'Mountain bike',
    SportType.swimming: 'Natação',
    SportType.skating: 'Patinação',
    SportType.skate: 'Skate',
    SportType.surf: 'Surf',
    SportType.climbing: 'Escalada',
    SportType.trekking: 'Trekking',
    SportType.boxing: 'Boxe',
    SportType.martialArts: 'Artes marciais',
    SportType.crossfit: 'CrossFit',
    SportType.fitness: 'Fitness',
    SportType.yoga: 'Ioga',
    SportType.golf: 'Golfe',
    SportType.tableTennis: 'Tênis de mesa',
    SportType.badminton: 'Badminton',
    SportType.other: 'Outro',
  };
}
