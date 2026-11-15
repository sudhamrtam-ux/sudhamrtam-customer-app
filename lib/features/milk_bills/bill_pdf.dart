// Copied from the staff app (lib/features/bills/bill_pdf.dart); keep the two the same.
// The monthly milk bill as a PDF, laid out like Sudhamrtam's paper
// bill. The same file is in the staff app and the customer app; it
// takes the server's print data (GET .../bills/{id}/print) as JSON.
//
// The built-in PDF font has no ₹ sign, so amounts use "Rs.".

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Prints ([share] false) or shares the PDF. Tests replace it.
Future<void> Function(Uint8List bytes, String name, {required bool share})
outputBillPdf = (bytes, name, {required share}) async {
  if (share) {
    await Printing.sharePdf(bytes: bytes, filename: '$name.pdf');
  } else {
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
  }
};

/// The Sudhamrtam logo for the bill; null if it cannot be read.
Future<Uint8List?> billLogo() async {
  try {
    final data = await rootBundle.load('assets/images/sudhamrtam_logo.jpg');
    return data.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _red = PdfColor.fromInt(0xFFC62828);
const _grey = PdfColor.fromInt(0xFF757575);

/// "2026-10-05" → "05-10-26".
String billPdfDate(String iso) =>
    '${iso.substring(8, 10)}-${iso.substring(5, 7)}-${iso.substring(2, 4)}';

/// "2026-10-05" → "05-Oct-26".
String billPdfLongDate(String iso) =>
    '${iso.substring(8, 10)}-${_months[int.parse(iso.substring(5, 7)) - 1]}-'
    '${iso.substring(2, 4)}';

/// 139500 → "1,395.00" (Indian grouping).
String billPdfAmount(int paise) {
  final negative = paise < 0;
  final digits = (paise.abs() ~/ 100).toString();
  var whole = digits;
  if (digits.length > 3) {
    final head = digits.substring(0, digits.length - 3);
    final groups = <String>[];
    for (var end = head.length; end > 0; end -= 2) {
      groups.insert(0, head.substring(end - 2 < 0 ? 0 : end - 2, end));
    }
    whole = '${groups.join(',')},${digits.substring(digits.length - 3)}';
  }
  final rest = (paise.abs() % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}$whole.$rest';
}

/// 500 → "0.50".
String billPdfLitres(int ml) => (ml / 1000).toStringAsFixed(2);

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', //
  'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen',
  'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = [
  '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', //
  'Eighty', 'Ninety',
];

String _below100(int n) => n < 20
    ? _ones[n]
    : [_tens[n ~/ 10], _ones[n % 10]].where((w) => w.isNotEmpty).join(' ');

String _below1000(int n) => [
  if (n >= 100) '${_ones[n ~/ 100]} Hundred',
  if (n % 100 > 0) _below100(n % 100),
].join(' ');

/// Whole number in Indian words: crore, lakh, thousand, hundred.
String _indianWords(int n) {
  if (n == 0) return 'Zero';
  final parts = <String>[
    if (n >= 10000000) '${_indianWords(n ~/ 10000000)} Crore',
    if ((n ~/ 100000) % 100 > 0) '${_below100((n ~/ 100000) % 100)} Lakh',
    if ((n ~/ 1000) % 100 > 0) '${_below100((n ~/ 1000) % 100)} Thousand',
    if (n % 1000 > 0) _below1000(n % 1000),
  ];
  return parts.join(' ');
}

/// 139500 → "Rupees One Thousand Three Hundred Ninety Five Only."
String rupeesInWords(int paise) {
  final rupees = paise ~/ 100;
  final rest = paise % 100;
  final words = 'Rupees ${_indianWords(rupees)}';
  return rest == 0
      ? '$words Only.'
      : '$words and ${_below100(rest)} Paise Only.';
}

/// A UPI payment link for the QR: the payee, the amount and a note.
String billUpiLink({
  required String upiId,
  required String payeeName,
  required int amountPaise,
  required String note,
}) =>
    'upi://pay?pa=${Uri.encodeComponent(upiId)}'
    '&pn=${Uri.encodeComponent(payeeName)}'
    '&am=${(amountPaise / 100).toStringAsFixed(2)}&cu=INR'
    '&tn=${Uri.encodeComponent(note)}';

String _shiftLabel(String shift) => switch (shift) {
  'early_morning' => 'Early morning',
  'morning' => 'Morning',
  _ => 'Evening',
};

String _frequencyLabel(Map<String, dynamic> plan) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return switch (plan['frequency']) {
    'daily' => 'Daily',
    'alternate_days' => 'Alternate days',
    'selected_days' => [
      for (final d in (plan['weekdays'] as List).cast<num>())
        days[d.toInt() - 1],
    ].join(', '),
    _ => 'Chosen dates',
  };
}

