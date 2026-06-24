/// Conceptos predefinidos de cobro del partido.
class ConceptosCobro {
  ConceptosCobro._();

  static const cancha = 'Cancha';
  static const pelotas = 'Pelotas';
  static const asado = 'Asado';
  static const barraSchop = 'Barra Schop';
  static const otros = 'Otros';

  static const todos = [cancha, pelotas, asado, barraSchop, otros];
  static const fijos = [cancha, pelotas];
  static const variables = [asado, barraSchop, otros];

  /// Sugerencias para cobros extra individuales por jugador.
  static const sugerenciasIndividuales = [
    'Raqueta alquilada',
    'Agua / bebida',
    'Multa',
    'Otros extra',
  ];

  static bool esFijo(String concepto) => fijos.contains(concepto);

  /// Texto corto para la UI del formulario de partido.
  static String ayudaUi(String concepto) => switch (concepto) {
        cancha => 'Costo total de la cancha. Se divide entre quienes jugaron.',
        pelotas => 'Pelotas o equipamiento. Se divide entre todos los asistentes.',
        asado => 'Solo quienes se quedaron al asado pagan este ítem.',
        barraSchop => 'Schop o consumo en barra. Marca quién participó.',
        otros => 'Otro gasto compartido. Elige quién lo paga.',
        _ => 'Gasto del partido.',
      };
}
