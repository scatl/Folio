import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:folio/api/entity/models.dart';
import 'package:folio/http/api_client.dart';

class PlaybackProgressEvent {
  const PlaybackProgressEvent({required this.workId, required this.username});

  final int workId;
  final String username;

  factory PlaybackProgressEvent.fromJson(Map<String, dynamic> json) {
    return PlaybackProgressEvent(
      workId: asInt(json['workId']),
      username: json['username']?.toString() ?? '',
    );
  }
}

class ScrapeBus {
  final stats = StreamController<ScrapeJobStats>.broadcast();
  final jobs = StreamController<ScrapeJobRow>.broadcast();
  final done = StreamController<ScrapeJobRow>.broadcast();
  final deleted = StreamController<int>.broadcast();
  final workRemoved = StreamController<int>.broadcast();
  final playback = StreamController<PlaybackProgressEvent>.broadcast();

  void add(String event, Map<String, dynamic> data) {
    switch (event) {
      case 'scrape.stats':
        stats.add(ScrapeJobStats.fromJson(data));
      case 'scrape.job':
        jobs.add(ScrapeJobRow.fromJson(data));
      case 'scrape.done':
        done.add(ScrapeJobRow.fromJson(data));
      case 'scrape.deleted':
        final id = asIntOrNull(data['id']);
        if (id != null) deleted.add(id);
      case 'work.removed':
        final workId = asIntOrNull(data['workId']);
        if (workId != null) workRemoved.add(workId);
      case 'playback.progress':
        playback.add(PlaybackProgressEvent.fromJson(data));
    }
  }

  void close() {
    stats.close();
    jobs.close();
    done.close();
    deleted.close();
    workRemoved.close();
    playback.close();
  }
}

class ScrapeEventClient {
  ScrapeEventClient(this.api, this.bus);

  final ApiClient api;
  final ScrapeBus bus;
  HttpClient? _client;
  bool _stopped = true;

  void start() {
    if (!_stopped) return;
    _stopped = false;
    unawaited(_loop());
  }

  void stop() {
    _stopped = true;
    _client?.close(force: true);
    _client = null;
  }

  Future<void> _loop() async {
    while (!_stopped) {
      try {
        await _listen();
      } catch (_) {
        // 连接断开后短暂等待再重连。
      }
      if (_stopped) return;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<void> _listen() async {
    final base = api.baseUrl;
    if (base == null || _stopped) return;
    final uri = Uri.parse('$base/api/events');
    final cookies = await api.jar.loadForRequest(uri);
    final client = HttpClient();
    _client = client;
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      if (cookies.isNotEmpty) {
        request.headers.set(
          HttpHeaders.cookieHeader,
          cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; '),
        );
      }
      final response = await request.close();
      if (response.statusCode == 401) {
        throw StateError('未登录');
      }
      if (response.statusCode != 200) {
        throw StateError('事件连接失败 (${response.statusCode})');
      }
      var event = 'message';
      final data = StringBuffer();
      await for (final line in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (_stopped) return;
        if (line.isEmpty) {
          final payload = data.toString();
          data.clear();
          final name = event;
          event = 'message';
          if (payload.isEmpty) continue;
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map) {
              bus.add(name, Map<String, dynamic>.from(decoded));
            }
          } catch (_) {
            // 忽略无法解析的事件。
          }
          continue;
        }
        if (line.startsWith(':')) continue;
        if (line.startsWith('event:')) {
          event = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          if (data.isNotEmpty) data.write('\n');
          data.write(line.substring(5).trimLeft());
        }
      }
    } finally {
      client.close(force: true);
      if (identical(_client, client)) _client = null;
    }
  }
}
