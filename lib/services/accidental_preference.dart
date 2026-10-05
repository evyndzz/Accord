import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AccidentalNotation {
  auto,
  sharp,
  flat,
}

class AccidentalPreferenceService extends ChangeNotifier {
  static const String _prefKey = 'accidental_notation';

  AccidentalNotation _notation = AccidentalNotation.auto;

  AccidentalNotation get notation => _notation;
  bool get isAuto => _notation == AccidentalNotation.auto;
  bool get isFlat => _notation == AccidentalNotation.flat;
  bool get isSharp => _notation == AccidentalNotation.sharp;

  static final AccidentalPreferenceService _instance = AccidentalPreferenceService._internal();
  factory AccidentalPreferenceService() => _instance;

  static AccidentalPreferenceService of(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<AccidentalPreferenceService>(context, listen: listen);
    } catch (_) {
      return _instance;
    }
  }

  AccidentalPreferenceService._internal() {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_prefKey);
      if (value == 'flat') {
        _notation = AccidentalNotation.flat;
      } else if (value == 'sharp') {
        _notation = AccidentalNotation.sharp;
      } else {
        _notation = AccidentalNotation.auto;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setNotation(AccidentalNotation newNotation) async {
    if (_notation == newNotation) return;
    _notation = newNotation;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final valStr = newNotation == AccidentalNotation.flat
          ? 'flat'
          : (newNotation == AccidentalNotation.sharp ? 'sharp' : 'auto');
      await prefs.setString(_prefKey, valStr);
    } catch (_) {}
  }

  /// Memformat akord (misal: "C#m7/G#") sesuai preferensi kres/mol yang aktif
  String formatChord(String chord) {
    return formatWithNotation(chord, _notation);
  }

  /// Konversi notasi kres/mol statis/util
  static String formatWithNotation(String chord, AccidentalNotation notation) {
    if (chord.trim().isEmpty || notation == AccidentalNotation.auto) {
      return chord;
    }

    // Pattern untuk menangani Root + Accidental + Quality + Bass
    final match = RegExp(r'^([A-G])([#b♯♭]?)([^/]*)(?:/([A-G])([#b♯♭]?))?$').firstMatch(chord.trim());
    if (match == null) {
      return chord;
    }

    final rootLetter = match.group(1)!;
    final rootAccidental = (match.group(2) ?? '').replaceAll('♯', '#').replaceAll('♭', 'b');
    final quality = match.group(3) ?? '';
    final bassLetter = match.group(4);
    final bassAccidental = (match.group(5) ?? '').replaceAll('♯', '#').replaceAll('♭', 'b');

    final formattedRoot = _convertNote('$rootLetter$rootAccidental', notation);
    if (bassLetter != null) {
      final formattedBass = _convertNote('$bassLetter$bassAccidental', notation);
      return '$formattedRoot$quality/$formattedBass';
    }

    return '$formattedRoot$quality';
  }

  static String _convertNote(String note, AccidentalNotation notation) {
    if (notation == AccidentalNotation.flat) {
      switch (note) {
        case 'C#': return 'Db';
        case 'D#': return 'Eb';
        case 'F#': return 'Gb';
        case 'G#': return 'Ab';
        case 'A#': return 'Bb';
        default: return note;
      }
    } else if (notation == AccidentalNotation.sharp) {
      switch (note) {
        case 'Db': return 'C#';
        case 'Eb': return 'D#';
        case 'Gb': return 'F#';
        case 'Ab': return 'G#';
        case 'Bb': return 'A#';
        default: return note;
      }
    }
    return note;
  }
}
