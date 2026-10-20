import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../theme/tv_theme.dart';
import '../widgets/tv_focus_button.dart';

enum StreamMode { direct, compat, transcode }

class TVPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? compatUrl;
  final String? transcodeUrl;
  final String title;
  final String subtitle;
  final bool isDolbyVision;

  const TVPlayerScreen({
    super.key,
    required this.videoUrl,
    this.compatUrl,
    this.transcodeUrl,
    required this.title,
    this.subtitle = 'Direct 4K Local Stream',
    this.isDolbyVision = false,
  });

  @override
  State<TVPlayerScreen> createState() => _TVPlayerScreenState();
}

class _TVPlayerScreenState extends State<TVPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _userFriendlyError = '';
  bool _showControls = true;
  Timer? _hideTimer;
  String _statusNotification = '';
  Timer? _notificationTimer;
  String _seekFeedback = '';
  Timer? _seekFeedbackTimer;

  StreamMode _currentMode = StreamMode.direct;
  int _retryCount = 0;

  final FocusNode _screenFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    // If the file is known Dolby Vision, start directly with compat mode on devices that might struggle,
    // or try direct and auto-fallback
    _initPlayer(StreamMode.direct);
  }

  String _getUrlForMode(StreamMode mode) {
    switch (mode) {
      case StreamMode.direct:
        return widget.videoUrl;
      case StreamMode.compat:
        return widget.compatUrl ?? '${widget.videoUrl}?compat=1';
      case StreamMode.transcode:
        return widget.transcodeUrl ?? '${widget.videoUrl}?mode=transcode';
    }
  }

  Future<void> _initPlayer(StreamMode mode) async {
    setState(() {
      _currentMode = mode;
      _hasError = false;
      _isInitialized = false;
      _userFriendlyError = '';
    });

    final targetUrl = _getUrlForMode(mode);

    try {
      if (_controller != null) {
        _controller!.removeListener(_videoListener);
        await _controller!.dispose();
        _controller = null;
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(targetUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

      await controller.initialize();
      controller.addListener(_videoListener);
      await controller.play();

      if (!mounted) return;

      setState(() {
        _controller = controller;
        _isInitialized = true;
        _hasError = false;
      });

      if (mode != StreamMode.direct) {
        _showNotification(mode == StreamMode.compat
            ? '⚡ Switched to Universal 4K Remux Mode'
            : '⚡ Switched to Hardware Transcode Mode');
      }

      _startHideTimer();
    } catch (e) {
      if (!mounted) return;

      // Auto-fallback check
      if (mode == StreamMode.direct && _retryCount == 0) {
        _retryCount++;
        _showNotification('🔄 Auto-switching to Universal 4K Mode...');
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          _initPlayer(StreamMode.compat);
          return;
        }
      }

      if (mode == StreamMode.compat && _retryCount == 1) {
        _retryCount++;
        _showNotification('🔄 Auto-switching to Hardware Transcode...');
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          _initPlayer(StreamMode.transcode);
          return;
        }
      }

      // If all automatic attempts failed, display clean helpful error
      setState(() {
        _hasError = true;
        _userFriendlyError =
            'This video format (Dolby Vision / HEVC) exceeded the device\'s hardware codec limit. You can play it using Universal Compatibility mode.';
      });
    }
  }

  void _videoListener() {
    if (mounted && _controller != null) {
      if (_controller!.value.hasError && _isInitialized) {
        // Player failed during playback
        if (_currentMode == StreamMode.direct) {
          _initPlayer(StreamMode.compat);
        } else if (_currentMode == StreamMode.compat) {
          _initPlayer(StreamMode.transcode);
        } else {
          setState(() {
            _hasError = true;
            _userFriendlyError = 'Playback interrupted by media decoder error.';
          });
        }
      } else {
        setState(() {});
      }
    }
  }

  void _showNotification(String msg) {
    setState(() {
      _statusNotification = msg;
    });
    _notificationTimer?.cancel();
    _notificationTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _statusNotification = '';
        });
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      setState(() {
        _showControls = true;
      });
      _hideTimer?.cancel();
    } else {
      _controller!.play();
      _startHideTimer();
    }
  }

  void _seekRelative(int seconds) {
    if (_controller == null || !_isInitialized) return;
    final current = _controller!.value.position;
    final total = _controller!.value.duration;
    var target = current + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (target > total) target = total;

    _controller!.seekTo(target);

    setState(() {
      _seekFeedback = seconds > 0 ? '+$seconds s' : '$seconds s';
      _showControls = true;
    });
    _startHideTimer();

    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _seekFeedback = '';
        });
      }
    });
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _hideTimer?.cancel();
    _notificationTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _screenFocusNode.dispose();
    if (_controller != null) {
      _controller!.removeListener(_videoListener);
      _controller!.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      // D-Pad OK / Enter / Space -> Toggle Play/Pause
      if (event.logicalKey == LogicalKeyboardKey.select ||
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        _togglePlayPause();
        return KeyEventResult.handled;
      }

      // D-Pad Right -> +10s
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        _seekRelative(10);
        return KeyEventResult.handled;
      }

      // D-Pad Left -> -10s
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        _seekRelative(-10);
        return KeyEventResult.handled;
      }

      // D-Pad Up / Down -> Show controls
      if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
          event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _showControls = !_showControls;
        });
        if (_showControls) _startHideTimer();
        return KeyEventResult.handled;
      }

      // Back / Escape -> Exit Player
      if (event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.goBack) {
        Navigator.pop(context);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _screenFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () {
            setState(() {
              _showControls = !_showControls;
            });
            if (_showControls) _startHideTimer();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video Viewport
              Center(
                child: (_isInitialized && _controller != null)
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio > 0
                            ? _controller!.value.aspectRatio
                            : 16 / 9,
                        child: VideoPlayer(_controller!),
                      )
                    : (_hasError
                        ? _buildErrorView()
                        : _buildLoadingView()),
              ),

              // Buffering spinner
              if (_isInitialized && (_controller?.value.isBuffering ?? false))
                const Center(
                  child: CircularProgressIndicator(
                    color: TVTheme.emerald,
                    strokeWidth: 4,
                  ),
                ),

              // Center Pause Indicator (large pulse icon)
              if (_isInitialized && !(_controller?.value.isPlaying ?? true) && !_hasError)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
                    ),
                    child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 54),
                  ),
                ),

              // Seek Feedback Overlay (+10s / -10s)
              if (_seekFeedback.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: TVTheme.emerald, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: TVTheme.emerald.withValues(alpha: 0.4),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Text(
                      _seekFeedback,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

              // Top Notification Toast (Mode switch)
              if (_statusNotification.isNotEmpty)
                Positioned(
                  top: 24,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: TVTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: TVTheme.emerald, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Text(
                        _statusNotification,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),

              // OSD Controls Overlay
              if (_showControls && _isInitialized && _controller != null)
                _buildControlsOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 52,
          height: 52,
          child: CircularProgressIndicator(
            color: TVTheme.emerald,
            strokeWidth: 4,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _currentMode == StreamMode.direct
              ? 'Loading 4K Stream...'
              : (_currentMode == StreamMode.compat
                  ? 'Initializing Universal 4K Remux...'
                  : 'Starting Hardware Transcode...'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: TVTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.8),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: TVTheme.crimson.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: TVTheme.crimson.withValues(alpha: 0.4)),
              ),
              child: const Icon(Icons.hd_outlined, color: TVTheme.crimson, size: 44),
            ),
            const SizedBox(height: 18),
            const Text(
              '4K Codec Compatibility Notice',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _userFriendlyError,
              style: const TextStyle(
                color: TVTheme.textSecondary,
                fontSize: 14.5,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                TVFocusButton(
                  icon: const Icon(Icons.bolt, size: 20),
                  label: 'Universal 4K Remux',
                  isPrimary: true,
                  autoFocus: true,
                  onTap: () {
                    _retryCount = 0;
                    _initPlayer(StreamMode.compat);
                  },
                ),
                TVFocusButton(
                  icon: const Icon(Icons.tune, size: 18),
                  label: 'Hardware Transcode',
                  isPrimary: false,
                  onTap: () {
                    _retryCount = 0;
                    _initPlayer(StreamMode.transcode);
                  },
                ),
                TVFocusButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  label: 'Retry Direct',
                  isPrimary: false,
                  onTap: () {
                    _retryCount = 0;
                    _initPlayer(StreamMode.direct);
                  },
                ),
                TVFocusButton(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: 'Exit',
                  isPrimary: false,
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsOverlay() {
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    final progress = dur.inMilliseconds > 0 ? pos.inMilliseconds / dur.inMilliseconds : 0.0;

    String modeLabel = 'DIRECT 4K';
    Color modeColor = TVTheme.cyan;
    if (_currentMode == StreamMode.compat) {
      modeLabel = 'UNIVERSAL 4K REMUX';
      modeColor = TVTheme.emerald;
    } else if (_currentMode == StreamMode.transcode) {
      modeLabel = 'TRANSCODE 1080P';
      modeColor = Colors.orangeAccent;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.88),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.94),
          ],
          stops: const [0.0, 0.28, 0.65, 1.0],
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: Row(
                children: [
                  TVFocusButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    label: 'Back',
                    isPrimary: false,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: const TextStyle(
                            color: TVTheme.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Mode Badge & Toggle
                  GestureDetector(
                    onTap: () {
                      if (_currentMode == StreamMode.direct) {
                        _initPlayer(StreamMode.compat);
                      } else if (_currentMode == StreamMode.compat) {
                        _initPlayer(StreamMode.transcode);
                      } else {
                        _initPlayer(StreamMode.direct);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: modeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: modeColor.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.tune, color: modeColor, size: 14),
                          const SizedBox(width: 6),
                          Text(
                            modeLabel,
                            style: TextStyle(
                              color: modeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              child: Column(
                children: [
                  // Progress Bar
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbColor: TVTheme.emerald,
                      activeTrackColor: TVTheme.emerald,
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                      trackHeight: 7,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                      overlayColor: TVTheme.emeraldGlow,
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged: (val) {
                        final newPos = Duration(milliseconds: (val * dur.inMilliseconds).toInt());
                        _controller!.seekTo(newPos);
                        _startHideTimer();
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Time indicators and TV D-Pad hint
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(pos),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            _controller!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                            color: TVTheme.emerald,
                            size: 26,
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'OK: Play/Pause  •  ◀ ▶: ±10s  •  Back: Exit',
                            style: TextStyle(
                              color: TVTheme.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _formatDuration(dur),
                        style: const TextStyle(
                          color: TVTheme.textMuted,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
