# Checkout Safety Sign-off — Roadmap Phase 1

**Status:** Approved by owner (Nagaraju), 6 November 2026
**Prepared:** 6 November 2026
**Scope:** Local (on-device SQLite) checkout in the Flutter customer app.
Orders are saved **on the phone only**. They are not sent to Sudhamrtam and no payment is taken.

---

## 1. Safety rules

Each rule below is enforced in code and covered by automated tests.

| # | Rule | How it is enforced | Test evidence |
|---|------|--------------------|---------------|
| 1 | **A retry never creates a new order ID.** | `CheckoutOrderSession` reuses the durable pending order, or the in-session order while the cart is locked. `OrderSubmissionService` never generates IDs. | `checkout_order_session_test.dart`; coordinator test *"Retry after submission failure uses original ID"*; screen tests *"Failed checkout retries with the same order ID"* and *"Retry resubmits the original order despite later changes"* |
| 2 | **The cart is never cleared unless a saved order exactly matches the original snapshot.** | `OrderSnapshotEquivalence` compares every immutable field, including recipient name and phone. Reconciliation clears the SQLite cart and marks the checkout complete in one transaction. | `order_submission_snapshot_safety_test.dart` (different quantity or price rejected); coordinator *"Different order cannot replace refresh-failed checkout"*; `order_snapshot_equivalence_test.dart` |
| 3 | **The cart stays locked while a checkout might be unfinished.** | The recovery lock is set *before* durable preparation and released only after full success. | Coordinator tests: *"Submission failure preserves cart and activates recovery lock"*, *"Committed preparation with lost confirmation retains recovery lock"*, *"Cart refresh failure retains pending checkout and recovery lock"* |
| 4 | **Preparation is all-or-nothing.** | The pending order and the cart snapshot are written in one transaction. Preparation is refused if the cart changed or another checkout is unresolved. | `atomic_checkout_preparation_test.dart` (rollback, idempotency, changed cart, second checkout rejected) |
| 5 | **No duplicate orders.** | An existing order with the same ID is accepted only if it matches the snapshot, and is never saved twice. Concurrent submissions are rejected. | *"Matching existing order is accepted without saving again"*, *"Concurrent submissions are rejected"*, *"Finishing twice does not create a second order"* |
| 6 | **A lost save confirmation is handled safely.** | After a save error, the order is re-read and accepted only if it matches. | *"Save error after successful write is safely verified"*, *"Mismatched saved order after save error is rejected"* |
| 7 | **The app never starts with an inconsistent checkout.** | Startup recovery runs **before** the cart loads. Records that don't match up (orphaned or conflicting) block startup without changing any data. | `checkout_orphaned_reconciliation_test.dart`; coordinator *"Orphaned reconciliation blocks startup and new checkout"*; `checkout_startup_*` tests |
| 8 | **The customer can always get out of recovery.** | When an order was started but never saved, the customer can **Finish Placing Order** (using the original snapshot) or **Cancel Order, Keep Cart**. Cancel is refused if the order was already saved. | `checkout_unfinished_order_decision_test.dart`, `checkout_recovery_gate_decision_test.dart` |
| 9 | **Cart save failures block checkout.** | A failed cart save stops the checkout lock from proceeding. | `cart_checkout_persistence_failure_test.dart` |

Full suite at sign-off: **241 tests passing**. `flutter analyze` reports no issues.

## 2. Device verification (Motorola moto g85 5G, Android 16)

Confirmed by the owner on 6 November 2026, using a debug build:

- [x] Store Pickup and Home Delivery test orders placed; the cart clears afterwards.
- [x] Delivery orders show the recipient name, phone and address.
- [x] Orders appear in Order History.
- [x] Online Payment disables order placement.
- [x] **Scenario A:** failure after preparation, then force-close. The Unfinished Order screen appears, and **Finish** saves the order and clears the cart.
- [x] **Scenario B:** the same as A, but **Cancel** keeps the cart and creates no order.
- [x] **Scenario C:** failure after the order was saved, then force-close. The app recovers automatically on restart.

## 3. Known limitations (accepted for Phase 1)

1. **Local only.** Orders never leave the phone. A customer could believe an order was placed with Sudhamrtam.
2. **Provisional prices.** Prices are taken from the sudhamrtam.in "Praneeth Pranav Flora" area. Curd is ₹120 / 500 g, as given by the owner. There is no area-based pricing.
3. **Cash on Delivery only.** There is no payment integration.
4. **No sign-in.** Orders are tied to a single local customer (`local_customer`).
5. **The recovery lock lasts for the session.** After a restart, startup recovery takes over, as verified in Scenarios A–C.
6. **Older delivery orders** saved before database v8 show the recipient as "Not recorded".

## 4. Release decision

**Recommendation:** approve this checkout as **safe for debug testing**, but keep **Place Order disabled in release builds** until the backend exists (Phase 8). Because of limitation 1, enabling it in a public release would let customers "place" orders that Sudhamrtam never receives.

The release switch is `CheckoutScreen.enableTestOrders`, which defaults to `kDebugMode`.

## 5. Approval

- [x] I approve the safety rules and device results above for Phase 1.
- [x] I agree to keep Place Order disabled in release builds until the backend order API is live.

Approved by: **Nagaraju**  Date: **06 Nov 2026**

---

## Addendum (after sign-off)

- **6 Nov 2026:** The owner clarified that Curd is **₹120 per kg** in both areas. The "₹120 / 500 g" in limitation 2 was an assumption by the assistant. The app catalog now uses `1 kg`. This does not affect the safety rules above.
