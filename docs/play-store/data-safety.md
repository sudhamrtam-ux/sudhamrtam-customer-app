# Google Play data safety: Sudhamrtam (as entered 27 Nov 2026)

What the owner entered in Play Console → App content → Data safety on 27 Nov 2026 (customer app
1.0.22). Worked out from the code and the privacy page (https://api.sudhamrtam.in/privacy).
When the app starts collecting something new, update this file and the Play form together.

## Data collection and security

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS only; release builds refuse plain HTTP) |
| Account creation methods | **Username and other authentication** (the mobile number plus a one-time code on WhatsApp; no password, no Google sign-in) |
| Account deletion web link | https://api.sudhamrtam.in/delete-account (in the app, Account → Delete my account, or by email/phone without the app) |

"Shared" is **No** everywhere: Hostinger, Supabase, Firebase, Cashfree and MSG91 only process data
for us, which Google does not count as sharing. We do not sell data or give it to others for their own use.

## Data types

| Data type (Play's name) | Required or optional | Ephemeral | Purposes |
|---|---|---|---|
| Personal info → **Name** | Required | No | App functionality, Account management |
| Personal info → **Email address** | Optional | No | Account management |
| Personal info → **Phone number** | Required | No | App functionality, Account management |
| Personal info → **Address** | Required | No | App functionality |
| Location → **Precise location** | Required | No | App functionality |
| Financial info → **User payment info** | Optional | **Yes** | App functionality |
| Financial info → **Purchase history** | Required | No | App functionality, Fraud prevention / security / compliance, Account management |
| Photos and videos → **Photos** | Optional | No | Account management |
| Messages → **Other in-app messages** | Optional | No | App functionality |
| Device or other IDs | Required | No | App functionality |

Why each one:
- **Precise location:** every delivery address has a pin on the map; "use my location" reads the GPS
  once, with permission. Only the chosen pin is saved, never background location. Approximate
  location is **not** ticked.
- **User payment info:** card or UPI details are typed into Cashfree's checkout; Sudhamrtam never sees
  or keeps them, hence ephemeral and optional (Cash on Delivery needs none).
- **Purchase history:** orders, bills and payments; kept about six years for tax records, which the
  delete-account page says, hence the compliance purpose.
- **Device or other IDs:** the Firebase notification token, registered after sign-in.

Not collected (left unticked): approximate location, user IDs, race, religion, political or sexual
orientation, credit score, other financial info, health and fitness, emails, SMS, videos, audio,
files, calendar, contacts, app activity, web browsing, app info and performance (no Crashlytics or
analytics), advertising ID.
