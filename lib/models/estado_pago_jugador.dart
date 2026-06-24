import 'package:flutter/material.dart';

import '../utils/formatters.dart';

enum TipoPago { ninguno, total, parcial }

/// Estado de pago de un jugador en el formulario de partido.
class EstadoPagoJugador {
  TipoPago tipo;
  final TextEditingController montoParcial;
  bool abonoConfirmado;

  EstadoPagoJugador({
    this.tipo = TipoPago.ninguno,
    this.abonoConfirmado = false,
    TextEditingController? montoParcial,
  }) : montoParcial = montoParcial ?? TextEditingController();

  double montoEfectivo(double totalDebido) {
    switch (tipo) {
      case TipoPago.ninguno:
        return 0;
      case TipoPago.total:
        return totalDebido > 0 ? totalDebido : 0;
      case TipoPago.parcial:
        if (!abonoConfirmado) return 0;
        return roundMoney(parseMoney(montoParcial.text)).toDouble();
    }
  }

  void dispose() => montoParcial.dispose();
}
