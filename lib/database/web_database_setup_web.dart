import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// The website: the same SQLite database, kept in the browser
/// (IndexedDB) by `sqflite_common_ffi_web`. It needs
/// `web/sqlite3.wasm` and `web/sqflite_sw.js`
/// (`dart run sqflite_common_ffi_web:setup`).
Future<void> useWebDatabaseIfNeeded() async {
  databaseFactory = databaseFactoryFfiWeb;
}
