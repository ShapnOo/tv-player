import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/media.dart';
import '../theme/tv_theme.dart';
import '../widgets/tv_focus_card.dart';
import '../widgets/tv_focus_button.dart';
import 'player_screen.dart';

class TVSeriesScreen extends StatefulWidget {
  final SeriesItem series;
  final String baseUrl;

  const TVSeriesScreen({
    super.key,
    required this.series,
    required this.baseUrl,
  });

  @override
  State<TVSeriesScreen> createState() => _TVSeriesScreenState();
}

class _TVSeriesScreenState extends State<TVSeriesScreen> {
  late EpisodeItem _focusedEpisode;

  @override
  void initState() {
    super.initState();
    _focusedEpisode = widget.series.episodes.isNotEmpty
        ? widget.series.episodes.first
        : EpisodeItem(
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

  void _playEpisode(EpisodeItem ep) {
    if (ep.id.isEmpty) return;
    Navigator.push(
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final epCount = widget.series.episodes.length;

    return Scaffold(
      backgroundColor: TVTheme.background,
      body: Stack(
        children: [
          // Background Backdrop Ambient Glow
          Positioned.fill(
            child: widget.series.episodes.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: _focusedEpisode.thumbnailUrl(widget.baseUrl),
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox(),
                    color: Colors.black.withValues(alpha: 0.82),
                    colorBlendMode: BlendMode.darken,
                  )
                : const SizedBox(),
          ),

          // Gradient Overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    TVTheme.background.withValues(alpha: 0.92),
                    TVTheme.background,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Back Button & Breadcrumb
                  Row(
                    children: [
                      TVFocusButton(
                        icon: const Icon(Icons.arrow_back),
                        label: 'Back',
                        isPrimary: false,
                        onTap: () => Navigator.pop(context),
                      ),
                      const SizedBox(width: 20),
                      Text(
                        'Series  /  ${widget.series.title}',
                        style: const TextStyle(
                          color: TVTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Hero Billboard for Series
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 4K & Season Badges
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: TVTheme.emerald.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: TVTheme.emerald.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'TV SERIES',
                                    style: TextStyle(
                                      color: TVTheme.emerald,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  '$epCount Episodes  •  ${widget.series.seasonsCount} Season(s)',
                                  style: const TextStyle(
                                    color: TVTheme.textSecondary,
                                    fontSize: 14,
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
                                fontSize: 36,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Selected: ${_focusedEpisode.title} (${_focusedEpisode.sizeFormatted})',
                              style: const TextStyle(
                                color: TVTheme.textSecondary,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 18),
                            // Play Focused Episode Button
                            if (widget.series.episodes.isNotEmpty)
                              TVFocusButton(
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  size: 24,
                                ),
                                label:
                                    'Play Episode ${_focusedEpisode.episodeNumber}',
                                isPrimary: true,
                                autoFocus: true,
                                onTap: () => _playEpisode(_focusedEpisode),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 36),

                  // Episodes Header
                  const Text(
                    'Episodes',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Horizontal Episode Cards Carousel (TV Remote D-Pad friendly)
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.series.episodes.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 20),
                      itemBuilder: (context, index) {
                        final ep = widget.series.episodes[index];

                        return TVFocusCard(
                          width: 280,
                          height: 185,
                          onFocusChange: (hasF) {
                            if (hasF) {
                              setState(() {
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
                                      size: 38,
                                    ),
                                  ),
                                ),
                                errorWidget: (_, _, _) => Container(
                                  color: TVTheme.surfaceElevated,
                                  child: const Center(
                                    child: Icon(
                                      Icons.play_circle_outline,
                                      color: TVTheme.textMuted,
                                      size: 38,
                                    ),
                                  ),
                                ),
                              ),

                              // Bottom Title Gradient
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
                                        'Episode ${ep.episodeNumber}',
                                        style: const TextStyle(
                                          color: TVTheme.emerald,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        ep.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        ep.sizeFormatted,
                                        style: const TextStyle(
                                          color: TVTheme.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // Top Episode Pill
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
                                      color: Colors.white.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Text(
                                    'EP ${ep.episodeNumber.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
}
