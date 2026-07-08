// ============================================================
// KATIYA STATION RMS — REPORT EXPORT
// Builds professional PDF and Excel documents from a [ReportData]
// snapshot and delivers them cross-platform (web / Android / Windows):
//   • print      → native print dialog (Printing)
//   • PDF        → share / download (Printing)
//   • Excel      → save / download (FileSaver)
// Shared by the Manager and Cashier report screens.
// ============================================================

import 'dart:typed_data';

import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Non-error signal shown to the user as an info message rather than a
/// failure — e.g. when printing falls back to a PDF download.
class ExportNotice implements Exception {
  final String message;
  ExportNotice(this.message);
  @override
  String toString() => message;
}

/// Cross-platform byte save/download that does NOT use a plugin method
/// channel (file_saver web uses direct browser APIs), so it works even
/// when other native plugins aren't registered.
Future<void> _saveBytes(Uint8List bytes, String name, String ext, MimeType mime) async {
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    fileExtension: ext,
    mimeType: mime,
  );
}

// ── Report model ────────────────────────────────────────────

class ReportMetric {
  final String label;
  final double value;
  final bool isCount; // render as a plain integer instead of currency
  const ReportMetric(this.label, this.value, {this.isCount = false});
}

class ReportPaymentRow {
  final String method;
  final int count;
  final double amount;
  const ReportPaymentRow(this.method, this.count, this.amount);
}

class ReportData {
  final String title; // e.g. "Sales Report" / "Financial Report"
  final String branchName;
  final String generatedBy; // "Full Name (Role)"
  final String timeframe; // Daily / Weekly / Monthly / Yearly
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final List<ReportMetric> summary;
  final List<ReportPaymentRow> paymentBreakdown;
  final List<Map<String, dynamic>> transactions; // recent bills (may be empty)
  final String highlightLabel; // headline figure (Net Profit / Total Collected)
  final double highlightValue;
  final bool highlightGoodWhenPositive;

  const ReportData({
    required this.title,
    required this.branchName,
    required this.generatedBy,
    required this.timeframe,
    required this.rangeStart,
    required this.rangeEnd,
    required this.summary,
    required this.paymentBreakdown,
    required this.transactions,
    required this.highlightLabel,
    required this.highlightValue,
    this.highlightGoodWhenPositive = true,
  });

  String get fileName =>
      'Katiya_Station_${timeframe}_Report_${DateFormat('yyyy-MM-dd').format(rangeEnd)}';
}

// ── Formatting helpers ──────────────────────────────────────

final _money = NumberFormat('#,##0.00');
String _npr(double v) => 'NPR ${_money.format(v)}';
String _rangeLabel(ReportData d) =>
    '${DateFormat('dd MMM yyyy').format(d.rangeStart)}  –  ${DateFormat('dd MMM yyyy').format(d.rangeEnd)}';

String _prettyMethod(String raw) {
  if (raw.isEmpty) return '—';
  return raw
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

// ── Public actions ──────────────────────────────────────────

Future<void> printReport(ReportData data) async {
  final bytes = await buildReportPdf(data);
  try {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: data.fileName);
  } on MissingPluginException {
    // The printing plugin isn't registered on this build (a newly added
    // plugin needs a full app rebuild, not a hot restart). Rather than
    // failing, hand the user the PDF to open and print themselves.
    await _saveBytes(bytes, data.fileName, 'pdf', MimeType.pdf);
    throw ExportNotice(
        'Printing isn’t available on this build — the report was downloaded as a PDF instead. Open it and print from there.');
  }
}

Future<void> downloadReportPdf(ReportData data) async {
  final bytes = await buildReportPdf(data);
  // Deliver via file_saver (no plugin method channel) so this works even
  // where Printing.sharePdf would throw MissingPluginException.
  await _saveBytes(bytes, data.fileName, 'pdf', MimeType.pdf);
}

Future<void> downloadReportExcel(ReportData data) async {
  final bytes = buildReportExcel(data);
  await _saveBytes(Uint8List.fromList(bytes), data.fileName, 'xlsx', MimeType.microsoftExcel);
}

// ── PDF ─────────────────────────────────────────────────────

final PdfColor _brand = PdfColor.fromHex('#B3122A');
final PdfColor _ink = PdfColor.fromHex('#1C1C1E');
final PdfColor _muted = PdfColor.fromHex('#6B7280');

