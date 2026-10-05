import 'package:flutter/services.dart';

class AppLifecycleHelper {
  static const MethodChannel _channel = MethodChannel('com.example.accord/app_lifecycle');

  /// Moves the current Android activity to the background without destroying it.
  /// The app process and audio playback will continue in the background.
  static Future<void> moveToBackground() async {
    try {
      await _channel.invokeMethod('moveToBackground');
    } catch (_) {
      // Fallback
      await SystemNavigator.pop();
    }
  }
}
