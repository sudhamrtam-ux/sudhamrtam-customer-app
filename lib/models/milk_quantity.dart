/// Milk quantities per delivery (owner decision 2026-11-11).
///
/// Milk goes out in 1 L, 500 ml and 750 ml packets: whole litres
/// plus at most one 500 ml or 750 ml packet. So a delivery is 0.5 L
/// to 10 L in 250 ml steps, but never x.25 L (1.25 L cannot be
/// packed). The server checks the same rule.
const int minimumMilkMl = 500;
const int maximumMilkMl = 10000;

/// 500, 750, 1000, 1500, 1750, 2000, … are allowed; 250, 1250 are not.
bool isAllowedMilkMl(int ml) =>
    ml >= minimumMilkMl &&
    ml <= maximumMilkMl &&
    ml % 250 == 0 &&
    ml % 1000 != 250;

/// The next allowed quantity above [ml] (null at the maximum).
int? nextMilkMl(int ml) {
  for (var next = ml + 250; next <= maximumMilkMl; next += 250) {
    if (isAllowedMilkMl(next)) return next;
  }
  return null;
}

/// The next allowed quantity below [ml] (null at the minimum).
int? previousMilkMl(int ml) {
  for (var previous = ml - 250; previous >= minimumMilkMl; previous -= 250) {
    if (isAllowedMilkMl(previous)) return previous;
  }
  return null;
}

/// 1000 → "1 L", 1500 → "1.5 L", 750 → "0.75 L".
String milkLitresText(int ml) {
  if (ml % 1000 == 0) return '${ml ~/ 1000} L';
  return '${(ml / 1000).toStringAsFixed(ml % 100 == 0 ? 1 : 2)} L';
}
