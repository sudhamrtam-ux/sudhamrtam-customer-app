/// Chooses the SQLite engine for the website (the app built for the
/// web). On Android and iOS this does nothing: sqflite's own engine
/// is used, as before.
library;

export 'web_database_setup_stub.dart'
    if (dart.library.js_interop) 'web_database_setup_web.dart';
