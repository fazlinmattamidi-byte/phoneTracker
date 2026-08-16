import 'package:flutter/services.dart';

import 'plate_types.dart';

class PpOcrDictionary {
  const PpOcrDictionary(this.entries);

  final List<String> entries;

  int get classCount => entries.length + 1;

  static PpOcrDictionary fromText(String raw, {bool appendSpace = true}) {
    final entries = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (appendSpace) entries.add(' ');
    return PpOcrDictionary(List<String>.unmodifiable(entries));
  }

  static Future<PpOcrDictionary> fromAsset(
    String assetPath, {
    AssetBundle? bundle,
    bool appendSpace = true,
  }) async {
    final raw = await (bundle ?? rootBundle).loadString(assetPath);
    return PpOcrDictionary.fromText(raw, appendSpace: appendSpace);
  }
}

class PpOcrDecodeResult {
  const PpOcrDecodeResult({
    required this.rawText,
    required this.confidence,
    required this.characterConfidences,
  });

  final String rawText;
  final double confidence;
  final List<CharacterConfidence> characterConfidences;
}

PpOcrDecodeResult decodePpOcrCtcTimesteps(
  List<List<double>> timesteps,
  PpOcrDictionary dictionary, {
  int blankIndex = 0,
}) {
  final chars = <String>[];
  final charConfs = <CharacterConfidence>[];
  var previousIndex = blankIndex;

  for (final scores in timesteps) {
    if (scores.isEmpty) {
      previousIndex = blankIndex;
      continue;
    }

    final winner = _argMax(scores);
    final maxIndex = winner.index;
    final maxScore = winner.value.clamp(0.0, 1.0);

    if (maxIndex != blankIndex && maxIndex != previousIndex) {
      final dictionaryIndex = maxIndex - 1;
      if (dictionaryIndex >= 0 && dictionaryIndex < dictionary.entries.length) {
        final char = dictionary.entries[dictionaryIndex];
        if (char.isNotEmpty && char != ' ') {
          chars.add(char);
          charConfs.add(CharacterConfidence(
            char: char,
            confidence: maxScore,
            position: charConfs.length,
          ));
        }
      }
    }
    previousIndex = maxIndex;
  }

  final confidence = charConfs.isEmpty
      ? 0.0
      : charConfs
              .map((item) => item.confidence)
              .reduce((left, right) => left + right) /
          charConfs.length;

  return PpOcrDecodeResult(
    rawText: chars.join(),
    confidence: confidence,
    characterConfidences: List<CharacterConfidence>.unmodifiable(charConfs),
  );
}

PpOcrDecodeResult decodePpOcrCtcFlat(
  List<double> output,
  PpOcrDictionary dictionary, {
  required int sequenceLength,
  required int classCount,
  int blankIndex = 0,
}) {
  if (sequenceLength <= 0 || classCount <= 0) {
    return const PpOcrDecodeResult(
      rawText: '',
      confidence: 0,
      characterConfidences: <CharacterConfidence>[],
    );
  }

  final timesteps = <List<double>>[];
  for (var timestep = 0; timestep < sequenceLength; timestep += 1) {
    final offset = timestep * classCount;
    if (offset >= output.length) break;
    final end = (offset + classCount).clamp(0, output.length);
    timesteps.add(output.sublist(offset, end));
  }
  return decodePpOcrCtcTimesteps(
    timesteps,
    dictionary,
    blankIndex: blankIndex,
  );
}

({int index, double value}) _argMax(List<double> values) {
  var bestIndex = 0;
  var bestValue = values.first;
  for (var index = 1; index < values.length; index += 1) {
    final value = values[index];
    if (value > bestValue) {
      bestIndex = index;
      bestValue = value;
    }
  }
  return (index: bestIndex, value: bestValue);
}
