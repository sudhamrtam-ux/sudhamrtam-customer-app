import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';

import 'package:sudhamrtam_customer_app/app/splash_video.dart';

/// A player whose video never finishes loading.
class _SlowPlayer extends VideoPlayerController {
  _SlowPlayer() : super.asset(splashVideoAsset);

  @override
  Future<void> initialize() => Completer<void>().future;
}

/// The opening animation (owner, 2026-11-17) never keeps the app shut.
void main() {
  testWidgets('a video that cannot play opens the app at once', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      SplashVideoApp(
        onDone: () => done++,
        player: (_) => throw StateError('no video'),
      ),
    );
    await tester.pump();
    expect(done, 1);
  });

  testWidgets('a tap skips it, once', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      SplashVideoApp(onDone: () => done++, player: (_) => _SlowPlayer()),
    );
    await tester.tap(find.byKey(const Key('splashVideo')));
    await tester.tap(find.byKey(const Key('splashVideo')));
    expect(done, 1);
    await tester.pump(const Duration(seconds: 10));
    expect(done, 1);
  });

  testWidgets('it never lasts longer than the limit', (tester) async {
    var done = 0;
    await tester.pumpWidget(
      SplashVideoApp(
        onDone: () => done++,
        player: (_) => _SlowPlayer(),
        maxDuration: const Duration(seconds: 8),
      ),
    );
    await tester.pump(const Duration(seconds: 7));
    expect(done, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(done, 1);
  });

  test('fills a phone; shows the whole animation on a wide screen', () {
    // Phones (tall): fill the screen.
    expect(splashFit(const Size(412, 915)), BoxFit.cover);
    expect(splashFit(const Size(360, 640)), BoxFit.cover);
    // A computer's browser or a tablet on its side: all of it, in the middle.
    expect(splashFit(const Size(1920, 1000)), BoxFit.contain);
    expect(splashFit(const Size(1280, 800)), BoxFit.contain);
    // A square-ish window or a tablet held upright.
    expect(splashFit(const Size(800, 800)), BoxFit.contain);
    expect(splashFit(const Size(800, 1280)), BoxFit.cover);
  });
}
