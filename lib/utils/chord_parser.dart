class ChordToken {
  final String chord;
  final int charIndex;

  const ChordToken({required this.chord, required this.charIndex});
}

class ParsedLine {
  final String plainText;
  final List<ChordToken> chords;

  const ParsedLine({required this.plainText, required this.chords});
}

class ChordParser {
  static final _bracketRegex = RegExp(r'\[([^\]]+)]');

  /// Parse "[Bm]Baby, I love [Em]you" into ParsedLine
  static ParsedLine parse(String rawLine) {
    final plain = StringBuffer();
    final tokens = <ChordToken>[];
    int lastEnd = 0;

    for (final match in _bracketRegex.allMatches(rawLine)) {
      plain.write(rawLine.substring(lastEnd, match.start));
      final chord = match.group(1)!;
      tokens.add(ChordToken(chord: chord, charIndex: plain.length));
      lastEnd = match.end;
    }
    plain.write(rawLine.substring(lastEnd));

    return ParsedLine(plainText: plain.toString(), chords: tokens);
  }

  /// Extract unique chord names from a single raw line
  static List<String> extractChords(String rawLine) {
    final chords = <String>[];
    final seen = <String>{};
    for (final match in _bracketRegex.allMatches(rawLine)) {
      final chord = match.group(1)!;
      if (seen.add(chord)) {
        chords.add(chord);
      }
    }
    return chords;
  }

  /// Extract all unique chords from multiple raw lines
  static List<String> extractAllChords(List<String> rawLines) {
    final chords = <String>[];
    final seen = <String>{};
    for (final line in rawLines) {
      for (final match in _bracketRegex.allMatches(line)) {
        final chord = match.group(1)!;
        if (seen.add(chord)) {
          chords.add(chord);
        }
      }
    }
    return chords;
  }
}
