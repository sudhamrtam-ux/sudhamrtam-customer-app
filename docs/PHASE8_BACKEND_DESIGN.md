# Phase 8 — Backend Design Proposal

**Status:** Draft for owner review — no backend code yet
**Prepared:** 6 November 2026
**Decisions already made by the owner:**
- Build a **new backend**, shared by the Flutter app and a future website. Do not extend the old PHP site.
- **Import** delivery areas, routes, products and prices from the old site's database. The owner has access to it.
- **OTP login run by the backend, delivered through MSG91**: WhatsApp now, SMS once DLT approval for Sudhamrtam's sender comes through (7 November 2026; replaces the earlier Firebase Phone Auth plan, which needed paid Blaze billing at about ₹6 per SMS).
- Place Order stays **disabled in release builds** until this backend's order API is live (Phase 1 sign-off).
- **Order rules** (7 November 2026): free home delivery with a **₹200 minimum order**; **delivery only** (no store pickup at launch); **Cash on Delivery** only; orders placed by **9 PM India time** are delivered the next morning, later ones the day after. Kept in the backend's `src/orders/rules.ts` and published at `GET /v1/order-rules`.
- **One price per product for every customer, in every area** (6 November 2026). There is no area picker in the app. Areas and routes are used only for delivery planning and addresses.

---

## 1. Architecture

```
Flutter app ──HTTPS/JSON──▶  Sudhamrtam API (Node.js + TypeScript)  ──▶  PostgreSQL
                                    │
                                    └── MSG91 (WhatsApp now, SMS after DLT) delivers login codes
```

- **API:** Node.js with TypeScript and a lightweight framework (Fastify). The JSON API is versioned under `/v1`.
- **Database:** PostgreSQL, with schema changes managed by versioned migration files.
- **Location:** a separate repository, `D:\Sudhamrtam\sudhamrtam_backend`. The app repository stays Flutter-only.
- **Hosting:** to be decided (see §9). Use an India region (Mumbai), since customer data falls under India's DPDP Act 2023.
- **Admin panel and website (Phases 9 and 12)** use the same API, with staff roles.

### Login flow (built in step 8b)
1. The customer enters their phone number. `POST /v1/auth/otp/request` makes a 6-digit code, stores only its hash, and sends it through MSG91.
2. The customer enters the code. `POST /v1/auth/otp/verify` checks it, finds or creates the `customers` row **by phone number**, and returns a session token.
3. The app sends the token with each API call (`Authorization: Bearer …`) and keeps it in the phone's encrypted storage.
4. Limits: codes expire after 5 minutes, 5 wrong tries, 30 seconds between codes, 5 codes per phone per hour.
5. The delivery channel can change (WhatsApp → SMS after DLT) without changing accounts or the database.

During development, the code is printed in the server log, and **test numbers** (`+91 9999900001`, code `123456`) never get a message.

---

## 2. Core principles

1. **The server decides prices.** The app shows prices, but the server re-prices every order from the current price list. Prices are the same for all customers.
2. **Money is stored in whole paise** (`integer`), never as decimals. ₹85.00 is stored as `8500`.
3. **Orders are created idempotently, keyed by the app's order ID.** This keeps the Phase 1 guarantee (no duplicate orders, retries reuse the same ID) all the way to the server.
4. **Orders are snapshots.** Product names, units, prices, the address and the recipient are copied into the order and never change afterwards. Only the order status changes.
5. **Every change of status or money is recorded:** order status history and a ledger of wallet entries that are only ever added to, never edited.

---

## 3. Database (PostgreSQL)

### Catalog and pricing (imported from the old site, one price per product)
| Table | Key columns |
|---|---|
| `service_areas` | `id`, `name` (e.g. "Praneeth Pranav Flora", "Nizampet"), `is_active` |
| `delivery_routes` | `id`, `area_id`, `route_number`, `name` |
| `products` | `id` (text, **same IDs as the app**: `cow_milk`, `curd`, …), `name`, `category`, `description`, `unit_label` (`1 L`, `1 kg`, `500 g`), `is_active` |
| `product_prices` | `product_id`, `price_paise`, `is_available`, `effective_from` (price history kept). Replaced the earlier `area_prices` table (migration `0002_flat_prices`) |

