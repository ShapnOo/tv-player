import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/media.dart';

class ApiService extends ChangeNotifier {
  static const String _defaultIp = '10.81.100.62';
  static const int _defaultPort = 5050;

  // Candidate hosts for auto-discovery
  static const List<String> _candidateHosts = [
    '10.81.100.62', // Mac Wi-Fi IP for real Hisense TV
    '10.0.2.2',     // Android Emulator host loopback
    '198.19.254.2', // Secondary network interface
    'localhost',    // Desktop / Web
    '127.0.0.1',    // Direct loopback / ADB reverse
  ];

  String _baseUrl = 'http://$_defaultIp:$_defaultPort';
  bool _isConnected = false;
  bool _isLoading = false;
  String _errorMessage = '';

  ServerInfo? _serverInfo;
  List<MovieItem> _movies = [];
  List<SeriesItem> _series = [];
  final Map<String, WatchProgress> _progressMap = {};

  String get baseUrl => _baseUrl;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  ServerInfo? get serverInfo => _serverInfo;
  List<MovieItem> get movies => _movies;
  List<SeriesItem> get series => _series;
  Map<String, WatchProgress> get progressMap => _progressMap;

  WatchProgress? getProgress(String id) => _progressMap[id];
  bool isWatched(String id) => _progressMap[id]?.isWatched ?? false;

  List<MovieItem> get continueWatchingMovies {
    final list = _movies.where((m) => getProgress(m.id)?.inProgress == true).toList();
    list.sort((a, b) {
      final pA = getProgress(a.id)?.updatedAt ?? 0;
      final pB = getProgress(b.id)?.updatedAt ?? 0;
      return pB.compareTo(pA);
    });
    return list;
  }

  List<EpisodeItem> get continueWatchingEpisodes {
    final List<EpisodeItem> allEps = [];
    for (final s in _series) {
      allEps.addAll(s.episodes.where((e) => getProgress(e.id)?.inProgress == true));
    }
    allEps.sort((a, b) {
      final pA = getProgress(a.id)?.updatedAt ?? 0;
      final pB = getProgress(b.id)?.updatedAt ?? 0;
      return pB.compareTo(pA);
    });
    return allEps;
  }

  ApiService() {
    _init();
  }

  Future<File?> _getLocalConfigFile() async {
    try {
      final appDir = Directory('/data/user/0/com.shapno.tv.shapno_tv/files');
      if (!appDir.existsSync()) {
        appDir.createSync(recursive: true);
      }
      return File('${appDir.path}/saved_server.txt');
    } catch (_) {
      try {
        final tmpDir = Directory.systemTemp;
        return File('${tmpDir.path}/shapno_saved_server.txt');
      } catch (_) {}
    }
    return null;
  }

  Future<void> _init() async {
    try {
      final file = await _getLocalConfigFile();
      if (file != null && await file.exists()) {
        final saved = (await file.readAsString()).trim();
        if (saved.isNotEmpty) {
          _baseUrl = saved;
        }
      }
    } catch (e) {
      debugPrint('[ApiService] Error reading saved config: $e');
    }
    await checkAndLoad();
  }

  Future<void> setBaseUrl(String newUrl) async {
    String cleanUrl = newUrl.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      cleanUrl = 'http://$cleanUrl';
    }
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    _baseUrl = cleanUrl;

    try {
      final file = await _getLocalConfigFile();
      if (file != null) {
        await file.writeAsString(_baseUrl);
      }
    } catch (e) {
      debugPrint('[ApiService] Error saving config: $e');
    }