Future<Uint8List> buildReportPdf(ReportData d) async {
  final doc = pw.Document(title: d.fileName);
  final good = d.highlightGoodWhenPositive
      ? d.highlightValue >= 0
      : d.highlightValue <= 0;
  final highlightColor = good ? PdfColor.fromHex('#1B8E5A') : _brand;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 36),
      header: (ctx) => ctx.pageNumber == 1 ? _pdfHeader(d) : _pdfRunningHeader(d),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'Katiya Station RMS   •   Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ),
      build: (ctx) => [
        _pdfMetaBlock(d),
        pw.SizedBox(height: 6),
        _pdfHighlight(d.highlightLabel, _npr(d.highlightValue), highlightColor),
        pw.SizedBox(height: 18),
        _pdfSectionTitle('Summary'),
        pw.SizedBox(height: 6),
        _pdfSummaryTable(d),
        if (d.paymentBreakdown.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          _pdfSectionTitle('Payment Breakdown'),
          pw.SizedBox(height: 6),
          _pdfPaymentTable(d),
        ],
        if (d.transactions.isNotEmpty) ...[
          pw.SizedBox(height: 18),
          _pdfSectionTitle('Recent Transactions (latest ${d.transactions.length})'),
          pw.SizedBox(height: 6),
          _pdfTransactionsTable(d),
        ],
      ],
    ),
  );

  return doc.save();
}

pw.Widget _pdfHeader(ReportData d) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: _brand,
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('KATIYA STATION',
                style: pw.TextStyle(
                    color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
            pw.Text('Restaurant & Bar — Management System',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
          ],
        ),
        pw.Spacer(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(d.title,
                style: pw.TextStyle(
                    color: PdfColors.white, fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Text('${d.timeframe} Report',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 9)),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _pdfRunningHeader(ReportData d) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      padding: const pw.EdgeInsets.only(bottom: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _brand, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Katiya Station — ${d.title}',
              style: pw.TextStyle(fontSize: 9, color: _brand, fontWeight: pw.FontWeight.bold)),
          pw.Text('${d.timeframe}  •  ${_rangeLabel(d)}',
              style: pw.TextStyle(fontSize: 8, color: _muted)),
        ],
      ),
    );

pw.Widget _pdfMetaRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(text: '$label:  ', style: pw.TextStyle(fontSize: 9, color: _muted)),
          pw.TextSpan(text: value, style: pw.TextStyle(fontSize: 9, color: _ink, fontWeight: pw.FontWeight.bold)),
        ]),
      ),
    );

pw.Widget _pdfHighlight(String label, String value, PdfColor color) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(14),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F6F7F9'),
      borderRadius: pw.BorderRadius.circular(8),
      border: pw.Border.all(color: PdfColor.fromHex('#E5E7EB')),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(label.toUpperCase(),
            style: pw.TextStyle(fontSize: 11, color: _muted, letterSpacing: 0.5, fontWeight: pw.FontWeight.bold)),
        pw.Text(value, style: pw.TextStyle(fontSize: 18, color: color, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );
}

pw.Widget _pdfSectionTitle(String text) => pw.Text(text,
    style: pw.TextStyle(fontSize: 12, color: _ink, fontWeight: pw.FontWeight.bold));

pw.Widget _pdfSummaryTable(ReportData d) {
  return pw.TableHelper.fromTextArray(
    headers: ['Metric', 'Value'],
    data: d.summary
        .map((m) => [m.label, m.isCount ? m.value.toInt().toString() : _npr(m.value)])
        .toList(),
    headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
    headerDecoration: pw.BoxDecoration(color: _brand),
    cellStyle: pw.TextStyle(fontSize: 9, color: _ink),
    rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E5E7EB'), width: .5))),
    cellHeight: 22,
    cellAlignments: {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
    columnWidths: {0: const pw.FlexColumnWidth(2.6), 1: const pw.FlexColumnWidth(1.4)},
  );
}

pw.Widget _pdfPaymentTable(ReportData d) {
  return pw.TableHelper.fromTextArray(
    headers: ['Payment Method', 'Transactions', 'Amount'],
    data: d.paymentBreakdown
        .map((r) => [_prettyMethod(r.method), r.count.toString(), _npr(r.amount)])
        .toList(),
    headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9),
    headerDecoration: pw.BoxDecoration(color: _brand),
    cellStyle: pw.TextStyle(fontSize: 9, color: _ink),
    rowDecoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColor.fromHex('#E5E7EB'), width: .5))),
    cellHeight: 20,
    cellAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.center,
      2: pw.Alignment.centerRight,
    },
  );
}

