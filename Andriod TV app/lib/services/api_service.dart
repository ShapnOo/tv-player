import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media.dart';

class ApiService extends ChangeNotifier {
  static const String _defaultIp = '10.81.100.62';
  static const int _defaultPort = 5050;
  static const String _prefKeyBaseUrl = 'saved_base_url';

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

  String get baseUrl => _baseUrl;
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  ServerInfo? get serverInfo => _serverInfo;
  List<MovieItem> get movies => _movies;
  List<SeriesItem> get series => _series;

  ApiService() {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKeyBaseUrl);
    if (saved != null && saved.isNotEmpty) {
      _baseUrl = saved;
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyBaseUrl, _baseUrl);
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
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefKeyBaseUrl, _baseUrl);

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
