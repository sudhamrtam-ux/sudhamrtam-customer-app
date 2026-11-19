# Google Play Console answers: Sudhamrtam customer app (draft, 19 Nov 2026)

Package `com.sudhamrtam.customer`, version 1.0.3+4. For the owner to copy into Play Console.
Worked out from the app and the live server on 19 Nov 2026. The store listing is in
`store-listing.md` and the Data safety answers are in `data-safety.md`; this file covers everything else.

Play Console shows these under **Dashboard → Set up your app** (most are under **App content**).
Answer them in this order.

---

## 1. Create the app

| Question | Answer |
|---|---|
| App name | Sudhamrtam: Fresh Milk & More |
| Default language | English (United Kingdom) – en-GB, or English (India) if offered |
| App or game | App |
| Free or paid | Free |
| Declarations | Tick both (Developer Program Policies, US export laws) |

## 2. Privacy policy

`https://api.sudhamrtam.in/privacy`

## 3. App access

Choose **All or some functionality is restricted**, then **Add new instructions**:

| Field | Answer |
|---|---|
| Name | Reviewer sign-in |
| Username / phone | `+91 _________` (one number from Hostinger's `OTP_TEST_NUMBERS`) |
| Password / code | the code after `=` for that number in `OTP_TEST_NUMBERS` |
| Any other information | see the text below |

Text for "Any other information":

> Sign in with the mobile number above. No WhatsApp message is sent to this test number: type the
> one-time code given above. To try an order, add a delivery address (drop the pin anywhere on the map),
> add products to the cart and choose Cash on Delivery. Orders from this number are test orders and
> are not delivered.

Keep this number in `OTP_TEST_NUMBERS` for as long as the app is on Play, and add it to the
clean-up list (`tools/test_customers_cleanup.sql`) before launch.

## 4. Ads

**No, my app does not contain ads.**

## 5. Content rating

Start the questionnaire. Email: Contact@sudhamrtam.in. Category: **All other app types**.

| Question (shortened) | Answer |
|---|---|
| Violence, blood, fear | No |
| Sexuality, nudity | No |
| Bad language | No |
| Controlled substances (alcohol, tobacco, drugs) | No |
| Crude humour | No |
| Gambling, simulated gambling | No |
| Can users interact or exchange content with each other? | **No** (Help & Support messages go only to Sudhamrtam, not to other users) |
| Does the app share the user's current physical location with other users? | **No** (the address pin goes only to Sudhamrtam's delivery staff) |
| Can users buy digital goods? | **No** (only physical products: milk, curd, ghee, oils, honey) |
| Is the app a web browser or search engine? | No |
| Is the app primarily a news or educational product? | No |

Expected result: **Everyone / 3+** (IARC), as there is nothing objectionable.

## 6. Target audience and content

| Question | Answer |
|---|---|
| Target age groups | **18 and over** only (the privacy page says the app is for adults who manage their household's orders) |
| Could the app unintentionally appeal to children? | **No** |
| Store listing shown to children? | Not asked once only 18+ is chosen |

## 7. News app

**No.**

## 8. COVID-19 contact tracing and status apps

**My app is not a publicly available COVID-19 contact tracing or status app.**

## 9. Data safety

Use `data-safety.md` (still correct for 1.0.3+4: order help conversations are "Other in-app messages",
already listed). Account deletion web link: `https://api.sudhamrtam.in/delete-account` (how to delete in
the app, or without it by email or phone).

## 10. Government apps

**No.**

## 11. Financial features

**My app doesn't provide any financial features.** Online payment at checkout (Cashfree) is paying for
products, not a financial service, so none of the boxes apply (no loans, banking, crypto, insurance,
investments or money transfer between people).

## 12. Health apps

**My app does not have any health features.** (Selling milk and food is not a health feature.)

## 13. Advertising ID

**No.** The app does not use the advertising ID (checked in the 1.0.3+4 build: it does not ask for
`com.google.android.gms.permission.AD_ID`).

## 14. Payments (no form, but reviewers check it)

The app sells physical goods delivered to the door, so Google Play's own billing is **not** required;
paying through Cashfree or cash is allowed. Nothing to declare.

## 15. Store settings

| Field | Answer |
|---|---|
| App category | Food & Drink |
| Tags | Food delivery, Groceries (up to 5; add "Dairy" if offered) |
| Email | Contact@sudhamrtam.in |
| Phone | +91 86882 21433 |
| Website | leave empty unless there is a brand website |
| External marketing | leave on (default) |

## 16. Countries / regions

**India** only (Production → Countries / regions). Deliveries are only in Hyderabad.

## 17. First release (internal testing)

| Field | Answer |
|---|---|
| Track | Testing → Internal testing |
| Testers | create an email list with the testers' Gmail addresses |
| App signing | **Use Google-generated key** (Play App Signing, the default) |
| App bundle | `D:\Sudhamrtam\apks_to_share\Sudhamrtam-customer-1.0.3+4.aab` |
| Release name | 1.0.3 (4) (filled in automatically) |

Release notes (`<en-GB>` box):

```
First release of the Sudhamrtam app: order fresh milk, curd, ghee, honey and wood-pressed oils for next-morning delivery, set up daily milk plans, see monthly milk bills, track your orders and get help with an order in the app.
```

After the first upload: **Setup → App signing** shows the **SHA-1** of Google's app signing key. Add
it to the Google Maps API key's Android restrictions (package `com.sudhamrtam.customer`), or maps
stay blank in the copy installed from Play.

---

## Must do before submitting

1. **Account deletion page:** `https://api.sudhamrtam.in/delete-account` (backend, 19 Nov). Check it
   opens after the server is redeployed. Requests that arrive by email or phone are deleted by hand:
   confirm the number, then delete the account.
2. **Reviewer number** in `OTP_TEST_NUMBERS` (section 3).
3. **Cashfree.** Still the sandbox on the live server. Fine for internal testing; before production,
   switch to live or take the keys off Hostinger so only Cash on Delivery shows.
4. **Developer account type.** A *personal* account must run a closed test with at least 12 testers
   for 14 days before it can apply for production. An *organisation* account (needs a D-U-N-S number)
   does not.
5. **Screenshots.** `screenshots/` has 5 (Home, Shop, product, Cart, Milk plan) from before the new
   My Orders page; they are fine to submit. A My Orders screenshot can be added later.