pw.Widget _pdfTransactionsTable(ReportData d) {
  return pw.TableHelper.fromTextArray(
    headers: ['Date & Time', 'Bill #', 'Method', 'Status', 'Amount'],
    data: d.transactions.map((b) {
      final dt = DateTime.tryParse(b['created_at'] as String? ?? '')?.toLocal();
      return [
        dt != null ? DateFormat('dd MMM yy, hh:mm a').format(dt) : '—',
        (b['bill_number'] as String?) ?? '—',
        _prettyMethod((b['payment_method'] as String?) ?? ''),
        _prettyMethod((b['payment_status'] as String?) ?? ''),
        _npr((b['total_amount'] as num?)?.toDouble() ?? 0),
      ];
    }).toList(),
    headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8.5),
    headerDecoration: pw.BoxDecoration(color: _ink),
    cellStyle: pw.TextStyle(fontSize: 8, color: _ink),
    oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#F6F7F9')),
    cellHeight: 18,
    cellAlignments: {
      0: pw.Alignment.centerLeft,
      1: pw.Alignment.centerLeft,
      2: pw.Alignment.centerLeft,
      3: pw.Alignment.centerLeft,
      4: pw.Alignment.centerRight,
    },
    columnWidths: {
      0: const pw.FlexColumnWidth(2.2),
      1: const pw.FlexColumnWidth(1.6),
      2: const pw.FlexColumnWidth(1.3),
      3: const pw.FlexColumnWidth(1.1),
      4: const pw.FlexColumnWidth(1.4),
    },
  );
}

// The meta block (branch / period / generated) sits under the header on p.1.
// Kept as a build() item via a wrapper so it flows with the content.
pw.Widget _pdfMetaBlock(ReportData d) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _pdfMetaRow('Branch', d.branchName),
            _pdfMetaRow('Period', _rangeLabel(d)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            _pdfMetaRow('Generated', DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())),
            _pdfMetaRow('By', d.generatedBy),
          ]),
        ],
      ),
    );

// ── Excel ───────────────────────────────────────────────────

