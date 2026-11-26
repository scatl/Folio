import 'package:flutter_test/flutter_test.dart';
import 'package:folio/play/subtitles.dart';

void main() {
  test('rankSubtitles prefers matching stem', () {
    final ranked = rankSubtitles('Movie.Name.2020.mkv', [
      'other.srt',
      'Movie.Name.2020.chs.ass',
      'Movie.Name.2020.srt',
      'readme.txt',
    ]);
    expect(ranked.map((item) => item.name).toList(), [
      'Movie.Name.2020.srt',
      'Movie.Name.2020.chs.ass',
      'other.srt',
    ]);
    expect(ranked.first.recommended, isTrue);
    expect(ranked.last.recommended, isFalse);
  });
}
