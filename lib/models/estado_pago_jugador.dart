import 'package:flutter/material.dart';

import '../utils/formatters.dart';

enum TipoPago { ninguno, total, parcial }

/// Estado de pago de un jugador en el formulario de partido.
class EstadoPagoJugador {
  TipoPago tipo;
  final TextEditingController montoParcial;

  EstadoPagoJugador({
    this.tipo = TipoPago.ninguno,
    TextEditingController? montoParcial,
  }) : montoParcial = montoParcial ?? TextEditingController();

  double montoEfectivo(double totalDebido) {
    switch (tipo) {
      case TipoPago.ninguno:
        return 0;
      case TipoPago.total:
        return totalDebido > 0 ? totalDebido : 0;
      case TipoPago.parcial:
        return roundMoney(double.tryParse(montoParcial.text) ?? 0).toDouble();
    }
  }

  void dispose() => montoParcial.dispose();
}
