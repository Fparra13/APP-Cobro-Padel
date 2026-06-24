import 'package:flutter/material.dart';

/// Cobro extra manual asignado a un solo jugador en el formulario de partido.
class CobroIndividualEntry {
  final String id;
  final TextEditingController conceptoCtrl;
  final TextEditingController montoCtrl;
  String? comprobantePath;
  bool guardado;

  CobroIndividualEntry({
    String? id,
    String concepto = '',
    String monto = '',
    this.comprobantePath,
    this.guardado = false,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        conceptoCtrl = TextEditingController(text: concepto),
        montoCtrl = TextEditingController(text: monto);

  double get monto => double.tryParse(montoCtrl.text) ?? 0;

  String get concepto => conceptoCtrl.text.trim();

  bool get tieneDatos => concepto.isNotEmpty || monto > 0;

  void dispose() {
    conceptoCtrl.dispose();
    montoCtrl.dispose();
  }
}
