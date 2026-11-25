import 'package:flutter_test/flutter_test.dart';

import 'package:sudhamrtam_customer_app/features/milk_bills/bill_pdf.dart';
import 'package:sudhamrtam_customer_app/services/milk_bill_api_client.dart';

/// Pack products on bills and in the month (owner request 2026-11-25,
/// subscriptions step 5): packs apart from the litres.
void main() {
  test('a month with milk and curd packs', () {
    final month = MilkDeliveryMonth.fromJson({
      'month': '2026-11',
      'deliveries': [
        {
          'date': '2026-11-08',
          'shift': 'morning',
          'outcome': 'delivered',
          'reason': null,
          'items': [
            {
              'product_id': 'cow_milk',
              'name': 'Cow Milk',
              'quantity_ml': 1500,
              'measure': 'litre',
              'unit_label': '1 L',
              'unit_price_paise': 8000,
              'amount_paise': 12000,
            },
            {
              'product_id': 'curd',
              'name': 'Curd',
              'quantity_ml': 2,
              'measure': 'pack',
              'unit_label': '500 g',
              'unit_price_paise': 6000,
              'amount_paise': 12000,
            },
          ],
        },
      ],
      'totals': {
        'delivered': 1,
        'not_delivered': 0,
        'paused': 0,
        'not_marked': 0,
        'delivered_ml': 1500,
        'delivered_packs': {'curd': 2},
        'amount_paise': 24000,
      },
      'bill': null,
    });
    final day = month.deliveries.single;
    expect(day.quantityMl, 1500);
    expect(day.packs, 2);
    expect(day.items.map((i) => i.amountText), ['1.50 L', '2 × 500 g']);
    // The rate per litre leaves the pack price out.
    expect(month.rates, {8000});
  });

  test('bill lines and the printed bill count packs apart', () {
    final line = MilkBillLine.fromJson({
      'delivery_date': '2026-11-08',
      'shift': 'morning',
      'product_name': 'Curd',
      'quantity_ml': 2,
      'unit_price_paise': 6000,
      'amount_paise': 12000,
      'measure': 'pack',
      'unit_label': '500 g',
    });
    expect(line.isPack, isTrue);
    expect(line.amountText, '2 × 500 g');
    expect(
      MilkBillMilk.fromJson({
        'product_name': 'Buffalo Milk',
        'quantity_ml': 2000,
        'amount_paise': 18000,
      }).amountText,
      '2.00 L',
    );

    Map<String, Object?> l(String date, int q, String measure) => {
      'delivery_date': date,
      'quantity_ml': q,
      'measure': measure,
    };
    final days = billPdfDays({
      'bill': {
        'month': '2026-11',
        'lines': [
          l('2026-11-08', 1000, 'litre'),
          l('2026-11-08', 2, 'pack'),
          l('2026-11-09', 3, 'pack'),
        ],
      },
      'deliveries': <Object>[],
    });
    final eighth = days[7];
    expect(eighth.ml, 1000);
    expect(eighth.packs, 2);
    // A day with only packs still counts as delivered.
    final ninth = days[8];
    expect(ninth.text, '3 pk');
    expect(ninth.delivered, isTrue);
    expect(days.where((d) => d.delivered), hasLength(2));
  });
}
