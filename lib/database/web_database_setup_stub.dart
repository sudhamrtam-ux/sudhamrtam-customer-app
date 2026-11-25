import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

/// Phones: sqflite's own engine; nothing to set up. The Windows desktop
/// app (2026-11-25): SQLite through FFI, kept in the app's support
/// folder, which an update of the app keeps.
Future<void> useWebDatabaseIfNeeded() async {
  if (!Platform.isWindows) return;
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  await databaseFactory.setDatabasesPath(
    (await getApplicationSupportDirectory()).path,
  );
}
