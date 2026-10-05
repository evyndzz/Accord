import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import 'providers/cosmic_theme_provider.dart';
import 'providers/library_provider.dart';
import 'providers/player_provider.dart';
import 'providers/profile_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/song_editor_screen.dart';
import 'services/accidental_preference.dart';
import 'services/audio_player_service.dart';
import 'services/google_drive_audio_service.dart';
import 'services/google_drive_sync_service.dart';
import 'services/local_database.dart';
import 'services/notification_service.dart';
import 'utils/app_lifecycle_helper.dart';
import 'widgets/glass_nav_bar.dart';
import 'widgets/mini_player.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pre-compile liquid glass shaders so first-frame glass renders cleanly
  await LiquidGlassShaders.ensureLoaded()
      .catchError((_) {}); // graceful fallback on unsupported platforms

  // Desktop audio engine initialization (Linux/Windows/macOS)
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    try {
      String? libmpvPath;
      if (Platform.isLinux) {
        final exeDir = File(Platform.resolvedExecutable).parent.path;
        final candidateDirs = [
          '$exeDir/lib',
          '/home/vin/Coding/Accord/accord/linux/libs',
          'linux/libs',
        ];

        for (final dir in candidateDirs) {
          final mpvFile = File('$dir/libmpv.so');
          final mpvFile2 = File('$dir/libmpv.so.2');
          if (mpvFile.existsSync() || mpvFile2.existsSync()) {
            final targetPath = mpvFile.existsSync() ? mpvFile.path : mpvFile2.path;
            final deps = [
              'libXpresent.so.1',
              'libva-wayland.so.2',
              'libsndio.so.7',
              'libsixel.so.1',
              'liblua5.2.so.0',
              'libmujs.so.3',
            ];
            for (final dep in deps) {
              final depFile = File('$dir/$dep');
              if (depFile.existsSync()) {
                try {
                  DynamicLibrary.open(depFile.path);
                } catch (_) {}
              }
            }
            libmpvPath = targetPath;
            break;
          }
        }
      }

      JustAudioMediaKit.ensureInitialized(
        linux: true,
        windows: true,
        macOS: true,
        libmpv: libmpvPath,
      );
    } catch (e) {
      debugPrint('JustAudioMediaKit init notice: $e');
    }
  }

  // Mobile background audio notification
  if (!kIsWeb && Platform.isAndroid) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.example.accord.audio',
        androidNotificationChannelName: 'Accord Music Playback',
        androidNotificationOngoing: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      );
    } catch (e) {
      debugPrint('JustAudioBackground init notice: $e');
    }
  }

  // Initialize offline SQLite DB
  final localDb = LocalDatabase.instance;
  await localDb.database;

  final audioPlayerService = AudioPlayerService();

  try {
    await NotificationService.instance.init(
      onNotificationTap: (String songId) async {
        final song = await LocalDatabase.instance.getSong(songId);
        if (song != null && navigatorKey.currentState != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (_) => SongEditorScreen(existingSong: song),
            ),
          );
        }
      },
    );
  } catch (e) {
    debugPrint('NotificationService init notice: $e');
  }

  runApp(AccordApp(localDb: localDb, audioPlayerService: audioPlayerService));
}

class AccordApp extends StatelessWidget {
  final LocalDatabase localDb;
  final AudioPlayerService audioPlayerService;

  const AccordApp({
    super.key,
    required this.localDb,
    required this.audioPlayerService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AudioPlayerService>.value(value: audioPlayerService),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
        ChangeNotifierProvider(create: (_) => GoogleDriveAudioService()),
        ChangeNotifierProvider(create: (_) => GoogleDriveSyncService()),
        ChangeNotifierProvider(
          create: (ctx) => PlayerProvider(
            audioPlayerService: ctx.read<AudioPlayerService>(),
            localDb: localDb,
            driveSyncService: ctx.read<GoogleDriveSyncService>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => LibraryProvider(localDb: localDb),
        ),
        ChangeNotifierProvider(create: (_) => CosmicThemeProvider()),
        ChangeNotifierProvider(create: (_) => AccidentalPreferenceService()),
      ],
      child: MaterialApp(
        title: 'Accord',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.black,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD9F99D),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const AccordHome(),
      ),
    );
  }
}

