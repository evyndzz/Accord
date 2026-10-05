import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/song.dart';
import 'audio_cache_service.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();

  AudioPlayer get player => _player;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<bool> get playingStream => _player.playingStream;

  bool get isPlaying => _player.playing;
  bool get hasLoadedAudio => _player.audioSource != null;
  Duration get currentPosition => _player.position;
  Duration? get currentDuration => _player.duration;
  Duration get duration => _player.duration ?? Duration.zero;

  /// Play a local audio file or an online audio URL with background notification support
  Future<bool> playSong(Song song) async {
    try {
      MediaItem? mediaItem;
      try {
        mediaItem = MediaItem(
          id: song.id,
          album: 'Accord Music',
          title: song.title,
          artist: song.artist,
          artUri: song.albumArtUrl != null && song.albumArtUrl!.isNotEmpty
              ? Uri.tryParse(song.albumArtUrl!)
              : null,
        );
      } catch (e) {
        debugPrint('Error creating MediaItem tag: $e');
      }

      // 1. Direct local file path (local disk, downloaded, or cached) -> HIGHEST PRIORITY (0ms latency!)
      final localFilePath = song.filePath;
      if (localFilePath != null && localFilePath.isNotEmpty) {
        final file = File(localFilePath);
        if (file.existsSync() && file.lengthSync() > 10000) {
          debugPrint('playSong: Playing directly from local disk (0ms delay): $localFilePath');
          try {
            final audioSource = mediaItem != null
                ? AudioSource.file(localFilePath, tag: mediaItem)
                : AudioSource.file(localFilePath);
            await _player.setAudioSource(audioSource);
            await _player.play();
            return true;
          } catch (e) {
            debugPrint('playSong AudioSource.file failed: $e. Trying Uri.file...');
            try {
              final uriSource = AudioSource.uri(Uri.file(localFilePath), tag: mediaItem);
              await _player.setAudioSource(uriSource);
              await _player.play();
              return true;
            } catch (e2) {
              debugPrint('playSong Uri.file failed: $e2');
            }
          }
        }
      }

      // 2. Check if AudioCacheService has already cached this track ID
      if (song.id.isNotEmpty) {
        final cachedPath = await AudioCacheService.instance.getCachedPathIfExists(song.id);
        if (cachedPath != null && File(cachedPath).existsSync()) {
          debugPrint('playSong: Playing from cached storage (0ms delay): $cachedPath');
          try {
            final audioSource = mediaItem != null
                ? AudioSource.file(cachedPath, tag: mediaItem)
                : AudioSource.file(cachedPath);
            await _player.setAudioSource(audioSource);
            await _player.play();
            return true;
          } catch (e) {
            debugPrint('playSong cached AudioSource.file failed: $e');
          }
        }
      }

      // 3. Online stream URL (HTTP / HTTPS / content://)
      if (song.streamUrl != null && song.streamUrl!.isNotEmpty) {
        try {
          final uri = Uri.parse(song.streamUrl!);

          // For remote HTTP/HTTPS on mobile, use LockCachingAudioSource so downloaded chunks are retained on disk.
          // On desktop (Linux/Windows/macOS), media_kit plays standard AudioSource.uri directly with high performance.
          if (!kIsWeb && Platform.isAndroid && (uri.scheme == 'http' || uri.scheme == 'https')) {
            try {
              final cachePath = await AudioCacheService.instance.getCacheFilePath(song.id);
              final cacheFile = File(cachePath);
              // ignore: experimental_member_use
              final cachingSource = LockCachingAudioSource(
                uri,
                cacheFile: cacheFile,
                tag: mediaItem,
              );
              await _player.setAudioSource(cachingSource);
              await _player.play();
              return true;
            } catch (eCache) {
              debugPrint('LockCachingAudioSource failed ($eCache), falling back to standard uri source...');
            }
          }

          // On desktop (Linux/Windows/macOS), use direct AudioSource.uri without headers.
          // In just_audio, passing `headers` spawns an internal local HTTP proxy on 127.0.0.1,
          // which fails with libmpv. Direct AudioSource.uri allows libmpv to stream natively.
          if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
            final audioSource = mediaItem != null
                ? AudioSource.uri(uri, tag: mediaItem)
                : AudioSource.uri(uri);
            await _player.setAudioSource(audioSource);
            await _player.play();
            return true;
          }

          // Fallback to standard AudioSource.uri with mobile browser User-Agent
          final audioSource = mediaItem != null
              ? AudioSource.uri(
                  uri,
                  headers: const {
                    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Chrome/120.0.0.0 Mobile Safari/537.36',
                  },
                  tag: mediaItem,
                )
              : AudioSource.uri(
                  uri,
                  headers: const {
                    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) Chrome/120.0.0.0 Mobile Safari/537.36',
                  },
                );
          await _player.setAudioSource(audioSource);
          await _player.play();
          return true;
        } catch (e1) {
          debugPrint('playSong streamUrl failed: $e1. Trying plain uri fallback...');
          try {
            final uri = Uri.parse(song.streamUrl!);
            await _player.setAudioSource(AudioSource.uri(uri));
            await _player.play();
            return true;
          } catch (e1b) {
            debugPrint('playSong plain streamUrl failed: $e1b');
          }
        }
      }

      debugPrint('No playable audio source for: ${song.title}');
      return false;
    } catch (e) {
      debugPrint('Fatal error in playSong: $e');
      return false;
    }
  }

  Future<void> play() async {
    if (_player.audioSource != null) {
      await _player.play();
    }
  }

  Future<void> pause() async {
    if (_player.audioSource != null && _player.playing) {
      await _player.pause();
    }
  }

  Future<void> togglePlay() async {
    if (_player.audioSource != null) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
    }
  }

  Future<void> seek(Duration position) async {
    if (_player.audioSource != null) {
      await _player.seek(position);
    }
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
  }

  Future<void> setLoopMode(LoopMode loopMode) async {
    await _player.setLoopMode(loopMode);
  }

  Future<void> stop() async {
    await _player.stop();
  }

  void dispose() {
    _player.dispose();
  }
}
