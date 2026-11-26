// An order receipt as a PDF (owner request 2026-11-26): who it is billed
// to and delivered to, the items, the total and the payment, in the
// milk bill's look. The built-in PDF font has no ₹ sign, so amounts use
// "Rs.".

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/combo_offer.dart';
import '../../models/customer_order.dart';
import '../milk_bills/bill_pdf.dart'
    show billPdfAmount, billPdfLongDate, rupeesInWords;

const _company = 'Sudhamrtam';
const _companyAddress =
    '1-47, Donthi Village, Shivampet Mandal, Medak Dist, Telangana - 502334';
const _companyContact = '+91 86882 21433  |  sudhamrtam@gmail.com';

const _deep = PdfColor.fromInt(0xFF2E5A1C);
const _fresh = PdfColor.fromInt(0xFF82B440);
const _pale = PdfColor.fromInt(0xFFF1F6EA);
const _paleLine = PdfColor.fromInt(0xFFDCE6CF);
const _ink = PdfColor.fromInt(0xFF1F2A17);
const _muted = PdfColor.fromInt(0xFF6B7464);

int _paise(double rupees) => (rupees * 100).round();

/// The built-in PDF font has no ₹ or ×: "Rs." and "x" instead.
String _plain(String text) => text.replaceAll('₹', 'Rs. ').replaceAll('×', 'x');

/// "2026-11-26T07:09" → "26-Nov-26, 07:09".
String _placed(DateTime at) {
  final l = at.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${billPdfLongDate('${l.year}-${two(l.month)}-${two(l.day)}')}, '
      '${two(l.hour)}:${two(l.minute)}';
}

