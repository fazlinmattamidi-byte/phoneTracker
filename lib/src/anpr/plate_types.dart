enum PlateCategory {
  standard,
  letterNumberSuffix,
  sabah,
  sarawak,
  langkawi,
  putrajaya,
  evSpecial,
  specialSeries,
  diplomatic,
  motorcycle,
  government,
  institutional,
  unknownValidCandidate,
}

extension PlateCategoryCode on PlateCategory {
  String get code {
    switch (this) {
      case PlateCategory.standard:
        return 'STANDARD';
      case PlateCategory.letterNumberSuffix:
        return 'LETTER_NUMBER_SUFFIX';
      case PlateCategory.sabah:
        return 'SABAH';
      case PlateCategory.sarawak:
        return 'SARAWAK';
      case PlateCategory.langkawi:
        return 'LANGKAWI';
      case PlateCategory.putrajaya:
        return 'PUTRAJAYA';
      case PlateCategory.evSpecial:
        return 'EV_SPECIAL';
      case PlateCategory.specialSeries:
        return 'SPECIAL_SERIES';
      case PlateCategory.diplomatic:
        return 'DIPLOMATIC';
      case PlateCategory.motorcycle:
        return 'MOTORCYCLE';
      case PlateCategory.government:
        return 'GOVERNMENT';
      case PlateCategory.institutional:
        return 'INSTITUTIONAL';
      case PlateCategory.unknownValidCandidate:
        return 'UNKNOWN_VALID_CANDIDATE';
    }
  }
}

enum PlateLayout {
  singleLine,
  twoLine,
  square,
}

extension PlateLayoutCode on PlateLayout {
  String get code {
    switch (this) {
      case PlateLayout.singleLine:
        return 'SINGLE_LINE';
      case PlateLayout.twoLine:
        return 'TWO_LINE';
      case PlateLayout.square:
        return 'SQUARE';
    }
  }
}

enum MatchType {
  exact,
  possible,
  none,
  insufficientConfidence,
}

extension MatchTypeCode on MatchType {
  String get code {
    switch (this) {
      case MatchType.exact:
        return 'EXACT';
      case MatchType.possible:
        return 'POSSIBLE';
      case MatchType.none:
        return 'NONE';
      case MatchType.insufficientConfidence:
        return 'INSUFFICIENT_CONFIDENCE';
    }
  }
}

class CharacterConfidence {
  const CharacterConfidence({
    required this.char,
    required this.confidence,
    required this.position,
    this.alternatives,
  });

  final String char;
  final double confidence;
  final int position;
  final List<CharacterAlternative>? alternatives;
}

class CharacterAlternative {
  const CharacterAlternative({
    required this.char,
    required this.confidence,
  });

  final String char;
  final double confidence;
}
