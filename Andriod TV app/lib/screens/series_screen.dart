import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../models/media.dart';
import '../services/api_service.dart';
import '../theme/tv_theme.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_focus_button.dart';
import 'player_screen.dart';

class TVSeriesScreen extends StatefulWidget {
  final SeriesItem series;
  final String baseUrl;
  final ApiService? apiService;

  const TVSeriesScreen({
    super.key,
    required this.series,
    required this.baseUrl,
    this.apiService,
  });

  @override
  State<TVSeriesScreen> createState() => _TVSeriesScreenState();
}

class _TVSeriesScreenState extends State<TVSeriesScreen> {
  late EpisodeItem _focusedEpisode;
  EpisodeItem? _previewEpisode;
  VideoPlayerController? _bannerController;
  bool _isBannerInitialized = false;
  int _bannerSessionId = 0;

  final ScrollController _seriesScrollController = ScrollController();
  final FocusNode _screenFocusNode = FocusNode(debugLabel: 'SeriesScreenFocus');
  final FocusNode _backButtonFocusNode = FocusNode(debugLabel: 'SeriesBackButton');

  @override
  void initState() {
    super.initState();

    if (widget.series.episodes.isNotEmpty) {
      _focusedEpisode = widget.series.episodes.first;

      // Check if there is an in-progress episode to focus by default
      if (widget.apiService != null) {
        for (final ep in widget.series.episodes) {
          final prog = widget.apiService!.getProgress(ep.id);
          if (prog != null && prog.inProgress) {
            _focusedEpisode = ep;
            break;
          }
        }
      }

      // Pick random episode for live Netflix-style billboard preview (matching web series.js)
      final randIdx = Random().nextInt(widget.series.episodes.length);
      _previewEpisode = widget.series.episodes[randIdx];
      _initBannerVideo(_previewEpisode!);
    } else {
      _focusedEpisode = EpisodeItem(
        id: '',
        title: 'No Episodes Found',
        seasonNumber: 1,
        episodeNumber: 1,
        fileName: '',
        sizeBytes: 0,
        sizeFormatted: '',
        format: 'MKV',
        seriesTitle: widget.series.title,
      );
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  void _ensureVisibleInSeriesScroll(BuildContext cardContext) {
    if (!mounted || !_seriesScrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_seriesScrollController.hasClients) return;
      final renderBox = cardContext.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      final cardOrigin = renderBox.localToGlobal(Offset.zero);
      final cardTop = cardOrigin.dy;
      final cardBottom = cardTop + renderBox.size.height * 1.05;
      final screenHeight = MediaQuery.of(cardContext).size.height;

      const double safeBottomMargin = 95.0;
      const double safeTopMargin = 70.0;

      double delta = 0.0;
      if (cardBottom > screenHeight - safeBottomMargin) {
        delta = cardBottom - (screenHeight - safeBottomMargin) + 25.0;
      } else if (cardTop < safeTopMargin) {
        delta = -(safeTopMargin - cardTop + 25.0);
      }

      if (delta != 0.0) {
        final current = _seriesScrollController.offset;
        final maxScroll = _seriesScrollController.position.maxScrollExtent;
        final target = (current + delta).clamp(0.0, maxScroll);
        if ((target - current).abs() > 4.0) {
          _seriesScrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  void _scrollToTopIfNeeded() {
    if (_seriesScrollController.hasClients && _seriesScrollController.offset > 0) {
      _seriesScrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _disposeBannerController() async {
    _bannerSessionId++;
    final old = _bannerController;
    _bannerController = null;
    if (mounted) {
      _safeSetState(() => _isBannerInitialized = false);
    }
    if (old != null) {
      try {
        await old.pause();
        await old.dispose();
      } catch (_) {}
    }
  }

  Future<void> _initBannerVideo(EpisodeItem ep) async {
    final currentSession = ++_bannerSessionId;

    try {
      final oldController = _bannerController;
      _bannerController = null;
      if (mounted) _safeSetState(() => _isBannerInitialized = false);
      if (oldController != null) {
        await oldController.pause().catchError((_) {});
        await oldController.dispose().catchError((_) {});
      }

      if (currentSession != _bannerSessionId || !mounted) return;

      final url = ep.isDolbyVision
          ? ep.compatUrl(widget.baseUrl)
          : ep.streamUrl(widget.baseUrl);

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      await controller.initialize();

      if (currentSession != _bannerSessionId || !mounted) {
        await controller.pause().catchError((_) {});
        await controller.dispose().catchError((_) {});
        return;
      }

      await controller.setVolume(0.0); // Muted for ambient TV billboard
      await controller.setLooping(true);
      await controller.play();

      if (currentSession != _bannerSessionId || !mounted) {
        await controller.pause().catchError((_) {});
        await controller.dispose().catchError((_) {});
        return;
      }

      // Seek to random position between 15% and 75% of episode runtime
      final totalSec = controller.value.duration.inSeconds;
      if (totalSec > 60) {
        final minSec = (totalSec * 0.15).toInt();
        final maxSec = (totalSec * 0.75).toInt();
        final span = max(1, maxSec - minSec);
        final randomSec = minSec + Random().nextInt(span);
        controller.seekTo(Duration(seconds: randomSec)).catchError((_) {});
      } else if (totalSec > 20) {
        final randomSec = Random().nextInt(totalSec - 10) + 5;
        controller.seekTo(Duration(seconds: randomSec)).catchError((_) {});
      }

      // Re-seed on loop
      controller.addListener(() {
        if (currentSession != _bannerSessionId) return;
        if (controller.value.isInitialized &&
            controller.value.duration.inSeconds > 60 &&
            controller.value.position >= controller.value.duration - const Duration(seconds: 3)) {
          final tSec = controller.value.duration.inSeconds;
          final minS = (tSec * 0.15).toInt();
          final maxS = (tSec * 0.75).toInt();
          final span = max(1, maxS - minS);
          final rndSec = minS + Random().nextInt(span);
          controller.seekTo(Duration(seconds: rndSec)).catchError((_) {});
        }
      });

      if (mounted && currentSession == _bannerSessionId) {
        _safeSetState(() {
          _bannerController = controller;
          _isBannerInitialized = true;
        });
      } else {
        await controller.pause().catchError((_) {});
        await controller.dispose().catchError((_) {});
      }
    } catch (e) {
      debugPrint('[SeriesBanner] Video preview notice (poster fallback): $e');
      if (mounted && currentSession == _bannerSessionId) {
        _safeSetState(() {
          _isBannerInitialized = false;
        });
      }
    }
  }

  void _handleExit() {
    _disposeBannerController();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _playEpisode(EpisodeItem ep, {int resumePos = 0}) async {
    if (ep.id.isEmpty) return;

    // Fully release hardware decoder so TV player gets exclusive access
    await _disposeBannerController();
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TVPlayerScreen(
          videoUrl: ep.streamUrl(widget.baseUrl),
          compatUrl: ep.compatUrl(widget.baseUrl),
          transcodeUrl: ep.transcodeUrl(widget.baseUrl),
          title: '${widget.series.title} - ${ep.title}',
          subtitle:
              'Season ${ep.seasonNumber} Episode ${ep.episodeNumber} • ${ep.sizeFormatted}',
          isDolbyVision: ep.isDolbyVision,
          mediaId: ep.id,
          apiService: widget.apiService,
          initialPositionSeconds: resumePos,
        ),
      ),
    );

    // Refresh watch state
    if (widget.apiService != null) {
      widget.apiService!.fetchProgress();
    }

    // Resume billboard loop upon return if still on this screen
    if (mounted && _previewEpisode != null) {
      _initBannerVideo(_previewEpisode!);
    }
  }

  @override
  void dispose() {
    _disposeBannerController();
    _seriesScrollController.dispose();
    _screenFocusNode.dispose();
    _backButtonFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final epCount = widget.series.episodes.length;
    final activePoster = _previewEpisode != null
        ? _previewEpisode!.thumbnailUrl(widget.baseUrl)
        : (_focusedEpisode.id.isNotEmpty
            ? _focusedEpisode.thumbnailUrl(widget.baseUrl)
            : '');

    // Check watch progress of focused episode
    final focusedProg = widget.apiService?.getProgress(_focusedEpisode.id);
    final hasProgress = focusedProg != null && focusedProg.inProgress;
    final isWatched = focusedProg != null && focusedProg.isWatched;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleExit();
      },
      child: Focus(
        focusNode: _screenFocusNode,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            // TV remote back keys -> Safely return to Home Screen
            if (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.goBack ||
                event.logicalKey == LogicalKeyboardKey.backspace) {
              _handleExit();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: TVTheme.background,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Full-bleed Hero Video Trailer (Vibrant, Clear, Classy Netflix Stage)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 520,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_isBannerInitialized &&
                        _bannerController != null &&
                        _bannerController!.value.isInitialized)
                      FittedBox(
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          width: _bannerController!.value.size.width > 0
                              ? _bannerController!.value.size.width
                              : 16,
                          height: _bannerController!.value.size.height > 0
                              ? _bannerController!.value.size.height
                              : 9,
                          child: VideoPlayer(_bannerController!),
                        ),
                      )
                    else if (activePoster.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: activePoster,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                        errorWidget: (_, _, _) => const SizedBox(),
                      ),

                    // A. Horizontal Soft Vignette: Dark on far left for title contrast, 100% clear on right for video
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              TVTheme.background.withValues(alpha: 0.96),
                              TVTheme.background.withValues(alpha: 0.68),
                              TVTheme.background.withValues(alpha: 0.20),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.22, 0.44, 0.65],
                          ),
                        ),
                      ),
                    ),

                    // B. Bottom Fade: Smoothly melts the video into the background where episodes start
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              TVTheme.background.withValues(alpha: 0.70),
                              TVTheme.background,
                            ],
                            stops: const [0.0, 0.58, 0.85, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // C. Top Subtle Shadow: Keeps back button and breadcrumb legible
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 75,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.45),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Main Content
              SafeArea(
                child: SingleChildScrollView(
                  controller: _seriesScrollController,
                  padding: const EdgeInsets.fromLTRB(48, 16, 48, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Bar: Back Button & Breadcrumb (Compact & Sleek)
                      Row(
                        children: [
                          TVFocusButton(
                            focusNode: _backButtonFocusNode,
                            icon: const Icon(Icons.arrow_back_rounded, size: 16),
                            label: 'Back to Home',
                            isPrimary: false,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5.5),
                            fontSize: 12,
                            borderRadius: 16,
                            onFocusChange: (hasF) {
                              if (hasF) _scrollToTopIfNeeded();
                            },
                            onTap: _handleExit,
                          ),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'Series  /  ${widget.series.title}',
                              style: const TextStyle(
                                color: TVTheme.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // Hero Billboard for Series (Borderless, Classy Netflix Stage)
                      SizedBox(
                        width: 520,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 4K & Season Badges
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: TVTheme.emerald.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: TVTheme.emerald,
                                      width: 1.0,
                                    ),
                                  ),
                                  child: const Text(
                                    'TV SERIES',
                                    style: TextStyle(
                                      color: TVTheme.emerald,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: TVTheme.cyan.withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: const Text(
                                    '4K UHD',
                                    style: TextStyle(
                                      color: TVTheme.cyan,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '$epCount Episodes  •  ${widget.series.seasonsCount} Season(s)',
                                  style: const TextStyle(
                                    color: TVTheme.textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // Series Title (Folder Name)
                            Text(
                              widget.series.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 34,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black,
                                    blurRadius: 14,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),

                            const SizedBox(height: 6),

                            // Previewing Chip (Web style random preview indicator)
                            if (_previewEpisode != null)
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: TVTheme.crimson.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: TVTheme.crimson.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(
                                          Icons.live_tv_rounded,
                                          color: TVTheme.crimson,
                                          size: 12,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'LIVE PREVIEW',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'S${_previewEpisode!.seasonNumber}:E${_previewEpisode!.episodeNumber} - ${_previewEpisode!.title}',
                                      style: TextStyle(
                                        color: TVTheme.textSecondary.withValues(alpha: 0.9),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        shadows: const [
                                          Shadow(color: Colors.black, blurRadius: 8),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),

                            const SizedBox(height: 16),

                            // Action Buttons (Using Wrap to guarantee zero overflow)
                            Wrap(
                              spacing: 9,
                              runSpacing: 8,
                              children: [
                                if (hasProgress) ...[
                                  TVFocusButton(
                                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                    label:
                                        'Resume Ep ${_focusedEpisode.episodeNumber} (${focusedProg.formatTime(focusedProg.posSeconds)})',
                                    isPrimary: true,
                                    autoFocus: true,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                    fontSize: 12.5,
                                    borderRadius: 8,
                                    onFocusChange: (hasF) {
                                      if (hasF) _scrollToTopIfNeeded();
                                    },
                                    onTap: () => _playEpisode(_focusedEpisode, resumePos: focusedProg.posSeconds),
                                  ),
                                  TVFocusButton(
                                    icon: const Icon(Icons.replay_rounded, size: 15),
                                    label: 'Start Over',
                                    isPrimary: false,
                                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                    fontSize: 12,
                                    borderRadius: 8,
                                    onFocusChange: (hasF) {
                                      if (hasF) _scrollToTopIfNeeded();
                                    },
                                    onTap: () => _playEpisode(_focusedEpisode, resumePos: 1),
                                  ),
                                ] else ...[
                                  TVFocusButton(
                                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                    label: isWatched
                                        ? 'Replay Ep ${_focusedEpisode.episodeNumber}'
                                        : 'Play Ep ${_focusedEpisode.episodeNumber}',
                                    isPrimary: true,
                                    autoFocus: true,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                                    fontSize: 12.5,
                                    borderRadius: 8,
                                    onFocusChange: (hasF) {
                                      if (hasF) _scrollToTopIfNeeded();
                                    },
                                    onTap: () => _playEpisode(_focusedEpisode),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 34),

                      // Episodes Section Header
                      Row(
                        children: [
                          const Text(
                            'Episodes',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: TVTheme.cyan.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: TVTheme.cyan.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              '${widget.series.episodes.length} TOTAL',
                              style: const TextStyle(
                                color: TVTheme.cyan,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Horizontal Episode Cards Carousel (TV Remote D-Pad friendly)
                      SizedBox(
                        height: 200,
                        child: ListView.separated(
                          clipBehavior: Clip.none,
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.series.episodes.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 16),
                          itemBuilder: (context, index) {
                            final ep = widget.series.episodes[index];
                            final prog = widget.apiService?.getProgress(ep.id);
                            final epWatched = prog?.isWatched ?? false;
                            final epInProgress = prog?.inProgress ?? false;

                            return Builder(
                              builder: (cardCtx) => TVFocusCard(
                                width: 250,
                                height: 150,
                                onFocusChange: (hasF) {
                                  if (hasF) {
                                    _ensureVisibleInSeriesScroll(cardCtx);
                                    _safeSetState(() {
                                      _focusedEpisode = ep;
                                    });
                                  }
                                },
                                onTap: () => _playEpisode(ep),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  // Episode Thumbnail
                                  CachedNetworkImage(
                                    imageUrl: ep.thumbnailUrl(widget.baseUrl),
                                    fit: BoxFit.cover,
                                    placeholder: (_, _) => Container(
                                      color: TVTheme.surfaceElevated,
                                      child: const Center(
                                        child: Icon(
                                          Icons.movie_creation_outlined,
                                          color: TVTheme.textMuted,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                    errorWidget: (_, _, _) => Container(
                                      color: TVTheme.surfaceElevated,
                                      child: const Center(
                                        child: Icon(
                                          Icons.play_circle_outline,
                                          color: TVTheme.textMuted,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Top Episode Pill
                                  Positioned(
                                    top: 7,
                                    left: 7,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.75),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: TVTheme.emerald.withValues(alpha: 0.7),
                                        ),
                                      ),
                                      child: Text(
                                        'EP ${ep.episodeNumber}',
                                        style: const TextStyle(
                                          color: TVTheme.emerald,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Top Right: WATCHED Badge
                                  if (epWatched)
                                    Positioned(
                                      top: 7,
                                      right: 7,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: TVTheme.emerald.withValues(alpha: 0.95),
                                          borderRadius: BorderRadius.circular(4),
                                          boxShadow: [
                                            BoxShadow(
                                              color: TVTheme.emerald.withValues(alpha: 0.6),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_rounded,
                                              color: Colors.black,
                                              size: 10,
                                            ),
                                            SizedBox(width: 2),
                                            Text(
                                              'WATCHED',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                  // Bottom Title Gradient
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            Colors.black.withValues(alpha: 0.96),
                                            Colors.black.withValues(alpha: 0.6),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            ep.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            epInProgress
                                                ? '${prog!.percent}% watched'
                                                : '${ep.format} • ${ep.sizeFormatted}',
                                            style: TextStyle(
                                              color: epInProgress ? TVTheme.emerald : TVTheme.textSecondary,
                                              fontSize: 10.5,
                                              fontWeight: epInProgress ? FontWeight.bold : FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // Bottom Progress Fill Line
                                  if (epInProgress)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        height: 4,
                                        color: Colors.white.withValues(alpha: 0.2),
                                        child: FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: (prog?.fraction ?? 0.0).clamp(0.0, 1.0),
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [TVTheme.emerald, Color(0xFF34D399)],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ));
                          },
                        ),
                      ),

                      // Generous TV Overscan Buffer for episode cards
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
