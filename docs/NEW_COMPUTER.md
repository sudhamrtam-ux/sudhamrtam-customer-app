# Moving Sudhamrtam development to another computer

For the owner. Covers the five Sudhamrtam repos (backend, customer, staff, procurement, counter).
Ayyappa Diksha is a separate project and is not moved by this guide.

The tool `tool/setup_new_computer.ps1` does most of it: it checks the computer, installs missing
programs with winget, clones the repos, puts the secret files in place from a USB drive, and fetches
the packages. Run it with `-CheckOnly` at any time to see what is missing without changing anything.

---

## On the old computer (once)

- [ ] **Push everything.** In each repo, commit and push. Anything not pushed stays behind.
- [ ] Plug in a USB drive (say it is `E:`) and run:
      ```
      powershell -ExecutionPolicy Bypass -File D:\Sudhamrtam\sudhamrtam_customer_app\tool\setup_new_computer.ps1 -ExportTo E:\
      ```
      It creates `E:\sudhamrtam-move\` with:
      - `files\` — the files that are never in git:
        - the signing key `signing\sudhamrtam-release.jks` and its password file;
        - each app's `android\key.properties`;
        - the Firebase files `google-services.json` (customer, staff);
        - the Maps keys `maps-key.txt` (customer Android and website);
        - `tools\nuget\nuget.exe`.
      - `claude-memory\` — Claude Code's notes about these projects.
      - `setup_new_computer.ps1` and this guide.
- [ ] Optional, if you want them there too: copy `D:\Sudhamrtam\apks_to_share`,
      `D:\Sudhamrtam\sudhamrtam_campaign` (banners, not in git) and `D:\Sudhamrtam\Backup` to the
      USB yourself.

**The USB drive now holds the signing key.** Keep it with you. Losing the key means the apps can
never be updated on Play; leaking it lets someone else sign as Sudhamrtam. Never email it, never put
it in a chat or in git.

## On the new computer

- [ ] Windows 10/11 with **winget** (it comes with "App Installer" from the Microsoft Store).
- [ ] Best: a **D: drive**, so the projects sit at `D:\Sudhamrtam` like now. Claude Code keeps its
      notes per folder path, and the signing settings point to `D:/Sudhamrtam/signing/...`.
      No D: drive? Use `-Root C:\Sudhamrtam`, and then change `storeFile=` in the four
      `android\key.properties` files to the new path.
- [ ] Plug in the USB drive and run (in PowerShell):
      ```
      powershell -ExecutionPolicy Bypass -File E:\sudhamrtam-move\setup_new_computer.ps1 -ImportFrom E:\sudhamrtam-move
      ```
      It asks before installing anything. It may open a **GitHub sign-in** window while it clones:
      sign in with the GitHub account that owns `sudhamrtam-ux`.
- [ ] When it says the Android SDK is missing: open **Android Studio** once, finish its setup wizard
      (Standard), close it, and run the script again.
- [ ] **Open a new terminal** (the new PATH and `PUB_CACHE` only apply there) and run it once more
      with `-CheckOnly`. Repeat until everything is green.
- [ ] `flutter doctor --android-licenses` and answer `y` to each.
- [ ] Only for Windows app builds: install **Visual Studio Community** with "Desktop development
      with C++" (visualstudio.microsoft.com). The script reports it but does not install it.
- [ ] Check it works: in `sudhamrtam_customer_app`, run `flutter analyze` and `flutter test`; in
      `sudhamrtam_backend`, run `npm test`.
- [ ] **Tablet:** plug it in, accept "Allow USB debugging" for this computer, check `adb devices`.
- [ ] **Browser sign-ins** (nothing to copy, just log in): GitHub, Play Console, Hostinger, Supabase,
      Cashfree, MSG91, Firebase / Google Cloud.
- [ ] **VS Code:** open the project folder and sign in to Claude Code.
- [ ] Delete `E:\sudhamrtam-move` from the USB drive (or keep the drive locked away as a backup).

## Every day when you switch computers

1. On the computer you leave: **commit and push** in every repo you changed.
2. On the computer you start on: **`git pull`** in those repos before working.
3. Never work on both at the same time without pushing in between.
4. Claude Code's notes do not sync by themselves. After a long session on one computer, copy
   the `memory` folders in `%USERPROFILE%\.claude\projects\` whose names start with `d--Sudhamrtam-`
   (any case) to the other one (or run `-ExportTo`
   again and copy just `claude-memory`).

## When the Flutter version changes

The script installs the Flutter version written at the top of `setup_new_computer.ps1`
(`$FlutterVersion`, 3.47.9 on 27 Nov 2026). After upgrading Flutter on one computer, update that line
and upgrade the other computer too, so both build the same apps.