class AccordHome extends StatefulWidget {
  const AccordHome({super.key});

  @override
  State<AccordHome> createState() => _AccordHomeState();
}

class _AccordHomeState extends State<AccordHome>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  late final AnimationController _miniPlayerAnimController;
  late final Animation<Offset> _miniPlayerSlideAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _miniPlayerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _miniPlayerSlideAnim = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.0, -0.65),
    ).animate(
      CurvedAnimation(
        parent: _miniPlayerAnimController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final driveAudio = context.read<GoogleDriveAudioService>();
        final library = context.read<LibraryProvider>();
        final driveSync = context.read<GoogleDriveSyncService>();

        driveSync.onSyncSuccess = () {
          if (mounted) {
            driveAudio.loadSongs();
            library.refreshLocalSongs();
          }
        };

        // Auto load Google Drive songs from local database
        driveAudio.loadSongs();
        library.refreshLocalSongs();

        // Trigger background cloud sync and reload upon finish
        driveSync.syncVault(silent: true).then((ok) {
          if (ok && mounted) {
            driveAudio.loadSongs();
            library.refreshLocalSongs();
          }
        });
        // Check if launched via notification click
        NotificationService.instance.getInitialNotificationPayload().then((payload) async {
          if (payload != null && mounted) {
            final song = await LocalDatabase.instance.getSong(payload);
            if (song != null && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => SongEditorScreen(existingSong: song)),
              );
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _miniPlayerAnimController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Auto-sync quietly from Google Drive whenever the app is brought to foreground
      final syncService = context.read<GoogleDriveSyncService>();
      if (syncService.isConfigured) {
        syncService.syncVault(silent: true).then((_) {
          if (mounted) {
            context.read<GoogleDriveAudioService>().loadSongs();
            context.read<LibraryProvider>().refreshLocalSongs();
          }
        });
      }
    }
  }

  Future<void> _navigateToPlayer() async {
    // 1. Miniplayer popup animates upwards
    await _miniPlayerAnimController.forward();
    if (!mounted) return;

    // 2. Followed by PlayerScreen sliding up smoothly from bottom
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PlayerScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slideAnim = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 1.0),
              end: Offset.zero,
            ).animate(slideAnim),
            child: child,
          );
        },
      ),
    );

    // 3. When player screen is closed (slid down), miniplayer popup returns to initial docked position
    if (mounted) {
      _miniPlayerAnimController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();

    final pages = [
      DashboardScreen(onNavigateToPlayer: _navigateToPlayer),
      SearchScreen(onNavigateToPlayer: _navigateToPlayer),
      LibraryScreen(onNavigateToPlayer: _navigateToPlayer),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // If not on Home tab, back button navigates back to Home tab
        if (_selectedIndex != 0) {
          setState(() => _selectedIndex = 0);
        } else {
          // If on Home tab on Android, move app to background without destroying it
          if (!kIsWeb && Platform.isAndroid) {
            AppLifecycleHelper.moveToBackground();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Base layer: scrollable pages
            IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
            // Bottom vignette gradient overlay behind navbar (kept low and subtle)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 75,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.25),
                        Colors.black.withValues(alpha: 0.65),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.40, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            // Floating Mini Player (if song playing)
            if (player.currentSong != null)
              Positioned(
                bottom: 106, // Raised slightly higher above the glass nav bar
                left: 0,
                right: 0,
                child: SlideTransition(
                  position: _miniPlayerSlideAnim,
                  child: MiniPlayer(
                    title: player.currentSong!.title,
                    artist: player.currentSong!.artist,
                    imageUrl: player.currentSong!.albumArtUrl,
                    isPlaying: player.isPlaying,
                    progress: player.progress,
                    gradientColors: player.currentSong!.gradientColors,
                    onTap: _navigateToPlayer,
                    onDragUp: _navigateToPlayer,
                    onPlayPauseTap: player.togglePlayPause,
                    isFavorite: context.watch<LibraryProvider>().isFavorite(player.currentSong!.id),
                    onFavoriteTap: () {
                      context.read<LibraryProvider>().toggleFavorite(player.currentSong!.id);
                    },
                  ),
                ),
              ),
            // Floating Glass Nav Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: GlassNavBar(
                selectedIndex: _selectedIndex,
                onItemTapped: (i) => setState(() => _selectedIndex = i),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
