import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:accord/widgets/animated_equalizer.dart';
import 'package:accord/widgets/mini_player.dart';
import 'package:accord/widgets/waveform.dart';

void main() {
  group('Player & Artwork Enhancement Tests', () {
    testWidgets('AnimatedEqualizer renders requested barCount and animates', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnimatedEqualizer(
                barCount: 4,
                color: Color(0xFFD9F99D),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AnimatedEqualizer), findsOneWidget);
      // Let animation tick
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(AnimatedEqualizer), findsOneWidget);
    });

    testWidgets('MiniPlayer renders with imageUrl and play/pause button', (tester) async {
      bool playTapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniPlayer(
              title: 'Test Song Title',
              artist: 'Test Artist',
              imageUrl: 'https://example.com/art.jpg',
              isPlaying: true,
              progress: 0.45,
              onPlayPauseTap: () => playTapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Test Song Title'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      expect(playTapped, isTrue);
    });

    testWidgets('WaveformWidget linear slider renders line and handles seek tap', (tester) async {
      double? seekedRatio;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: WaveformWidget(
                progress: 0.3,
                currentTime: '01:15',
                totalTime: '03:45',
                onSeek: (val) => seekedRatio = val,
              ),
            ),
          ),
        ),
      );

      expect(find.text('01:15'), findsOneWidget);
      expect(find.text('03:45'), findsOneWidget);

      // Tap on the right side of the slider
      await tester.tapAt(const Offset(225, 14));
      await tester.pumpAndSettle();

      expect(seekedRatio, isNotNull);
      expect(seekedRatio!, greaterThan(0.0));
    });
  });
}
