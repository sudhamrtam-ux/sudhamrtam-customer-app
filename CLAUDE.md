# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Sudhamrtam customer app: a Flutter (Android first, iOS later) shopping app for a premium organic dairy/oil brand. Everything is **local-only** right now: SQLite via `sqflite`, with no backend, auth, or payment integration. Brand primary green is `#82B440` (premium, organic, pastoral style).

`AGENTS.md` and `SUDHAMRTAM_CODEX_HANDOFF.md` hold the original working agreement. **The handoff doc is badly out of date** (it describes a Step 45 scaffold with only a Home screen). Trust the source tree, not the doc's status sections.

## Working agreement (from AGENTS.md)

- The user is on Windows + VS Code, is new to Flutter, and tests on a Motorola moto g85 5G over USB.
- Work one step at a time and wait for explicit user confirmation between steps. Inspect before modifying.
- Make small, targeted changes. Don't refactor unrelated code. Keep the five-tab shell (Home, Shop, Milk Plan, Cart, Account) working.
- Clearly label UI placeholders vs. real functionality. Never invent real prices, stock, photos, or claim payment/backend integrations exist.
- Never claim something was verified unless you actually ran or inspected it.

## Commands

```bash
flutter analyze                                   # run after every code change; expected: "No issues found!"
flutter test                                      # all unit/widget tests (SQLite via sqflite_common_ffi, runs on host)
flutter test test/checkout_validator_test.dart    # single file
flutter test --plain-name "substring of test name" test/some_test.dart   # single test
flutter test integration_test/order_restart_test.dart -d <device-id>     # on-device integration tests
flutter devices                                   # find the moto g85 device id
flutter run -d <device-id>
```

The root-level `verify_*.dart` / `verify_*.py` scripts are one-off manual checks against backup DB files at hard-coded `C:\Sudhamrtam\backups\...` paths. They are not part of the test suite.

## Architecture

### Startup gating (`lib/main.dart`, `lib/app/`)
`main()` runs `CheckoutStartupController.start()` **before** `runApp`. It first runs `CheckoutRecoveryExecutor.recoverAtStartup` and only initializes the global cart (`sudhamrtamCart.initialize`) if recovery returns `canContinueNormalStartup`. If recovery is blocked, a restricted `SudhamrtamRecoveryApp` shows `CheckoutRecoveryGateScreen` (retry only) and the normal `CustomerShell` stays unreachable. Cart initialization must never happen before recovery succeeds.

Global singletons live in `lib/app/sudhamrtam_app.dart`: `sudhamrtamCart` (`CartManager`) and `sudhamrtamMilkSubscriptions`. Both are `ChangeNotifier`s that screens listen to directly. There is no state-management package.

### Single SQLite database (`lib/database/milk_database_service.dart`)
Despite the name, `MilkDatabaseService.instance` owns the **one** app database (`sudhamrtam_milk.db`) for all tables: subscriptions, cart, orders, profiles/addresses, pending submissions, checkout reconciliations. Schema is versioned (currently **v8**; the version history is in the class doc comment).
- New installs: `_createTables`. Upgrades: `_upgradeDatabase` with cumulative `if (oldVersion < N)` blocks that must never drop customer data.
- A schema change means bumping `databaseVersion`, adding to both create and upgrade paths, and adding tests (see `sqlite_v8_order_recipient_test.dart` for a self-contained example; older v5–v7 tests depend on fixture DBs under `C:\Sudhamrtamackups\`).
- `CustomerOrder.toMap()` omits recipient keys when null, because durable pending payloads are compared byte-for-byte. Keep new optional order fields backward-compatible the same way.
- Other `*DatabaseService` / `*Service` classes are thin singletons that call `MilkDatabaseService.instance.database`.

### Durable checkout pipeline (the bulk of recent work)
Checkout is designed to be crash-safe. An order is identified by a stable preassigned ID, and the cart is only cleared once the saved order is proven to match the original snapshot.
1. `CartManager.beginCheckoutCartLock()` blocks cart mutations and drains queued SQLite saves. Cart persistence is an atomic full-snapshot replace (`CartDatabaseService`).
2. `AtomicCheckoutPreparationService` writes a `pending_order_submissions` row and a `checkout_reconciliations` snapshot in one transaction.
3. `OrderSubmissionService` saves the order (`OrderDatabaseService`). On retry it reuses the same ID, and an existing order must pass `OrderSnapshotEquivalence` (matching ID alone is not enough; status is excluded).
4. `CheckoutReconciliationService` clears the persisted cart and marks reconciliation complete in one transaction, then the in-memory `CartManager` is refreshed separately.
5. `PendingOrderSubmissionService.completeReconciledSubmission()` deletes the pending row only if the order exists and reconciliation is complete.

`DurableCheckoutCoordinator` (`lib/features/checkout/`) orchestrates these stages. Its doc comment lists the 10 steps. `CheckoutStartupRecoveryService` is the read-only inspector of this state. `CheckoutRecoveryExecutor` acts on it at startup. Any inconsistency yields a `blocked` status and leaves the cart untouched instead of auto-repairing it.

Invariants to preserve: never generate a new order ID on retry; never clear the cart without a matching reconciliation snapshot; unresolved checkouts keep the cart recovery lock held. These are signed off in `docs/CHECKOUT_SAFETY_SIGNOFF.md`.

- `CheckoutScreen` gets the order to submit from `CheckoutOrderSession` (durable pending order first, then the in-session order while recovery-locked, else a fresh one).
- An order prepared but never saved shows the **Unfinished Order** screen at startup. The customer picks Finish (`CheckoutRecoveryExecutor.finishAwaitingSubmission`) or Cancel (`cancelAwaitingSubmission`, which keeps the cart).
- **Place Order is enabled only in debug builds** (`CheckoutScreen.enableTestOrders` defaults to `kDebugMode`). The owner decided to keep it disabled in release until a backend order API exists. Debug builds also show a one-shot failure simulator (`CheckoutFaultInjector`) for device recovery tests.

### UI
Feature folders live under `lib/features/` (home, shop, milk_plan, cart, checkout, orders, account, shell). `CustomerShell` switches tab bodies by `_selectedIndex`. Products come from the static `ProductCatalog` in `lib/models/`; product IDs are persisted in cart and order rows, so they must stay stable. Catalog prices are provisional (from sudhamrtam.in, one delivery area), as documented in that file. Theme: `lib/core/theme/app_theme.dart` (Material 3, seeded from `#82B440`).

## Testing conventions

DB tests run on the host using `sqflite_common_ffi`, with an isolated temp-file database per test:

```dart
setUpAll(sqfliteFfiInit);
setUp(() async {
  directory = await Directory.systemTemp.createTemp('sudhamrtam_...');
  MilkDatabaseService.instance.configureForTesting(
    factory: databaseFactoryFfi,
    databasePath: '${directory.path}${Platform.pathSeparator}x.db');
});
tearDown(() async {
  await MilkDatabaseService.instance.close();
  MilkDatabaseService.instance.resetTestingConfiguration();
  await directory.delete(recursive: true);
});
```

`configureForTesting` throws if a connection is still open, so always close it in `tearDown`. Startup and recovery logic takes injected callbacks (e.g. `CheckoutStartupController(recover:, initializeCart:)`, `CheckoutRecoveryGateScreen`'s optional recovery callback) so it can be tested without the production DB.
