import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'theme.dart';

/// Start-up intro. Order: AuctionX logo fades in, then the intro video plays
/// (gavel, gold waves, logo reveal), then the logo zooms through into the app.
/// The video loads in the background while the logo shows, so it starts without a wait.
/// Tap anywhere to skip. It never blocks the app: if the video cannot play on this device
/// the logo is shown briefly and the app opens. Reduced motion shows only the logo, no movement.
class IntroSplash extends StatefulWidget {
  final VoidCallback onDone;
  const IntroSplash({super.key, required this.onDone});
  @override
  State<IntroSplash> createState() => _IntroSplashState();
}

class _IntroSplashState extends State<IntroSplash> with SingleTickerProviderStateMixin {
  static const _logoTime = Duration(milliseconds: 900);
  static const _zoomTime = Duration(milliseconds: 800);

  late final AnimationController _zoom = AnimationController(vsync: this, duration: _zoomTime);
  VideoPlayerController? _video;
  bool _ready = false; // video loaded
  bool _noVideo = false; // video could not load on this device
  bool _logoDone = false; // logo phase finished
  bool _videoOn = false; // video is shown instead of the logo
  bool _zooming = false;
  bool _finished = false;
  Timer? _logoTimer, _cap;

  @override
  void initState() {
    super.initState();
    _prepare(); // start loading the video right away
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _logoTimer = Timer(const Duration(milliseconds: 800), _finish);
        return;
      }
      _logoTimer = Timer(_logoTime, _onLogoDone);
      _cap = Timer(const Duration(seconds: 12), _startZoom); // safety net: never hold the app
    });
  }

  Future<void> _prepare() async {
    final c = VideoPlayerController.asset('assets/intro.mp4');
    try {
      await c.initialize().timeout(const Duration(seconds: 4));
      if (!mounted) {
        await c.dispose();
        return;
      }
      _video = c;
      _ready = true;
      _tryPlay();
    } catch (_) {
      await c.dispose();
      _noVideo = true;
      if (_logoDone) _startZoom();
    }
  }

  void _onLogoDone() {
    _logoDone = true;
    if (_noVideo) {
      _startZoom(); // video not supported here: logo only, then go in
    } else {
      _tryPlay();
    }
  }

  void _tryPlay() {
    final c = _video;
    if (!mounted || _zooming || !_logoDone || !_ready || c == null || _videoOn) return;
    // Browsers only allow autoplay when muted, so the web build plays silently.
    c.setVolume(kIsWeb ? 0 : 1);
    c.addListener(_checkEnd);
    setState(() => _videoOn = true);
    c.play();
  }

  void _checkEnd() {
    final v = _video?.value;
    if (v == null || !v.isInitialized || _zooming) return;
    if (v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 150)) {
      _startZoom();
    }
  }

  void _startZoom() {
    if (!mounted || _zooming) return;
    _zooming = true;
    _logoTimer?.cancel();
    _video?.pause();
    _zoom.forward().whenComplete(_finish);
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _cap?.cancel();
    widget.onDone();
  }

  @override
  void dispose() {
    _logoTimer?.cancel();
    _cap?.cancel();
    _video?.removeListener(_checkEnd);
    _video?.dispose();
    _zoom.dispose();
    super.dispose();
  }

  Widget _logoView() => TweenAnimationBuilder<double>(
        key: const ValueKey('logo'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => Opacity(
          opacity: t,
          child: Transform.scale(
            scale: 0.85 + 0.15 * t,
            child: Image.asset('assets/emblem.png', width: 260, height: 260),
          ),
        ),
      );

  Widget _videoView(VideoPlayerController v) => SizedBox.expand(
        key: const ValueKey('video'),
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(width: v.value.size.width, height: v.value.size.height, child: VideoPlayer(v)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final v = _video;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _startZoom,
      child: AnimatedBuilder(
        animation: _zoom,
        builder: (context, child) {
          final z = Curves.easeIn.transform(_zoom.value);
          return Opacity(
            opacity: 1 - z,
            child: Transform.scale(scale: 1 + 6 * z, child: child),
          );
        },
        child: Container(
          color: kBg,
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: _videoOn && v != null ? _videoView(v) : _logoView(),
          ),
        ),
      ),
    );
  }
}
