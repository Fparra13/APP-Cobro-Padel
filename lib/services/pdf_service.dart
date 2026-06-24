import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/deuda_partido_anterior.dart';
import '../models/desglose_jugador.dart';
import '../models/jugador.dart';
import '../models/partido.dart';
import '../repositories/jugador_repository.dart';
import '../repositories/partido_repository.dart';
import '../services/mensaje_cobro_service.dart';
import '../services/preferences_service.dart';
import '../services/share_service.dart';
import '../utils/formatters.dart';

class PdfService {
  final _prefs = PreferencesService();
  final _share = ShareService();
  final _partidoRepo = PartidoRepository();
  final _jugadorRepo = JugadorRepository();

  String _fmt(double v) => formatMoney(v);

  /// Texto seguro para fuentes PDF (sin unicode problemático).
  String _pdf(String text) => text
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('✓', 'OK')
      .replaceAll('·', ' - ');

  String _fechaDisplay(DateTime d) => formatFecha(d);

  String _fechaArchivo(DateTime d) => formatFechaArchivo(d);

  String _nombreArchivo(String base) {
    final limpio = base
        .replaceAll(RegExp(r'[/\\:*?"<>|]'), '-')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^a-zA-Z0-9_\-.áéíóúÁÉÍÓÚñÑ]'), '');
    return limpio.isEmpty ? 'reporte' : limpio;
  }

  Future<void> generarReporteSaldos(List<ResumenJugador> resumenes) async {
    final titular = await _prefs.titularNombre;
    final banco = await _prefs.bancoNombre;
    final cuenta = await _prefs.cuentaNumero;
    final pdf = pw.Document();
    final fecha = formatFechaHora(DateTime.now());
    final totalDeuda = resumenes.fold(
      0.0,
      (s, r) => s + (r.saldoActual > 0 ? r.saldoActual : 0),
    );
    final conDeuda = resumenes.where((r) => r.saldoActual > 0).length;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            _pdf('Reporte General de Saldos'),
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(_pdf('Generado: $fecha')),
          pw.SizedBox(height: 8),
          pw.Text(
            _pdf(
              conDeuda > 0
                  ? '$conDeuda jugador${conDeuda == 1 ? '' : 'es'} con deuda - Total ${_fmt(totalDeuda)}'
                  : 'Todos los jugadores estan al dia',
            ),
            style: pw.TextStyle(
              fontSize: 12,
              color: conDeuda > 0 ? PdfColors.red800 : PdfColors.green800,
            ),
          ),
          if (titular.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _bloqueTransferencia(titular, banco, cuenta),
          ],
          pw.SizedBox(height: 16),
          pw.Text(
            _pdf('Saldo acumulado por jugador'),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: [
              _pdf('Jugador'),
              _pdf('Saldo pendiente'),
              _pdf('Estado'),
            ],
            data: resumenes
                .map((r) => [
                      _pdf(r.jugador.nombre),
                      _fmt(r.saldoActual),
                      _pdf(r.saldoActual > 0 ? 'Debe' : 'Al dia'),
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            _pdf(
              'Nota: el detalle por item (cancha, pelotas, asado, etc.) '
              'esta en el PDF de cada partido o en la cuenta individual.',
            ),
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    await _guardarYCompartir(pdf, 'reporte_saldos');
  }

  Future<void> generarReportePartido(PartidoCompleto completo) async {
    final desglose = await _partidoRepo.getDesglose(completo.partido.id!);
    final partidoId = completo.partido.id!;
    final deudasPorJugador = <int, List<DeudaPartidoAnterior>>{};
    for (final d in desglose) {
      deudasPorJugador[d.jugadorId] =
          await _partidoRepo.getDeudasPartidosAnteriores(
        jugadorId: d.jugadorId,
        partidoActualId: partidoId,
      );
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          ..._encabezadoPartido(completo.partido),
          pw.SizedBox(height: 4),
          pw.Text(
            _pdf('Detalle de cobros por jugador e item'),
            style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          if (desglose.isEmpty)
            pw.Text(_pdf('Sin jugadores asistentes en este partido'))
          else
            ...desglose.expand(
              (d) => _seccionJugador(
                d,
                deudasAnteriores: deudasPorJugador[d.jugadorId] ?? [],
              ),
            ),
        ],
      ),
    );

    await _guardarYCompartir(
      pdf,
      'partido_${_fechaArchivo(completo.partido.fecha)}',
    );
  }

  Future<void> generarReportePersonal({
    required PartidoCompleto completo,
    required DesgloseJugador desglose,
    Jugador? jugador,
  }) async {
    final titular = await _prefs.titularNombre;
    final banco = await _prefs.bancoNombre;
    final cuenta = await _prefs.cuentaNumero;
    final deudasAnteriores = await _partidoRepo.getDeudasPartidosAnteriores(
      jugadorId: desglose.jugadorId,
      partidoActualId: completo.partido.id!,
    );
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            ..._encabezadoPartido(completo.partido, titulo: 'Tu cuenta - Padel'),
            pw.SizedBox(height: 4),
            pw.Text(
              _pdf('Hola ${desglose.nombre}!'),
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 20),
            ..._bloqueDeudaAnteriorPdf(desglose.saldoAnterior, deudasAnteriores),
            pw.Text(
              _pdf('Detalle de este partido'),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
            ),
            pw.SizedBox(height: 8),
            _tablaItems(desglose.lineas),
            pw.SizedBox(height: 12),
            _filaTotal('Subtotal partido', desglose.totalPartido, bold: true),
            pw.SizedBox(height: 8),
            if (desglose.saldoAnterior > 0)
              _filaTotal('Total con deuda anterior', desglose.totalDebido),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 8),
            if (desglose.montoPagado > 0)
              _filaTotal('Pagaste', desglose.montoPagado, color: PdfColors.green800),
            pw.SizedBox(height: 4),
            pw.Text(
              _pdf(
                desglose.pagado
                    ? 'Estado: PAGADO'
                    : desglose.pagoParcial
                        ? 'Saldo pendiente: ${_fmt(desglose.saldoRestante)}'
                        : 'Total a pagar: ${_fmt(desglose.saldoRestante)}',
              ),
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: desglose.pagado ? PdfColors.green800 : PdfColors.red800,
              ),
            ),
            if (titular.isNotEmpty) ...[
              pw.SizedBox(height: 24),
              _bloqueTransferencia(titular, banco, cuenta),
            ],
          ],
        ),
      ),
    );

    final nombre =
        'cuenta_${_nombreArchivo(desglose.nombre)}_${_fechaArchivo(completo.partido.fecha)}';
    final bytes = await pdf.save();
    await _guardarYCompartirBytes(bytes, nombre);
  }

  Future<void> enviarWhatsAppPersonal({
    required PartidoCompleto completo,
    required DesgloseJugador desglose,
    Jugador? jugador,
  }) async {
    final titular = await _prefs.titularNombre;
    final banco = await _prefs.bancoNombre;
    final cuenta = await _prefs.cuentaNumero;
    final deudasAnteriores = await _partidoRepo.getDeudasPartidosAnteriores(
      jugadorId: desglose.jugadorId,
      partidoActualId: completo.partido.id!,
    );

    final mensaje = MensajeCobroService.construirDetallePartido(
      partido: completo.partido,
      desglose: desglose,
      deudasAnteriores: deudasAnteriores,
      titular: titular,
      banco: banco,
      cuenta: cuenta,
    );

    await _share.compartirWhatsApp(
      mensaje: mensaje,
      telefono: jugador?.telefono,
    );
  }

  Future<void> enviarWhatsAppTodos(PartidoCompleto completo) async {
    final desglose = await _partidoRepo.getDesglose(completo.partido.id!);
    for (final d in desglose.where((x) => !x.pagado)) {
      final jugador = await _jugadorRepo.getById(d.jugadorId);
      await enviarWhatsAppPersonal(
        completo: completo,
        desglose: d,
        jugador: jugador,
      );
    }
  }

  List<pw.Widget> _seccionJugador(
    DesgloseJugador d, {
    List<DeudaPartidoAnterior> deudasAnteriores = const [],
  }) {
    final estado = d.pagado
        ? 'Pagado'
        : d.pagoParcial
            ? 'Pago parcial'
            : 'Debe';

    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _pdf(d.nombre),
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
            ),
            pw.Text(
              _pdf(estado),
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 11,
                color: d.pagado ? PdfColors.green800 : PdfColors.red800,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 6),
      ..._bloqueSaldoAnteriorPdf(d.saldoAnterior, deudasAnteriores),
      pw.SizedBox(height: 4),
      pw.Text(
        _pdf('Items cobrados'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      ),
      pw.SizedBox(height: 4),
      _tablaItems(d.lineas),
      pw.SizedBox(height: 6),
      _filaTotal('Cancha/pelotas', d.costoCanchaPelotas),
      if (d.costoExtras > 0)
        _filaTotal('Extras', d.costoExtras),
      if (d.saldoFavorAplicado > 0)
        _filaTotal(
          'Saldo a favor aplicado',
          -d.saldoFavorAplicado,
          color: PdfColors.blue800,
        ),
      if (d.montoPagado > 0)
        _filaTotal('Pago', d.montoPagado, color: PdfColors.green800),
      _filaTotal(
        d.pagado ? 'Estado' : 'Total a transferir',
        d.pagado
            ? (d.generaSaldoAFavor ? -d.saldoRestante : 0)
            : d.totalATransferir,
        bold: true,
        color: d.pagado ? PdfColors.green800 : PdfColors.red800,
      ),
      pw.SizedBox(height: 18),
    ];
  }

  String _lineaPartido(DateTime fecha, String? recinto) {
    final f = _fechaDisplay(fecha);
    final r = recinto?.trim();
    if (r != null && r.isNotEmpty) return '$f - $r';
    return f;
  }

  List<pw.Widget> _encabezadoPartido(Partido partido, {String? titulo}) {
    final fecha = _fechaDisplay(partido.fecha);
    final encabezado = titulo ?? 'Partido $fecha';
    return [
      pw.Text(
        _pdf(encabezado.contains(fecha) ? encabezado : '$encabezado $fecha'),
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      if (partido.recinto != null && partido.recinto!.trim().isNotEmpty) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          _pdf('Recinto: ${partido.recinto!.trim()}'),
          style: pw.TextStyle(fontSize: 12, color: PdfColors.grey800),
        ),
      ],
    ];
  }

  List<pw.Widget> _bloqueSaldoAnteriorPdf(
    double saldoAnterior,
    List<DeudaPartidoAnterior> deudas,
  ) {
    if (saldoAnterior == 0) return [];

    if (saldoAnterior < 0) {
      return [
        pw.Text(
          _pdf('Saldo a favor anterior: ${_fmt(-saldoAnterior)}'),
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 12,
            color: PdfColors.blue800,
          ),
        ),
        pw.SizedBox(height: 8),
      ];
    }

    return [
      pw.Text(
        _pdf('Deuda anterior: ${_fmt(saldoAnterior)}'),
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
      ),
      if (deudas.isNotEmpty) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          _pdf('Partidos pendientes:'),
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
        ),
        ...deudas.map(
          (d) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Text(
              _pdf(
                '- ${_lineaPartido(d.fecha, d.recinto)}: ${_fmt(d.montoPendiente)}',
              ),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ),
      ],
      pw.SizedBox(height: 8),
    ];
  }

  List<pw.Widget> _bloqueDeudaAnteriorPdf(
    double saldoAnterior,
    List<DeudaPartidoAnterior> deudas,
  ) =>
      _bloqueSaldoAnteriorPdf(saldoAnterior, deudas);

  pw.Widget _tablaItems(List<({String concepto, double monto})> lineas) {
    if (lineas.isEmpty) {
      return pw.Text(
        _pdf('Sin items de cobro registrados'),
        style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _celdaTabla('Concepto', bold: true),
            _celdaTabla('Monto', bold: true, align: pw.TextAlign.right),
          ],
        ),
        ...lineas.map(
          (l) => pw.TableRow(
            children: [
              _celdaTabla(_pdf(l.concepto)),
              _celdaTabla(_fmt(l.monto), align: pw.TextAlign.right),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _celdaTabla(
    String texto, {
    bool bold = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Text(
        texto,
        textAlign: align,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _filaTotal(
    String label,
    double monto, {
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            _pdf(label),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
          pw.Text(
            _fmt(monto),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _bloqueTransferencia(String titular, String banco, String cuenta) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _pdf('Datos para transferir'),
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(_pdf('Titular: $titular')),
        if (banco.isNotEmpty) pw.Text(_pdf('Banco: $banco')),
        if (cuenta.isNotEmpty) pw.Text(_pdf('Cuenta: $cuenta')),
      ],
    );
  }

  Future<String> _guardarYCompartir(pw.Document pdf, String nombre) async {
    final bytes = await pdf.save();
    return _guardarYCompartirBytes(bytes, nombre);
  }

  Future<String> _guardarYCompartirBytes(List<int> bytes, String nombre) async {
    final nombreSeguro = _nombreArchivo(nombre);
    final dir = await _getPdfDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filePath = p.join(dir.path, '${nombreSeguro}_$timestamp.pdf');
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    await Printing.sharePdf(
      bytes: Uint8List.fromList(bytes),
      filename: '$nombreSeguro.pdf',
    );

    return filePath;
  }

  Future<Directory> _getPdfDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final pdfDir = Directory(p.join(dir.path, 'PadelCobro', 'reportes'));
    if (!await pdfDir.exists()) await pdfDir.create(recursive: true);
    return pdfDir;
  }
}
