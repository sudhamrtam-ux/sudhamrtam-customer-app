"""Builds the website (the customer app for the web, sudhamrtam.in).

  python tool/build_web.py            # build/web for https://api.sudhamrtam.in
  python tool/build_web.py --zip      # also D:\\Sudhamrtam\\website_upload.zip for Hostinger
  python tool/build_web.py --api http://127.0.0.1:3000   # against the local backend

Google Maps: the address map needs a Maps JavaScript API key that is
restricted to the website's addresses (sudhamrtam.in, www.sudhamrtam.in,
localhost). Put it in web/maps-key.txt (git-ignored, like
android/maps-key.txt). This script adds the Maps script to
build/web/index.html. Without the file the website still works: the
address form then asks for the current location instead of a map.

--zip, as the staff app's tool/make_web_zip.py (decision 2026-11-16):
main.dart.js and flutter_bootstrap.js get hashed names each build
(Hostinger's CDN kept old copies for days); index.html points to them.
Zip paths use "/". The last zip is kept as website_upload_previous.zip.
"""

import argparse
import hashlib
import pathlib
import re
import shutil
import subprocess
import sys
import zipfile

APP = pathlib.Path(__file__).resolve().parent.parent
WEB = APP / 'build' / 'web'
KEY_FILE = APP / 'web' / 'maps-key.txt'
ZIP = pathlib.Path(r'D:\Sudhamrtam\website_upload.zip')
PREVIOUS_ZIP = ZIP.with_name('website_upload_previous.zip')
LIVE_API = 'https://api.sudhamrtam.in'


def short_hash(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


def replace_once(text: str, old: str, new: str, file: str) -> str:
    count = text.count(old)
    if count != 1:
        sys.exit(f'{file}: expected {old!r} once, found {count} times')
    return text.replace(old, new)


def read_maps_key() -> str | None:
    if not KEY_FILE.exists():
        return None
    key = KEY_FILE.read_text(encoding='utf-8').strip()
    if not re.fullmatch(r'AIza[0-9A-Za-z_\-]{35}', key):
        sys.exit(f'{KEY_FILE} does not look like a Google API key (AIza…, 39 characters)')
    return key


def build(api: str) -> None:
    flutter = shutil.which('flutter') or shutil.which('flutter.bat')
    if flutter is None:
        sys.exit('flutter is not on PATH')
    subprocess.run(
        [flutter, 'build', 'web', '--release', '--no-wasm-dry-run',
         f'--dart-define=API_BASE_URL={api}'],
        cwd=APP, check=True,
    )


def add_maps_script(key: str | None) -> None:
    index_path = WEB / 'index.html'
    index = index_path.read_text(encoding='utf-8')
    if key is None:
        print('Google Maps: OFF (no web/maps-key.txt); addresses use the current location only')
        return
    # Loaded before the app starts, so the map is ready when an
    # address form opens.
    script = f'  <script src="https://maps.googleapis.com/maps/api/js?key={key}"></script>\n</head>'
    index = replace_once(index, '</head>', script, 'index.html')
    index_path.write_text(index, encoding='utf-8')
    print('Google Maps: on (key from web/maps-key.txt)')


def make_zip() -> None:
    main_js = (WEB / 'main.dart.js').read_bytes()
    main_name = f'main.dart.{short_hash(main_js)}.js'

    bootstrap = (WEB / 'flutter_bootstrap.js').read_text(encoding='utf-8')
    bootstrap = replace_once(
        bootstrap, '"mainJsPath":"main.dart.js"', f'"mainJsPath":"{main_name}"',
        'flutter_bootstrap.js',
    )
    bootstrap_bytes = bootstrap.encode('utf-8')
    bootstrap_name = f'flutter_bootstrap.{short_hash(bootstrap_bytes)}.js'

    index = (WEB / 'index.html').read_text(encoding='utf-8')
    index = replace_once(
        index, 'src="flutter_bootstrap.js"', f'src="{bootstrap_name}"', 'index.html',
    )

    extra = {
        main_name: main_js,
        bootstrap_name: bootstrap_bytes,
        'index.html': index.encode('utf-8'),
    }

    if ZIP.exists():
        shutil.copyfile(ZIP, PREVIOUS_ZIP)
    ZIP.unlink(missing_ok=True)
    with zipfile.ZipFile(ZIP, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(WEB.rglob('*')):
            if path.is_file():
                name = path.relative_to(WEB).as_posix()
                if name in extra or name == 'maps-key.txt':
                    continue
                z.write(path, name)
        for name, data in extra.items():
            z.writestr(name, data)

    raw = ZIP.read_bytes()
    if b'assets/fonts' not in raw or b'assets\\fonts' in raw:
        sys.exit('zip paths look wrong (need forward slashes)')
    print(f'{ZIP} ({len(raw) // 1024} KB)')
    print(f'index.html -> {bootstrap_name} -> {main_name}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--api', default=LIVE_API, help=f'API address (default {LIVE_API})')
    parser.add_argument('--zip', action='store_true', help='also make the Hostinger upload zip')
    args = parser.parse_args()

    if args.zip and args.api != LIVE_API:
        sys.exit(f'--zip is for the live website: use the default --api {LIVE_API}')

    key = read_maps_key()
    build(args.api)
    # flutter copies everything in web/, the key file too: it must
    # never be served.
    (WEB / 'maps-key.txt').unlink(missing_ok=True)
    add_maps_script(key)
    if args.zip:
        make_zip()


if __name__ == '__main__':
    main()
