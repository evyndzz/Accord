import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/song.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  Function(String songId)? _onNotificationTap;

  static const String _channelId = 'accord_cloud_sync_channel';
  static const String _channelName = 'Accord Cloud Updates';
  static const String _channelDesc = 'Notifikasi lagu baru dan sinkronisasi cloud Accord';

  Future<void> init({Function(String songId)? onNotificationTap}) async {
    if (_isInitialized) return;
    _onNotificationTap = onNotificationTap;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      linux: linuxSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _onNotificationTap?.call(payload);
        }
      },
    );

    // Create high importance Android notification channel
    if (!kIsWeb && Platform.isAndroid) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
            playSound: true,
          ),
        );
        // Request notification permission for Android 13+
        await androidPlugin.requestNotificationsPermission();
      }
    }

    _isInitialized = true;
  }

  /// Check if the app was launched by tapping on a notification
  Future<String?> getInitialNotificationPayload() async {
    try {
      final details = await _notifications.getNotificationAppLaunchDetails();
      if (details != null && details.didNotificationLaunchApp) {
        return details.notificationResponse?.payload;
      }
    } catch (e) {
      debugPrint('getInitialNotificationPayload notice: $e');
    }
    return null;
  }

  /// Show a system OS notification when a new song is detected from Google Drive
  Future<void> showNewSongNotification(Song song) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'Lagu Baru: ${song.title}',
        styleInformation: BigTextStyleInformation(
          'Lagu "${song.title}" (${song.artist}) berhasil disinkronkan dari Google Drive. Ketuk notifikasi ini untuk melengkapi chord & lirik!',
          contentTitle: '🎵 Lagu Baru Terdeteksi!',
          summaryText: 'Google Drive Cloud',
        ),
      );

      const linuxDetails = LinuxNotificationDetails(
        urgency: LinuxNotificationUrgency.normal,
      );

      final notifDetails = NotificationDetails(
        android: androidDetails,
        linux: linuxDetails,
      );

      // Notification ID generated from song ID hashCode
      final notifId = song.id.hashCode & 0x7FFFFFFF;

      await _notifications.show(
        id: notifId,
        title: '🎵 Lagu Baru: ${song.title}',
        body: '"${song.title} - ${song.artist}" siap diedit chord & liriknya. Ketuk untuk buka editor.',
        notificationDetails: notifDetails,
        payload: song.id,
      );
    } catch (e) {
      debugPrint('Error showing new song notification: $e');
    }
  }
}