    await checkAndLoad();
  }

  Future<String?> _probeUrl(String url) async {
    try {
      debugPrint('[ApiService] Probing server at $url/api/server-info ...');
      final uri = Uri.parse('$url/api/server-info');
      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        debugPrint('[ApiService] Successfully connected to $url!');
        return url;
      }
    } catch (e) {
      debugPrint('[ApiService] Probe failed for $url: $e');
    }
    return null;
  }

  Future<bool> checkAndLoad() async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // 1. First probe current _baseUrl with 4s timeout
      String? activeUrl = await _probeUrl(_baseUrl);

      // 2. If current fails, try candidate hosts in parallel
      if (activeUrl == null) {
        debugPrint('[ApiService] Primary probe failed. Scanning candidate hosts...');
        final probeFutures = _candidateHosts.map((host) => _probeUrl('http://$host:$_defaultPort'));
        final results = await Future.wait(probeFutures);
        for (final res in results) {
          if (res != null) {
            activeUrl = res;
            break;
          }
        }
      }

      // 3. If still null, wait 1.5s and retry default IP once (Wi-Fi wake-up buffer on TV)
      if (activeUrl == null) {
        await Future.delayed(const Duration(milliseconds: 1500));
        activeUrl = await _probeUrl('http://$_defaultIp:$_defaultPort');
      }

      // If an active URL was discovered or confirmed
      if (activeUrl != null) {
        _baseUrl = activeUrl;
        try {
          final file = await _getLocalConfigFile();
          if (file != null) {
            await file.writeAsString(_baseUrl);
          }
        } catch (_) {}

        // Fetch Server Info
        final infoResp = await http.get(Uri.parse('$_baseUrl/api/server-info')).timeout(const Duration(seconds: 5));
        if (infoResp.statusCode == 200) {
          final infoData = jsonDecode(infoResp.body);
          _serverInfo = ServerInfo.fromJson(infoData);
        }

        // Fetch Media Catalog
        final mediaResp = await http.get(Uri.parse('$_baseUrl/api/media')).timeout(const Duration(seconds: 6));
        if (mediaResp.statusCode == 200) {
          final mediaData = jsonDecode(mediaResp.body);
          final rawMovies = (mediaData['movies'] as List<dynamic>?) ?? [];
          final rawSeries = (mediaData['series'] as List<dynamic>?) ?? [];

          _movies = rawMovies.map((m) => MovieItem.fromJson(m)).toList();
          _series = rawSeries.map((s) => SeriesItem.fromJson(s)).toList();
          _isConnected = true;
          _errorMessage = '';

          // Fetch Watch Progress / History from Server & Local Cache
          await fetchProgress();
        }
      } else {
        _isConnected = false;
        _errorMessage = 'Could not reach server at $_baseUrl. Please verify laptop Wi-Fi is connected to the same network.';
      }
    } catch (e) {
      _isConnected = false;
      _errorMessage = 'Connection error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    return _isConnected;
  }

  Future<File?> _getLocalProgressFile() async {
    try {
      final appDir = Directory('/data/user/0/com.shapno.tv.shapno_tv/files');
      if (!appDir.existsSync()) {
        appDir.createSync(recursive: true);
      }
      return File('${appDir.path}/saved_progress.json');
    } catch (_) {
      try {
        final tmpDir = Directory.systemTemp;
        return File('${tmpDir.path}/shapno_saved_progress.json');
      } catch (_) {}
    }
    return null;
  }

  Future<void> fetchProgress() async {
    // 1. Load local cache first for instant offline response
    try {
      final file = await _getLocalProgressFile();
      if (file != null && await file.exists()) {
        final raw = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(raw);
        data.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            _progressMap[k] = WatchProgress.fromJson(v);
          }
        });
      }
    } catch (e) {
      debugPrint('[ApiService] Local progress load notice: $e');
    }

    // 2. Fetch fresh watch progress from server
    if (!_isConnected) return;
    try {
      final url = Uri.parse('$_baseUrl/api/progress');
      final resp = await http.get(url).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(resp.body);
        data.forEach((k, v) {
          if (v is Map<String, dynamic>) {
            _progressMap[k] = WatchProgress.fromJson(v);
          }
        });

        // Update local file cache
        final file = await _getLocalProgressFile();
        if (file != null) {
          final Map<String, dynamic> toSave = {};
          _progressMap.forEach((k, v) => toSave[k] = v.toJson());
          await file.writeAsString(jsonEncode(toSave));
        }
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[ApiService] Server progress sync notice: $e');
    }
  }

  Future<void> saveProgress(
    String id,
    int pos,
    int dur, {
    String title = '',
    String seriesTitle = '',
  }) async {
    if (id.isEmpty) return;
    final isWatched = dur > 0 ? (pos / dur >= 0.9) : false;
    final prog = WatchProgress(
      id: id,
      posSeconds: pos,
      durSeconds: dur,
      isWatched: isWatched,
      title: title,
      seriesTitle: seriesTitle,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    _progressMap[id] = prog;
    notifyListeners();

    // 1. Asynchronously send to server
    try {
      if (_isConnected) {
        final url = Uri.parse('$_baseUrl/api/progress/$id');
        http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'pos': pos,
                'dur': dur,
                'title': title,
                'seriesTitle': seriesTitle,
              }),
            )
            .timeout(const Duration(seconds: 3))
            .catchError((_) => http.Response('', 500));
      }
    } catch (_) {}

    // 2. Update local disk file
    try {
      final file = await _getLocalProgressFile();
      if (file != null) {
        final Map<String, dynamic> toSave = {};
        _progressMap.forEach((k, v) => toSave[k] = v.toJson());
        await file.writeAsString(jsonEncode(toSave));
      }
    } catch (_) {}
  }

  Future<SeriesItem?> fetchSeriesDetails(String id) async {
    try {
      final url = Uri.parse('$_baseUrl/api/series/$id');
      final resp = await http.get(url).timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return SeriesItem.fromJson(data);
      }
    } catch (e) {
      debugPrint('Error fetching series details: $e');
    }
    return null;
  }
}