List<int> buildReportExcel(ReportData d) {
  final excel = Excel.createExcel();
  const sheetName = 'Report';
  final Sheet s = excel[sheetName];
  // Drop the auto-created default sheet so only ours remains.
  if (excel.sheets.keys.contains('Sheet1') && sheetName != 'Sheet1') {
    excel.delete('Sheet1');
  }
  excel.setDefaultSheet(sheetName);

  s.setColumnWidth(0, 30);
  s.setColumnWidth(1, 18);
  s.setColumnWidth(2, 16);
  s.setColumnWidth(3, 14);
  s.setColumnWidth(4, 16);

  // ExcelColor.fromHexString expects 8-digit ARGB (no leading '#').
  final titleStyle = CellStyle(
      bold: true, fontSize: 16, fontColorHex: ExcelColor.white, backgroundColorHex: ExcelColor.fromHexString('FFB3122A'));
  final subStyle = CellStyle(fontSize: 10, fontColorHex: ExcelColor.fromHexString('FF555555'));
  final metaLabelStyle = CellStyle(bold: true, fontSize: 10);
  final sectionStyle = CellStyle(
      bold: true, fontSize: 12, fontColorHex: ExcelColor.white, backgroundColorHex: ExcelColor.fromHexString('FFB3122A'));
  final headerStyle = CellStyle(bold: true, fontColorHex: ExcelColor.white, backgroundColorHex: ExcelColor.fromHexString('FF1C1C1E'));
  final labelStyle = CellStyle(bold: false);
  final valueStyle = CellStyle(horizontalAlign: HorizontalAlign.Right);
  final highlightStyle = CellStyle(bold: true, fontSize: 13, backgroundColorHex: ExcelColor.fromHexString('FFF0F0F0'));

  int r = 0;

  void put(int col, int row, CellValue v, {CellStyle? style}) {
    final c = s.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    c.value = v;
    if (style != null) c.cellStyle = style;
  }

  void mergeRow(int row, int fromCol, int toCol) {
    s.merge(CellIndex.indexByColumnRow(columnIndex: fromCol, rowIndex: row),
        CellIndex.indexByColumnRow(columnIndex: toCol, rowIndex: row));
  }

  // Title band
  put(0, r, TextCellValue('KATIYA STATION — ${d.title}'), style: titleStyle);
  mergeRow(r, 0, 4);
  r++;
  put(0, r, TextCellValue('Restaurant & Bar — Management System'), style: subStyle);
  mergeRow(r, 0, 4);
  r += 2;

  // Meta
  put(0, r, TextCellValue('Branch'), style: metaLabelStyle);
  put(1, r, TextCellValue(d.branchName));
  r++;
  put(0, r, TextCellValue('Timeframe'), style: metaLabelStyle);
  put(1, r, TextCellValue(d.timeframe));
  r++;
  put(0, r, TextCellValue('Period'), style: metaLabelStyle);
  put(1, r, TextCellValue(_rangeLabel(d)));
  r++;
  put(0, r, TextCellValue('Generated'), style: metaLabelStyle);
  put(1, r, TextCellValue(DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())));
  r++;
  put(0, r, TextCellValue('Generated By'), style: metaLabelStyle);
  put(1, r, TextCellValue(d.generatedBy));
  r += 2;

  // Highlight
  put(0, r, TextCellValue(d.highlightLabel), style: highlightStyle);
  put(1, r, DoubleCellValue(d.highlightValue), style: highlightStyle);
  r += 2;

  // Summary
  put(0, r, TextCellValue('SUMMARY'), style: sectionStyle);
  mergeRow(r, 0, 4);
  r++;
  put(0, r, TextCellValue('Metric'), style: headerStyle);
  put(1, r, TextCellValue('Value'), style: headerStyle);
  r++;
  for (final m in d.summary) {
    put(0, r, TextCellValue(m.label), style: labelStyle);
    put(1, r, m.isCount ? IntCellValue(m.value.toInt()) : DoubleCellValue(m.value), style: valueStyle);
    r++;
  }
  r++;

  // Payment breakdown
  if (d.paymentBreakdown.isNotEmpty) {
    put(0, r, TextCellValue('PAYMENT BREAKDOWN'), style: sectionStyle);
    mergeRow(r, 0, 4);
    r++;
    put(0, r, TextCellValue('Payment Method'), style: headerStyle);
    put(1, r, TextCellValue('Transactions'), style: headerStyle);
    put(2, r, TextCellValue('Amount'), style: headerStyle);
    r++;
    for (final row in d.paymentBreakdown) {
      put(0, r, TextCellValue(_prettyMethod(row.method)));
      put(1, r, IntCellValue(row.count), style: valueStyle);
      put(2, r, DoubleCellValue(row.amount), style: valueStyle);
      r++;
    }
    r++;
  }

  // Transactions
  if (d.transactions.isNotEmpty) {
    put(0, r, TextCellValue('RECENT TRANSACTIONS'), style: sectionStyle);
    mergeRow(r, 0, 4);
    r++;
    put(0, r, TextCellValue('Date & Time'), style: headerStyle);
    put(1, r, TextCellValue('Bill #'), style: headerStyle);
    put(2, r, TextCellValue('Method'), style: headerStyle);
    put(3, r, TextCellValue('Status'), style: headerStyle);
    put(4, r, TextCellValue('Amount'), style: headerStyle);
    r++;
    for (final b in d.transactions) {
      final dt = DateTime.tryParse(b['created_at'] as String? ?? '')?.toLocal();
      put(0, r, TextCellValue(dt != null ? DateFormat('dd MMM yy, hh:mm a').format(dt) : '—'));
      put(1, r, TextCellValue((b['bill_number'] as String?) ?? '—'));
      put(2, r, TextCellValue(_prettyMethod((b['payment_method'] as String?) ?? '')));
      put(3, r, TextCellValue(_prettyMethod((b['payment_status'] as String?) ?? '')));
      put(4, r, DoubleCellValue((b['total_amount'] as num?)?.toDouble() ?? 0), style: valueStyle);
      r++;
    }
  }

  return excel.save(fileName: '${d.fileName}.xlsx') ?? <int>[];
}