### Customers
| Table | Key columns |
|---|---|
| `customers` | `id` (uuid), `phone_e164` (unique), `full_name`, `email`, `created_at`, `deleted_at` |
| `customer_addresses` | `id`, `customer_id`, `area_id`, `label`, `recipient_name`, `phone`, address lines, `city`, `postal_code`, `latitude`, `longitude`, `is_default` (at most one per customer) |

### Orders
| Table | Key columns |
|---|---|
| `orders` | `id` (text, **client-generated**, validated as 32 hex characters), `customer_id`, `area_id`, `fulfillment` (`delivery`/`pickup`), `payment_method`, `status`, snapshots of `recipient_name`/`recipient_phone`/`delivery_address`, `notes`, `subtotal_paise`, `delivery_fee_paise`, `discount_paise`, `total_paise`, `request_hash`, `client_created_at`, `received_at` |
| `order_items` | `order_id`, `product_id`, `product_name`, `unit_label`, `quantity`, `unit_price_paise` |
| `order_status_history` | `order_id`, `status`, `changed_by`, `changed_at` |

### Milk subscriptions (mirrors the app's existing shift model)
| Table | Key columns |
|---|---|
| `subscriptions` | `id`, `customer_id`, `address_id`, `product_id` (`buffalo_milk`/`cow_milk`), `status` (`active`/`paused`/`cancelled`) |
| `subscription_shifts` | `subscription_id`, `shift` (`morning`/`evening`), `quantity_ml` (multiples of 500), `frequency` (`daily`/`alternateDays`/`selectedDays`/`randomDays`), `selected_weekdays`, `start_date`, `end_date` |
| `subscription_pauses` | `subscription_id`, `from_date`, `to_date` (also used for skips) |
| `delivery_occurrences` | generated per day: `subscription_id`, `date`, `shift`, `quantity_ml`, `unit_price_paise` snapshot, `status` (`scheduled`/`delivered`/`skipped`/`failed`) |

### Wallet (Phase 7, schema reserved now)
| Table | Key columns |
|---|---|
| `wallet_ledger` | `id`, `customer_id`, `entry_type` (`credit`/`debit`), `amount_paise`, `reference_type`, `reference_id`, `idempotency_key` (unique), `created_at`. Entries are only ever added, and the balance is their sum. |

---

## 4. API (version 1)

All endpoints require a session token unless marked *public*.

| Method & path | Purpose |
|---|---|
| `GET /v1/areas` *(public)* | Delivery areas |
| `GET /v1/catalog` *(public)* | All products with their current prices and availability (same for every customer) |
| `POST /v1/auth/otp/request`, `POST /v1/auth/otp/verify` *(public)*, `POST /v1/auth/logout` | Phone login (see §1) |
| `GET` / `PATCH /v1/me` | Profile |
| `DELETE /v1/me` | Account deletion request (Phase 3/13) |
| `GET` / `POST /v1/addresses`, `PATCH` / `DELETE /v1/addresses/{id}`, `POST /v1/addresses/{id}/default` | Saved addresses |
| **`PUT /v1/orders/{orderId}`** | **Idempotent order creation** (see §5) |
| `GET /v1/orders`, `GET /v1/orders/{orderId}` | Order history and details |
| `GET` / `POST /v1/subscriptions`, `PATCH /v1/subscriptions/{id}` | Subscriptions |
| `POST /v1/subscriptions/{id}/pauses`, `DELETE …/pauses/{pauseId}` | Pauses and skips |

---

## 5. Idempotent order creation — `PUT /v1/orders/{orderId}`

The app sends the same order snapshot it already stores durably: items with product ID, quantity and the unit price shown to the customer, plus fulfillment, payment method, address or recipient, and notes.

