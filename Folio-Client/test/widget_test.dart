import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/http/server_connection.dart';
import 'package:folio/widget/folio_nav_icon.dart';

void main() {
  test('normalizeBaseUrl accepts a host and port', () {
    expect(ServerConnection.parse('192.168.1.8:32700').baseUrl, 'http://192.168.1.8:32700');
    expect(ServerConnection.parse('https://nas.local:32700/').baseUrl, 'https://nas.local:32700');
  });

  testWidgets('nav icons paint the web glyphs', (tester) async {
    for (final glyph in FolioNavGlyph.values) {
      await tester.pumpWidget(MaterialApp(home: Center(child: FolioNavIcon(glyph, active: true))));
      expect(tester.takeException(), isNull);
    }
  });
}
