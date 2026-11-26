import 'dart:io';

bool runningTests() => Platform.environment.containsKey('FLUTTER_TEST');
