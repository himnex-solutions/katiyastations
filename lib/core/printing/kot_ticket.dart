// ============================================================
// KATIYA STATION RMS — KITCHEN ORDER TICKET (ESC/POS bytes)
// The paper a cook reads at the pass. Lives apart from the transport in
// thermal_printer_io.dart so the layout can be tested without a printer.
// Native only: pulled in through thermal_printer_io.dart, never on web.
// ============================================================

import 'dart:math' as math;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../utils/date_time_utils.dart';
import 'printer_config.dart';

/// Font A columns that fit on one line of this paper at normal width.
/// Double-width text fits half as many.
int paperCols(PrinterConfig cfg) => cfg.paperMm == 58 ? 32 : 48;

/// Hard-wraps [text] into lines of at most [width] characters, breaking on word
/// boundaries and prefixing continuation lines with [indent].
///
/// [Generator.text] never wraps — it hands the whole line to the printer, which
/// breaks it mid-word and, on some models, drops the tail outright. On a
/// kitchen ticket that can lose half an item name, so every line is measured
/// here against the real paper (32 columns on 58mm, 48 on 80mm) instead.
List<String> wrapForPaper(String text, int width, {String indent = ''}) {
  final safeWidth = math.max(width, indent.length + 4);
  final lines = <String>[];
  var line = '';
  var prefix = '';

  void push() {
    lines.add(prefix + line);
    line = '';
    prefix = indent;
  }

  for (var word in text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
    var room = safeWidth - prefix.length;
    // A single word too long for the paper is chopped across lines, never lost.
    while (word.length > room) {
      if (line.isNotEmpty) {
        push();
      } else {
        line = word.substring(0, room);
        word = word.substring(room);
        push();
      }
      room = safeWidth - prefix.length;
    }
    if (line.isEmpty) {
      line = word;
    } else if (line.length + 1 + word.length <= room) {
      line = '$line $word';
    } else {
      push();
      line = word;
    }
  }
  if (line.isNotEmpty) push();
  return lines;
}

/// Builds the KOT for [kot], which may be the socket payload (camelCase) or a
/// REST record (snake_case).
///
/// The ticket deliberately carries no branch name, address or phone: nobody at
/// the pass needs to be told where they work, and on an auto-printing station
/// every line is paper and seconds. What is left is what a cook actually reads
/// — table, KOT id, time, and the items with their quantities and notes — all
/// of it bold, with the table double-size so it carries across the kitchen.
Future<List<int>> buildKotBytes(
  PrinterConfig cfg,
  Map<String, dynamic> kot, {
  CapabilityProfile? profile,
}) async {
  final paper = cfg.paperMm == 58 ? PaperSize.mm58 : PaperSize.mm80;
  final g = Generator(paper, profile ?? await CapabilityProfile.load());
  var b = <int>[];

  final cols = paperCols(cfg);
  final bigCols = cols ~/ 2;

  final table = _f(kot, 'tableNumber', 'table_number');
  final kotNo = _f(kot, 'kotNumber', 'kot_number');
  final ticketNote = _f(kot, 'notes', 'notes');
  final title = _f(kot, 'title', 'title');
  final createdRaw = kot['createdAt'] ?? kot['created_at'];
  final when = DateTime.tryParse(createdRaw?.toString() ?? '') ?? DateTime.now();
  final items = (kot['items'] as List?) ?? const [];

  // Optional banner (e.g. "BAR") so a station's split ticket is unmistakable.
  if (title.isNotEmpty) {
    for (final line in wrapForPaper('*** $title ***', bigCols)) {
      b += g.text(line,
          styles: const PosStyles(
            align: PosAlign.center,
            bold: true,
            height: PosTextSize.size2,
            width: PosTextSize.size2,
          ));
    }
  }

  for (final line in wrapForPaper(table.isEmpty ? 'TAKEAWAY' : 'TABLE $table', bigCols)) {
    b += g.text(line,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ));
  }
  if (kotNo.isNotEmpty) {
    b += g.text(kotNo, styles: const PosStyles(align: PosAlign.center, bold: true));
  }
  b += g.text(formatDateTime(when), styles: const PosStyles(align: PosAlign.center, bold: true));
  b += g.hr(ch: '=');

  var totalQty = 0;
  for (final raw in items) {
    if (raw is! Map) continue;
    if ((raw['status'] as String?) == 'cancelled') continue;
    final name = (raw['name'] as String?)?.trim();
    if (name == null || name.isEmpty) continue;
    final qty = (raw['quantity'] as num?)?.toInt() ?? 1;
    totalQty += qty;

    // Quantity and name share one double-height line, so a count can never be
    // read off the neighbouring row.
    for (final line in wrapForPaper('$qty x ${name.toUpperCase()}', cols, indent: '    ')) {
      b += g.text(line, styles: const PosStyles(bold: true, height: PosTextSize.size2));
    }
    final note = (raw['note'] as String?)?.trim();
    if (note != null && note.isNotEmpty) {
      for (final line in wrapForPaper('>> $note', cols, indent: '   ')) {
        b += g.text(line, styles: const PosStyles(bold: true));
      }
    }
  }

  if (ticketNote.isNotEmpty) {
    b += g.hr();
    for (final line in wrapForPaper('NOTE: $ticketNote', cols, indent: '  ')) {
      b += g.text(line, styles: const PosStyles(bold: true));
    }
  }

  b += g.hr();
  b += g.text('Total items: $totalQty', styles: const PosStyles(bold: true, align: PosAlign.right));
  b += g.feed(2);
  b += g.cut();
  return b;
}

/// Reads a field by camelCase (socket payload) or snake_case (REST record).
String _f(Map m, String camel, String snake) => (m[camel] ?? m[snake] ?? '').toString().trim();