/// Two decimals, like the day table: "1.50 litre".
String _litresText(int ml) => '${(ml / 1000).toStringAsFixed(2)} litre';

/// What one date shows: litres delivered, or why there were none.
class BillPdfDay {
  const BillPdfDay(
    this.date,
    this.text, {
    this.ml = 0,
    this.missed = false,
    this.paused = false,
  });

  final String date;
  final String text;
  final int ml;
  final bool missed;
  final bool paused;
}

/// Each date of the bill's month: the billed litres, or "Not
/// delivered" / "Paused" / "-".
List<BillPdfDay> billPdfDays(Map<String, dynamic> print) {
  final bill = print['bill'] as Map<String, dynamic>;
  final month = bill['month'] as String;
  final year = int.parse(month.substring(0, 4));
  final m = int.parse(month.substring(5, 7));
  final days = DateTime.utc(year, m + 1, 0).day;
  final billed = <String, int>{};
  for (final line in (bill['lines'] as List).cast<Map<String, dynamic>>()) {
    final date = line['delivery_date'] as String;
    billed[date] = (billed[date] ?? 0) + (line['quantity_ml'] as int);
  }
  final deliveries = (print['deliveries'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  // An early bill (customer moving out) ends on period_end.
  final end = bill['period_end'] as String?;
  return [
    for (var d = 1; d <= days; d++)
      () {
        final date = '$month-${d.toString().padLeft(2, '0')}';
        if (end != null && date.compareTo(end) > 0) {
          return BillPdfDay(date, '-');
        }
        final ml = billed[date];
        if (ml != null) return BillPdfDay(date, billPdfLitres(ml), ml: ml);
        final that = deliveries.where((x) => x['date'] == date);
        if (that.any((x) => x['outcome'] == 'not_delivered')) {
          return BillPdfDay(date, 'Not delivered', missed: true);
        }
        if (that.any((x) => x['outcome'] == 'paused')) {
          return BillPdfDay(date, 'Paused', paused: true);
        }
        return BillPdfDay(date, '-');
      }(),
  ];
}

// ---- Layout (owner request 2026-11-15: a professional bill) --------

/// Sudhamrtam's details, as on https://sudhamrtam.in.
const _company = 'Sudhamrtam Pvt. Ltd.';
const _companyAddress =
    '1-47, Donthi Village, Shivampet Mandal, Medak Dist, Telangana - 502334';
const _companyContact = '+91 86882 21433  |  sudhamrtam@gmail.com';

const _deep = PdfColor.fromInt(0xFF2E5A1C);
const _fresh = PdfColor.fromInt(0xFF82B440);
const _pale = PdfColor.fromInt(0xFFF1F6EA);
const _paleLine = PdfColor.fromInt(0xFFDCE6CF);
const _ink = PdfColor.fromInt(0xFF1F2A17);
const _muted = PdfColor.fromInt(0xFF6B7464);
const _paleRed = PdfColor.fromInt(0xFFFDECEA);
const _paleGrey = PdfColor.fromInt(0xFFF0F0F0);
const _amber = PdfColor.fromInt(0xFFB26A00);

/// The bill as an A4 PDF. [logo] is the Sudhamrtam logo (JPEG/PNG).
Future<Uint8List> buildBillPdf(
  Map<String, dynamic> print, {
  Uint8List? logo,
}) async {
  final bill = print['bill'] as Map<String, dynamic>;
  final customer = print['customer'] as Map<String, dynamic>;
  final settings = print['settings'] as Map<String, dynamic>;
  final plans = (print['plans'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  final lines = (bill['lines'] as List).cast<Map<String, dynamic>>();
  final month = bill['month'] as String;
  final year = int.parse(month.substring(0, 4));
  final m = int.parse(month.substring(5, 7));
  final lastDay = DateTime.utc(year, m + 1, 0).day;
  final days = billPdfDays(print);
  final totalMl = days.fold<int>(0, (s, d) => s + d.ml);
  final deliveredDays = days.where((d) => d.ml > 0).length;
  final missedDays = days.where((d) => d.missed).length;
  final pausedDays = days.where((d) => d.paused).length;

  final subtotal = bill['subtotal_paise'] as int? ?? bill['total_paise'] as int;
  final discount = bill['discount_paise'] as int? ?? 0;
  final percent = bill['discount_percent_bp'] as int?;
  final gst = bill['gst_paise'] as int? ?? 0;
  final total = bill['total_paise'] as int;
  final status = bill['status'] as String? ?? 'draft';
  final paid = status == 'paid';
  // A "bill so far" for a month not billed yet (staff app).
  final notFinal = print['not_final'] == true;
  final gstin = settings['gstin'] as String?;

  // Charges: each milk (litres at its rate), then phone-order items.
  final charges = <(String, String, String, String, int)>[];
  for (final milk
      in (bill['milk'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    final rates = {
      for (final l in lines)
        if (l['product_id'] == milk['product_id']) l['unit_price_paise'] as int,
    };
    final gstRate = milk['gst_rate_bp'] as int? ?? 0;
    charges.add((
      '${milk['product_name']}',
      gstRate > 0
          ? 'Monthly delivery · GST ${(gstRate / 100).toStringAsFixed(gstRate % 100 == 0 ? 0 : 2)}%'
          : 'Monthly delivery',
      '${billPdfLitres(milk['quantity_ml'] as int)} L',
      rates.length == 1 ? '${billPdfAmount(rates.first)} / L' : 'As per date',
      milk['amount_paise'] as int,
    ));
  }
  final extras = <String, (String, String, int, int, int)>{};
  for (final i
      in (bill['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    final key =
        '${i['product_name']}|${i['unit_label']}|${i['unit_price_paise']}';
    final old = extras[key];
    extras[key] = (
      i['product_name'] as String,
      i['unit_label'] as String,
      i['unit_price_paise'] as int,
      (old?.$4 ?? 0) + (i['quantity'] as int),
      (old?.$5 ?? 0) + (i['amount_paise'] as int),
    );
  }
  for (final e in extras.values) {
    charges.add((
      e.$1,
      'Extra order · ${e.$2} pack',
      '${e.$4} x ${e.$2}',
      '${billPdfAmount(e.$3)} each',
      e.$5,
    ));
  }

  final phone = (customer['phone'] as String).replaceFirst('+91', '');
  final regNo = customer['reg_no'] as String?;
  final startDates = [for (final p in plans) p['start_date'] as String]..sort();
  final planStatus = plans.any((p) => p['status'] == 'active')
      ? 'Active'
      : plans.any((p) => p['status'] == 'paused')
      ? 'Paused'
      : plans.isEmpty
      ? '-'
      : 'Cancelled';

  final upiId = settings['upi_id'] as String?;
  final payee = (settings['account_name'] as String?) ?? 'Sudhamrtam';
  final monthName = '${_months[m - 1]} $year';
  final periodEnd = bill['period_end'] as String?;
  final periodText =
      '${billPdfLongDate('$month-01')} to '
      '${billPdfLongDate(periodEnd ?? '$month-${lastDay.toString().padLeft(2, '0')}')}';
  final issued = bill['issued_at'] as String?;
  final billDate = issued != null && issued.length >= 10
      ? billPdfLongDate(issued.substring(0, 10))
      : '-';
  final dueDate = bill['due_date'] as String?;
  final billNo =
      '${regNo ?? 'SM'}/${month.replaceAll('-', '')}'
      '${notFinal ? '/DRAFT' : ''}';

  final (stampText, stampColor) = notFinal
      ? ('NOT FINAL', _amber)
      : paid
      ? ('PAID', _deep)
      : status == 'cancelled'
      ? ('CANCELLED', _red)
      : status == 'draft'
      ? ('DRAFT', _amber)
      : ('DUE', _red);

  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink);
  const small = pw.TextStyle(fontSize: 7.5, color: _muted);
  const label = pw.TextStyle(fontSize: 7, color: _muted, letterSpacing: 0.6);

  pw.Widget box(String title, List<pw.Widget> children) => pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _paleLine, width: 0.8),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title.toUpperCase(), style: label.copyWith(color: _deep)),
        pw.SizedBox(height: 5),
        ...children,
      ],
    ),
  );

  pw.Widget kv(String k, String v, {double width = 62}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: width,
          child: pw.Text(k, style: small),
        ),
        pw.Expanded(child: pw.Text(v, style: bold.copyWith(fontSize: 8.5))),
      ],
    ),
  );

  // ---- The month as a calendar: Monday first.
  final firstWeekday = DateTime.utc(year, m, 1).weekday; // 1 = Monday
  final cells = <BillPdfDay?>[
    for (var i = 1; i < firstWeekday; i++) null,
    ...days,
  ];
  while (cells.length % 7 != 0) {
    cells.add(null);
  }
  pw.Widget dayCell(BillPdfDay? d) {
    if (d == null) return pw.Container(height: 26);
    final (bg, fg, text) = d.ml > 0
        ? (_pale, _deep, '${billPdfLitres(d.ml)} L')
        : d.missed
        ? (_paleRed, _red, 'Missed')
        : d.paused
        ? (_paleGrey, _grey, 'Paused')
        : (PdfColors.white, _muted, '-');
    return pw.Container(
      height: 26,
      margin: const pw.EdgeInsets.all(1.2),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(3),
        border: pw.Border.all(color: _paleLine, width: 0.4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '${int.parse(d.date.substring(8, 10))}',
            style: const pw.TextStyle(fontSize: 6.5, color: _muted),
          ),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              text,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: fg,
                fontWeight: d.ml > 0 ? pw.FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget calendar() => pw.Column(
    children: [
      pw.Row(
        children: [
          for (final w in const [
            'MON',
            'TUE',
            'WED',
            'THU',
            'FRI',
            'SAT',
            'SUN',
          ])
            pw.Expanded(
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Text(w, style: label, textAlign: pw.TextAlign.center),
              ),
            ),
        ],
      ),
      for (var r = 0; r < cells.length; r += 7)
        pw.Row(
          children: [
            for (final c in cells.sublist(r, r + 7))
              pw.Expanded(child: dayCell(c)),
          ],
        ),
    ],
  );

  // ---- Charges table.
  pw.Widget cell(
    String text, {
    pw.TextAlign align = pw.TextAlign.left,
    pw.TextStyle? style,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4.5),
    child: pw.Text(text, textAlign: align, style: style),
  );

  pw.Widget chargesTable() => pw.Table(
    columnWidths: const {
      0: pw.FixedColumnWidth(24),
      1: pw.FlexColumnWidth(3.2),
      2: pw.FlexColumnWidth(1.3),
      3: pw.FlexColumnWidth(1.3),
      4: pw.FlexColumnWidth(1.2),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _paleLine, width: 0.5),
      bottom: pw.BorderSide(color: _paleLine, width: 0.8),
    ),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _deep),
        children: [
          for (final (h, a) in const [
            ('#', pw.TextAlign.center),
            ('ITEM', pw.TextAlign.left),
            ('QTY', pw.TextAlign.right),
            ('RATE (Rs.)', pw.TextAlign.right),
            ('AMOUNT (Rs.)', pw.TextAlign.right),
          ])
            cell(
              h,
              align: a,
              style: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 7.5,
              ),
            ),
        ],
      ),
      for (var i = 0; i < charges.length; i++)
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: i.isOdd ? const PdfColor.fromInt(0xFFFAFCF7) : null,
          ),
          children: [
            cell('${i + 1}', align: pw.TextAlign.center, style: small),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(charges[i].$1, style: bold.copyWith(fontSize: 9)),
                  pw.Text(charges[i].$2, style: small),
                ],
              ),
            ),
            cell(charges[i].$3, align: pw.TextAlign.right),
            cell(charges[i].$4, align: pw.TextAlign.right),
            cell(
              billPdfAmount(charges[i].$5),
              align: pw.TextAlign.right,
              style: bold.copyWith(fontSize: 9),
            ),
          ],
        ),
      if (charges.isEmpty)
        pw.TableRow(
          children: [
            cell(''),
            cell('No deliveries charged', style: small),
            cell(''),
            cell(''),
            cell('0.00', align: pw.TextAlign.right),
          ],
        ),
    ],
  );

  pw.Widget sumRow(String k, String v, {bool strong = false}) => pw.Container(
    padding: pw.EdgeInsets.symmetric(horizontal: 8, vertical: strong ? 6 : 2.5),
    decoration: strong
        ? pw.BoxDecoration(
            color: _deep,
            borderRadius: pw.BorderRadius.circular(4),
          )
        : null,
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            k,
            style: strong
                ? pw.TextStyle(
                    color: PdfColors.white,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10.5,
                  )
                : const pw.TextStyle(color: _muted, fontSize: 9),
          ),
        ),
        pw.Text(
          v,
          style: strong
              ? pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                )
              : bold.copyWith(fontSize: 9),
        ),
      ],
    ),
  );

  final doc = pw.Document(
    title: 'Sudhamrtam milk bill $monthName',
    author: _company,
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      theme: pw.ThemeData.withFont().copyWith(
        defaultTextStyle: const pw.TextStyle(fontSize: 8.5, color: _ink),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ---- Header band
          pw.Container(
            color: _deep,
            padding: const pw.EdgeInsets.fromLTRB(28, 18, 28, 16),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logo != null)
                  pw.Container(
                    width: 58,
                    height: 58,
                    padding: const pw.EdgeInsets.all(3),
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.white,
                      shape: pw.BoxShape.circle,
                    ),
                    child: pw.ClipOval(
                      child: pw.Image(
                        pw.MemoryImage(logo),
                        fit: pw.BoxFit.cover,
                      ),
                    ),
                  ),
                if (logo != null) pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SUDHAMRTAM',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      pw.Text(
                        'Pure  |  Natural  |  Traditional',
                        style: const pw.TextStyle(
                          color: _fresh,
                          fontSize: 8.5,
                          letterSpacing: 1,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _companyAddress,
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 7.5,
                        ),
                      ),
                      pw.Text(
                        _companyContact +
                            (gstin != null ? '  |  GSTIN: $gstin' : ''),
                        style: const pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 7.5,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      gstin != null ? 'TAX INVOICE' : 'MILK BILL',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    pw.Text(
                      monthName,
                      style: const pw.TextStyle(color: _fresh, fontSize: 10),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(10),
                      ),
                      child: pw.Text(
                        stampText,
                        style: pw.TextStyle(
                          color: stampColor,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 9,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ---- Bill facts strip
          pw.Container(
            color: _pale,
            padding: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 7),
            child: pw.Row(
              children: [
                for (final (k, v) in [
                  ('BILL NO', billNo),
                  ('BILL DATE', notFinal ? 'Not issued' : billDate),
                  ('BILLING PERIOD', periodText),
                  (
                    'DUE DATE',
                    dueDate == null ? '-' : billPdfLongDate(dueDate),
                  ),
                ])
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(k, style: label),
                        pw.SizedBox(height: 1.5),
                        pw.Text(v, style: bold.copyWith(fontSize: 9)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(28, 12, 28, 14),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  if (periodEnd != null && !notFinal)
                    pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        color: _pale,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        'Final bill up to ${billPdfLongDate(periodEnd)} '
                        '(made early, before the month ended).',
                        style: bold.copyWith(color: _deep),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  if (notFinal)
                    pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 8),
                      padding: const pw.EdgeInsets.all(6),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFFFFF4E0),
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        lines.isEmpty
                            ? 'Bill so far - not final. The month is not over yet.'
                            : 'Bill so far - not final. Milk up to '
                                  '${billPdfLongDate(lines.last['delivery_date'] as String)}; '
                                  'the final bill comes after the month ends.',
                        style: bold.copyWith(color: _amber),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  // ---- Bill to / milk plan
                  pw.Table(
                    columnWidths: const {
                      0: pw.FlexColumnWidth(),
                      1: pw.FixedColumnWidth(10),
                      2: pw.FlexColumnWidth(),
                    },
                    children: [
                      pw.TableRow(
                        verticalAlignment: pw.TableCellVerticalAlignment.full,
                        children: [
                          box('Bill to', [
                            pw.Text(
                              (customer['name'] as String?) ?? 'Customer',
                              style: bold.copyWith(fontSize: 11),
                            ),
                            pw.SizedBox(height: 3),
                            if (regNo != null) kv('Reg No', regNo),
                            kv('Phone', phone),
                            kv(
                              'Address',
                              (customer['address'] as String?) ?? '-',
                            ),
                          ]),
                          pw.SizedBox(width: 10),
                          box('Milk plan', [
                            if (plans.isEmpty)
                              pw.Text('No milk plan this month.', style: small)
                            else
                              for (final p in plans)
                                kv(
                                  _shiftLabel(p['shift'] as String),
                                  '${p['product_name'] ?? 'Milk'} · '
                                  '${_litresText(p['quantity_ml'] as int)} · '
                                  '${_frequencyLabel(p)}',
                                  width: 70,
                                ),
                            kv(
                              'Started on',
                              startDates.isEmpty
                                  ? '-'
                                  : billPdfLongDate(startDates.first),
                              width: 70,
                            ),
                            kv('Plan status', planStatus, width: 70),
                          ]),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  // ---- Deliveries
                  pw.Row(
                    children: [
                      pw.Text(
                        'DELIVERIES THIS MONTH',
                        style: label.copyWith(color: _deep),
                      ),
                      pw.Spacer(),
                      pw.Text(
                        'Delivered $deliveredDays day(s) · '
                        '${billPdfLitres(totalMl)} L'
                        '${missedDays > 0 ? '   ·   Missed $missedDays' : ''}'
                        '${pausedDays > 0 ? '   ·   Paused $pausedDays' : ''}',
                        style: small,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  calendar(),
                  pw.SizedBox(height: 10),
                  // ---- Charges
                  chargesTable(),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 4, right: 16),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('AMOUNT IN WORDS', style: label),
                              pw.SizedBox(height: 2),
                              pw.Text(
                                rupeesInWords(total),
                                style: bold.copyWith(fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.SizedBox(
                        width: 210,
                        child: pw.Column(
                          children: [
                            sumRow('Subtotal', billPdfAmount(subtotal)),
                            if (discount > 0)
                              sumRow(
                                percent == null
                                    ? 'Discount'
                                    : 'Discount (${(percent / 100).toStringAsFixed(percent % 100 == 0 ? 0 : 2)}%)',
                                '- ${billPdfAmount(discount)}',
                              ),
                            if (gst > 0) sumRow('GST', billPdfAmount(gst)),
                            pw.SizedBox(height: 3),
                            sumRow(
                              paid ? 'Amount paid (Rs.)' : 'Amount due (Rs.)',
                              billPdfAmount(total),
                              strong: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // ---- How to pay
                  if (paid) ...[
                    pw.SizedBox(height: 14),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        color: _pale,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Center(
                        child: pw.Text(
                          'PAID IN FULL - thank you!',
                          style: bold.copyWith(color: _deep, fontSize: 13),
                        ),
                      ),
                    ),
                    pw.Spacer(),
                  ] else if (status != 'cancelled') ...[
                    pw.Spacer(),
                    pw.Container(
                      padding: const pw.EdgeInsets.all(10),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: _paleLine, width: 0.8),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'PAY BY BANK TRANSFER',
                                  style: label.copyWith(color: _deep),
                                ),
                                pw.SizedBox(height: 4),
                                kv('Account name', payee, width: 72),
                                kv(
                                  'Account no',
                                  (settings['account_number'] as String?) ??
                                      '-',
                                  width: 72,
                                ),
                                kv(
                                  'Bank',
                                  (settings['bank_name'] as String?) ?? '-',
                                  width: 72,
                                ),
                                kv(
                                  'IFSC',
                                  (settings['ifsc'] as String?) ?? '-',
                                  width: 72,
                                ),
                                kv(
                                  'Mobile',
                                  (settings['payee_phone'] as String?) ?? '-',
                                  width: 72,
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  'Or pay in the Sudhamrtam app, or in cash to '
                                  'our staff. Please mention your Reg No.',
                                  style: small,
                                ),
                              ],
                            ),
                          ),
                          if (upiId != null) ...[
                            pw.SizedBox(width: 12),
                            pw.Column(
                              children: [
                                pw.Text(
                                  'SCAN TO PAY (UPI)',
                                  style: label.copyWith(color: _deep),
                                ),
                                pw.SizedBox(height: 4),
                                pw.BarcodeWidget(
                                  barcode: pw.Barcode.qrCode(),
                                  data: billUpiLink(
                                    upiId: upiId,
                                    payeeName: payee,
                                    amountPaise: total,
                                    note: 'Milk bill $monthName',
                                  ),
                                  width: 92,
                                  height: 92,
                                ),
                                pw.SizedBox(height: 3),
                                pw.Text(
                                  'Rs. ${billPdfAmount(total)}',
                                  style: bold.copyWith(fontSize: 9),
                                ),
                                pw.Text(upiId, style: small),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else
                    pw.Spacer(),
                  pw.SizedBox(height: 8),
                  pw.Divider(color: _paleLine, thickness: 0.6),
                  pw.Text(
                    'Thank you for choosing Sudhamrtam. Found something wrong in '
                    'this bill? Call or WhatsApp +91 86882 21433 with your Reg No.',
                    style: small.copyWith(color: _ink),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'This is a computer-generated bill and needs no signature.',
                    style: small,
                    textAlign: pw.TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
