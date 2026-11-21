# Putting the website on sudhamrtam.in (Hostinger)

The website is this app built for the web. Customers sign in with the same WhatsApp code as in the phone app and see the same account: orders, milk plans, bills and addresses. It replaces the old PHP site in `public_html`. The old site's products, prices and areas are already in the new backend.

Do the parts in this order. Part 1 must work before Part 4, or the new website cannot reach the API and sign-in shows "Cannot reach the server".

## 1. Let the API accept the website

1. Send the backend change to GitHub. In PowerShell, in `D:\Sudhamrtam\sudhamrtam_backend`:
   ```powershell
   git push
   ```
   Then redeploy the API as usual (`sudhamrtam_backend\docs\DEPLOY_HOSTINGER.md`).
2. hPanel → the API's Node.js app → **Environment variables**. Add:

   | Name | Value |
   |---|---|
   | `CUSTOMER_WEB_ORIGINS` | `https://sudhamrtam.in,https://www.sudhamrtam.in` |

   Save and redeploy.
3. Check: the API's runtime log says `Customer website: https://sudhamrtam.in, https://www.sudhamrtam.in`. Also, in PowerShell:
   ```powershell
   curl.exe -i -X OPTIONS https://api.sudhamrtam.in/v1/catalog -H "Origin: https://sudhamrtam.in" -H "Access-Control-Request-Method: GET"
   ```
   The answer must start with `HTTP/1.1 204` and contain `access-control-allow-origin: https://sudhamrtam.in`. If it says `404`, the new code is not deployed yet. If there is no `access-control-allow-origin` line, the setting is missing or mistyped.

## 2. Back up the old site

hPanel → **Websites** → `sudhamrtam.in` → **File Manager** → open `public_html`.

1. Turn on **Show hidden files**, so `.htaccess` is shown too.
2. Select everything in `public_html` → **Compress** → zip. Download the zip and keep it in `D:\Sudhamrtam\Backup` (for example `old_site_public_html_2026-11.zip`).
3. If the old site used a database (hPanel → **Databases**), export it too, with **phpMyAdmin → Export**. The new website does not use it, but keep it.

## 3. Build the upload zip

In PowerShell, in `D:\Sudhamrtam\sudhamrtam_customer_app`:
```powershell
python tool/build_web.py --zip
```
This makes `D:\Sudhamrtam\website_upload.zip` and keeps the previous one as `website_upload_previous.zip`. The output says whether the address map is on (`Google Maps: on`) or off. Off is fine: customers then mark their home with their current location. To turn the map on later, see Part 7.

## 4. Replace the old site

In File Manager, `public_html`:

1. **Look before deleting.** Delete the old site's files and folders: `index.php`, `products.php`, `css`, `img`, `lib`, `.htaccess` and so on. **Do not delete** folders that belong to other sites. If the staff site (`staff.sudhamrtam.in`) or anything else lives in a folder inside `public_html`, leave that folder alone. If you are not sure, rename a folder instead of deleting it.
2. **Upload** `D:\Sudhamrtam\website_upload.zip` into `public_html`.
3. Right-click it → **Extract** → into `public_html` itself (not into a new folder). Then delete the zip.
4. `public_html` now holds `index.html`, `.htaccess`, `main.dart.<letters>.js`, `flutter_bootstrap.<letters>.js`, `sqlite3.wasm`, `sqflite_sw.js` and the folders `assets`, `canvaskit` and `icons`.
5. hPanel → **Security → SSL**: SSL active for `sudhamrtam.in` and `www.sudhamrtam.in`, and **Force HTTPS** on.

## 5. Check

On a computer and on a phone's browser:

- [ ] `https://sudhamrtam.in` shows the Sudhamrtam animation, then Home.
- [ ] Shop shows the products with photos and today's prices.
- [ ] Account → Sign in with phone: the WhatsApp code arrives and sign-in works. Use your own number: your orders, milk plan and addresses are the same as in the phone app.
- [ ] Close the tab, open the site again: still signed in.
- [ ] `https://www.sudhamrtam.in` changes to `https://sudhamrtam.in`.
- [ ] An old link such as `https://sudhamrtam.in/products.php` opens the website.
- [ ] `https://staff.sudhamrtam.in` still works.

If something is wrong, Part 6 puts the old site back.

## 6. Going back to the old site

File Manager → `public_html`: delete the new files (Part 4, step 4), upload the backup zip from Part 2, and extract it into `public_html`.

## 7. Later

- **Address map:** in Google Cloud Console, enable **Maps JavaScript API** and create an API key. Restrict it to **Websites**: `https://sudhamrtam.in/*`, `https://www.sudhamrtam.in/*` and `http://localhost/*`, and to the Maps JavaScript API. Save the key, only the key, in `D:\Sudhamrtam\sudhamrtam_customer_app\web\maps-key.txt`. This file is never committed or uploaded. Then build again (Part 3) and upload (below).
- **Online payment on the website:** Cashfree must accept the website. Cashfree Payment Gateway Dashboard → **Developers → Whitelisting → Add New → Website URL** → `https://sudhamrtam.in`. Cashfree checks that the site has **Contact Us**, **Terms and Conditions** and **Refunds and Cancellations** pages, and usually answers within 24 hours.
- **Updating the website:** build again (Part 3), upload `website_upload.zip` into `public_html` and extract it over the old files. Each build has its own file names, so customers get the new version at once. Old `main.dart.*.js` files may stay; they are never loaded again.
