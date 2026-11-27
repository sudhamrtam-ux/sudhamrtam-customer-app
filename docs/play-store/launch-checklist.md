# Sudhamrtam public launch checklist

For the owner. Written 27 Nov 2026, when the closed test (1.0.23) was running.
Tick each box in order. Steps marked **(owner only)** are done in Play Console,
Hostinger, Supabase or Cashfree; never paste keys, passwords or login codes into a chat.

---

## A. While the closed test runs (the 14 days)

- [ ] **12 or more testers** have joined (Closed testing → Alpha → Testers shows the count) and
      stayed for **14 days in a row**. Play Console's Dashboard shows when "Apply for production" opens.
- [ ] **Tester feedback** collected (WhatsApp replies, Contact@sudhamrtam.in, Play's private feedback)
      and the important problems fixed in a new build.
- [ ] **Maps on Play copies:** App integrity → Play app signing → *App signing key* SHA-1 added to the
      Android Maps key (package `com.sudhamrtam.customer`). Check: install from Play, open Add address,
      the map shows.
- [ ] **Cashfree in the app:** Cashfree has whitelisted `com.sudhamrtam.customer` (an Android entry shows
      *Approved* in their dashboard). Then one small real payment **in the app**, check it shows "Paid
      online" in the staff app, and refund it from Cashfree.
      If Cashfree is still waiting on launch day: decide whether to launch with Cash on Delivery only.
- [ ] **Reviewer number** is still in Hostinger `OTP_TEST_NUMBERS` and matches Play Console →
      App content → App access. Keep it for as long as the app is on Play.
- [ ] **Store listing** final: screenshots (done 27 Nov), description, prices in the app are today's.
- [ ] **Offers and combos** read well in public: no test text, no spelling mistakes (an old combo was
      named "Festivel offer"), no festival that has already passed.
- [ ] **Delivery side ready:** every area customers can pick has a route and a partner; partners use
      the staff app; the counter printer works.

## B. Apply for production (Play Console)

- [ ] Dashboard → **Apply for production**. Google asks about the test: how many testers, how you
      got feedback, what you changed. Honest short answers: testers were customers and family;
      feedback by WhatsApp and email; list the fixes you made.
- [ ] Wait for Google's answer (up to about 7 days).
- [ ] Production → **Create new release** → **Add from library** → pick the latest closed-test build
      (no new upload needed) → release notes → Countries: **India** → roll out to **100%**
      (or 20% first if you want to start small).
- [ ] Publishing overview → **Send for review**. When it shows *Published*, the public link works:
      `https://play.google.com/store/apps/details?id=com.sudhamrtam.customer`

## C. The day before launch: clean out test data (owner only)

Do this **after the day's deliveries are all marked**, so no live delivery is touched.

- [ ] **Backup:** Supabase → the Sudhamrtam project → Database → Backups: check there is a backup from
      today (or make one).
- [ ] **List the test numbers:** every number in Hostinger `OTP_TEST_NUMBERS`, plus any of your own
      numbers used only for testing. Do **not** list a number whose orders are real.
- [ ] Put the numbers in **both** files in `sudhamrtam_backend/tools/`, one per line, in `+91…` form:
      `test_customers_preview.sql` and `test_customers_cleanup.sql`.
- [ ] Supabase → SQL Editor → run **the preview**. Read the counts (orders, bills, plans, stops, help
      conversations, feedback, subscription closings). Do they look like only test data?
- [ ] Run **the cleanup**. The last result row must show **0** in every `…_left` column. The test
      accounts themselves stay, so the reviewer can still sign in.
- [ ] Not covered by the cleanup (decide separately): counter bills, farmer and milk collection data,
      staff cash handovers.
- [ ] Open the staff app: Home, Orders and Bills show no test orders.

## D. Launch day

- [ ] Play page opens with the public link above, and **Install** works on a phone that was not a tester.
- [ ] Website `sudhamrtam.in` opens and shows the latest version (`/version.json`).
- [ ] Hostinger: `CASHFREE_ENV=production`, the API app is running (start-up log has no errors).
- [ ] Place **one real order** yourself from the Play copy (small, Cash on Delivery or online), check it
      in the staff app, then deliver or cancel it.
- [ ] **Announce:** WhatsApp message to customers with the Play link and the website; tell the delivery
      partners to mention the app at the door.
- [ ] If Cashfree had asked for the public Play link for their whitelisting, send it to them now.

## E. The first week

- [ ] Every morning: staff app Home (orders today, to deliver), Cashfree dashboard (payments match
      "Paid online" orders), help conversations answered.
- [ ] Play Console → Ratings and reviews: reply to every review, good or bad.
- [ ] Note what customers ask for most; that is the next round of work.

---

Related: `play-console-answers.md` (form answers), `store-listing.md`, `data-safety.md`,
`sudhamrtam_backend/tools/test_customers_*.sql`.
