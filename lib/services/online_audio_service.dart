import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class ResolvedAudioTrack {
  final String streamUrl;
  final int durationMs;
  final String? artworkUrl;
  final bool isFullSong;

  const ResolvedAudioTrack({
    required this.streamUrl,
    required this.durationMs,
    this.artworkUrl,
    this.isFullSong = true,
  });
}

class OnlineAudioService {
  static final Map<String, ResolvedAudioTrack> _cache = {};
  static final Map<String, Future<ResolvedAudioTrack?>> _inFlight = {};
  static YoutubeExplode? _yt;

  static YoutubeExplode get _ytClient => _yt ??= YoutubeExplode();

  /// Background prefetch to warm up stream resolution
  static void prefetchAudio(String title, String artist) {
    resolveAudio(title, artist).catchError((_) => null);
  }

  /// Fast stream check to verify URL does not return 403 Forbidden
  static Future<bool> _verifyStreamPlayable(String url) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(milliseconds: 1500);
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(milliseconds: 1500));
      req.headers.set('Range', 'bytes=0-100');
      req.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 14) Chrome/120.0.0.0 Mobile Safari/537.36');
      final res = await req.close().timeout(const Duration(milliseconds: 1500));
      final ok = res.statusCode == 200 || res.statusCode == 206;
      client.close(force: true);
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Resolve a FULL SONG audio stream (Opus/M4A 128-160kbps) via YouTube Explode.
  /// If YouTube stream returns 403 or blocks, falls back cleanly to Apple Music/iTunes AAC stream.
  static Future<ResolvedAudioTrack?> resolveAudio(String title, String artist) async {
    final queryKey = '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
    if (_cache.containsKey(queryKey)) {
      return _cache[queryKey];
    }
    if (_inFlight.containsKey(queryKey)) {
      return _inFlight[queryKey]!;
    }

    final future = _doResolveAudio(title, artist, queryKey);
    _inFlight[queryKey] = future;
    try {
      final res = await future;
      return res;
    } finally {
      _inFlight.remove(queryKey);
    }
  }

  static Future<ResolvedAudioTrack?> _doResolveAudio(String title, String artist, String queryKey) async {
    try {
      final query = '$title $artist audio';
      final searchResults = await _ytClient.search
          .search(query)
          .timeout(const Duration(seconds: 4));

      if (searchResults.isNotEmpty) {
        // Filter: pick video with sensible song length (< 12 minutes)
        final video = searchResults.firstWhere(
          (v) => (v.duration?.inMinutes ?? 0) < 12,
          orElse: () => searchResults.first,
        );

        final manifest = await _ytClient.videos.streamsClient
            .getManifest(video.id)
            .timeout(const Duration(seconds: 4));

        final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
        final streamUrl = audioStreamInfo.url.toString();

        // Fast check: verify URL is actually playable and not returning 403
        final isPlayable = await _verifyStreamPlayable(streamUrl);
        if (isPlayable) {
          final durationMs = (video.duration?.inMilliseconds ?? 0) > 0
              ? video.duration!.inMilliseconds
              : 210000;

          final track = ResolvedAudioTrack(
            streamUrl: streamUrl,
            durationMs: durationMs,
            artworkUrl: video.thumbnails.highResUrl,
            isFullSong: true,
          );

          _cache[queryKey] = track;
          return track;
        } else {
          debugPrint('YouTube stream URL for "$title" failed playable check (403/throttled). Instant fallback to Apple CDN...');
        }
      }
    } catch (e) {
      debugPrint('YouTube Explode search error for "$title": $e');
    }

    // 2. Fallback: iTunes search preview
    try {
      final term = Uri.encodeComponent('$title $artist');
      final url = Uri.parse('https://itunes.apple.com/search?term=$term&media=music&limit=1');
      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first as Map<String, dynamic>;
          final previewUrl = first['previewUrl'] as String?;
          final artworkUrl = first['artworkUrl100'] as String?;
          final trackTimeMillis = first['trackTimeMillis'] as int? ?? 30000;

          if (previewUrl != null && previewUrl.isNotEmpty) {
            final track = ResolvedAudioTrack(
              streamUrl: previewUrl,
              durationMs: trackTimeMillis,
              artworkUrl: artworkUrl?.replaceAll('100x100bb', '600x600bb'),
              isFullSong: false,
            );
            _cache[queryKey] = track;
            return track;
          }
        }
      }
    } catch (e) {
      debugPrint('iTunes preview fallback error for "$title": $e');
    }

    return null;
  }

  /// Convenience method for stream URL only
  static Future<String?> resolveStreamUrl(String title, String artist) async {
    final track = await resolveAudio(title, artist);
    return track?.streamUrl;
  }

  /// Resolve artwork if not already present
  static String? getCachedArtwork(String title, String artist) {
    final queryKey = '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
    return _cache[queryKey]?.artworkUrl;
  }
}
