# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Sudhamrtam customer app: a Flutter (Android first, iOS later) shopping app for a premium organic dairy/oil brand. Android package: `com.sudhamrtam.customer`. Data lives on the phone in SQLite (`sqflite`). A build can optionally talk to the Sudhamrtam backend (`../sudhamrtam_backend`, Node/PostgreSQL) for the catalog, phone login, the profile and saved addresses, and placing orders (Cash on Delivery); payments, order history and subscriptions are still local-only. Brand primary green is `#82B440` (premium, organic, pastoral style).

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
Despite the name, `MilkDatabaseService.instance` owns the **one** app database (`sudhamrtam_milk.db`) for all tables: subscriptions, cart, orders, profiles/addresses, pending submissions, checkout reconciliations. Schema is versioned (currently **v11**; the version history is in the class doc comment).
- New installs: `_createTables`. Upgrades: `_upgradeDatabase` with cumulative `if (oldVersion < N)` blocks that must never drop customer data.
- A schema change means bumping `databaseVersion`, adding to both create and upgrade paths, and adding tests (see `sqlite_v8_order_recipient_test.dart` for a self-contained example; older v5–v7 tests depend on fixture DBs under `C:\Sudhamrtam\backups\`).
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
- **Where orders go:** `OrderDestination` (`lib/features/checkout/order_destination.dart`), set by main(). With a server, `OrderSubmissionService`'s default `saveOrder` sends `PUT /v1/orders/{id}` first (`OrderApiClient`, idempotent) and saves on the phone only after the server accepted it; retries reuse the same ID and request body (built only from the order snapshot). `CustomerOrder.addressId` (v11, omitted from `toMap()` when null) tells the server which saved address. `cancelAwaitingSubmission` asks the server first: an order the server has is finished, not cancelled; if the server can't be reached nothing is cancelled. `OrderRejectedException` (400/409/422, e.g. `PRICE_CHANGED`) means retrying can't help: checkout offers "Cancel Order and Review Cart". `OrderApiException` means retry later.
- **Place Order:** with a server (`CheckoutScreen.sendsToServer`), enabled in every build for signed-in customers: delivery only, Cash on Delivery only, address must have a delivery area, ₹200 minimum and 9 PM cut-off from `GET /v1/order-rules` (owner rules, kept in the backend). Without a server, local test orders only in debug builds (`enableTestOrders` defaults to `kDebugMode`); release builds without `API_BASE_URL` still cannot order. Debug builds also show a one-shot failure simulator (`CheckoutFaultInjector`) for device recovery tests.

### Backend connection and login
- The server is used only when the build sets `--dart-define=API_BASE_URL=...` (`lib/services/catalog_api_client.dart`). Release builds currently set none, so they make no network calls. On the phone in development: run the backend, `adb reverse tcp:3000 tcp:3000`, then `flutter run -d <device-id> --dart-define=API_BASE_URL=http://127.0.0.1:3000` (cleartext HTTP is allowed in debug builds only).
- Phone login: screens use the `PhoneAuthGateway` interface (`lib/services/phone_auth_service.dart`); `ApiPhoneAuthGateway` calls the backend's `/v1/auth/otp/*` endpoints and keeps the session token in `flutter_secure_storage`. The backend sends the code (MSG91 WhatsApp planned; development prints it in the server log). Test number `+91 9999900001`, code `123456`. Firebase is no longer used. Global: `sudhamrtamAuth` (null without a server).
- Profile and addresses: screens save through `sudhamrtamAccount` (`AccountSyncService`, `lib/services/account_sync_service.dart`), never the DB services directly. The phone keeps one local copy under customer ID `local_customer` (checkout reads it). Signed out: local only. First sync per account (`app_settings` key `account_linked_customer_id`): phone data is uploaded, the server's values win, then the phone mirrors the server. Signed in: each change goes to the server first (`AccountApiClient`), then the phone; offline means nothing changes. Addresses the server rejects stay on the phone (`account_unsynced_address_ids`). Sign-out deletes the local profile and addresses. Address IDs are app-generated and used as the server ID (`PUT /v1/addresses/{id}`), so retries never duplicate. `CustomerAddress.areaId` holds the server delivery area (null for old addresses).

### UI
Feature folders live under `lib/features/` (home, shop, milk_plan, cart, checkout, orders, account, shell). `CustomerShell` switches tab bodies by `_selectedIndex`. Products come from `CatalogRepository` (`lib/models/catalog_repository.dart`): the cached `/v1/catalog` response, with the static `ProductCatalog` as offline fallback. Every customer gets the same price in every area (owner decision; there is no area picker). Product IDs are persisted in cart and order rows, so they must stay stable. Theme: `lib/core/theme/app_theme.dart` (Material 3, seeded from `#82B440`).

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
