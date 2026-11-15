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

const _brown = PdfColor.fromInt(0xFF3E2723);
const _red = PdfColor.fromInt(0xFFC62828);
const _grey = PdfColor.fromInt(0xFF757575);
const _line = PdfColor.fromInt(0xFFBDBDBD);

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
  return [
    for (var d = 1; d <= days; d++)
      () {
        final date = '$month-${d.toString().padLeft(2, '0')}';
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
  final firstHalf = days.take(15).toList();
  final secondHalf = days.skip(15).toList();
  int sum(List<BillPdfDay> list) => list.fold(0, (s, d) => s + d.ml);

  final subtotal = bill['subtotal_paise'] as int? ?? bill['total_paise'] as int;
  final discount = bill['discount_paise'] as int? ?? 0;
  final percent = bill['discount_percent_bp'] as int?;
  final gst = bill['gst_paise'] as int? ?? 0;
  final total = bill['total_paise'] as int;
  final paid = bill['status'] == 'paid';
  // A "bill so far" for a month not billed yet (staff app).
  final notFinal = print['not_final'] == true;
  final rates = {for (final l in lines) l['unit_price_paise'] as int};
  final milkList = (bill['milk'] as List? ?? const [])
      .cast<Map<String, dynamic>>();
  final milkPaise = milkList.fold<int>(
    0,
    (s, m) => s + (m['amount_paise'] as int),
  );
  // Phone-order items, one row per product.
  final extras = <String, (int, int)>{};
  for (final i
      in (bill['items'] as List? ?? const []).cast<Map<String, dynamic>>()) {
    final key = '${i['product_name']} ${i['unit_label']}';
    final (q, a) = extras[key] ?? (0, 0);
    extras[key] = (q + (i['quantity'] as int), a + (i['amount_paise'] as int));
  }

  final phone = (customer['phone'] as String).replaceFirst('+91', '');
  final startDates = [for (final p in plans) p['start_date'] as String]..sort();
  final shifts = <String>{
    for (final s in const ['early_morning', 'morning', 'evening'])
      if (plans.any((p) => p['shift'] == s)) _shiftLabel(s),
  };
  final status = plans.any((p) => p['status'] == 'active')
      ? 'Active'
      : plans.any((p) => p['status'] == 'paused')
      ? 'Paused'
      : plans.isEmpty
      ? '-'
      : 'Cancelled';
  final freq = <String>{
    for (final p in plans)
      '${_frequencyLabel(p)} | ${_litresText(p['quantity_ml'] as int)}'
          '${plans.length > 1 ? ' (${_shiftLabel(p['shift'] as String)})' : ''}',
  }.join('; ');

  final upiId = settings['upi_id'] as String?;
  final payee = (settings['account_name'] as String?) ?? 'Sudhamrtam';
  final monthName = '${_months[m - 1]} $year';

  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  pw.Widget field(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 82,
          child: pw.Text('$label :', textAlign: pw.TextAlign.right),
        ),
        pw.SizedBox(width: 6),
        pw.Expanded(child: pw.Text(value, style: bold)),
      ],
    ),
  );

  pw.Widget dayTable(List<BillPdfDay> list) => pw.Table(
    border: pw.TableBorder.all(color: _line, width: 0.5),
    columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1)},
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F1F1)),
        children: [
          for (final h in const ['Date', 'Qty (Ltr)'])
            pw.Padding(
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text(h, style: bold, textAlign: pw.TextAlign.center),
            ),
        ],
      ),
      for (final d in list)
        pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(
                billPdfDate(d.date),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(
                d.text,
                textAlign: pw.TextAlign.center,
                style: d.missed
                    ? const pw.TextStyle(color: _red, fontSize: 8)
                    : d.paused
                    ? const pw.TextStyle(color: _grey, fontSize: 8)
                    : null,
              ),
            ),
          ],
        ),
    ],
  );

  pw.Widget amountRow(String label, String value, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text('$label =', style: strong ? bold : null),
            pw.SizedBox(width: 8),
            pw.Container(
              width: 90,
              alignment: pw.Alignment.centerRight,
              decoration: strong
                  ? const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(width: 0.8),
                        bottom: pw.BorderSide(width: 1.6),
                      ),
                    )
                  : null,
              child: pw.Text(
                value,
                style: strong ? bold.copyWith(fontSize: 12) : bold,
              ),
            ),
          ],
        ),
      );

  final doc = pw.Document(title: 'Sudhamrtam milk bill $monthName');
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
      theme: pw.ThemeData.withFont().copyWith(
        defaultTextStyle: const pw.TextStyle(fontSize: 9.5),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ---- Heading
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null)
                pw.Image(pw.MemoryImage(logo), width: 70, height: 70)
              else
                pw.SizedBox(width: 70),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'Sudhamrtam',
                      style: pw.TextStyle(
                        fontSize: 30,
                        fontWeight: pw.FontWeight.bold,
                        color: _brown,
                      ),
                    ),
                    pw.Text('Milk Bill', style: bold.copyWith(fontSize: 15)),
                    pw.Text(
                      '${billPdfLongDate('$month-01')}  to  '
                      '${billPdfLongDate('$month-${lastDay.toString().padLeft(2, '0')}')}',
                      style: const pw.TextStyle(
                        fontSize: 11,
                        decoration: pw.TextDecoration.underline,
                      ),
                    ),
                    if (settings['gstin'] != null)
                      pw.Text('GSTIN: ${settings['gstin']}'),
                    if (notFinal)
                      pw.Text(
                        lines.isEmpty
                            ? 'BILL SO FAR - NOT FINAL'
                            : 'BILL SO FAR - NOT FINAL (milk up to '
                                  '${billPdfLongDate(lines.last['delivery_date'] as String)})',
                        style: bold.copyWith(color: _red, fontSize: 11),
                      ),
                  ],
                ),
              ),
              pw.SizedBox(width: 70),
            ],
          ),
          pw.SizedBox(height: 8),
          // ---- Customer and plan
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  children: [
                    if (customer['reg_no'] != null)
                      field('Reg No', customer['reg_no'] as String),
                    field('Name', (customer['name'] as String?) ?? '-'),
                    field('Phone No', phone),
                    field('Address', (customer['address'] as String?) ?? '-'),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  children: [
                    field(
                      'Start Date',
                      startDates.isEmpty
                          ? '-'
                          : billPdfLongDate(startDates.first),
                    ),
                    field(
                      'Delivery Shift',
                      shifts.isEmpty ? '-' : shifts.join(', '),
                    ),
                    field('Freq & Qty', freq.isEmpty ? '-' : freq),
                    field('Status', status),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          // ---- Dates and litres, two halves
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: dayTable(firstHalf)),
              pw.SizedBox(width: 12),
              pw.Expanded(child: dayTable(secondHalf)),
            ],
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Center(
                  child: pw.Text(
                    'A = ${billPdfLitres(sum(firstHalf))}',
                    style: bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Text(
                    'B = ${billPdfLitres(sum(secondHalf))}',
                    style: bold,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 6),
          // ---- Amounts
          amountRow(
            'Total Litres (A+B)',
            billPdfLitres(sum(firstHalf) + sum(secondHalf)),
          ),
          if (rates.length == 1)
            amountRow(
              'Rate @ Rs.${billPdfAmount(rates.first).replaceAll('.00', '')}/- per litre',
              billPdfAmount(milkPaise),
            )
          else ...[
            for (final milk in milkList)
              amountRow(
                '${milk['product_name']} ${billPdfLitres(milk['quantity_ml'] as int)} L',
                billPdfAmount(milk['amount_paise'] as int),
              ),
          ],
          for (final e in extras.entries)
            amountRow(
              'Extra: ${e.key} x ${e.value.$1}',
              billPdfAmount(e.value.$2),
            ),
          amountRow('Actual amount', billPdfAmount(subtotal)),
          amountRow(
            percent == null
                ? 'Discount'
                : 'Discount (${(percent / 100).toStringAsFixed(percent % 100 == 0 ? 0 : 2)}%)',
            billPdfAmount(-discount),
          ),
          amountRow('GST', billPdfAmount(gst)),
          amountRow('Total (Rs.)', billPdfAmount(total), strong: true),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'In words : ${rupeesInWords(total)}',
              style: bold.copyWith(fontSize: 10.5),
            ),
          ),
          pw.Spacer(),
          // ---- Where to pay
          pw.Container(
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.8)),
            padding: const pw.EdgeInsets.all(8),
            child: paid
                ? pw.Center(
                    child: pw.Text(
                      'PAID - thank you!',
                      style: bold.copyWith(
                        fontSize: 16,
                        color: const PdfColor.fromInt(0xFF2E7D32),
                      ),
                    ),
                  )
                : pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              'Bank Details',
                              style: bold.copyWith(fontSize: 12),
                            ),
                            pw.SizedBox(height: 4),
                            field(
                              'Name',
                              (settings['account_name'] as String?) ?? '-',
                            ),
                            field(
                              'Account No',
                              (settings['account_number'] as String?) ?? '-',
                            ),
                            field(
                              'Bank Name',
                              (settings['bank_name'] as String?) ?? '-',
                            ),
                            field(
                              'IFSC Code',
                              (settings['ifsc'] as String?) ?? '-',
                            ),
                            field(
                              'Mobile No',
                              (settings['payee_phone'] as String?) ?? '-',
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 12),
                      pw.Column(
                        children: [
                          pw.Text(
                            'PhonePe / GPay',
                            style: bold.copyWith(fontSize: 12),
                          ),
                          pw.SizedBox(height: 4),
                          if (upiId != null) ...[
                            pw.BarcodeWidget(
                              barcode: pw.Barcode.qrCode(),
                              data: billUpiLink(
                                upiId: upiId,
                                payeeName: payee,
                                amountPaise: total,
                                note: 'Milk bill $monthName',
                              ),
                              width: 100,
                              height: 100,
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              'Scan to pay Rs.${billPdfAmount(total)}',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                            pw.Text(
                              'UPI ID : $upiId',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ] else
                            pw.SizedBox(
                              width: 110,
                              child: pw.Text(
                                'Pay in the Sudhamrtam app or in cash to our staff.',
                                textAlign: pw.TextAlign.center,
                                style: const pw.TextStyle(color: _grey),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Note : Please let us know if you find any discrepancy in the bill, '
            'and mention your tower and flat number.',
            style: bold.copyWith(color: _red, fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
