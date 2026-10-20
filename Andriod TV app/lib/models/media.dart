class ServerInfo {
  final String status;
  final int port;
  final List<String> ips;
  final String primaryUrl;
  final int mediaCount;
  final int moviesCount;
  final int seriesCount;

  ServerInfo({
    required this.status,
    required this.port,
    required this.ips,
    required this.primaryUrl,
    required this.mediaCount,
    required this.moviesCount,
    required this.seriesCount,
  });

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    return ServerInfo(
      status: json['status'] ?? 'unknown',
      port: json['port'] ?? 5050,
      ips: (json['ips'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      primaryUrl: json['primaryUrl'] ?? '',
      mediaCount: json['mediaCount'] ?? 0,
      moviesCount: json['moviesCount'] ?? 0,
      seriesCount: json['seriesCount'] ?? 0,
    );
  }
}

class MovieItem {
  final String id;
  final String title;
  final String cleanTitle;
  final String fileName;
  final String relativePath;
  final int sizeBytes;
  final String sizeFormatted;
  final String format;
  final String? year;
  final bool hasSubtitles;
  final bool is4K;
  final bool isDolbyVision;
  final bool isHDR;

  MovieItem({
    required this.id,
    required this.title,
    required this.cleanTitle,
    required this.fileName,
    required this.relativePath,
    required this.sizeBytes,
    required this.sizeFormatted,
    required this.format,
    this.year,
    required this.hasSubtitles,
    this.is4K = false,
    this.isDolbyVision = false,
    this.isHDR = false,
  });

  factory MovieItem.fromJson(Map<String, dynamic> json) {
    return MovieItem(
      id: json['id'] ?? '',
      title: json['cleanTitle'] ?? json['title'] ?? 'Untitled Movie',
      cleanTitle: json['cleanTitle'] ?? json['title'] ?? 'Untitled Movie',
      fileName: json['fileName'] ?? '',
      relativePath: json['relativePath'] ?? '',
      sizeBytes: json['sizeBytes'] ?? 0,
      sizeFormatted: json['sizeFormatted'] ?? '',
      format: (json['format'] ?? 'MKV').toString().toUpperCase(),
      year: json['year']?.toString(),
      hasSubtitles: json['hasSubtitles'] == true,
      is4K: json['is4K'] == true || (json['fileName'] ?? '').toString().toLowerCase().contains('2160p'),
      isDolbyVision: json['isDolbyVision'] == true || (json['fileName'] ?? '').toString().toLowerCase().contains('.dv.'),
      isHDR: json['isHDR'] == true || (json['fileName'] ?? '').toString().toLowerCase().contains('hdr'),
    );
  }

  String streamUrl(String baseUrl) => '$baseUrl/api/stream/$id';
  String compatUrl(String baseUrl) => '$baseUrl/api/stream/$id?compat=1';
  String transcodeUrl(String baseUrl) => '$baseUrl/api/transcode/$id';
  String thumbnailUrl(String baseUrl) => '$baseUrl/api/thumbnail/$id';
}

class EpisodeItem {
  final String id;
  final String title;
  final int seasonNumber;
  final int episodeNumber;
  final String fileName;
  final int sizeBytes;
  final String sizeFormatted;
  final String format;
  final String seriesTitle;
  final bool is4K;
  final bool isDolbyVision;
  final bool isHDR;

  EpisodeItem({
    required this.id,
    required this.title,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.fileName,
    required this.sizeBytes,
    required this.sizeFormatted,
    required this.format,
    required this.seriesTitle,
    this.is4K = false,
    this.isDolbyVision = false,
    this.isHDR = false,
  });

  factory EpisodeItem.fromJson(Map<String, dynamic> json, String seriesTitle) {
    return EpisodeItem(
      id: json['id'] ?? '',
      title: json['title'] ?? json['cleanTitle'] ?? 'Episode ${json['episode'] ?? 1}',
      seasonNumber: json['season'] ?? 1,
      episodeNumber: json['episode'] ?? 1,
      fileName: json['fileName'] ?? '',
      sizeBytes: json['sizeBytes'] ?? 0,
      sizeFormatted: json['sizeFormatted'] ?? '',
      format: (json['format'] ?? 'MKV').toString().toUpperCase(),
      seriesTitle: seriesTitle,
      is4K: json['is4K'] == true || (json['fileName'] ?? '').toString().toLowerCase().contains('2160p'),
      isDolbyVision: json['isDolbyVision'] == true || (json['fileName'] ?? '').toString().toLowerCase().contains('.dv.'),
      isHDR: json['isHDR'] == true || (json['fileName'] ?? '').toString().toLowerCase().contains('hdr'),
    );
  }

  String streamUrl(String baseUrl) => '$baseUrl/api/stream/$id';
  String compatUrl(String baseUrl) => '$baseUrl/api/stream/$id?compat=1';
  String transcodeUrl(String baseUrl) => '$baseUrl/api/transcode/$id';
  String thumbnailUrl(String baseUrl) => '$baseUrl/api/thumbnail/$id';
}

class SeriesItem {
  final String id;
  final String title;
  final String relPath;
  final int seasonsCount;
  final int episodesCount;
  final List<EpisodeItem> episodes;

  SeriesItem({
    required this.id,
    required this.title,
    required this.relPath,
    required this.seasonsCount,
    required this.episodesCount,
    required this.episodes,
  });

  factory SeriesItem.fromJson(Map<String, dynamic> json) {
    final title = json['title'] ?? 'Untitled Series';
    final rawEpisodes = (json['episodes'] as List<dynamic>?) ?? [];
    final eps = rawEpisodes
        .map((e) => EpisodeItem.fromJson(e as Map<String, dynamic>, title))
        .toList();

    return SeriesItem(
      id: json['id'] ?? '',
      title: title,
      relPath: json['relPath'] ?? '',
      seasonsCount: json['seasonsCount'] ?? 1,
      episodesCount: json['episodesCount'] ?? eps.length,
      episodes: eps,
    );
  }

  String firstEpisodeThumbnail(String baseUrl) {
    if (episodes.isNotEmpty) {
      return episodes.first.thumbnailUrl(baseUrl);
    }
    return '';
  }
}

class WatchProgress {
  final String id;
  final int posSeconds;
  final int durSeconds;
  final bool isWatched;
  final String title;
  final String seriesTitle;
  final int updatedAt;

  WatchProgress({
    required this.id,
    required this.posSeconds,
    required this.durSeconds,
    required this.isWatched,
    this.title = '',
    this.seriesTitle = '',
    required this.updatedAt,
  });

  double get fraction =>
      durSeconds > 0 ? (posSeconds / durSeconds).clamp(0.0, 1.0) : 0.0;

  int get percent => (fraction * 100).round();

  bool get inProgress => posSeconds > 15 && !isWatched && fraction < 0.92;

  String formatTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  factory WatchProgress.fromJson(Map<String, dynamic> json) {
    return WatchProgress(
      id: json['id']?.toString() ?? '',
      posSeconds: json['pos'] is int
          ? json['pos']
          : (json['pos'] as num?)?.toInt() ?? 0,
      durSeconds: json['dur'] is int
          ? json['dur']
          : (json['dur'] as num?)?.toInt() ?? 0,
      isWatched: json['watched'] == true,
      title: json['title']?.toString() ?? '',
      seriesTitle: json['seriesTitle']?.toString() ?? '',
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt']
          : (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pos': posSeconds,
        'dur': durSeconds,
        'watched': isWatched,
        'title': title,
        'seriesTitle': seriesTitle,
        'updatedAt': updatedAt,
      };
}

