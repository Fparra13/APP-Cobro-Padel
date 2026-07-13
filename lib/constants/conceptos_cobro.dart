/// Conceptos de cobro del partido.
///
/// Los gastos compartidos (variables) usan texto libre guardado en Supabase;
/// [variablesLegacy] solo sirve para migrar partidos antiguos.
class ConceptosCobro {
  ConceptosCobro._();

  static const cancha = 'Cancha';
  static const pelotas = 'Pelotas';
  static const asado = 'Asado';
  static const barraSchop = 'Barra Schop';
  static const otros = 'Otros';

  static const fijos = [cancha, pelotas];
  static const variablesLegacy = [asado, barraSchop, otros];

  @Deprecated('Usar gastos compartidos con texto libre')
  static const variables = variablesLegacy;

  static const todos = [cancha, pelotas, ...variablesLegacy];

  /// Sugerencias para cobros extra individuales por jugador.
  static const sugerenciasIndividuales = [
    'Raqueta alquilada',
    'Agua / bebida',
    'Multa',
    'Otros extra',
  ];

  static bool esFijo(String concepto) => fijos.contains(concepto);

  static bool esVariableLegacy(String concepto) =>
      variablesLegacy.contains(concepto);

  static bool esVariableCompartida(String concepto) =>
      !esFijo(concepto);

  /// Texto corto para la UI del formulario de partido.
  static String ayudaUi(String concepto) => switch (concepto) {
        cancha => 'Costo total de la cancha. Se divide entre quienes jugaron.',
        pelotas => 'Pelotas o equipamiento. Se divide entre todos los asistentes.',
        asado => 'Solo quienes se quedaron al asado pagan este ítem.',
        barraSchop => 'Consumición o consumo en barra. Marca quién participó.',
        otros => 'Otro gasto compartido. Elige quién lo paga.',
        _ => 'Gasto del encuentro.',
      };
}
