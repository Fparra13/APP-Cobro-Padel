import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/app_repositories.dart';
import '../core/sport_theme.dart';
import '../models/deuda_partido_anterior.dart';
import '../models/desglose_jugador.dart';
import '../models/jugador.dart';
import '../models/partido.dart';
import '../repositories/partido_repository.dart';
import '../services/calculation_service.dart';
import '../utils/formatters.dart';

class PdfService {
  AppRepositories get _repos {
    final repos = AppRepositories.tryActive;
    if (repos == null) {
      throw const AppRepositoriesUnavailable();
    }
    return repos;
  }

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
                  ? '$conDeuda participante${conDeuda == 1 ? '' : 's'} con pendiente - Total ${_fmt(totalDeuda)}'
                  : 'Todos los participantes estan al dia',
            ),
            style: pw.TextStyle(
              fontSize: 12,
              color: conDeuda > 0 ? PdfColors.red800 : PdfColors.green800,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            _pdf('Saldo acumulado por participante'),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: [
              _pdf('Participante'),
              _pdf('Saldo pendiente'),
              _pdf('Estado'),
            ],
            data: resumenes
                .map((r) => [
                      _pdf(r.jugador.nombre),
                      _fmt(r.saldoActual),
                      _pdf(r.saldoActual > 0 ? 'Pendiente' : 'Al dia'),
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            _pdf(
              'Nota: el detalle por item (cancha, pelotas, asado, etc.) '
              'esta en el PDF de cada encuentro o en la cuenta individual.',
            ),
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    await _guardarYCompartir(pdf, 'reporte_saldos');
  }

  Future<void> generarReportePartido(PartidoCompleto completo) async {
    final desglose = await _repos.getDesglose(completo.partido.id!);
    final partidoId = completo.partido.id!;
    final deudasPorJugador = <String, List<DeudaPartidoAnterior>>{};
    for (final d in desglose) {
      deudasPorJugador[d.jugadorKeyId] =
          await _repos.getDeudasPartidosAnteriores(
        jugadorId: d.jugadorKeyId,
        partidoActualId: partidoId,
      );
    }

    final hayDeudores = desglose.any((d) => d.saldoRestante > 0);

    final pdf = pw.Document();
    final ordenados = List<DesgloseJugador>.from(desglose)
      ..sort((a, b) {
        int prio(DesgloseJugador d) {
          if (d.saldoRestante > 0) return 0;
          if (d.pagoParcial) return 1;
          return 2;
        }
        final cmp = prio(a).compareTo(prio(b));
        if (cmp != 0) return cmp;
        return a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase());
      });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 44),
        build: (context) => [
          ..._encabezadoPartido(completo.partido, titulo: 'Informe del encuentro'),
          pw.SizedBox(height: 6),
          pw.Text(
            _pdf('Generado: ${formatFechaHora(DateTime.now())}'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 16),
          ..._resumenGastosPartido(completo, desglose.length),
          pw.SizedBox(height: 18),
          if (ordenados.isNotEmpty) ...[
            _tituloSeccion('Resumen por participante'),
            pw.SizedBox(height: 8),
            _tablaResumenJugadores(ordenados),
            pw.SizedBox(height: 20),
            _tituloSeccion('Detalle por participante'),
            pw.SizedBox(height: 4),
            pw.Text(
              _pdf(
                'Cada bloque muestra: items del encuentro, pendiente anterior, '
                'total a aportar, aporte parcial y saldo pendiente.',
              ),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 10),
            ...ordenados.expand(
              (d) => _seccionJugador(
                d,
                deudasAnteriores: deudasPorJugador[d.jugadorKeyId] ?? [],
              ),
            ),
          ] else
            pw.Text(_pdf('Sin participantes asistentes en este encuentro')),
          if (hayDeudores) ...[
            pw.SizedBox(height: 16),
            pw.Text(
              _pdf(
                'Datos para aportar: se envian por aviso en la app o WhatsApp '
                '(no se incluyen en este informe).',
              ),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ],
      ),
    );

    await _guardarYCompartir(
      pdf,
      'encuentro_${_fechaArchivo(completo.partido.fecha)}',
    );
  }

  Future<void> generarReportePersonal({
    required PartidoCompleto completo,
    required DesgloseJugador desglose,
    Jugador? jugador,
  }) async {
    final deudasAnteriores = await _repos.getDeudasPartidosAnteriores(
      jugadorId: desglose.jugadorKeyId,
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
            ..._encabezadoPartido(completo.partido, titulo: 'Tu cuenta'),
            pw.SizedBox(height: 4),
            pw.Text(
              _pdf('Hola ${desglose.nombre}!'),
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 16),
            ..._cuentaJugador(
              desglose,
              deudasAnteriores: deudasAnteriores,
              compacto: false,
            ),
            if (desglose.saldoRestante > 0.005) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                _pdf(
                  'Datos para aportar: revisa el aviso en la app o el mensaje '
                  'del organizador.',
                ),
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
              ),
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

  List<pw.Widget> _seccionJugador(
    DesgloseJugador d, {
    List<DeudaPartidoAnterior> deudasAnteriores = const [],
  }) {
    final estado = _estadoJugadorPdf(d);

    return [
      pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: pw.BoxDecoration(
                color: estado.color,
                borderRadius: const pw.BorderRadius.only(
                  topLeft: pw.Radius.circular(7),
                  topRight: pw.Radius.circular(7),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    _pdf(d.nombre),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 13,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Text(
                    _pdf(estado.etiqueta),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 11,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: _cuentaJugador(
                  d,
                  deudasAnteriores: deudasAnteriores,
                  compacto: true,
                ),
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 14),
    ];
  }

  /// Bloque contable claro: partido → deuda anterior → total → abono → pendiente.
  List<pw.Widget> _cuentaJugador(
    DesgloseJugador d, {
    List<DeudaPartidoAnterior> deudasAnteriores = const [],
    required bool compacto,
  }) {
    final widgets = <pw.Widget>[];

    if (!compacto) {
      widgets.add(
        pw.Text(
          _pdf('Detalle de este encuentro'),
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
        ),
      );
      widgets.add(pw.SizedBox(height: 6));
    }

    widgets.add(_tablaItems(d.lineas));
    widgets.add(pw.SizedBox(height: 8));
    widgets.add(_filaTotal('Subtotal encuentro', d.totalPartido, bold: true));

    if (d.saldoAnterior != 0) {
      widgets.add(pw.SizedBox(height: 6));
      if (d.saldoAnterior > 0) {
        widgets.add(
          _filaTotal('Pendiente anterior', d.saldoAnterior, color: PdfColors.orange800),
        );
        if (deudasAnteriores.isNotEmpty) {
          for (final deuda in deudasAnteriores) {
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 12, top: 2),
                child: pw.Text(
                  _pdf(
                    '  - ${_lineaPartido(deuda.fecha, deuda.recinto)}: '
                    '${_fmt(deuda.pendienteNeto)}',
                  ),
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                ),
              ),
            );
          }
        }
      } else {
        widgets.add(
          _filaTotal(
            'Saldo a favor anterior',
            -d.saldoAnterior,
            color: PdfColors.blue800,
          ),
        );
      }
    }

    if (d.saldoFavorAplicado > 0) {
      widgets.add(
        _filaTotal(
          'Descuento saldo a favor',
          -d.saldoFavorAplicado,
          color: PdfColors.blue800,
        ),
      );
    }

    widgets.add(pw.SizedBox(height: 4));
    widgets.add(
      pw.Divider(color: PdfColors.grey400, thickness: 0.5),
    );
    widgets.add(pw.SizedBox(height: 4));

    final totalAPagar = d.totalDebido > 0 ? d.totalDebido : 0.0;
    widgets.add(
      _filaTotal('Total a aportar', totalAPagar, bold: true),
    );
    if (d.totalDebido <= 0 && d.saldoAnterior < 0) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            _pdf('El saldo a favor anterior cubre este encuentro.'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.blue800),
          ),
        ),
      );
    }

    if (d.montoPagado > 0) {
      widgets.add(
        _filaTotal('Aporte registrado', -d.montoPagado, color: PdfColors.green800),
      );
    }

    widgets.add(pw.SizedBox(height: 6));
    widgets.add(_filaResultadoFinal(d));

    return widgets;
  }

  pw.Widget _filaResultadoFinal(DesgloseJugador d) {
    final estado = _estadoJugadorPdf(d);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: estado.color,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            _pdf(estado.tituloResultado),
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11,
              color: PdfColors.white,
            ),
          ),
          pw.Text(
            _pdf(estado.montoResultado),
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 12,
              color: PdfColors.white,
            ),
          ),
        ],
      ),
    );
  }

  ({String etiqueta, String tituloResultado, String montoResultado, PdfColor color})
      _estadoJugadorPdf(DesgloseJugador d) {
    if (d.saldoRestante > 0) {
      return (
        etiqueta: d.pagoParcial ? 'Aporte parcial' : 'Pendiente',
        tituloResultado: 'PENDIENTE',
        montoResultado: _fmt(d.saldoRestante),
        color: PdfColors.red800,
      );
    }
    if (d.saldoRestante < 0) {
      return (
        etiqueta: 'Saldo a favor',
        tituloResultado: 'SALDO A FAVOR',
        montoResultado: _fmt(-d.saldoRestante),
        color: PdfColors.blue800,
      );
    }
    return (
      etiqueta: 'Al dia',
      tituloResultado: 'AL DIA',
      montoResultado: d.montoPagado > 0 ? 'Registrado ${_fmt(d.montoPagado)}' : 'Sin pendiente',
      color: PdfColors.green800,
    );
  }

  pw.Widget _tituloSeccion(String titulo) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const pw.BoxDecoration(
        color: PdfColors.green50,
        border: pw.Border(
          left: pw.BorderSide(color: PdfColors.green800, width: 3),
        ),
      ),
      child: pw.Text(
        _pdf(titulo),
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 12,
          color: PdfColors.green900,
        ),
      ),
    );
  }

  List<pw.Widget> _resumenGastosPartido(
    PartidoCompleto completo,
    int nAsistentes,
  ) {
    final p = completo.partido;
    final filas = <List<String>>[];
    var totalGastos = 0.0;

    if (p.costoCancha > 0) {
      totalGastos += p.costoCancha;
      final unit = nAsistentes > 0
          ? CalculationService.prorrateoCancha(
              costoCancha: p.costoCancha,
              cantidadAsistentes: nAsistentes,
            )
          : 0.0;
      filas.add([
        'Cancha',
        _fmt(p.costoCancha),
        nAsistentes > 0
            ? 'Entre $nAsistentes = ${_fmt(unit)} c/u'
            : 'Sin asistentes',
      ]);
    }

    if (p.costoPelotas > 0) {
      totalGastos += p.costoPelotas;
      final unit = nAsistentes > 0
          ? CalculationService.prorrateoPelotas(
              costoPelotas: p.costoPelotas,
              cantidadAsistentes: nAsistentes,
            )
          : 0.0;
      filas.add([
        'Pelotas',
        _fmt(p.costoPelotas),
        nAsistentes > 0
            ? 'Entre $nAsistentes = ${_fmt(unit)} c/u'
            : 'Sin asistentes',
      ]);
    }

    for (final cv in completo.costosVariables) {
      if (cv.montoTotal <= 0) continue;
      totalGastos += cv.montoTotal;
      final nAsignados =
          (completo.asignacionesPorCosto[cv.id] ?? []).length;
      filas.add([
        _pdf(cv.concepto),
        _fmt(cv.montoTotal),
        nAsignados > 0
            ? 'Asignado a $nAsignados participante${nAsignados == 1 ? '' : 's'}'
            : 'Sin asignar',
      ]);
    }

    if (filas.isEmpty) {
      return [
        _tituloSeccion('Gastos del encuentro'),
        pw.SizedBox(height: 8),
        pw.Text(
          _pdf('No hay gastos registrados en este encuentro.'),
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      ];
    }

    return [
      _tituloSeccion('Gastos del encuentro'),
      pw.SizedBox(height: 4),
      pw.Text(
        _pdf(
          nAsistentes > 0
              ? '$nAsistentes participante${nAsistentes == 1 ? '' : 's'} asistieron. '
                  'Cancha y pelotas se reparten en partes iguales.'
              : 'Sin asistentes registrados.',
        ),
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: ['Concepto', 'Total pagado', 'Reparto'],
        data: filas,
        headerStyle: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          fontSize: 10,
          color: PdfColors.white,
        ),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
        cellStyle: const pw.TextStyle(fontSize: 10),
        cellAlignment: pw.Alignment.centerLeft,
        columnWidths: {
          0: const pw.FlexColumnWidth(1.4),
          1: const pw.FlexColumnWidth(1.2),
          2: const pw.FlexColumnWidth(2.4),
        },
      ),
      pw.SizedBox(height: 6),
      _filaTotal('Total gastos del encuentro', totalGastos, bold: true),
    ];
  }

  pw.Widget _tablaResumenJugadores(List<DesgloseJugador> jugadores) {
    return pw.TableHelper.fromTextArray(
      headers: [
        'Participante',
        'Encuentro',
        'Pend. ant.',
        'Aporte',
        'Pendiente',
        'Estado',
      ],
      data: jugadores.map((d) {
        final estado = _estadoJugadorPdf(d);
        final deudaAnt = d.saldoAnterior > 0
            ? _fmt(d.saldoAnterior)
            : d.saldoAnterior < 0
                ? 'Favor ${_fmt(-d.saldoAnterior)}'
                : '-';
        final pendiente = d.saldoRestante > 0
            ? _fmt(d.saldoRestante)
            : d.saldoRestante < 0
                ? 'Favor ${_fmt(-d.saldoRestante)}'
                : '-';
        return [
          _pdf(d.nombre),
          _fmt(d.totalPartido),
          deudaAnt,
          d.montoPagado > 0 ? _fmt(d.montoPagado) : '-',
          pendiente,
          estado.etiqueta,
        ];
      }).toList(),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: 9,
        color: PdfColors.white,
      ),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      columnWidths: {
        0: const pw.FlexColumnWidth(1.8),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(0.9),
        4: const pw.FlexColumnWidth(1),
        5: const pw.FlexColumnWidth(0.9),
      },
    );
  }

  String _lineaPartido(DateTime fecha, String? recinto) {
    final f = _fechaDisplay(fecha);
    final r = recinto?.trim();
    if (r != null && r.isNotEmpty) return '$f - $r';
    return f;
  }

  List<pw.Widget> _encabezadoPartido(Partido partido, {String? titulo}) {
    final fecha = _fechaDisplay(partido.fecha);
    final sportPalette = SportThemeConfig.paletteFor(partido.sportType);
    final sportLabel = partido.sportType.labelEs;
    final encabezado = titulo ?? 'Informe $sportLabel — $fecha';
    return [
      pw.Text(
        _pdf(encabezado.contains(fecha) ? encabezado : '$encabezado $fecha'),
        style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 2),
      pw.Text(
        _pdf('${sportPalette.emoji} $sportLabel'),
        style: pw.TextStyle(fontSize: 12, color: PdfColors.grey800),
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

  pw.Widget _tablaItems(List<({String concepto, double monto})> lineas) {
    if (lineas.isEmpty) {
      return pw.Text(
        _pdf('Sin items de aporte registrados'),
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
    final pdfDir = Directory(p.join(dir.path, 'Kloovi', 'reportes'));
    if (!await pdfDir.exists()) await pdfDir.create(recursive: true);
    return pdfDir;
  }
}
