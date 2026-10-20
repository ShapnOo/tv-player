import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';

import '../models/media.dart';
import '../services/api_service.dart';
import '../theme/tv_theme.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_focus_button.dart';
import 'player_screen.dart';
import 'series_screen.dart';
import 'settings_dialog.dart';

class TVHomeScreen extends StatefulWidget {
  final ApiService apiService;

  const TVHomeScreen({super.key, required this.apiService});

  @override
  State<TVHomeScreen> createState() => _TVHomeScreenState();
}

class _TVHomeScreenState extends State<TVHomeScreen> {
  String _selectedFilter = 'all'; // 'all', 'movies', 'series'

  // Currently focused item from carousel
  MovieItem? _focusedMovie;
  SeriesItem? _focusedSeries;

  // Netflix-style Ambient Banner Looping Video
  MovieItem? _bannerMovie;
  VideoPlayerController? _bannerController;
  bool _isBannerInitialized = false;

  DateTime? _lastBackPressTime;

  @override
  void initState() {
    super.initState();
    widget.apiService.addListener(_onServiceUpdate);
    _checkAndStartBanner();
  }

  @override
  void dispose() {
    widget.apiService.removeListener(_onServiceUpdate);
    _bannerController?.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      _checkAndStartBanner();
      setState(() {});
    }
  }

  void _checkAndStartBanner() {
    if (_bannerMovie == null && widget.apiService.movies.isNotEmpty) {
      final randIdx = Random().nextInt(widget.apiService.movies.length);
      final randomMovie = widget.apiService.movies[randIdx];
      _bannerMovie = randomMovie;
      _focusedMovie = randomMovie;
      _initBannerVideo(randomMovie);
    }
  }

  Future<void> _initBannerVideo(MovieItem movie) async {
    try {
      final oldController = _bannerController;
      _bannerController = null;
      if (mounted) setState(() => _isBannerInitialized = false);
      if (oldController != null) {
        await oldController.dispose();
      }

      final url = movie.isDolbyVision
          ? movie.compatUrl(widget.apiService.baseUrl)
          : movie.streamUrl(widget.apiService.baseUrl);

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );

      await controller.initialize();
      await controller.setVolume(0.0); // Ambient Muted Loop
      await controller.setLooping(true);
      await controller.play();

      // Soft seek past studio logo asynchronously if duration permits
      if (controller.value.duration.inSeconds > 50) {
        controller.seekTo(const Duration(seconds: 20)).catchError((_) {});
      }

      if (mounted) {
        setState(() {
          _bannerController = controller;
          _isBannerInitialized = true;
        });
      } else {
        await controller.dispose();
      }
    } catch (e) {
      debugPrint('[HomeBanner] Video preview notice (poster fallback): $e');
      if (mounted) {
        setState(() => _isBannerInitialized = false);
      }
    }
  }

  Future<void> _openMovie(MovieItem movie, {int resumePos = 0}) async {
    _bannerController?.pause();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TVPlayerScreen(
          videoUrl: movie.streamUrl(widget.apiService.baseUrl),
          compatUrl: movie.compatUrl(widget.apiService.baseUrl),
          transcodeUrl: movie.transcodeUrl(widget.apiService.baseUrl),
          title: movie.title,
          subtitle:
              '${movie.format} • ${movie.sizeFormatted} • ${movie.isDolbyVision ? 'Dolby Vision • ' : ''}4K UHD',
          isDolbyVision: movie.isDolbyVision,
          mediaId: movie.id,
          apiService: widget.apiService,
          initialPositionSeconds: resumePos,
        ),
      ),
    );

    if (mounted && _isBannerInitialized && _bannerController != null) {
      _bannerController!.play();
    }
  }

  Future<void> _openMovieCompat(MovieItem movie) async {
    _bannerController?.pause();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TVPlayerScreen(
          videoUrl: movie.compatUrl(widget.apiService.baseUrl),
          compatUrl: movie.compatUrl(widget.apiService.baseUrl),
          transcodeUrl: movie.transcodeUrl(widget.apiService.baseUrl),
          title: movie.title,
          subtitle:
              '${movie.format} • ${movie.sizeFormatted} • Universal 4K Remux',
          isDolbyVision: movie.isDolbyVision,
          mediaId: movie.id,
          apiService: widget.apiService,
        ),
      ),
    );

    if (mounted && _isBannerInitialized && _bannerController != null) {
      _bannerController!.play();
    }
  }

  Future<void> _openEpisode(EpisodeItem ep) async {
    _bannerController?.pause();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TVPlayerScreen(
          videoUrl: ep.streamUrl(widget.apiService.baseUrl),
          compatUrl: ep.compatUrl(widget.apiService.baseUrl),
          transcodeUrl: ep.transcodeUrl(widget.apiService.baseUrl),
          title: '${ep.seriesTitle} - ${ep.title}',
          subtitle:
              'Season ${ep.seasonNumber} Episode ${ep.episodeNumber} • ${ep.sizeFormatted}',
          isDolbyVision: ep.isDolbyVision,
          mediaId: ep.id,
          apiService: widget.apiService,
        ),
      ),
    );

    if (mounted && _isBannerInitialized && _bannerController != null) {
      _bannerController!.play();
    }
  }

  Future<void> _openSeries(SeriesItem series) async {
    _bannerController?.pause();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TVSeriesScreen(
          series: series,
          baseUrl: widget.apiService.baseUrl,
          apiService: widget.apiService,
        ),
      ),
    );

    if (mounted && _isBannerInitialized && _bannerController != null) {
      _bannerController!.play();
    }
  }

  void _openSettings() {
    showDialog(
      context: context,
      builder: (_) => TVSettingsDialog(apiService: widget.apiService),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.apiService;

    if (api.isLoading && api.movies.isEmpty && api.series.isEmpty) {
      return _buildLoadingScreen();
    }

    if (!api.isConnected && api.movies.isEmpty && api.series.isEmpty) {
      return _buildOfflineScreen();
    }

    // Determine what to display in the Hero Showcase
    final heroMovie = _bannerMovie ??
        (_focusedMovie ?? (api.movies.isNotEmpty ? api.movies.first : null));
    final currentSeries = _focusedSeries;

    final isMovieHero = currentSeries == null && heroMovie != null;
    final heroTitle = isMovieHero
        ? heroMovie.title
        : (currentSeries != null ? currentSeries.title : 'Shapno Media Stream');

    final heroSubtitle = isMovieHero
        ? '${heroMovie.format}  •  ${heroMovie.sizeFormatted}  •  4K UHD'
        : (currentSeries != null
            ? '${currentSeries.episodesCount} Episodes  •  ${currentSeries.seasonsCount} Season(s)'
            : 'Local Streaming Server');

    final heroThumbnail = isMovieHero
        ? heroMovie.thumbnailUrl(api.baseUrl)
        : (currentSeries != null
            ? currentSeries.firstEpisodeThumbnail(api.baseUrl)
            : '');

    final continueMovies = api.continueWatchingMovies;
    final continueEps = api.continueWatchingEpisodes;
    final hasContinueWatching =
        continueMovies.isNotEmpty || continueEps.isNotEmpty;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: TVTheme.emerald, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'Press Back again to exit Shapno TV',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              backgroundColor: TVTheme.surfaceElevated,
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: TVTheme.emerald.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
            ),
          );
          return;
        }
        SystemNavigator.pop();
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
                  // Live Video Trailer
                  if (_isBannerInitialized && _bannerController != null && isMovieHero)
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
                  else if (heroThumbnail.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: heroThumbnail,
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

                  // B. Bottom Fade: Smoothly melts the video into the background where carousels begin
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

                  // C. Top Subtle Shadow: Keeps top navigation bar legible without dimming the video
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

            // 2. Main Page Content (Header + Hero Billboard Info + Carousels)
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Navigation Bar (Refined, Compact, Classy)
                    _buildHeaderBar(api),

                    const SizedBox(height: 28),

                    // Netflix Hero Billboard (Seamless, Borderless, Classy Typography)
                    _buildHeroBillboard(
                      title: heroTitle,
                      subtitle: heroSubtitle,
                      isMovie: isMovieHero,
                      currentMovie: heroMovie,
                      currentSeries: currentSeries,
                      api: api,
                    ),

                    const SizedBox(height: 38),

                    // Continue Watching Section (Netflix Style)
                    if (hasContinueWatching && _selectedFilter != 'series') ...[
                      _buildSectionHeader(
                        title: 'Continue Watching',
                        badgeText: 'RESUME',
                        badgeColor: TVTheme.emerald,
                      ),
                      const SizedBox(height: 12),
                      _buildContinueWatchingCarousel(api, continueMovies, continueEps),
                      const SizedBox(height: 26),
                    ],

                    // Movies Horizontal Carousel
                    if (_selectedFilter != 'series' && api.movies.isNotEmpty) ...[
                      _buildSectionHeader(
                        title: 'Movies',
                        badgeText: '${api.movies.length} AVAILABLE',
                        badgeColor: TVTheme.crimson,
                      ),
                      const SizedBox(height: 12),
                      _buildMoviesCarousel(api),
                      const SizedBox(height: 26),
                    ],

                    // TV Series Horizontal Carousel
                    if (_selectedFilter != 'movies' && api.series.isNotEmpty) ...[
                      _buildSectionHeader(
                        title: 'TV Series',
                        badgeText: '${api.series.length} SHOWS',
                        badgeColor: TVTheme.cyan,
                      ),
                      const SizedBox(height: 12),
                      _buildSeriesCarousel(api),
                      const SizedBox(height: 26),
                    ],

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar(ApiService api) {
    return Row(
      children: [
        // Brand: SHAPNO with emerald pulse
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: api.isConnected ? TVTheme.emerald : TVTheme.crimson,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (api.isConnected ? TVTheme.emerald : TVTheme.crimson)
                        .withValues(alpha: 0.7),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'SHAPNO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '4K TV',
                style: TextStyle(
                  color: TVTheme.emerald,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(width: 28),

        // Navigation filter buttons (Compact Netflix-style Pills)
        TVFocusButton(
          label: 'All (${api.movies.length + api.series.length})',
          isPrimary: _selectedFilter == 'all',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5.5),
          fontSize: 12,
          borderRadius: 16,
          onTap: () => setState(() => _selectedFilter = 'all'),
        ),
        const SizedBox(width: 8),
        TVFocusButton(
          label: 'Movies (${api.movies.length})',
          isPrimary: _selectedFilter == 'movies',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5.5),
          fontSize: 12,
          borderRadius: 16,
          onTap: () => setState(() => _selectedFilter = 'movies'),
        ),
        const SizedBox(width: 8),
        TVFocusButton(
          label: 'Series (${api.series.length})',
          isPrimary: _selectedFilter == 'series',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5.5),
          fontSize: 12,
          borderRadius: 16,
          onTap: () => setState(() => _selectedFilter = 'series'),
        ),

        const Spacer(),

        // Connected IP pill with quick click to settings
        TVFocusButton(
          icon: const Icon(Icons.wifi, size: 14),
          label: api.isConnected
              ? api.baseUrl.replaceAll('http://', '')
              : 'Offline',
          isPrimary: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          fontSize: 11.5,
          borderRadius: 16,
          onTap: _openSettings,
        ),
        const SizedBox(width: 8),

        // Refresh button
        TVFocusButton(
          icon: const Icon(Icons.refresh, size: 14),
          label: 'Sync',
          isPrimary: false,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          fontSize: 11.5,
          borderRadius: 16,
          onTap: () => widget.apiService.checkAndLoad(),
        ),
      ],
    );
  }

  // Borderless, Expansive Netflix Billboard Stage
  Widget _buildHeroBillboard({
    required String title,
    required String subtitle,
    required bool isMovie,
    MovieItem? currentMovie,
    SeriesItem? currentSeries,
    required ApiService api,
  }) {
    // Check watch progress of billboard movie
    final prog = (isMovie && currentMovie != null)
        ? api.getProgress(currentMovie.id)
        : null;

    final hasProgress = prog != null && prog.inProgress;
    final isWatched = prog != null && prog.isWatched;

    return SizedBox(
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Classy Minimalist Tagline Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isMovie
                      ? TVTheme.crimson.withValues(alpha: 0.25)
                      : TVTheme.cyan.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isMovie ? TVTheme.crimson : TVTheme.cyan,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  isMovie ? 'FEATURED 4K' : 'FEATURED SERIES',
                  style: TextStyle(
                    color: isMovie ? TVTheme.crimson : TVTheme.cyan,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (isWatched) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: TVTheme.emerald.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: TVTheme.emerald, width: 1.0),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, color: TVTheme.emerald, size: 11),
                      SizedBox(width: 3),
                      Text(
                        'WATCHED',
                        style: TextStyle(
                          color: TVTheme.emerald,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (hasProgress) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: TVTheme.emerald.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: TVTheme.emerald, width: 1.0),
                  ),
                  child: Text(
                    '${prog.percent}% WATCHED',
                    style: const TextStyle(
                      color: TVTheme.emerald,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
              if (isMovie && currentMovie != null && currentMovie.isDolbyVision) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'VISION',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: TVTheme.cyan.withValues(alpha: 0.5)),
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
            ],
          ),

          const SizedBox(height: 10),

          // 2. Movie / Series Title (Large, Bold Netflix Hero Typography)
          Text(
            title,
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

          // 3. Classy Inline Metadata
          Text(
            subtitle,
            style: TextStyle(
              color: TVTheme.textSecondary.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w500,
              shadows: const [
                Shadow(
                  color: Colors.black,
                  blurRadius: 8,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 4. Refined Compact Action Buttons (Netflix Style)
          Wrap(
            spacing: 9,
            runSpacing: 8,
            children: [
              if (isMovie && currentMovie != null) ...[
                if (hasProgress) ...[
                  TVFocusButton(
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: 'Resume (${prog.formatTime(prog.posSeconds)})',
                    isPrimary: true,
                    autoFocus: true,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    fontSize: 12.5,
                    borderRadius: 8,
                    onTap: () => _openMovie(currentMovie, resumePos: prog.posSeconds),
                  ),
                  TVFocusButton(
                    icon: const Icon(Icons.replay_rounded, size: 15),
                    label: 'Start Over',
                    isPrimary: false,
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    fontSize: 12,
                    borderRadius: 8,
                    onTap: () => _openMovie(currentMovie, resumePos: 1),
                  ),
                ] else ...[
                  TVFocusButton(
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: isWatched ? 'Watch Again' : 'Play',
                    isPrimary: true,
                    autoFocus: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    fontSize: 12.5,
                    borderRadius: 8,
                    onTap: () => _openMovie(currentMovie),
                  ),
                ],
                if (currentMovie.isDolbyVision)
                  TVFocusButton(
                    icon: const Icon(Icons.bolt, size: 15),
                    label: 'Universal 4K',
                    isPrimary: false,
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    fontSize: 12,
                    borderRadius: 8,
                    onTap: () => _openMovieCompat(currentMovie),
                  ),
              ] else if (!isMovie && currentSeries != null)
                TVFocusButton(
                  icon: const Icon(Icons.playlist_play_rounded, size: 18),
                  label: 'Browse Episodes',
                  isPrimary: true,
                  autoFocus: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  fontSize: 12.5,
                  borderRadius: 8,
                  onTap: () => _openSeries(currentSeries),
                ),
              TVFocusButton(
                icon: const Icon(Icons.info_outline_rounded, size: 15),
                label: 'More Info',
                isPrimary: false,
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                fontSize: 12,
                borderRadius: 8,
                onTap: _openSettings,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String badgeText,
    required Color badgeColor,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
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
            color: badgeColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: badgeColor.withValues(alpha: 0.45)),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              color: badgeColor,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }

  // Continue Watching Carousel (Netflix Style with Live Progress Bar)
  Widget _buildContinueWatchingCarousel(
    ApiService api,
    List<MovieItem> movies,
    List<EpisodeItem> episodes,
  ) {
    final totalCount = movies.length + episodes.length;

    return SizedBox(
      height: 200,
      child: ListView.separated(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: totalCount,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final isMovieItem = index < movies.length;
          final movie = isMovieItem ? movies[index] : null;
          final ep = !isMovieItem ? episodes[index - movies.length] : null;

          final id = isMovieItem ? movie!.id : ep!.id;
          final title = isMovieItem ? movie!.title : '${ep!.seriesTitle} - S${ep.seasonNumber}:E${ep.episodeNumber}';
          final thumb = isMovieItem
              ? movie!.thumbnailUrl(api.baseUrl)
              : ep!.thumbnailUrl(api.baseUrl);

          final prog = api.getProgress(id);
          final fraction = prog?.fraction ?? 0.0;
          final percent = prog?.percent ?? 0;
          final posStr = prog != null ? prog.formatTime(prog.posSeconds) : '';

          return TVFocusCard(
            width: 240,
            height: 145,
            onFocusChange: (hasF) {
              if (hasF && isMovieItem) {
                setState(() {
                  _focusedMovie = movie;
                  _focusedSeries = null;
                });
              }
            },
            onTap: () {
              if (isMovieItem) {
                _openMovie(movie!, resumePos: prog?.posSeconds ?? 0);
              } else {
                _openEpisode(ep!);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: thumb,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => Container(color: TVTheme.surfaceElevated),
                ),

                // Top Resume Tag
                Positioned(
                  top: 7,
                  left: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: TVTheme.emerald),
                    ),
                    child: Text(
                      'RESUME AT $posStr',
                      style: const TextStyle(
                        color: TVTheme.emerald,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),

                // Bottom Gradient & Title
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
                          title,
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
                          '$percent% completed',
                          style: const TextStyle(
                            color: TVTheme.emerald,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Netflix Bottom Progress Bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 4,
                    color: Colors.white.withValues(alpha: 0.25),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: fraction.clamp(0.0, 1.0),
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
          );
        },
      ),
    );
  }

  Widget _buildMoviesCarousel(ApiService api) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: api.movies.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final movie = api.movies[index];
          final prog = api.getProgress(movie.id);
          final isWatched = prog?.isWatched ?? false;
          final inProgress = prog?.inProgress ?? false;

          return TVFocusCard(
            width: 240,
            height: 145,
            onFocusChange: (hasF) {
              if (hasF) {
                setState(() {
                  _focusedMovie = movie;
                  _focusedSeries = null;
                });
              }
            },
            onTap: () => _openMovie(movie),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: movie.thumbnailUrl(api.baseUrl),
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: TVTheme.surfaceElevated,
                    child: const Center(
                      child: Icon(
                        Icons.movie_outlined,
                        color: TVTheme.textMuted,
                        size: 32,
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: TVTheme.surfaceElevated,
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: TVTheme.emerald,
                        size: 38,
                      ),
                    ),
                  ),
                ),

                // Top Left Badges
                Positioned(
                  top: 7,
                  left: 7,
                  child: Row(
                    children: [
                      if (movie.isDolbyVision)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'VISION',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      if (movie.is4K)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: TVTheme.cyan.withValues(alpha: 0.6),
                            ),
                          ),
                          child: const Text(
                            '4K UHD',
                            style: TextStyle(
                              color: TVTheme.cyan,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Top Right: WATCHED Badge
                if (isWatched)
                  Positioned(
                    top: 7,
                    right: 7,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
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
                          Icon(Icons.check_rounded, color: Colors.black, size: 10),
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

                // Bottom Gradient Title
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
                          movie.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              inProgress
                                  ? '${prog!.percent}% watched'
                                  : movie.sizeFormatted,
                              style: TextStyle(
                                color: inProgress ? TVTheme.emerald : TVTheme.textSecondary,
                                fontSize: 10.5,
                                fontWeight: inProgress ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: TVTheme.crimson.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                movie.format,
                                style: const TextStyle(
                                  color: TVTheme.crimson,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Netflix Progress Fill Bar at Bottom
                if (inProgress)
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
          );
        },
      ),
    );
  }

  Widget _buildSeriesCarousel(ApiService api) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        scrollDirection: Axis.horizontal,
        itemCount: api.series.length,
        separatorBuilder: (_, _) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final series = api.series[index];
          return TVFocusCard(
            width: 240,
            height: 145,
            onFocusChange: (hasF) {
              if (hasF) {
                setState(() {
                  _focusedSeries = series;
                  _focusedMovie = null;
                });
              }
            },
            onTap: () => _openSeries(series),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: series.firstEpisodeThumbnail(api.baseUrl),
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    color: TVTheme.surfaceElevated,
                    child: const Center(
                      child: Icon(Icons.tv, color: TVTheme.textMuted, size: 32),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: TVTheme.surfaceElevated,
                    child: const Center(
                      child: Icon(
                        Icons.subscriptions,
                        color: TVTheme.cyan,
                        size: 38,
                      ),
                    ),
                  ),
                ),

                // Top Badge: Shows series folder tag
                Positioned(
                  top: 7,
                  left: 7,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: TVTheme.cyan.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      '${series.episodesCount} EPISODES',
                      style: const TextStyle(
                        color: TVTheme.cyan,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                // Bottom Gradient Title
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
                          series.title,
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
                          '${series.seasonsCount} Season(s) • ${series.episodesCount} Ep',
                          style: const TextStyle(
                            color: TVTheme.textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return const Scaffold(
      backgroundColor: TVTheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: TVTheme.emerald),
            SizedBox(height: 20),
            Text(
              'Connecting to Shapno Streaming Server...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineScreen() {
    return Scaffold(
      backgroundColor: TVTheme.background,
      body: Center(
        child: Container(
          width: 580,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: TVTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: TVTheme.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                color: TVTheme.crimson,
                size: 44,
              ),
              const SizedBox(height: 12),
              const Text(
                'Cannot Connect to Laptop',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Current Target: ${widget.apiService.baseUrl}',
                style: const TextStyle(
                  color: TVTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
              if (widget.apiService.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: TVTheme.crimson.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: TVTheme.crimson.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    widget.apiService.errorMessage,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  TVFocusButton(
                    label: 'Retry Connection (10.81.100.62)',
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    isPrimary: true,
                    autoFocus: true,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    fontSize: 13,
                    onTap: () async {
                      await widget.apiService.setBaseUrl('http://10.81.100.62:5050');
                    },
                  ),
                  TVFocusButton(
                    label: 'Configure IP',
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    isPrimary: false,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    fontSize: 12.5,
                    onTap: _openSettings,
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
