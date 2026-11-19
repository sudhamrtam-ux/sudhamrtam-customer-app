# Google Play data safety answers: Sudhamrtam (draft, 19 Nov 2026)

Worked out from the code (customer app 1.0.1+2, backend 3866101) and the privacy page
(https://api.sudhamrtam.in/privacy). For the owner to enter in Play Console → App content → Data safety.

## Section 1: Data collection and security

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS only; release builds refuse plain HTTP) |
| Do you provide a way for users to request that their data is deleted? | **Yes**: in the app (Account → Delete my account) and the web link below |
| Account deletion web link | https://api.sudhamrtam.in/privacy (section "Your rights") |

"Shared" below is **No** everywhere: Google does not count service providers that process data
for us (Hostinger, Supabase, Firebase, Cashfree, MSG91) as sharing. We do not sell data or give
it to others for their own use.

## Section 2: Data types

| Data type (Play's name) | Collected | Shared | Required or optional | Purposes |
|---|---|---|---|---|
| Personal info → **Name** | Yes | No | Required | App functionality, Account management |
| Personal info → **Email address** | Yes | No | Optional | Account management (bills) |
| Personal info → **Phone number** | Yes | No | Required | App functionality, Account management, Developer communications |
| Personal info → **Address** | Yes | No | Required (to order) | App functionality |
| Location → **Precise location** | Yes | No | Required (to order) | App functionality |
| Financial info → **Purchase history** | Yes | No | Required | App functionality, Account management |
| Financial info → **User payment info** | Yes (through Cashfree's checkout) | No | Optional (only for online payment) | App functionality |
| Photos and videos → **Photos** | Yes | No | Optional | Account management (profile photo) |
| Messages → **Other in-app messages** | Yes | No | Optional | App functionality (Help & Support, feedback) |
| Device or other IDs | Yes | No | Required | App functionality (phone notifications) |

Why each one:
- Precise location: every delivery address must have a pin on the map (`map_location_field.dart`);
  "use my location" reads the phone's GPS once, with permission. Only the chosen pin is saved, never
  location in the background.
- User payment info: card or UPI details are typed into Cashfree's checkout inside the app (Cashfree
  SDK). Sudhamrtam never sees or stores them.
- Device or other IDs: the Firebase notification token (`PUT /v1/push-token`).

Not collected (answer No): contacts, calendar, SMS, call logs, files, audio, health, fitness, web
browsing, installed apps, search history, crash logs or diagnostics (no Crashlytics), advertising ID,
race, religion, political or sexual orientation, other financial info (no credit score, no salary).

For every collected type, Play also asks:
- Is this data processed ephemerally? **No**
- Is collection required or optional? As in the table.

## To check before submitting

1. **Privacy page:** done 19 Nov 2026 (backend f47b3e3): it now names the map location saved with each
   address and the one-time "Use my current location" read.
2. **SDKs:** Google expects data collected by SDKs to be declared too. Check Cashfree's and Google's own
   notes for their SDKs (Cashfree PG SDK, Google Maps SDK, Firebase Cloud Messaging); if one says it
   collects something more (for example device diagnostics), add it.
