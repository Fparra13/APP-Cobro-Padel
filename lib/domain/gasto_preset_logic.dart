import '../constants/conceptos_cobro.dart';
import '../constants/expense_icon.dart';
import '../models/shared_expense_entry.dart';

/// Resuelve presets de cancha/pelotas desde gastos compartidos (texto libre).
///
/// Sigue persistiendo en `partidos.costo_cancha` / `costo_pelotas` para no
/// romper desglose, PDF ni migraciones.
class GastoPresetLogic {
  GastoPresetLogic._();

  static bool isVenuePreset(String label) =>
      label.trim() == ConceptosCobro.cancha;

  static bool isEquipmentPreset(String label) =>
      label.trim() == ConceptosCobro.pelotas;

  static bool isFixedPreset(String label) => ConceptosCobro.esFijo(label.trim());

  static ExpenseIconKey iconForPreset(String concepto) {
    if (isVenuePreset(concepto)) return ExpenseIconKey.court;
    if (isEquipmentPreset(concepto)) return ExpenseIconKey.ball;
    return ExpenseIconKey.general;
  }

  /// Primer gasto compartido con ese concepto canónico (Cancha/Pelotas).
  static SharedExpenseEntry? findPreset(
    Iterable<SharedExpenseEntry> gastos,
    String concepto,
  ) {
    for (final g in gastos) {
      if (g.label == concepto) return g;
    }
    return null;
  }

  static double montoPreset(
    Iterable<SharedExpenseEntry> gastos,
    String concepto,
  ) {
    final g = findPreset(gastos, concepto);
    if (g == null) return 0;
    return g.monto > 0 ? g.monto : 0;
  }

  static String? comprobantePreset(
    Iterable<SharedExpenseEntry> gastos,
    String concepto,
  ) {
    final g = findPreset(gastos, concepto);
    if (g == null || g.monto <= 0) return null;
    return g.comprobantePath;
  }

  /// Gastos que van a `costos_variables` (excluye presets mapeados a columnas).
  static List<SharedExpenseEntry> sharedForVariables(
    Iterable<SharedExpenseEntry> gastos,
  ) {
    return [
      for (final g in gastos)
        if (!isFixedPreset(g.label) && g.monto > 0 && g.label.isNotEmpty) g,
    ];
  }
}
