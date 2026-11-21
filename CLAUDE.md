# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Sudhamrtam customer app: a Flutter (Android first, iOS later) shopping app for a premium organic dairy/oil brand. Android package: `com.sudhamrtam.customer`. Data lives on the phone in SQLite (`sqflite`). A build can optionally talk to the Sudhamrtam backend (`../sudhamrtam_backend`, Node/PostgreSQL) for the catalog, phone login, the profile and saved addresses, placing orders (Cash on Delivery or online with Cashfree), milk plans and monthly milk bills; order history is still kept on the phone. Brand primary green is `#82B440` (premium, organic, pastoral style).

Separate product from Ayyappa Diksha (`../AyyappaDiksha`, `../ayyappa_diksha_backend`): own repository (`github.com/sudhamrtam-ux/sudhamrtam-customer-app`), own backend, own Firebase project and signing key. Never share code by path, copy files across, or push one project's commits to the other's remote. A session working on this app stays in this folder.

## Working agreement

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
flutter build apk --release --dart-define=API_BASE_URL=https://api.sudhamrtam.in   # build for customers (bump `version:` in pubspec.yaml first)
```

- Release builds are signed through `android/key.properties` (key in `D:\Sudhamrtam\signing`). Without that file they fall back to the debug key and cannot update installed apps. The address-map Google Maps key is read from `android/maps-key.txt`; without it the map is blank. `android/app/google-services.json` (Firebase) is also needed. All three are git-ignored and must be on the build machine.
- Kotlin "this and base files have different roots": the user env var `PUB_CACHE=D:\PubCache` keeps packages on the project's drive; an older terminal lacks it (`$env:PUB_CACHE='D:\PubCache'` or open a new one).

The root-level `verify_*.dart` / `verify_*.py` scripts are one-off manual checks against backup DB files at hard-coded `D:\Sudhamrtam\backups\...` paths. They are not part of the test suite.

## Architecture

### Startup gating (`lib/main.dart`, `lib/app/`)
`main()` runs `CheckoutStartupController.start()` **before** `runApp`. It first runs `CheckoutRecoveryExecutor.recoverAtStartup` and only initializes the global cart (`sudhamrtamCart.initialize`) if recovery returns `canContinueNormalStartup`. If recovery is blocked, a restricted `SudhamrtamRecoveryApp` shows `CheckoutRecoveryGateScreen` (retry only) and the normal `CustomerShell` stays unreachable. Cart initialization must never happen before recovery succeeds.

Global singletons live in `lib/app/sudhamrtam_app.dart`: `sudhamrtamCart` (`CartManager`) and `sudhamrtamMilkSubscriptions`. Both are `ChangeNotifier`s that screens listen to directly. There is no state-management package.

### Single SQLite database (`lib/database/milk_database_service.dart`)
Despite the name, `MilkDatabaseService.instance` owns the **one** app database (`sudhamrtam_milk.db`) for all tables: subscriptions, cart, orders, profiles/addresses, pending submissions, checkout reconciliations. Schema is versioned (currently **v21**; the version history is in the class doc comment).
- New installs: `_createTables`. Upgrades: `_upgradeDatabase` with cumulative `if (oldVersion < N)` blocks that must never drop customer data.
- A schema change means bumping `databaseVersion`, adding to both create and upgrade paths, and adding tests (see `sqlite_v8_order_recipient_test.dart` for a self-contained example; older v5–v7 tests depend on fixture DBs under `D:\Sudhamrtam\backups\`).
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
- **Place Order:** with a server (`CheckoutScreen.sendsToServer`), enabled in every build for signed-in customers: delivery only, Cash on Delivery, or online with Cashfree when the server's order rules offer it (`offersOnlinePayment`; `PaymentLauncher` / `PaymentScreen` in `lib/features/payment/`, and only the server's check marks it paid), address must have a delivery area and a map location, ₹200 minimum and 9 PM cut-off from `GET /v1/order-rules` (owner rules, kept in the backend). Without a server, local test orders only in debug builds (`enableTestOrders` defaults to `kDebugMode`); release builds without `API_BASE_URL` still cannot order. Debug builds also show a one-shot failure simulator (`CheckoutFaultInjector`) for device recovery tests.

### Backend connection and login
- The server is used only when the build sets `--dart-define=API_BASE_URL=...` (`lib/services/catalog_api_client.dart`). Builds for customers use `https://api.sudhamrtam.in`; a build without the define makes no network calls. On the phone in development: run the backend, `adb reverse tcp:3000 tcp:3000`, then `flutter run -d <device-id> --dart-define=API_BASE_URL=http://127.0.0.1:3000` (cleartext HTTP is allowed in debug builds only).
- Phone login: screens use the `PhoneAuthGateway` interface (`lib/services/phone_auth_service.dart`); `ApiPhoneAuthGateway` calls the backend's `/v1/auth/otp/*` endpoints and keeps the session token in `flutter_secure_storage`. The backend sends the code: on the live server on WhatsApp through MSG91 (working since 18 Nov 2026); in development it prints it in the server log. The app shows the server's message as is, e.g. "We could not send the code" (`SEND_FAILED`; MSG91's reason is in the server's runtime log). Test number `+91 9999900001`, code `123456` on the local backend; the live server only accepts the numbers in its `OTP_TEST_NUMBERS` (keep one for Play Store review). Firebase is used only for phone notifications: `PushNotifications` (`lib/services/push_notifications.dart`, global `sudhamrtamPush`) registers the FCM token with `PUT /v1/push-token` after sign-in and removes it before sign-out (`ApiPhoneAuthGateway.beforeSignOut`); a tapped message notification opens `MessagesScreen` via `sudhamrtamNavigatorKey`. Firebase starts only in builds with a server, and a failure leaves the app working without notifications. `android/app/google-services.json` (git-ignored) holds the project. Global: `sudhamrtamAuth` (null without a server).
- Profile and addresses: screens save through `sudhamrtamAccount` (`AccountSyncService`, `lib/services/account_sync_service.dart`), never the DB services directly. The phone keeps one local copy under customer ID `local_customer` (checkout reads it). Signed out: local only. First sync per account (`app_settings` key `account_linked_customer_id`): phone data is uploaded, the server's values win, then the phone mirrors the server. Signed in: each change goes to the server first (`AccountApiClient`), then the phone; offline means nothing changes. Addresses the server rejects stay on the phone (`account_unsynced_address_ids`). Sign-out deletes the local profile and addresses. Address IDs are app-generated and used as the server ID (`PUT /v1/addresses/{id}`), so retries never duplicate. `CustomerAddress.areaId` holds the server delivery area (null for old addresses).

