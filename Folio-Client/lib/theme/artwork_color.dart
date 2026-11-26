import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:folio/theme/folio_theme.dart';

/// 从海报或背景图取出一个适合铺在详情页上的深色。
Future<Color> artworkBackground(String url) async {
  final provider = ResizeImage(CachedNetworkImageProvider(url), width: 48);
  final stream = provider.resolve(const ImageConfiguration());
  final completer = Completer<ui.Image>();
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image);
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  final image = await completer.future;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) return FolioColors.bgDeep;
  return _backgroundTone(bytes, image.width, image.height);
}

Color _backgroundTone(ByteData data, int width, int height) {
  final step = math.max(1, math.max(width, height) ~/ 40);
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var weight = 0.0;
  final pixels = data.buffer.asUint8List();
  for (var y = 0; y < height; y += step) {
    for (var x = 0; x < width; x += step) {
      final index = (y * width + x) * 4;
      if (index + 3 >= pixels.length) continue;
      final alpha = pixels[index + 3];
      if (alpha < 160) continue;
      final color = Color.fromARGB(255, pixels[index], pixels[index + 1], pixels[index + 2]);
      final hsl = HSLColor.fromColor(color);
      if (hsl.lightness < 0.06 || hsl.lightness > 0.94) continue;
      final sample = 0.2 + hsl.saturation;
      red += pixels[index] * sample;
      green += pixels[index + 1] * sample;
      blue += pixels[index + 2] * sample;
      weight += sample;
    }
  }
  if (weight <= 0) return FolioColors.bgDeep;
  final tone = HSLColor.fromColor(Color.fromARGB(255, (red / weight).round(), (green / weight).round(), (blue / weight).round()));
  return tone.withSaturation(tone.saturation.clamp(0.18, 0.72)).withLightness(0.16).toColor();
}

class ArtworkTint extends StatefulWidget {
  const ArtworkTint({super.key, required this.url, required this.child});

  final String? url;
  final Widget child;

  @override
  State<ArtworkTint> createState() => _ArtworkTintState();
}

class _ArtworkTintState extends State<ArtworkTint> {
  Color _color = FolioColors.bgDeep;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ArtworkTint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _color = FolioColors.bgDeep);
      return;
    }
    try {
      final color = await artworkBackground(url);
      if (mounted) setState(() => _color = color);
    } catch (_) {
      if (mounted) setState(() => _color = FolioColors.bgDeep);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: _color, child: widget.child);
  }
}
