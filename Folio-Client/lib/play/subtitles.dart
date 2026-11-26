import 'dart:convert';
import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';

class SubtitleCandidate {
  const SubtitleCandidate({required this.name, required this.score});

  final String name;
  final int score;

  bool get recommended => score > 0;
}

const subtitleExtensions = {'srt', 'ass', 'ssa', 'vtt', 'sub', 'smi'};

/// 按与视频文件名的相近程度排序；同目录外挂字幕列表用。
List<SubtitleCandidate> rankSubtitles(String videoFileName, Iterable<String> names) {
  final stem = _stem(videoFileName).toLowerCase();
  final ranked = <SubtitleCandidate>[];
  for (final raw in names) {
    final name = raw.trim();
    if (name.isEmpty) continue;
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.') + 1).toLowerCase() : '';
    if (!subtitleExtensions.contains(ext)) continue;
    ranked.add(SubtitleCandidate(name: name, score: _subtitleScore(stem, name)));
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return ranked;
}

int _subtitleScore(String videoStem, String subtitleName) {
  if (videoStem.isEmpty) return 0;
  final subStem = _stem(subtitleName).toLowerCase();
  if (subStem == videoStem) return 100;
  if (subStem.startsWith('$videoStem.') || subStem.startsWith('${videoStem}_') || subStem.startsWith('$videoStem ')) {
    return 80;
  }
  if (subStem.startsWith(videoStem)) return 60;
  if (subStem.contains(videoStem)) return 40;
  return 0;
}

String _stem(String fileName) {
  final slash = fileName.replaceAll('\\', '/').lastIndexOf('/');
  final base = slash >= 0 ? fileName.substring(slash + 1) : fileName;
  final dot = base.lastIndexOf('.');
  if (dot <= 0) return base;
  return base.substring(0, dot);
}

bool looksBinary(Uint8List bytes) {
  if (_utf16Encoding(bytes) != null) return false;
  final sample = bytes.length < 512 ? bytes.length : 512;
  var zeros = 0;
  for (var i = 0; i < sample; i++) {
    if (bytes[i] == 0) zeros++;
  }
  return zeros > 8;
}

String decodeSubtitleBytes(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  final utf16 = _utf16Encoding(bytes);
  if (utf16 == _Utf16.le) {
    final start = bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE ? 2 : 0;
    return _decodeUtf16(bytes, start, Endian.little);
  }
  if (utf16 == _Utf16.be) {
    final start = bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF ? 2 : 0;
    return _decodeUtf16(bytes, start, Endian.big);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return gbk_bytes.decode(bytes);
  }
}

enum _Utf16 { le, be }

_Utf16? _utf16Encoding(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    if (bytes.length >= 4 && bytes[2] == 0 && bytes[3] == 0) return null;
    return _Utf16.le;
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _Utf16.be;
  }
  final sample = bytes.length < 256 ? bytes.length : 256;
  if (sample < 8) return null;
  final pairs = sample ~/ 2;
  var le = 0;
  var be = 0;
  for (var i = 0; i + 1 < sample; i += 2) {
    if (bytes[i] != 0 && bytes[i + 1] == 0) le++;
    if (bytes[i] == 0 && bytes[i + 1] != 0) be++;
  }
  if (le > pairs * 0.6) return _Utf16.le;
  if (be > pairs * 0.6) return _Utf16.be;
  return null;
}

String _decodeUtf16(Uint8List bytes, int start, Endian endian) {
  final data = ByteData.sublistView(bytes, start);
  final units = <int>[];
  for (var i = 0; i + 1 < data.lengthInBytes; i += 2) {
    final unit = data.getUint16(i, endian);
    if (unit != 0) units.add(unit);
  }
  return String.fromCharCodes(units);
}
