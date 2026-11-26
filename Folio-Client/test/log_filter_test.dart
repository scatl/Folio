import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folio/logs/log_filter.dart';
import 'package:folio/logs/log_record.dart';
import 'package:folio/logs/log_view.dart';
import 'package:folio/theme/folio_theme.dart';

void main() {
  test('keeps stack traces with the error and treats unleveled lines as info', () {
    const text = '''
2026-10-26T11:29:01.123+08:00  INFO 1 --- [main] c.s.folio.App : started
2026-10-26T11:29:02.000+08:00 ERROR 1 --- [main] c.s.folio.App : boom
java.lang.IllegalStateException: boom
	at com.scatl.folio.App.run(App.kt:10)
2026-10-26T03:29:03.123Z [play] probe start
''';

    final errors = filterLog(text, LogLevel.error);
    expect(errors.count, 1);
    expect(errors.text, contains('IllegalStateException'));
    expect(errors.text, isNot(contains('started')));
    expect(errors.text, isNot(contains('probe start')));

    final info = filterLog(text, LogLevel.info);
    expect(info.count, 2);
    expect(info.text, contains('started'));
    expect(info.text, contains('probe start'));

    expect(filterLog(text, LogLevel.all).count, 3);
  });

  test('maps warn and debug tokens', () {
    const text = '''
2026-10-26 11:00:00.100  WARN 12 --- [nio] c.s.folio.App : slow
2026-10-26T11:00:01.100Z DEBUG 12 --- [nio] c.s.folio.App : detail
''';

    expect(filterLog(text, LogLevel.warn).count, 1);
    expect(filterLog(text, LogLevel.debug).text, contains('detail'));
  });

  test('splits a server line into time, level, source, and folded stack', () {
    const text = '''
2026-10-26T11:29:02.000+08:00 ERROR 1 --- [main] c.s.folio.library.LibraryService : boom
java.lang.IllegalStateException: boom
	at com.scatl.folio.App.run(App.kt:10)
2026-10-26T03:29:03.123Z [play] probe start
''';

    final records = parseLog(text);
    expect(records, hasLength(2));

    final error = records.first;
    expect(error.time, '11:29:02');
    expect(error.date, '2026-10-26');
    expect(error.level, LogLevel.error);
    expect(error.source, isEmpty);
    expect(error.message, 'boom');
    expect(error.detail, '进程 1 · 线程 main');
    expect(error.extra, hasLength(2));

    final client = records.last;
    expect(client.level, LogLevel.info);
    expect(client.source, 'play');
    expect(client.message, 'probe start');
    expect(client.detail, isNull);
    expect(client.extra, isEmpty);
  });

  test('keeps the level when the line has an application name before the thread', () {
    const text = '''
2026-10-26T11:29:02.000+08:00 ERROR 1 --- [folio-server] [main] c.s.folio.library.LibraryService : boom
2026-10-26T11:29:03.000+08:00  INFO 1 --- [folio-server] [main] c.s.folio.App : started
''';

    final records = parseLog(text);
    expect(records.first.level, LogLevel.error);
    expect(records.first.source, isEmpty);
    expect(records.first.message, 'boom');
    expect(records.first.detail, '进程 1 · folio-server · 线程 main');
    expect(filterLog(text, LogLevel.error).count, 1);
    expect(filterLog(text, LogLevel.info).count, 1);
  });

  test('groups local lines by day with today first', () {
    final days = localLogDays(
      const [
        '2026-10-25T09:00:00.000 [play] yesterday',
        'continued',
        '2026-10-26T09:00:00.000 [play] today',
        '2026-10-24T09:00:00.000 [play] older',
      ],
      now: DateTime(2026, 10, 26, 12),
    );

    expect(days.map((day) => day.label).toList(), ['今天', '2026-10-25', '2026-10-24']);
    expect(days.first.lines, ['2026-10-26T09:00:00.000 [play] today']);
    expect(days[1].lines, ['2026-10-25T09:00:00.000 [play] yesterday', 'continued']);
  });

  testWidgets('opens a detail sheet without showing the logger name', (tester) async {
    const text = '''
2026-10-26T11:29:02.000+08:00 ERROR 1 --- [main] c.s.folio.library.LibraryService : boom
java.lang.IllegalStateException: boom
	at com.scatl.folio.App.run(App.kt:10)
''';
    final scroll = ScrollController();
    addTearDown(scroll.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: folioTheme(),
      home: Scaffold(
        body: LogRecordView(
          controller: scroll,
          text: text,
          level: LogLevel.all,
        ),
      ),
    ));

    expect(find.text('11:29:02'), findsOneWidget);
    expect(find.text('错误'), findsOneWidget);
    expect(find.text('boom'), findsOneWidget);
    expect(find.textContaining('LibraryService'), findsNothing);
    expect(find.textContaining('IllegalStateException'), findsNothing);

    await tester.tap(find.text('boom'));
    await tester.pumpAndSettle();

    expect(find.textContaining('IllegalStateException'), findsOneWidget);
    expect(find.text('进程 1 · 线程 main'), findsOneWidget);
    expect(find.textContaining('LibraryService'), findsNothing);
  });
}
