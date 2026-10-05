import 'package:accord/providers/profile_provider.dart';
import 'package:accord/widgets/glass_nav_bar.dart';
import 'package:accord/widgets/liquid_glass_container.dart';
import 'package:accord/widgets/planet_orbit_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_profile_name': 'Test Musician',
      'user_profile_avatar_id': 'cosmic_astronaut',
    });
  });

  group('Universe Liquid Glass & Navigation Tests', () {
    test('ProfileProvider loads and updates profile data', () async {
      final profile = ProfileProvider();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(profile.name, equals('Test Musician'));
      expect(profile.avatarId, equals('cosmic_astronaut'));

      await profile.updateProfile(
        newName: 'Star Lord',
        newAvatarId: 'pixel_planet',
        newCustomImagePath: '/dummy/path/avatar.jpg',
      );

      expect(profile.name, equals('Star Lord'));
      expect(profile.avatarId, equals('pixel_planet'));
      expect(profile.customImagePath, equals('/dummy/path/avatar.jpg'));
      expect(profile.currentAvatarOption.name, equals('Pixel Planet'));
    });

    testWidgets('GlassNavBar renders 3 items and uses BackdropFilter for liquid glass blur', (tester) async {
      int tappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: GlassNavBar(
              selectedIndex: 0,
              onItemTapped: (idx) {
                tappedIndex = idx;
              },
            ),
          ),
        ),
      );

      // Verify BackdropFilter is used for iOS liquid glass effect
      expect(find.byType(BackdropFilter), findsWidgets);

      // Verify Home is active with label
      expect(find.text('Home'), findsOneWidget);
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.folder_copy_rounded), findsOneWidget);
      // Dedicated player icon removed from nav bar
      expect(find.byIcon(Icons.music_note_rounded), findsNothing);

      // Tap Search
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pumpAndSettle();
      expect(tappedIndex, equals(1));

      // Tap Library
      await tester.tap(find.byIcon(Icons.folder_copy_rounded));
      await tester.pumpAndSettle();
      expect(tappedIndex, equals(2));
    });

    testWidgets('LiquidGlassContainer renders child with backdrop filter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LiquidGlassContainer(
              child: Text('Frosted Content'),
            ),
          ),
        ),
      );

      expect(find.text('Frosted Content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('PlanetOrbitWidget renders custom paint without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PlanetOrbitWidget(size: 200),
          ),
        ),
      );

      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
