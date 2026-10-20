import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

  // Currently highlighted item in the hero billboard
  MovieItem? _focusedMovie;
  SeriesItem? _focusedSeries;

  @override
  void initState() {
    super.initState();
    widget.apiService.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    widget.apiService.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) {
      if (_focusedMovie == null && widget.apiService.movies.isNotEmpty) {
        setState(() {
          _focusedMovie = widget.apiService.movies.first;
        });
      }
      setState(() {});
    }
  }

  void _openMovie(MovieItem movie) {
    Navigator.push(
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
        ),
      ),
    );
  }

  void _openSeries(SeriesItem series) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TVSeriesScreen(series: series, baseUrl: widget.apiService.baseUrl),
      ),
    );
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

    // Determine what to show in the Hero Billboard
    final currentMovie =
        _focusedMovie ?? (api.movies.isNotEmpty ? api.movies.first : null);
    final currentSeries = _focusedSeries;

    final isMovieHero = currentSeries == null && currentMovie != null;
    final heroTitle = isMovieHero
        ? currentMovie.title
        : (currentSeries != null ? currentSeries.title : 'Shapno Media Stream');

    final heroSubtitle = isMovieHero
        ? '${currentMovie.format}  •  ${currentMovie.sizeFormatted}  •  4K UHD'
        : (currentSeries != null
              ? '${currentSeries.episodesCount} Episodes  •  ${currentSeries.seasonsCount} Season(s)'
              : 'Local Streaming Server');

    final heroThumbnail = isMovieHero
        ? currentMovie.thumbnailUrl(api.baseUrl)
        : (currentSeries != null
              ? currentSeries.firstEpisodeThumbnail(api.baseUrl)
              : '');

    return Scaffold(
      backgroundColor: TVTheme.background,
      body: Stack(
        children: [
          // Ambient Background Backdrop
          if (heroThumbnail.isNotEmpty)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: heroThumbnail,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox(),
                color: Colors.black.withValues(alpha: 0.85),
                colorBlendMode: BlendMode.darken,
              ),
            ),

          // Gradient overlay for cinematic readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    TVTheme.background.withValues(alpha: 0.88),
                    TVTheme.background,
                  ],
                  stops: const [0.0, 0.4, 0.95],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Navigation Bar
                  _buildHeaderBar(api),

                  const SizedBox(height: 18),

                  // Hero Featured Billboard (Top 38% of TV screen)
                  _buildHeroBillboard(
                    title: heroTitle,
                    subtitle: heroSubtitle,
                    isMovie: isMovieHero,
                    currentMovie: currentMovie,
                    currentSeries: currentSeries,
                  ),

                  const SizedBox(height: 24),

                  // Scrollable Content Rows (Movies & Series)
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Movies Row
                          if (_selectedFilter != 'series' &&
                              api.movies.isNotEmpty) ...[
                            _buildSectionHeader(
                              title: 'Movies',
                              badgeText: '${api.movies.length} AVAILABLE',
                              badgeColor: TVTheme.crimson,
                            ),
                            const SizedBox(height: 12),
                            _buildMoviesCarousel(api),
                            const SizedBox(height: 28),
                          ],

                          // Series Row
                          if (_selectedFilter != 'movies' &&
                              api.series.isNotEmpty) ...[
                            _buildSectionHeader(
                              title: 'TV Series',
                              badgeText: '${api.series.length} SHOWS',
                              badgeColor: TVTheme.cyan,
                            ),
                            const SizedBox(height: 12),
                            _buildSeriesCarousel(api),
                            const SizedBox(height: 24),
                          ],
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
    );
  }

  Widget _buildHeaderBar(ApiService api) {
    return Row(
      children: [
        // Brand: Shapno with pulse emerald dot
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: api.isConnected ? TVTheme.emerald : TVTheme.crimson,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (api.isConnected ? TVTheme.emerald : TVTheme.crimson)
                        .withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'SHAPNO',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '4K TV',
                style: TextStyle(
                  color: TVTheme.emerald,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(width: 36),

        // Navigation filter tabs
        _buildNavFilterChip(
          'All',
          'all',
          api.movies.length + api.series.length,
        ),
        const SizedBox(width: 8),
        _buildNavFilterChip('Movies', 'movies', api.movies.length),
        const SizedBox(width: 8),
        _buildNavFilterChip('Series', 'series', api.series.length),

        const Spacer(),

        // Connected IP pill with quick click to settings
        TVFocusButton(
          icon: const Icon(Icons.wifi, size: 16),
          label: api.isConnected
              ? api.baseUrl.replaceAll('http://', '')
              : 'Offline • Click to Configure',
          isPrimary: false,
          onTap: _openSettings,
        ),
        const SizedBox(width: 10),

        // Refresh button
        TVFocusButton(
          icon: const Icon(Icons.refresh, size: 16),
          label: 'Sync',
          isPrimary: false,
          onTap: () => widget.apiService.checkAndLoad(),
        ),
      ],
    );
  }

  Widget _buildNavFilterChip(String label, String key, int count) {
    final isSelected = _selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? TVTheme.emerald : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : TVTheme.textSecondary,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? TVTheme.emerald : TVTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openMovieCompat(MovieItem movie) {
    Navigator.push(
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
        ),
      ),
    );
  }

  Widget _buildHeroBillboard({
    required String title,
    required String subtitle,
    required bool isMovie,
    MovieItem? currentMovie,
    SeriesItem? currentSeries,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      decoration: BoxDecoration(
        color: TVTheme.surfaceGlass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isMovie
                            ? TVTheme.crimson.withValues(alpha: 0.25)
                            : TVTheme.cyan.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isMovie ? TVTheme.crimson : TVTheme.cyan,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        isMovie ? 'FEATURED MOVIE' : 'FEATURED SERIES',
                        style: TextStyle(
                          color: isMovie ? TVTheme.crimson : TVTheme.cyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (isMovie && currentMovie != null && currentMovie.isDolbyVision) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'VISION • HDR',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: TVTheme.cyan.withValues(alpha: 0.5)),
                      ),
                      child: const Text(
                        '4K UHD',
                        style: TextStyle(
                          color: TVTheme.cyan,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: TVTheme.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (isMovie && currentMovie != null) ...[
                      TVFocusButton(
                        icon: const Icon(Icons.play_arrow_rounded, size: 24),
                        label: 'Watch Movie',
                        isPrimary: true,
                        autoFocus: true,
                        onTap: () => _openMovie(currentMovie),
                      ),
                      const SizedBox(width: 12),
                      if (currentMovie.isDolbyVision)
                        TVFocusButton(
                          icon: const Icon(Icons.bolt, size: 20),
                          label: 'Universal 4K',
                          isPrimary: false,
                          onTap: () => _openMovieCompat(currentMovie),
                        ),
                    ] else if (!isMovie && currentSeries != null)
                      TVFocusButton(
                        icon: const Icon(Icons.playlist_play_rounded, size: 24),
                        label: 'Browse Episodes',
                        isPrimary: true,
                        autoFocus: true,
                        onTap: () => _openSeries(currentSeries),
                      ),
                    const SizedBox(width: 12),
                    TVFocusButton(
                      icon: const Icon(Icons.info_outline, size: 18),
                      label: 'Server Info',
                      isPrimary: false,
                      onTap: _openSettings,
                    ),
                  ],
                ),
              ],
            ),
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
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
          ),
          child: Text(
            badgeText,
            style: TextStyle(
              color: badgeColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMoviesCarousel(ApiService api) {
    return SizedBox(
      height: 205,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: api.movies.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final movie = api.movies[index];
          return TVFocusCard(
            width: 275,
            height: 200,
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
                        size: 38,
                      ),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: TVTheme.surfaceElevated,
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: TVTheme.emerald,
                        size: 44,
                      ),
                    ),
                  ),
                ),

                // Top Badges
                Positioned(
                  top: 10,
                  left: 10,
                  child: Row(
                    children: [
                      if (movie.isDolbyVision)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 6),
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
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      if (movie.is4K)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: TVTheme.cyan.withValues(alpha: 0.6)),
                          ),
                          child: const Text(
                            '4K UHD',
                            style: TextStyle(
                              color: TVTheme.cyan,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Bottom Gradient
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.96),
                          Colors.black.withValues(alpha: 0.65),
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
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Text(
                              movie.sizeFormatted,
                              style: const TextStyle(
                                color: TVTheme.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: TVTheme.crimson.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                movie.format,
                                style: const TextStyle(
                                  color: TVTheme.crimson,
                                  fontSize: 10.5,
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
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSeriesCarousel(ApiService api) {
    return SizedBox(
      height: 205,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: api.series.length,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, index) {
          final series = api.series[index];
          return TVFocusCard(
            width: 275,
            height: 200,
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
                      child: Icon(Icons.tv, color: TVTheme.textMuted, size: 38),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    color: TVTheme.surfaceElevated,
                    child: const Center(
                      child: Icon(
                        Icons.subscriptions,
                        color: TVTheme.cyan,
                        size: 44,
                      ),
                    ),
                  ),
                ),

                // Top Badge: Shows series folder tag
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
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
                        fontSize: 10.5,
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
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.96),
                          Colors.black.withValues(alpha: 0.65),
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
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${series.seasonsCount} Season(s) • ${series.episodesCount} Ep',
                          style: const TextStyle(
                            color: TVTheme.textSecondary,
                            fontSize: 12,
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
          width: 600,
          padding: const EdgeInsets.all(36),
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
                size: 48,
              ),
              const SizedBox(height: 14),
              const Text(
                'Cannot Connect to Laptop',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
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
              const SizedBox(height: 22),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  TVFocusButton(
                    label: 'Retry Connection (10.81.100.62)',
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    isPrimary: true,
                    autoFocus: true,
                    onTap: () async {
                      await widget.apiService.setBaseUrl('http://10.81.100.62:5050');
                    },
                  ),
                  TVFocusButton(
                    label: 'Configure IP',
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                    isPrimary: false,
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
