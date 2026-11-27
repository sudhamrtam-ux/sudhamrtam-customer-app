# Google Play Console answers: Sudhamrtam customer app (as entered 27 Nov 2026)

Package `com.sudhamrtam.customer`. What the owner entered in Play Console on 27 Nov 2026, for app
updates and as a model for the other Sudhamrtam apps. The store listing is in `store-listing.md`,
Data safety in `data-safety.md`, and the go-public steps in `launch-checklist.md`.

## Developer account

| Item | Answer |
|---|---|
| Account type | **Personal** (identity and phone verified 27 Nov). A personal account must run a closed test with 12+ testers for 14 days before production. |
| Trader status | **Trader** (account level and for this app) |
| Developer page | Icon `graphics/icon-512.png`, header `graphics/developer-header-4096x2304.jpg`, website https://sudhamrtam.in |

## Create the app

| Question | Answer |
|---|---|
| App name | Sudhamrtam: Fresh Milk & More |
| Default language | English (India) – en-IN |
| App or game / Free or paid | App / Free |

## App content (Policy and programs → App content)

| Form | Answer |
|---|---|
| Privacy policy | https://api.sudhamrtam.in/privacy |
| App access (sign-in details) | **All or some functionality is restricted** → "Reviewer sign-in": a number from Hostinger `OTP_TEST_NUMBERS` (+91…) and its fixed code, typed by the owner into Play only. Note below. |
| Ads | **No** |
| Content rating | Category **All other app types**; email Contact@sudhamrtam.in; online content **Yes** (products, prices and offers load from the server), every content question **No**; users interact or share **No**; location shared with others **No**; digital purchases **No** |
| Target audience | **18 and over** only; the optional minor-blocking setting **left off** (no Play purchases, and it can block real adult customers) |
| Data safety | See `data-safety.md` |
| Government app | **No** |
| Financial features | **My app doesn't provide any financial features** (paying for products through Cashfree is ordinary checkout) |
| Health | **No health features** |
| Advertising ID | **No** (the merged manifest has no `AD_ID` permission) |
| App-level trader + Terms of Service | Trader app; https://api.sudhamrtam.in/terms |
| News / COVID-19 apps | No |

App access note ("Any other information", 390 / 500 characters):

```
Sign in with the mobile number above. No WhatsApp message is sent to this test number: type the one-time code given above. To try an order, add a delivery address (drop the pin on the map), add products to the cart (minimum order Rs 200) and choose Cash on Delivery. Please do not pay online: online payments are real payments. Orders from this number are test orders and are not delivered.
```

Keep the reviewer number in `OTP_TEST_NUMBERS` for as long as the app is on Play.

## Store settings

Category **Food & Drink**; contact email Contact@sudhamrtam.in; website https://sudhamrtam.in.

## Releases

| Item | Answer |
|---|---|
| App signing | **Play App Signing** with Google's key (default). Upload key: `customer` alias, SHA-1 41:42:47:B2:…:86:7B. |
| Track | **Closed testing – Alpha**, countries **India**, testers by email list **"Sudhamrtam testers"**, feedback Contact@sudhamrtam.in |
| Releases | 1.0.22 (23) published 27 Nov; 1.0.23 (24) sent for review 27 Nov |
| Managed publishing | **Off** (approved changes go live by themselves) |
| Join link | Testers tab → How testers join → Join on Android → Copy link (testers need their Play Gmail on the list) |

Release notes are written per release in the `<en-IN>` box.

## After the first upload

**Setup → App integrity → Play app signing** shows the **App signing key** SHA-1. It must be added to
the Android Google Maps key (package `com.sudhamrtam.customer`), or the address map is blank in copies
installed from Play. Keep the upload key's entry there too (for APKs installed directly).