/// The receipt for [order] as an A4 PDF. [orderRef] is its short
/// number (e.g. SUD0000027) when known; [payment] says how it is paid,
/// e.g. "Paid online" or "Cash on Delivery".
Future<Uint8List> buildOrderReceiptPdf(
  CustomerOrder order, {
  String? orderRef,
  required String payment,
  required String status,
  Uint8List? logo,
}) async {
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _ink);
  const small = pw.TextStyle(fontSize: 7.5, color: _muted);
  final number = orderRef ?? order.id;
  final total = _paise(order.subtotal);
  final isDelivery = order.fulfillmentMethod == FulfillmentMethod.delivery;

  pw.Widget box(String title, List<pw.Widget> children) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _paleLine),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: bold.copyWith(color: _deep, fontSize: 8, letterSpacing: 1),
          ),
          pw.SizedBox(height: 5),
          ...children,
        ],
      ),
    ),
  );

  final billedName = order.billingName ?? order.recipientName ?? 'Customer';
  final billedPhone = order.billingPhone ?? order.recipientPhone;
  final billedAddress = order.billingAddress ?? order.deliveryAddress;

  pw.Widget cell(String text, {bool right = false, pw.TextStyle? style}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(
          text,
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: style,
        ),
      );

  final doc = pw.Document(
    title: 'Sudhamrtam order receipt $number',
    author: _company,
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      theme: pw.ThemeData.withFont().copyWith(
        defaultTextStyle: const pw.TextStyle(fontSize: 9, color: _ink),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // ---- Header band
          pw.Container(
            color: _deep,
            padding: const pw.EdgeInsets.fromLTRB(28, 18, 28, 16),
            child: pw.Row(
              children: [
                if (logo != null) ...[
                  pw.Container(
                    width: 54,
                    height: 54,
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
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SUDHAMRTAM',
                        style: pw.TextStyle(
                          color: PdfColors.white,
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      pw.Text(
                        'Pure  |  Natural  |  Traditional',
                        style: const pw.TextStyle(color: _fresh, fontSize: 8.5),
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
                        _companyContact,
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
                      'ORDER RECEIPT',
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      number,
                      style: pw.TextStyle(
                        color: _fresh,
                        fontSize: orderRef == null ? 7 : 12,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Placed ${_placed(order.createdAt)}',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(28, 18, 28, 0),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // ---- Billed to / Deliver to
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    box('Billed to', [
                      pw.Text(billedName, style: bold.copyWith(fontSize: 10.5)),
                      if (billedPhone != null) pw.Text('Phone: $billedPhone'),
                      if (billedAddress != null) pw.Text(billedAddress),
                    ]),
                    pw.SizedBox(width: 10),
                    box(isDelivery ? 'Deliver to' : 'Store pickup', [
                      if (isDelivery) ...[
                        pw.Text(
                          order.recipientName ?? '-',
                          style: bold.copyWith(fontSize: 10.5),
                        ),
                        if (order.recipientPhone != null)
                          pw.Text('Phone: ${order.recipientPhone}'),
                        pw.Text(order.deliveryAddress ?? '-'),
                        if (order.deliveryDate != null) ...[
                          pw.SizedBox(height: 3),
                          pw.Text(
                            'Delivery: ${billPdfLongDate(order.deliveryDate!)}',
                            style: bold,
                          ),
                        ],
                      ] else
                        pw.Text('Collected at the Sudhamrtam store.'),
                    ]),
                  ],
                ),
                pw.SizedBox(height: 16),
                // ---- Items
                pw.Table(
                  border: pw.TableBorder.all(color: _paleLine, width: 0.6),
                  columnWidths: const {
                    0: pw.FixedColumnWidth(24),
                    1: pw.FlexColumnWidth(4),
                    2: pw.FixedColumnWidth(40),
                    3: pw.FixedColumnWidth(70),
                    4: pw.FixedColumnWidth(80),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: _pale),
                      children: [
                        cell('#', style: bold),
                        cell('Item', style: bold),
                        cell('Qty', right: true, style: bold),
                        cell('Price (Rs.)', right: true, style: bold),
                        cell('Amount (Rs.)', right: true, style: bold),
                      ],
                    ),
                    for (final (i, item) in order.items.indexed)
                      pw.TableRow(
                        children: [
                          cell('${i + 1}'),
                          cell(
                            _plain(
                              '${item.productName}'
                              '${isComboProductId(item.productId) ? ' (combo offer)' : ''}'
                              ' - ${item.unit}',
                            ),
                          ),
                          cell('${item.quantity}', right: true),
                          cell(
                            billPdfAmount(_paise(item.unitPrice)),
                            right: true,
                          ),
                          cell(
                            billPdfAmount(_paise(item.totalPrice)),
                            right: true,
                          ),
                        ],
                      ),
                  ],
                ),
                pw.SizedBox(height: 8),
                // ---- Totals
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        'Amount in words: ${rupeesInWords(total)}',
                        style: small,
                      ),
                    ),
                    pw.SizedBox(width: 16),
                    pw.Container(
                      width: 190,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: _pale,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Column(
                        children: [
                          for (final (label, value) in [
                            (
                              'Items (${order.totalQuantity})',
                              billPdfAmount(total),
                            ),
                            ('Delivery', 'Free'),
                          ])
                            pw.Row(
                              mainAxisAlignment:
                                  pw.MainAxisAlignment.spaceBetween,
                              children: [pw.Text(label), pw.Text(value)],
                            ),
                          pw.Divider(color: _paleLine, height: 10),
                          pw.Row(
                            mainAxisAlignment:
                                pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(
                                'Total',
                                style: bold.copyWith(fontSize: 11),
                              ),
                              pw.Text(
                                'Rs. ${billPdfAmount(total)}',
                                style: bold.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 14),
                // ---- Payment and status
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _paleLine),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.RichText(
                          text: pw.TextSpan(
                            children: [
                              pw.TextSpan(text: 'Payment: ', style: bold),
                              pw.TextSpan(text: payment),
                            ],
                          ),
                        ),
                      ),
                      pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(text: 'Order status: ', style: bold),
                            pw.TextSpan(text: status),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Text('Instructions: ${order.notes!.trim()}', style: small),
                ],
              ],
            ),
          ),
          pw.Spacer(),
          pw.Container(
            color: _pale,
            padding: const pw.EdgeInsets.fromLTRB(28, 10, 28, 12),
            child: pw.Text(
              'Thank you for choosing Sudhamrtam. This receipt is computer '
              'generated and needs no signature. For help: $_companyContact',
              textAlign: pw.TextAlign.center,
              style: small,
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
