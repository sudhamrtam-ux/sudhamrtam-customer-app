import 'running_tests_stub.dart'
    if (dart.library.io) 'running_tests_io.dart'
    as impl;

/// True inside `flutter test` (endless animations stay still there,
/// so screens can settle).
final bool runningTests = impl.runningTests();
