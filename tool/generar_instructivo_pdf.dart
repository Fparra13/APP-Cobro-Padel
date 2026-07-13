import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Genera INSTRUCTIVO.pdf desde el contenido de la guía de uso.
/// Ejecutar: dart run tool/generar_instructivo_pdf.dart
Future<void> main() async {
  final pdf = pw.Document();
  final now = DateTime.now();
  final fecha =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => [
        pw.Text(
          'Kloovi - Guia de uso',
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'App para organizar partidos, repartir gastos y llevar el cobro del grupo.',
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey800),
        ),
        pw.Text(
          'Generado: $fecha',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 20),
        ..._secciones(),
      ],
    ),
  );

  final bytes = await pdf.save();
  final root = Directory.current;
  final out = File('${root.path}/INSTRUCTIVO.pdf');
  await out.writeAsBytes(bytes);

  final desktop = File('${Platform.environment['HOME']}/Desktop/INSTRUCTIVO_Kloovi.pdf');
  await desktop.writeAsBytes(bytes);

  stdout.writeln('PDF generado: ${out.path}');
  stdout.writeln('Copia en Escritorio: ${desktop.path}');
}

List<pw.Widget> _secciones() {
  return [
    _titulo('1. Primeros pasos'),
    _lista([
      'Config (menu inferior): ingresa datos bancarios (titular, banco, cuenta). Se usan en WhatsApp y PDF.',
      'Jugadores: agrega a tu grupo con nombre y WhatsApp (opcional pero recomendado).',
      'Marca Jugador habitual a quienes juegan seguido; aparecen al crear partidos.',
    ]),
    _titulo('2. Menu principal'),
    _tabla([
      ['Pestana', 'Para que sirve'],
      ['Inicio', 'Resumen de deudas, pagos rapidos y accesos directos'],
      ['Jugadores', 'Crear, editar y ver fichas'],
      ['Historial', 'Partidos jugados y ranking del grupo'],
      ['Respaldo', 'Exportar/importar datos y PDF de saldos'],
      ['Config', 'Datos bancarios y recordatorios automaticos'],
    ]),
    _titulo('3. Crear un partido'),
    pw.Text(
      'Toca el boton verde Partido (abajo a la derecha en Inicio):',
      style: const pw.TextStyle(fontSize: 10),
    ),
    pw.SizedBox(height: 6),
    _subtitulo('A) Organizar convocatoria (antes de jugar, sin cobros)'),
    _lista([
      'Define fecha, recinto, cupos e invita jugadores.',
      'Marca quien confirmo, rechazo o esta invitado.',
      'Compartir convocatoria por WhatsApp (grupo o directo).',
      'Importar respuestas pegando mensajes del chat.',
      'Al confirmar el partido: Ir a cobrar para registrar gastos y pagos.',
    ]),
    _subtitulo('B) Registrar partido jugado (con cobros)'),
    pw.Text('Completa en este orden:', style: const pw.TextStyle(fontSize: 10)),
    pw.SizedBox(height: 4),
    _lista([
      'Datos: fecha, recinto y notas.',
      'Gastos: Cancha, Pelotas, Asado, Barra Schop, Otros. Cancha y pelotas se reparten entre asistentes. Asado, schop y otros: marca quien participo.',
      'Jugadores y pagos: Pago total (al dia), Abono (confirmar abono) o Sin pago (deuda).',
      'Resumen: revisa totales y guarda.',
    ]),
    pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4, bottom: 8),
      child: pw.Text(
        'Las deudas anteriores se suman automaticamente. Un abono mayor al total genera saldo a favor.',
        style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
      ),
    ),
    _titulo('4. Inicio - operaciones diarias'),
    _subtitulo('Resumen del grupo'),
    pw.Text('Muestra total por cobrar, jugadores con deuda y al dia.',
        style: const pw.TextStyle(fontSize: 10)),
    pw.SizedBox(height: 6),
    _subtitulo('Herramientas'),
    _lista([
      'PDF saldos: informe del grupo.',
      'Ultimo partido: ver, editar o generar PDF.',
      'Recordar deudores: WhatsApp masivo a quienes deben.',
      'Jugadores: ir a la lista.',
    ]),
    _subtitulo('Registrar pagos (planilla)'),
    _lista([
      'Marca uno o mas deudores.',
      'Varios seleccionados: pago total de cada uno.',
      'Un solo jugador: pago total o abono parcial.',
    ]),
    _titulo('5. Ficha del jugador'),
    _lista([
      'Accede desde Ver ficha de un jugador (Inicio) o tocando un jugador.',
      'Saldo actual, partidos jugados y pagados.',
      'Historial de cargos y abonos (filtros por tipo).',
      'Foto del jugador (opcional).',
      'Registrar pago manual (total o abono).',
      'Recordar / WhatsApp: detalle del partido, deuda anterior y datos de transferencia.',
    ]),
    _titulo('6. Jugadores'),
    _lista([
      'Nuevo jugador: nombre, WhatsApp y si es habitual.',
      'Toca una tarjeta para ficha o editar.',
      'Estadisticas (icono arriba): participacion, buen pagador, pago rapido, activo reciente, convocatorias, total aportado, mayor deuda.',
    ]),
    _titulo('7. Historial y ranking'),
    _lista([
      'Partidos: lista de jugados y convocatorias. Detalle, editar, PDF o eliminar.',
      'Ranking: clasificacion del grupo por partidos y otros criterios.',
    ]),
    _titulo('8. WhatsApp'),
    _lista([
      'La app abre WhatsApp con el mensaje listo.',
      'Incluye: detalle del partido, deuda anterior, total pendiente y datos bancarios.',
      'Requisito: el jugador debe tener numero de WhatsApp guardado.',
    ]),
    _titulo('9. Respaldo'),
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(
        'Haz respaldo antes de cambiar de celular. Los datos viven solo en el telefono.',
        style: pw.TextStyle(fontSize: 9, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700),
      ),
    ),
    _lista([
      'Exportar .db: copia exacta de la base de datos.',
      'Exportar JSON: formato legible.',
      'Importar: restaura un respaldo (reemplaza todo).',
      'Reporte PDF de saldos: desde Respaldo o Inicio.',
    ]),
    _titulo('10. Configuracion'),
    _subtitulo('Datos bancarios'),
    pw.Text('Titular, banco, cuenta y RUT. Aparecen en mensajes y reportes.',
        style: const pw.TextStyle(fontSize: 10)),
    pw.SizedBox(height: 6),
    _subtitulo('Recordatorios automaticos'),
    _lista([
      'Notificacion si hay deudas sin cobrar despues de X dias.',
      'Configura: activar/desactivar, dias de espera (1-30), hora del aviso.',
    ]),
    _titulo('Flujo tipico'),
    pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColors.green50,
        borderRadius: pw.BorderRadius.circular(6),
        border: pw.Border.all(color: PdfColors.green200),
      ),
      child: pw.Text(
        'Agregar jugadores -> Organizar convocatoria -> Confirmar asistentes '
        '-> Ir a cobrar -> Registrar gastos y pagos -> Recordar deudores por WhatsApp\n\n'
        'O directamente: Registrar partido jugado si no necesitas convocatoria previa.',
        style: const pw.TextStyle(fontSize: 10),
      ),
    ),
    pw.SizedBox(height: 12),
    _titulo('Consejos'),
    _lista([
      'Desliza hacia abajo en cualquier lista para actualizar.',
      'Usa Respaldo con frecuencia.',
      'Los habituales ahorran tiempo al armar partidos.',
      'Si alguien transfiere despues, usa Registrar pagos en Inicio o en su ficha.',
    ]),
  ];
}

pw.Widget _titulo(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10, bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.green800,
      ),
    ),
  );
}

pw.Widget _subtitulo(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _lista(List<String> items) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: items
        .map(
          (item) => pw.Padding(
            padding: const pw.EdgeInsets.only(left: 8, bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('- ', style: const pw.TextStyle(fontSize: 10)),
                pw.Expanded(
                  child: pw.Text(item, style: const pw.TextStyle(fontSize: 10)),
                ),
              ],
            ),
          ),
        )
        .toList(),
  );
}

pw.Widget _tabla(List<List<String>> rows) {
  return pw.TableHelper.fromTextArray(
    data: rows,
    headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
    cellStyle: const pw.TextStyle(fontSize: 10),
    cellAlignment: pw.Alignment.centerLeft,
    headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
    cellHeight: 22,
    columnWidths: {
      0: const pw.FlexColumnWidth(1.2),
      1: const pw.FlexColumnWidth(2.8),
    },
  );
}
