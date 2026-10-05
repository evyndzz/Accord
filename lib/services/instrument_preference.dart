import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum InstrumentType {
  piano,
  guitar,
  nashville,
}

class InstrumentPreferenceService extends ChangeNotifier {
  static const String _prefKey = 'accord_instrument_type';

  InstrumentType _instrument = InstrumentType.piano;

  InstrumentType get instrument => _instrument;
  bool get isPiano => _instrument == InstrumentType.piano;
  bool get isGuitar => _instrument == InstrumentType.guitar;
  bool get isNashville => _instrument == InstrumentType.nashville;

  String get displayName {
    switch (_instrument) {
      case InstrumentType.piano:
        return 'Piano 11 Tuts (Voicing)';
      case InstrumentType.guitar:
        return 'Gitar 6 Senar (Fretboard)';
      case InstrumentType.nashville:
        return 'Notasi Angka / Derajat (I-IV-V)';
    }
  }

  String get shortLabel {
    switch (_instrument) {
      case InstrumentType.piano:
        return 'Piano';
      case InstrumentType.guitar:
        return 'Gitar';
      case InstrumentType.nashville:
        return 'Angka';
    }
  }

  IconData get icon {
    switch (_instrument) {
      case InstrumentType.piano:
        return Icons.piano_rounded;
      case InstrumentType.guitar:
        return Icons.music_note_rounded;
      case InstrumentType.nashville:
        return Icons.numbers_rounded;
    }
  }

  static final InstrumentPreferenceService _instance = InstrumentPreferenceService._internal();
  factory InstrumentPreferenceService() => _instance;

  static InstrumentPreferenceService of(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<InstrumentPreferenceService>(context, listen: listen);
    } catch (_) {
      return _instance;
    }
  }

  InstrumentPreferenceService._internal() {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_prefKey);
      if (value == 'guitar') {
        _instrument = InstrumentType.guitar;
      } else if (value == 'nashville') {
        _instrument = InstrumentType.nashville;
      } else {
        _instrument = InstrumentType.piano;
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setInstrument(InstrumentType newInstrument) async {
    if (_instrument == newInstrument) return;
    _instrument = newInstrument;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final valStr = newInstrument == InstrumentType.guitar
          ? 'guitar'
          : (newInstrument == InstrumentType.nashville ? 'nashville' : 'piano');
      await prefs.setString(_prefKey, valStr);
    } catch (_) {}
  }
}
