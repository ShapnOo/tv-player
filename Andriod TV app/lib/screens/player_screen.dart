import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/api_service.dart';
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
  final String mediaId;
  final ApiService? apiService;
  final int initialPositionSeconds;

  const TVPlayerScreen({
    super.key,
    required this.videoUrl,
    this.compatUrl,
    this.transcodeUrl,
    required this.title,
    this.subtitle = 'Direct 4K Local Stream',
    this.isDolbyVision = false,
    this.mediaId = '',
    this.apiService,
    this.initialPositionSeconds = 0,
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
  Timer? _progressSaveTimer;

  // Netflix Interactive Scrubbing State
  bool _isScrubbing = false;
  Duration _scrubTarget = Duration.zero;
  int _scrubStepSeconds = 10;
  DateTime _lastScrubTime = DateTime.now();
  Timer? _scrubCommitDebounce;

  StreamMode _currentMode = StreamMode.direct;
  int _retryCount = 0;
  bool _hasInitialSeekPerformed = false;

  // TV Remote D-Pad Focus Nodes
  final FocusNode _bgFocusNode = FocusNode(debugLabel: 'PlayerBackground');
  final FocusNode _playPauseFocusNode = FocusNode(debugLabel: 'PlayPause');
  final FocusNode _rewindFocusNode = FocusNode(debugLabel: 'Rewind10');
  final FocusNode _forwardFocusNode = FocusNode(debugLabel: 'Forward10');
  final FocusNode _backFocusNode = FocusNode(debugLabel: 'BackBtn');
  final FocusNode _restartFocusNode = FocusNode(debugLabel: 'RestartBtn');
  final FocusNode _modeFocusNode = FocusNode(debugLabel: 'StreamModeBtn');
  final FocusNode _timelineFocusNode = FocusNode(debugLabel: 'TimelineScrubber');

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    // Start with direct mode or auto-fallback
    _initPlayer(StreamMode.direct);

    // Initial focus on Center Play/Pause button
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playPauseFocusNode.requestFocus();
      }
    });

    // Periodic watch progress saver (every 4 seconds)
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _saveCurrentProgress();
    });
  }

  void _saveCurrentProgress() {
    if (_controller != null &&
        _isInitialized &&
        widget.mediaId.isNotEmpty &&
        widget.apiService != null) {
      final pos = _controller!.value.position.inSeconds;
      final dur = _controller!.value.duration.inSeconds;
      if (dur > 0 && pos > 0) {
        widget.apiService!.saveProgress(
          widget.mediaId,
          pos,
          dur,
          title: widget.title,
        );
      }
    }
  }

  String _getUrlForMode(StreamMode mode) {
    switch (mode) {
      case StreamMode.direct:
        return widget.videoUrl;
      case StreamMode.compat:
        return widget.compatUrl ?? '${widget.videoUrl}.mp4?compat=1';
      case StreamMode.transcode:
        return widget.transcodeUrl ?? '${widget.videoUrl}.mp4?mode=transcode';
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
        try {
          await _controller!.pause();
          await _controller!.dispose();
        } catch (_) {}
        _controller = null;
      }

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(targetUrl),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

      await controller.initialize();
      controller.addListener(_videoListener);

      // Auto-resume from saved position (Netflix style)
      if (!_hasInitialSeekPerformed) {
        int targetResume = 0;
        if (widget.initialPositionSeconds > 0) {
          targetResume = widget.initialPositionSeconds;
        } else if (widget.apiService != null && widget.mediaId.isNotEmpty) {
          final prog = widget.apiService!.getProgress(widget.mediaId);
          if (prog != null && prog.posSeconds > 15 && !prog.isWatched) {
            targetResume = prog.posSeconds;
          }
        }

        if (targetResume > 15 &&
            targetResume < (controller.value.duration.inSeconds - 25)) {
          await controller.seekTo(Duration(seconds: targetResume));
          _hasInitialSeekPerformed = true;
          _showNotification(
            '⚡ Resumed playback from ${_formatDuration(Duration(seconds: targetResume))}',
          );
        } else {
          _hasInitialSeekPerformed = true;
        }
      }

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _showControls) {
          _playPauseFocusNode.requestFocus();
        }
      });
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

      setState(() {
        _hasError = true;
        _userFriendlyError = widget.isDolbyVision
            ? 'This video format (Dolby Vision / HEVC) requires special decoding. You can play it using Universal Compatibility mode below.'
            : 'Playback encountered an issue ($e). Try switching playback mode below.';
      });
    }
  }

  void _videoListener() {
    if (mounted && _controller != null) {
      if (_controller!.value.hasError && _isInitialized) {
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
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        _hideControlsOverlay();
      }
    });
  }

  void _revealControls({FocusNode? targetFocus}) {
    setState(() {
      _showControls = true;
    });
    _startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showControls) {
        (targetFocus ?? _playPauseFocusNode).requestFocus();
      }
    });
  }

  void _hideControlsOverlay() {
    _hideTimer?.cancel();
    setState(() {
      _showControls = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_showControls) {
        _bgFocusNode.requestFocus();
      }
    });
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _saveCurrentProgress();
      setState(() {
        _showControls = true;
      });
      _hideTimer?.cancel();
      _playPauseFocusNode.requestFocus();
    } else {
      _controller!.play();
      _saveCurrentProgress();
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
    _saveCurrentProgress();

    setState(() {
      _seekFeedback = seconds > 0 ? '+$seconds s' : '$seconds s';
    });

    _seekFeedbackTimer?.cancel();
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() {
          _seekFeedback = '';
        });
      }
    });

    if (_showControls) {
      _startHideTimer();
    }
  }

  // Interactive Netflix Timeline Scrubbing
  void _onScrubStep(int direction) {
    if (_controller == null || !_isInitialized) return;

    final now = DateTime.now();
    final elapsedMs = now.difference(_lastScrubTime).inMilliseconds;
    _lastScrubTime = now;

    if (!_isScrubbing) {
      _isScrubbing = true;
      _scrubTarget = _controller!.value.position;
      _scrubStepSeconds = 10;
    } else {
      // Rapid pressing accelerates: 10s -> 20s -> 45s -> 90s -> 180s -> 300s
      if (elapsedMs < 280) {
        _scrubStepSeconds = min(300, (_scrubStepSeconds * 1.5).round());
      } else if (elapsedMs > 700) {
        _scrubStepSeconds = 10;
      }
    }

    final total = _controller!.value.duration;
    var newTarget = _scrubTarget + Duration(seconds: direction * _scrubStepSeconds);
    if (newTarget < Duration.zero) newTarget = Duration.zero;
    if (newTarget > total) newTarget = total;

    setState(() {
      _scrubTarget = newTarget;
    });

    _scrubCommitDebounce?.cancel();
    _scrubCommitDebounce = Timer(const Duration(milliseconds: 1400), () {
      _commitScrub();
    });

    _startHideTimer();
  }

  void _onSeekToFraction(double fraction) {
    if (_controller == null || !_isInitialized) return;
    final total = _controller!.value.duration;
    final targetMs = (total.inMilliseconds * fraction).round();
    final target = Duration(milliseconds: targetMs);

    setState(() {
      _isScrubbing = true;
      _scrubTarget = target;
    });

    _scrubCommitDebounce?.cancel();
    _scrubCommitDebounce = Timer(const Duration(milliseconds: 1400), () {
      _commitScrub();
    });

    _startHideTimer();
  }

  void _commitScrub() {
    _scrubCommitDebounce?.cancel();
    if (!_isScrubbing || _controller == null || !_isInitialized) return;
    final target = _scrubTarget;
    _isScrubbing = false;
    _controller!.seekTo(target);
    _saveCurrentProgress();
    _showNotification('⚡ Seeked to ${_formatDuration(target)}');
    setState(() {});
    _startHideTimer();
  }

  void _cancelScrub() {
    _scrubCommitDebounce?.cancel();
    if (_isScrubbing) {
      setState(() {
        _isScrubbing = false;
      });
    }
  }

  void _restartFromBeginning() {
    if (_controller == null || !_isInitialized) return;
    _controller!.seekTo(Duration.zero);
    _saveCurrentProgress();
    _showNotification('↺ Restarted from 00:00');
    _startHideTimer();
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

  void _cycleMode() {
    _startHideTimer();
    if (_currentMode == StreamMode.direct) {
      _initPlayer(StreamMode.compat);
    } else if (_currentMode == StreamMode.compat) {
      _initPlayer(StreamMode.transcode);
    } else {
      _initPlayer(StreamMode.direct);
    }
  }

  void _handleExit() {
    _scrubCommitDebounce?.cancel();
    _progressSaveTimer?.cancel();
    _saveCurrentProgress();
    WakelockPlus.disable();
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_videoListener);
      c.pause().catchError((_) {});
      c.dispose().catchError((_) {});
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _scrubCommitDebounce?.cancel();
    _progressSaveTimer?.cancel();
    _saveCurrentProgress();
    WakelockPlus.disable();
    _hideTimer?.cancel();
    _notificationTimer?.cancel();
    _seekFeedbackTimer?.cancel();
    _bgFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _rewindFocusNode.dispose();
    _forwardFocusNode.dispose();
    _backFocusNode.dispose();
    _restartFocusNode.dispose();
    _modeFocusNode.dispose();
    _timelineFocusNode.dispose();
    final c = _controller;
    _controller = null;
    if (c != null) {
      c.removeListener(_videoListener);
      c.pause().catchError((_) {});
      c.dispose().catchError((_) {});
    }
    super.dispose();
  }

  // Handle remote keys when controls are HIDDEN
  KeyEventResult _handleBackgroundKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Physical TV Remote Media Keys
    if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.mediaPlay) {
      if (!(_controller?.value.isPlaying ?? true)) _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.mediaPause) {
      if (_controller?.value.isPlaying ?? false) _togglePlayPause();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.mediaFastForward) {
      _revealControls(targetFocus: _timelineFocusNode);
      _onScrubStep(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.mediaRewind) {
      _revealControls(targetFocus: _timelineFocusNode);
      _onScrubStep(-1);
      return KeyEventResult.handled;
    }

    // D-Pad Left / Right seeks/scrubs directly with Netflix Timeline active
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _revealControls(targetFocus: _timelineFocusNode);
      _onScrubStep(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _revealControls(targetFocus: _timelineFocusNode);
      _onScrubStep(-1);
      return KeyEventResult.handled;
    }

    // D-Pad Up / Down / OK / Select reveals Netflix controls with Timeline focused
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _revealControls(targetFocus: _timelineFocusNode);
      return KeyEventResult.handled;
    }

    // Back key when controls hidden -> Exit player
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      _handleExit();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showControls) {
          _hideControlsOverlay();
        } else {
          _handleExit();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () {
            if (_showControls) {
              _hideControlsOverlay();
            } else {
              _revealControls();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background Video Viewport
              Center(
                child: (_isInitialized && _controller != null)
                    ? AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio > 0
                            ? _controller!.value.aspectRatio
                            : 16 / 9,
                        child: VideoPlayer(_controller!),
                      )
                    : (_hasError ? _buildErrorView() : _buildLoadingView()),
              ),

              // Hidden Controls Remote Receiver Focus Node
              if (!_showControls)
                Positioned.fill(
                  child: Focus(
                    focusNode: _bgFocusNode,
                    autofocus: true,
                    onKeyEvent: _handleBackgroundKeyEvent,
                    child: const SizedBox.expand(),
                  ),
                ),

              // Buffering indicator
              if (_isInitialized && (_controller?.value.isBuffering ?? false))
                const Center(
                  child: CircularProgressIndicator(
                    color: TVTheme.emerald,
                    strokeWidth: 4,
                  ),
                ),

              // Center Pause Indicator (when paused with controls hidden)
              if (_isInitialized &&
                  !(_controller?.value.isPlaying ?? true) &&
                  !_showControls &&
                  !_hasError)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.pause_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                ),

              // HUD Seek Feedback (+10s / -10s)
              if (_seekFeedback.isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: TVTheme.emerald, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: TVTheme.emerald.withValues(alpha: 0.5),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _seekFeedback.contains('+')
                              ? Icons.fast_forward_rounded
                              : Icons.fast_rewind_rounded,
                          color: TVTheme.emerald,
                          size: 34,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _seekFeedback,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Mode Toast Notification
              if (_statusNotification.isNotEmpty)
                Positioned(
                  top: 28,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: TVTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: TVTheme.emerald, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 20,
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

              // Netflix OSD Controls Overlay
              if (_showControls && _isInitialized && _controller != null)
                _buildNetflixControlsOverlay(),
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
              ? 'Loading 4K Master...'
              : (_currentMode == StreamMode.compat
                  ? 'Initializing Universal 4K Remux...'
                  : 'Starting Hardware Transcode...'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Container(
        width: 620,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: TVTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.85),
              blurRadius: 36,
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
              '4K Playback Notice',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _userFriendlyError,
              style: const TextStyle(
                color: TVTheme.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 26),
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
                  onTap: _handleExit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetflixControlsOverlay() {
    final pos = _isScrubbing ? _scrubTarget : _controller!.value.position;
    final actualPos = _controller!.value.position;
    final dur = _controller!.value.duration;
    final isPlaying = _controller!.value.isPlaying;
    final progress = dur.inMilliseconds > 0
        ? pos.inMilliseconds / dur.inMilliseconds
        : 0.0;

    String modeLabel = 'Direct 4K';
    if (_currentMode == StreamMode.compat) {
      modeLabel = 'Universal 4K';
    } else if (_currentMode == StreamMode.transcode) {
      modeLabel = 'Transcode';
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.90),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.96),
          ],
          stops: const [0.0, 0.18, 0.55, 1.0],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(48, 16, 48, 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. Top Bar: Back Button, Title + Badges, Mode Switcher
              Row(
                children: [
                  _PlayerTVButton(
                    focusNode: _backFocusNode,
                    icon: const Icon(Icons.arrow_back_rounded, size: 16),
                    label: 'Back',
                    isPrimary: false,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                    borderRadius: 8,
                    fontSize: 12,
                    onTap: _handleExit,
                    onDirectionalKey: (key) {
                      _startHideTimer();
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _timelineFocusNode.requestFocus();
                      } else if (key == LogicalKeyboardKey.arrowRight) {
                        _modeFocusNode.requestFocus();
                      }
                    },
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: TextStyle(
                            color: TVTheme.textSecondary.withValues(alpha: 0.9),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Quick Mode Switcher in top right
                  _PlayerTVButton(
                    focusNode: _modeFocusNode,
                    icon: const Icon(Icons.tune_rounded, size: 15),
                    label: modeLabel,
                    isPrimary: false,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6.5),
                    borderRadius: 8,
                    fontSize: 12,
                    onTap: _cycleMode,
                    onDirectionalKey: (key) {
                      _startHideTimer();
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _timelineFocusNode.requestFocus();
                      } else if (key == LogicalKeyboardKey.arrowLeft) {
                        _backFocusNode.requestFocus();
                      }
                    },
                  ),
                ],
              ),

              // 2. Center: COMPLETELY EMPTY & CLEAR (Movie is 100% visible, no giant buttons!)
              const Spacer(),

              // 3. Bottom Control Deck (Netflix Unified Panel)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A. Interactive Continuous Scrubbable Timeline Bar with floating seek bubble
                  _PlayerTimelineScrubber(
                    focusNode: _timelineFocusNode,
                    pos: pos,
                    actualPos: actualPos,
                    dur: dur,
                    progress: progress,
                    isScrubbing: _isScrubbing,
                    scrubTarget: _scrubTarget,
                    formatDuration: _formatDuration,
                    onScrubLeft: () => _onScrubStep(-1),
                    onScrubRight: () => _onScrubStep(1),
                    onCommit: _commitScrub,
                    onCancel: _cancelScrub,
                    onSeekToFraction: _onSeekToFraction,
                    onDirectionalKey: (key) {
                      _startHideTimer();
                      if (key == LogicalKeyboardKey.arrowDown) {
                        _playPauseFocusNode.requestFocus();
                      } else if (key == LogicalKeyboardKey.arrowUp) {
                        _backFocusNode.requestFocus();
                      }
                    },
                  ),

                  const SizedBox(height: 14),

                  // B. Netflix Bottom Buttons Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Rewind 10s
                      _PlayerTVButton(
                        focusNode: _rewindFocusNode,
                        icon: const Icon(Icons.replay_10_rounded, size: 18),
                        label: '-10s',
                        isPrimary: false,
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        borderRadius: 8,
                        fontSize: 12,
                        onTap: () => _seekRelative(-10),
                        onDirectionalKey: (key) {
                          _startHideTimer();
                          if (key == LogicalKeyboardKey.arrowUp) {
                            _timelineFocusNode.requestFocus();
                          } else if (key == LogicalKeyboardKey.arrowRight) {
                            _playPauseFocusNode.requestFocus();
                          }
                        },
                      ),
                      const SizedBox(width: 12),

                      // Play / Pause Master Button
                      _PlayerTVButton(
                        focusNode: _playPauseFocusNode,
                        icon: Icon(
                          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 20,
                        ),
                        label: isPlaying ? 'Pause' : 'Play',
                        isPrimary: true,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7.5),
                        borderRadius: 8,
                        fontSize: 12.5,
                        onTap: () {
                          _togglePlayPause();
                          _startHideTimer();
                        },
                        onDirectionalKey: (key) {
                          _startHideTimer();
                          if (key == LogicalKeyboardKey.arrowUp) {
                            _timelineFocusNode.requestFocus();
                          } else if (key == LogicalKeyboardKey.arrowLeft) {
                            _rewindFocusNode.requestFocus();
                          } else if (key == LogicalKeyboardKey.arrowRight) {
                            _forwardFocusNode.requestFocus();
                          }
                        },
                      ),
                      const SizedBox(width: 12),

                      // Forward 10s
                      _PlayerTVButton(
                        focusNode: _forwardFocusNode,
                        icon: const Icon(Icons.forward_10_rounded, size: 18),
                        label: '+10s',
                        isPrimary: false,
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                        borderRadius: 8,
                        fontSize: 12,
                        onTap: () => _seekRelative(10),
                        onDirectionalKey: (key) {
                          _startHideTimer();
                          if (key == LogicalKeyboardKey.arrowUp) {
                            _timelineFocusNode.requestFocus();
                          } else if (key == LogicalKeyboardKey.arrowLeft) {
                            _playPauseFocusNode.requestFocus();
                          } else if (key == LogicalKeyboardKey.arrowRight) {
                            _restartFocusNode.requestFocus();
                          }
                        },
                      ),
                      const SizedBox(width: 12),

                      // Restart from 00:00
                      _PlayerTVButton(
                        focusNode: _restartFocusNode,
                        icon: const Icon(Icons.replay_rounded, size: 16),
                        label: 'Start Over',
                        isPrimary: false,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        borderRadius: 8,
                        fontSize: 12,
                        onTap: _restartFromBeginning,
                        onDirectionalKey: (key) {
                          _startHideTimer();
                          if (key == LogicalKeyboardKey.arrowUp) {
                            _timelineFocusNode.requestFocus();
                          } else if (key == LogicalKeyboardKey.arrowLeft) {
                            _forwardFocusNode.requestFocus();
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom TV Focusable Control Button with Netflix Glow & D-Pad Steering
class _PlayerTVButton extends StatefulWidget {
  final FocusNode focusNode;
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final ValueChanged<LogicalKeyboardKey>? onDirectionalKey;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final double? fontSize;

  const _PlayerTVButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.onDirectionalKey,
    this.padding,
    this.borderRadius = 8.0,
    this.fontSize,
  });

  @override
  State<_PlayerTVButton> createState() => _PlayerTVButtonState();
}

class _PlayerTVButtonState extends State<_PlayerTVButton> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    _isFocused = widget.focusNode.hasFocus;
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Focused: Glowing Emerald for Primary, Radiant White for Secondary
    // Unfocused: Crisp Solid White for Primary, Semi-transparent Glass for Secondary
    final Color bgColor = _isFocused
        ? (widget.isPrimary ? TVTheme.emerald : Colors.white)
        : (widget.isPrimary
            ? Colors.white
            : Colors.white.withValues(alpha: 0.16));

    final Color fgColor = _isFocused
        ? Colors.black
        : (widget.isPrimary ? Colors.black : Colors.white);

    final effectivePadding = widget.padding ??
        (widget.isPrimary
            ? const EdgeInsets.symmetric(horizontal: 18, vertical: 8)
            : const EdgeInsets.symmetric(horizontal: 13, vertical: 7));

    final effectiveFontSize = widget.fontSize ?? (widget.isPrimary ? 13.0 : 12.0);
    final effectiveIconSize = widget.isPrimary ? 20.0 : 16.0;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          if (widget.onDirectionalKey != null) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.arrowRight) {
              widget.onDirectionalKey!(event.logicalKey);
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: effectivePadding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isFocused
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.20),
                width: _isFocused ? 2.0 : 1.0,
              ),
              boxShadow: _isFocused
                  ? [
                      BoxShadow(
                        color: (widget.isPrimary ? TVTheme.emerald : Colors.white)
                            .withValues(alpha: 0.55),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8,
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: fgColor,
                    size: effectiveIconSize,
                  ),
                  child: widget.icon,
                ),
                if (widget.label.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: fgColor,
                      fontSize: effectiveFontSize,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Selectable & D-Pad Scrubbable Netflix Timeline Widget
class _PlayerTimelineScrubber extends StatefulWidget {
  final FocusNode focusNode;
  final Duration pos;
  final Duration actualPos;
  final Duration dur;
  final double progress;
  final bool isScrubbing;
  final Duration scrubTarget;
  final String Function(Duration) formatDuration;
  final VoidCallback onScrubLeft;
  final VoidCallback onScrubRight;
  final VoidCallback onCommit;
  final VoidCallback onCancel;
  final ValueChanged<double> onSeekToFraction;
  final ValueChanged<LogicalKeyboardKey>? onDirectionalKey;

  const _PlayerTimelineScrubber({
    required this.focusNode,
    required this.pos,
    required this.actualPos,
    required this.dur,
    required this.progress,
    required this.isScrubbing,
    required this.scrubTarget,
    required this.formatDuration,
    required this.onScrubLeft,
    required this.onScrubRight,
    required this.onCommit,
    required this.onCancel,
    required this.onSeekToFraction,
    this.onDirectionalKey,
  });

  @override
  State<_PlayerTimelineScrubber> createState() => _PlayerTimelineScrubberState();
}

class _PlayerTimelineScrubberState extends State<_PlayerTimelineScrubber> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    _isFocused = widget.focusNode.hasFocus;
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayPos = widget.isScrubbing ? widget.scrubTarget : widget.pos;
    final deltaSeconds = widget.isScrubbing
        ? (widget.scrubTarget.inSeconds - widget.actualPos.inSeconds)
        : 0;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // OK/Select commits scrub
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            if (widget.isScrubbing) {
              widget.onCommit();
            } else {
              widget.onScrubRight();
            }
            return KeyEventResult.handled;
          }

          // Left/Right scrubs continuously along the bar!
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onScrubLeft();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onScrubRight();
            return KeyEventResult.handled;
          }

          // Back cancels scrub if active
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack) {
            if (widget.isScrubbing) {
              widget.onCancel();
              return KeyEventResult.handled;
            }
          }

          // Up/Down navigation to other buttons
          if (widget.onDirectionalKey != null) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.arrowDown) {
              if (widget.isScrubbing) {
                widget.onCommit();
              }
              widget.onDirectionalKey!(event.logicalKey);
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barWidth = constraints.maxWidth;
          final clampedProgress = widget.progress.clamp(0.0, 1.0);
          final thumbX = clampedProgress * barWidth;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Scrubber Track & Floating Seek Preview Bubble
              SizedBox(
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Floating Netflix Seek Tooltip Bubble (Above Scrubber Thumb)
                    if (widget.isScrubbing)
                      Positioned(
                        left: (thumbX - 52).clamp(0.0, max(0.0, barWidth - 104)),
                        bottom: 22,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141414).withValues(alpha: 0.96),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: TVTheme.emerald, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: TVTheme.emerald.withValues(alpha: 0.5),
                                blurRadius: 14,
                                spreadRadius: 1,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.8),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.formatDuration(widget.scrubTarget),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              if (deltaSeconds != 0)
                                Text(
                                  deltaSeconds > 0
                                      ? '+${widget.formatDuration(Duration(seconds: deltaSeconds))}'
                                      : '-${widget.formatDuration(Duration(seconds: -deltaSeconds))}',
                                  style: const TextStyle(
                                    color: TVTheme.emerald,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                    // Gesture area for Touch / Pointer dragging
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 24,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          if (barWidth > 0) {
                            final frac = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                            widget.onSeekToFraction(frac);
                          }
                        },
                        onHorizontalDragStart: (details) {
                          if (barWidth > 0) {
                            final frac = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                            widget.onSeekToFraction(frac);
                          }
                        },
                        onHorizontalDragUpdate: (details) {
                          if (barWidth > 0) {
                            final frac = (details.localPosition.dx / barWidth).clamp(0.0, 1.0);
                            widget.onSeekToFraction(frac);
                          }
                        },
                        onHorizontalDragEnd: (details) {
                          widget.onCommit();
                        },
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            // Background Track
                            Container(
                              height: _isFocused ? 7 : 5,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),

                            // Played / Scrubbed Active Track
                            FractionallySizedBox(
                              widthFactor: clampedProgress,
                              child: Container(
                                height: _isFocused ? 7 : 5,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [TVTheme.emerald, Color(0xFF34D399)],
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  boxShadow: _isFocused
                                      ? [
                                          BoxShadow(
                                            color: TVTheme.emerald.withValues(alpha: 0.7),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            ),

                            // Glowing Netflix Circular Scrubber Thumb
                            Positioned(
                              left: (thumbX - (_isFocused ? 9 : 7)).clamp(0.0, max(0.0, barWidth - (_isFocused ? 18 : 14))),
                              child: Container(
                                width: _isFocused ? 18 : 14,
                                height: _isFocused ? 18 : 14,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: TVTheme.emerald,
                                    width: _isFocused ? 3.0 : 2.0,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isFocused ? TVTheme.emerald : Colors.white)
                                          .withValues(alpha: 0.8),
                                      blurRadius: _isFocused ? 12 : 6,
                                      spreadRadius: _isFocused ? 2 : 1,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 2. Timestamps and Netflix Remote Guidance Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.formatDuration(displayPos),
                    style: TextStyle(
                      color: (widget.isScrubbing || _isFocused)
                          ? TVTheme.emerald
                          : Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    _isFocused
                        ? '◀ ▶: Scrub Bar  •  OK: Jump Here  •  ▼: Controls'
                        : '◀ ▶: Seek  •  OK: Select  •  Back: Hide',
                    style: TextStyle(
                      color: _isFocused ? Colors.white : TVTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    widget.formatDuration(widget.dur),
                    style: const TextStyle(
                      color: TVTheme.textMuted,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
