import 'package:folio/api/entity/models.dart';

class ServerLogFile {
  const ServerLogFile({
    required this.name,
    required this.label,
    required this.size,
    required this.compressed,
    required this.modifiedAt,
  });

  final String name;
  final String label;
  final int size;
  final bool compressed;
  final String modifiedAt;

  factory ServerLogFile.fromJson(Map<String, dynamic> json) {
    return ServerLogFile(
      name: json['name']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      size: asInt(json['size']),
      compressed: asBool(json['compressed']),
      modifiedAt: json['modifiedAt']?.toString() ?? '',
    );
  }
}

class ServerLogList {
  const ServerLogList({
    required this.directory,
    required this.available,
    required this.message,
    required this.files,
  });

  final String? directory;
  final bool available;
  final String? message;
  final List<ServerLogFile> files;

  factory ServerLogList.fromJson(Map<String, dynamic> json) {
    final raw = json['files'];
    final files = raw is List
        ? raw.whereType<Map>().map((item) => ServerLogFile.fromJson(Map<String, dynamic>.from(item))).toList()
        : const <ServerLogFile>[];
    final directory = json['directory']?.toString();
    final message = json['message']?.toString();
    return ServerLogList(
      directory: directory == null || directory.isEmpty ? null : directory,
      available: asBool(json['available']),
      message: message == null || message.isEmpty ? null : message,
      files: files,
    );
  }
}

class ServerLogContent {
  const ServerLogContent({
    required this.name,
    required this.label,
    required this.size,
    required this.compressed,
    required this.modifiedAt,
    required this.truncated,
    required this.lineCount,
    required this.totalLines,
    required this.text,
  });

  final String name;
  final String label;
  final int size;
  final bool compressed;
  final String modifiedAt;
  final bool truncated;
  final int lineCount;
  final int totalLines;
  final String text;

  factory ServerLogContent.fromJson(Map<String, dynamic> json) {
    return ServerLogContent(
      name: json['name']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      size: asInt(json['size']),
      compressed: asBool(json['compressed']),
      modifiedAt: json['modifiedAt']?.toString() ?? '',
      truncated: asBool(json['truncated']),
      lineCount: asInt(json['lineCount']),
      totalLines: asInt(json['totalLines']),
      text: json['text']?.toString() ?? '',
    );
  }
}