### Website (web build, in progress)
The same app is built for the web as the sudhamrtam.in website (`python tool/build_web.py`, `--zip` for the Hostinger upload `D:\Sudhamrtam\website_upload.zip`, `--api http://127.0.0.1:3000` for the local backend), with the same login and account; the backend allows it through `CUSTOMER_WEB_ORIGINS`. Web-only differences: the SQLite database lives in the browser's IndexedDB through `sqflite_common_ffi_web` (`lib/database/web_database_setup*.dart`, a conditional import, so phones are unchanged; it needs `web/sqlite3.wasm` and `web/sqflite_sw.js` from `dart run sqflite_common_ffi_web:setup`), Firebase notifications are skipped (`kIsWeb`), and location comes from the browser. The address map needs a Maps JavaScript API key restricted to the website's addresses in `web/maps-key.txt` (git-ignored); `tool/build_web.py` adds the Maps script to `build/web/index.html` and never ships the file. Without it `googleMapsLoaded` (`lib/features/account/web_maps*.dart`) is false and `MapLocationField` gets no `mapBuilder`: no map, current location only (still required). Still open: Cashfree's web redirect, and uploading to Hostinger.

### Milk plan shifts
`MilkDeliveryShift` is `earlyMorning`, `morning`, `evening` (delivery order). The phone stores the enum name; the server uses `early_morning` (`apiName` / `fromApi`). Quantities per delivery follow `lib/models/milk_quantity.dart` (1 L, 500 ml and 750 ml packets: 0.5–10 L, never x.25 L; the server and the v17 schedules CHECK enforce the same). Early morning is last evening's milk kept cold overnight; its changes close at 9 PM the evening before (morning 6 AM, evening 6 PM; the server enforces them by fixing each list at its deadline). Shop orders stay on the morning run. v12 rebuilt `milk_shift_schedules` to allow the new shift (SQLite cannot alter a CHECK).

### Milk plan approval and addresses
- Vacation (v18): "Pause → Going on vacation" opens `VacationDaysScreen` (tap any days, or add a date range); `MilkSubscription.vacationDates` holds them, the plan stays active and the server skips those days. The older paused-with-`resumeOn` vacation is still shown but no longer created.
- Reg No: the server gives each customer `SM-1001`, … once with their first plan approval; the Account tab shows it (`AccountSyncService.refreshRegNo`, kept in `app_settings` key `account_reg_no`, cleared on sign-out). The same number is on every bill.
- New milk plans wait for Sudhamrtam's approval (`MilkSubscription.approval`, v15): `isWaitingForApproval` shows "Waiting for approval" and no milk is delivered; rejected plans are cancelled with `rejectReason`. `MilkPlanSyncService.refresh` re-reads plans when the app resumes, Home or Milk Plan is opened (at most every 15 s) and on pull-down, so approvals show without a restart.
- Addresses carry society (`societyId`/`societyName` from Sudhamrtam's list per area, or typed `societyOther`), `block`, `flat` and `isHouse` (v16). The form requires flat, and society + block unless an independent house; `AddressDetailsCard` on Home asks once (dismissal in `app_settings`) when a saved address lacks them. Deliveries are sorted by them on the server. A society Sudhamrtam gave an address (`SocietyChoice.hasAddress`, from `/v1/areas/{id}/societies`) fills in street, city, state and PIN: the form then asks only flat, block and the optional `deliveryNote` (v19), which partners see on the stop.

### Milk bills
`lib/features/milk_bills/` shows monthly milk bills from the server (`MilkBillApiClient`, global `sudhamrtamMilkBills`; null without a server). They are not stored on the phone. `MilkBillsReminder` at the top of the Milk Plan tab shows unpaid bills and the due date; the Account tab links to the list. Online payment uses the same `PaymentLauncher` as orders, and only the server's check says a bill is paid. Staff record cash payments in the staff app (`../sudhamrtam_staff_app`).

### UI
Feature folders live under `lib/features/` (home, shop, milk_plan, cart, checkout, orders, account, shell, plus server-only messages, milk_bills, payment, feedback, support). Each server feature has a client in `lib/services/` that is null/unused without `API_BASE_URL`. `CustomerShell` switches tab bodies by `_selectedIndex`. Products come from `CatalogRepository` (`lib/models/catalog_repository.dart`): the cached `/v1/catalog` response, with the static `ProductCatalog` as offline fallback. Every customer gets the same price in every area (owner decision; there is no area picker). Product IDs are persisted in cart and order rows, so they must stay stable. Theme: `lib/core/theme/app_theme.dart` (Material 3, seeded from `#82B440`).

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