| Situation | Response | What the app does |
|---|---|---|
| New ID, valid, prices match | **201 Created** with the saved order | Reconcile the cart and remove the pending record (same as today) |
| ID already exists with an **identical** request (same `request_hash`) | **200 OK** with the existing order | Treated as success. This covers a lost response or a retry |
| ID exists with **different** content | **409 `ORDER_ID_CONFLICT`** | Stop. Show recovery (never overwrite) |
| A price changed since the customer saw it | **409 `PRICE_CHANGED`** with current prices | Show the new prices. The customer re-confirms, which creates a **new** order. The old pending record is cancelled through the existing "Cancel Order, Keep Cart" path |
| Product unavailable, address outside the delivery areas, etc. | **422** with error codes | Show the error. The cart is kept |
| Network failure or timeout | — | The pending record stays. Retry later with the **same ID** |

This maps directly onto the app's existing code. `OrderSubmissionService`'s `saveOrder` and `getOrderById` hooks become `PUT` and `GET` calls, and the local `pending_order_submissions` table becomes the app's offline **outbox** (orders saved on the phone and sent when the connection allows). Startup recovery and the Unfinished Order screen keep working unchanged.

---

## 6. App changes (done in small steps, after each backend part exists)

1. The catalog is loaded from `/v1/catalog`. Products are cached locally, and the hard-coded `ProductCatalog` becomes an offline fallback.
2. Login screen using the backend's OTP endpoints.
3. Profile and addresses sync with the API. Addresses gain a delivery area.
4. Order submission goes through the outbox to `PUT /v1/orders/{id}`. **Only then** is Place Order enabled in release builds.
5. Order history reads from the API, cached locally.
6. Subscriptions sync with the API.

**Data already on phones:** on first sign-in, the local profile and saved addresses are offered for upload. Local **test orders are not uploaded**, because they were debug test orders.

---

## 7. Importing data from the old website

Needed from the old database: **areas, routes, products and prices only.**

Please export those tables (phpMyAdmin → Export → SQL, or `mysqldump`) to a folder **outside any git repository**, for example `D:\Sudhamrtam\old_site_export\`.

- **Do not** include customer, user, login or password tables. They aren't needed, and they contain personal data.
- I will read the export, propose how each table maps onto the new schema (§3), and write an import script for your review.

---

## 8. Security basics (from the first version)

- Every request verifies the session token. Customers can only read or change their own records, which is enforced in every query.
- Rate limits on login and order endpoints.
- Secrets (database URL, MSG91 key, OTP secret) are kept in environment variables and never committed.
- HTTPS only. Daily database backups with a tested restore.
- Request logging without personal data. Order and money changes are recorded in history tables.

---

## 9. Delivery plan

| Step | Backend | App |
|---|---|---|
| 8a | Repo skeleton, PostgreSQL migrations, catalog tables, **old-site import**, `GET /v1/areas`, `GET /v1/catalog` | Load the catalog from the API (cached, offline fallback) |
| 8b | OTP login, `customers`, sessions, `/v1/me`, addresses | Login screen; profile and address sync |
| 8c | Orders: `PUT`/`GET`, re-pricing, status history | Outbox submission; enable release Place Order (Cash on Delivery) |
| 8d | Subscriptions, pauses and skips, delivery occurrence generation | Subscription sync |
| 8e | Staff roles for the admin panel (Phase 9) | — |

Each step is reviewed, tested and confirmed by you before the next one starts.

---

## 10. Decisions needed from you

1. **Hosting budget and provider.** Options range from a free tier for development to a small cloud server with managed PostgreSQL for the pilot. When we reach 8a, I'll compare 2–3 concrete options using current prices.
2. **MSG91 account** under the Sudhamrtam email, with a WhatsApp Business number and an approved Authentication template.
3. ~~Business rules for orders~~ — decided 7 November 2026 (see the top of this document).
4. **The old site export** described in §7.
