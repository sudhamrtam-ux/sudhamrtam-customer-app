import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The opening animation (owner, 2026-11-17).
const splashVideoAsset = 'assets/videos/sudhamrtam_splash.mp4';

/// The colour around the video (and of Android's own launch screen),
/// the same as the video's first frame, so the start looks seamless.
const splashBackground = Color(0xFFF8E4C2);

/// Makes the player for [asset]; tests replace it.
typedef SplashPlayerFactory = VideoPlayerController Function(String asset);

VideoPlayerController _assetPlayer(String asset) =>
    VideoPlayerController.asset(asset);

/// Shown first when the app opens from its icon: the Sudhamrtam
/// animation plays once while the app gets ready behind it. A tap
/// skips it; if the video cannot play, [onDone] is called at once.
/// [onDone] is called exactly once.
class SplashVideoApp extends StatelessWidget {
  const SplashVideoApp({
    super.key,
    required this.onDone,
    this.player = _assetPlayer,
    this.maxDuration = const Duration(seconds: 8),
  });

  final VoidCallback onDone;
  final SplashPlayerFactory player;

  /// Never longer than this, whatever the video does.
  final Duration maxDuration;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SplashVideoScreen(
      onDone: onDone,
      player: player,
      maxDuration: maxDuration,
    ),
  );
}

class SplashVideoScreen extends StatefulWidget {
  const SplashVideoScreen({
    super.key,
    required this.onDone,
    this.player = _assetPlayer,
    this.maxDuration = const Duration(seconds: 8),
  });

  final VoidCallback onDone;
  final SplashPlayerFactory player;
  final Duration maxDuration;

  @override
  State<SplashVideoScreen> createState() => _SplashVideoScreenState();
}

class _SplashVideoScreenState extends State<SplashVideoScreen> {
  VideoPlayerController? _controller;
  Timer? _limit;
  bool _done = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _limit = Timer(widget.maxDuration, _finish);
    _start();
  }

  Future<void> _start() async {
    try {
      final controller = widget.player(splashVideoAsset);
      _controller = controller;
      await controller.initialize();
      if (_done || !mounted) return;
      await controller.setVolume(0);
      controller.addListener(_onTick);
      await controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      // No animation is fine: the app opens straight away.
      debugPrint('Opening animation could not play: $error');
      _finish();
    }
  }

  void _onTick() {
    final value = _controller?.value;
    if (value == null || !value.isInitialized) return;
    if (value.hasError) {
      _finish();
    } else if (value.duration > Duration.zero &&
        value.position >= value.duration) {
      _finish();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _limit?.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _limit?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: splashBackground,
      body: GestureDetector(
        key: const Key('splashVideo'),
        behavior: HitTestBehavior.opaque,
        // A tap skips the animation.
        onTap: _finish,
        child: SizedBox.expand(
          child: _ready && controller != null
              ? FittedBox(
                  // Fills the screen; the edges are cut on very
                  // tall or wide screens rather than leaving bars.
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
