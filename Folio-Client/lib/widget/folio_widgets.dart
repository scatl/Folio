import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:folio/api/entity/models.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/util/app_log.dart';

class FolioBackdrop extends StatelessWidget {
  const FolioBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1016), FolioColors.bgDeep, Color(0xFF080A0E)],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: -80,
            top: -120,
            child: _Glow(color: Color(0x295FB3A8), size: 280),
          ),
          const Positioned(
            right: -60,
            top: -40,
            child: _Glow(color: Color(0x24D4A574), size: 240),
          ),
          child,
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({super.key, required this.work, this.onTap, this.onLongPress, this.kindOverride});

  final WorkCard work;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? kindOverride;

  @override
  Widget build(BuildContext context) {
    final rating = work.rating?.toStringAsFixed(1);
    final caption = [
      if (work.year != null) '${work.year}',
      if (work.genres.isNotEmpty) work.genres.take(2).join(' / '),
    ].join(' · ');
    final watched = work.watchState == 'watched'
        ? '已看'
        : work.watchState == 'watching'
            ? '在看'
            : null;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (work.posterUrl != null && work.posterUrl!.isNotEmpty)
                    LayoutBuilder(
                      builder: (context, constraints) => CachedNetworkImage(
                        imageUrl: work.posterUrl!,
                        fit: BoxFit.cover,
                        memCacheWidth: folioMemCachePx(context, constraints.maxWidth),
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, _) => PosterImage.cardPlaceholder(),
                        errorWidget: (_, _, _) => PosterImage.cardPlaceholder(),
                      ),
                    )
                  else
                    PosterImage.cardPlaceholder(),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xD9080A0E)],
                        stops: [0.45, 1],
                      ),
                    ),
                  ),
                  if (watched != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _Chip(text: watched, accent: work.watchState == 'watched'),
                    ),
                  Positioned(
                    left: 4,
                    right: 4,
                    bottom: 4,
                    child: Row(
                      children: [
                        _Chip(text: kindOverride ?? work.kindLabel),
                        const Spacer(),
                        if (rating != null) _Chip(text: rating, accent: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          work.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.2),
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: FolioColors.inkMuted, fontSize: 12),
            ),
          ),
      ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: accent ? FolioColors.copperSoft : const Color(0x99080A0E),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent ? const Color(0x73D4A574) : FolioColors.lineStrong),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: accent ? FolioColors.copper : FolioColors.ink,
        ),
      ),
    );
  }
}

/// 按屏幕像素取整后的解码宽度。同一档尺寸共用内存缓存，返回上一页时不会重新解码。
int? folioMemCachePx(BuildContext context, double logical) {
  if (!logical.isFinite || logical <= 0) return null;
  final px = logical * MediaQuery.devicePixelRatioOf(context);
  const step = 64;
  final bucket = (px / step).ceil() * step;
  if (bucket < 64) return 64;
  if (bucket > 1280) return 1280;
  return bucket;
}

class PosterImage extends StatefulWidget {
  const PosterImage({super.key, required this.url, this.fallback = ''});

  final String? url;
  final String fallback;

  /// 占位：低对比柔和底 + 无彩色 Folio mark（避免对角半透明渐变留下色带）。
  static Widget placeholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A2422),
            FolioColors.bgSoft,
            Color(0xFF221E1A),
          ],
        ),
      ),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.36,
          child: SvgPicture.asset(
            'assets/folio_mark.svg',
            fit: BoxFit.contain,
            colorFilter: const ColorFilter.mode(FolioColors.inkFaint, BlendMode.srcIn),
          ),
        ),
      ),
    );
  }

  static Widget cardPlaceholder() => placeholder();

  @override
  State<PosterImage> createState() => _PosterImageState();
}

class _PosterImageState extends State<PosterImage> {
  String? _loggedFailUrl;

  void _logFail(String url, Object error) {
    if (_loggedFailUrl == url) return;
    _loggedFailUrl = url;
    appLog('poster', 'fail $url error=$error');
  }

  @override
  void didUpdateWidget(covariant PosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _loggedFailUrl = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth ? constraints.maxWidth : null;
        final height = constraints.hasBoundedHeight ? constraints.maxHeight : null;
        final fallbackBox = PosterImage.placeholder();
        final url = widget.url?.trim();
        final image = url == null || url.isEmpty
            ? fallbackBox
            : CachedNetworkImage(
                imageUrl: url,
                width: width,
                height: height,
                memCacheWidth: width == null ? null : folioMemCachePx(context, width),
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (_, _) => fallbackBox,
                errorWidget: (_, _, error) {
                  _logFail(url, error);
                  return fallbackBox;
                },
              );
        if (width == null && height == null) return image;
        return SizedBox(width: width, height: height, child: image);
      },
    );
  }
}

/// 全局空态 / 错误态：上图案、下文案（可选操作），居中。
class EmptyHint extends StatelessWidget {
  const EmptyHint({super.key, required this.title, this.body = '', this.error = false, this.action});

  final String title;
  final String body;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                error ? const _ErrorMark() : const _EmptyMark(),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: folioDisplay(size: 22, weight: FontWeight.w400),
                ),
                if (body.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: error ? FolioColors.danger.withValues(alpha: 0.85) : FolioColors.inkMuted,
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: 14),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空态 / 错误态共用的主操作按钮（铜底）。
class EmptyHintAction extends StatelessWidget {
  const EmptyHintAction({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: FolioColors.copper,
        foregroundColor: const Color(0xFF1A1208),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Text(label),
    );
  }
}

/// 叠放的空海报框：铜描边 + 青绿点缀，贴合 Folio 暗色影视气质。
class _EmptyMark extends StatelessWidget {
  const _EmptyMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 88,
      child: CustomPaint(painter: _EmptyMarkPainter()),
    );
  }
}

class _EmptyMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 4;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          FolioColors.copper.withValues(alpha: 0.16),
          FolioColors.teal.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 52));
    canvas.drawCircle(Offset(cx, cy), 52, glow);

    void frame(Rect rect, double angle, Color stroke, double width) {
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(angle);
      final local = Rect.fromCenter(center: Offset.zero, width: rect.width, height: rect.height);
      final rrect = RRect.fromRectAndRadius(local, const Radius.circular(8));
      canvas.drawRRect(
        rrect,
        Paint()..color = const Color(0x6612151C),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = stroke,
      );
      // 海报内一条淡横线，暗示空内容
      final inset = local.deflate(10);
      canvas.drawLine(
        Offset(inset.left, inset.center.dy - 6),
        Offset(inset.right, inset.center.dy - 6),
        Paint()
          ..color = stroke.withValues(alpha: 0.35)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(inset.left, inset.center.dy + 4),
        Offset(inset.left + inset.width * 0.55, inset.center.dy + 4),
        Paint()
          ..color = stroke.withValues(alpha: 0.22)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }

    frame(
      Rect.fromCenter(center: Offset(cx - 14, cy - 2), width: 44, height: 62),
      -0.18,
      FolioColors.lineStrong,
      1.2,
    );
    frame(
      Rect.fromCenter(center: Offset(cx + 12, cy - 4), width: 44, height: 62),
      0.14,
      FolioColors.lineStrong,
      1.2,
    );
    frame(
      Rect.fromCenter(center: Offset(cx, cy), width: 48, height: 66),
      -0.03,
      FolioColors.copper.withValues(alpha: 0.75),
      1.5,
    );

    // 底部一点青绿，像资料库点缀
    canvas.drawCircle(
      Offset(cx + 18, cy + 28),
      2.4,
      Paint()..color = FolioColors.teal.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 裂开的海报框：珊瑚描边，表示加载 / 连接失败。
class _ErrorMark extends StatelessWidget {
  const _ErrorMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 88,
      child: CustomPaint(painter: _ErrorMarkPainter()),
    );
  }
}

class _ErrorMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 2;
    const danger = FolioColors.danger;

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          danger.withValues(alpha: 0.2),
          danger.withValues(alpha: 0.05),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 50));
    canvas.drawCircle(Offset(cx, cy), 50, glow);

    // 左半海报
    canvas.save();
    canvas.translate(cx - 6, cy);
    canvas.rotate(-0.12);
    final left = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(-10, 0), width: 40, height: 58),
      const Radius.circular(8),
    );
    canvas.drawRRect(left, Paint()..color = const Color(0x8812151C));
    canvas.drawRRect(
      left,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = danger.withValues(alpha: 0.7),
    );
    canvas.drawLine(
      const Offset(-22, -8),
      const Offset(-2, -8),
      Paint()
        ..color = danger.withValues(alpha: 0.28)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // 右半海报（略错位，像裂开）
    canvas.save();
    canvas.translate(cx + 8, cy + 2);
    canvas.rotate(0.16);
    final right = RRect.fromRectAndRadius(
      Rect.fromCenter(center: const Offset(8, 0), width: 40, height: 58),
      const Radius.circular(8),
    );
    canvas.drawRRect(right, Paint()..color = const Color(0x8812151C));
    canvas.drawRRect(
      right,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = danger.withValues(alpha: 0.55),
    );
    canvas.drawLine(
      const Offset(-2, 4),
      const Offset(18, 4),
      Paint()
        ..color = danger.withValues(alpha: 0.22)
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();

    // 中间裂痕
    final crack = Paint()
      ..color = danger.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(cx - 2, cy - 28)
      ..lineTo(cx + 3, cy - 10)
      ..lineTo(cx - 4, cy + 6)
      ..lineTo(cx + 2, cy + 28);
    canvas.drawPath(path, crack);

    // 裂痕旁小点
    canvas.drawCircle(Offset(cx + 14, cy - 18), 2.2, Paint()..color = danger.withValues(alpha: 0.75));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 页面级加载：叠放海报依次点亮，可选文案。按钮和行内用 [FolioSpinner]、[FolioRefreshIcon]。
class FolioLoading extends StatefulWidget {
  const FolioLoading({super.key, this.label});

  final String? label;

  @override
  State<FolioLoading> createState() => _FolioLoadingState();
}

class _FolioLoadingState extends State<FolioLoading> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mark = AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return CustomPaint(
          size: const Size(96, 88),
          painter: _LoadingMarkPainter(t: _pulse.value),
        );
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mark,
              if (widget.label != null && widget.label!.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  widget.label!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: FolioColors.inkMuted, fontSize: 14, height: 1.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 按钮、行内、列表底部的细圈。
class FolioSpinner extends StatelessWidget {
  const FolioSpinner({super.key, this.size = 20, this.strokeWidth = 2});

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: FolioColors.copper,
      ),
    );
  }
}

/// 刷新按钮：加载时原地旋转，不换成页面加载标。
class FolioRefreshIcon extends StatefulWidget {
  const FolioRefreshIcon({super.key, required this.spinning});

  final bool spinning;

  @override
  State<FolioRefreshIcon> createState() => _FolioRefreshIconState();
}

class _FolioRefreshIconState extends State<FolioRefreshIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _turns;

  @override
  void initState() {
    super.initState();
    _turns = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    if (widget.spinning) _turns.repeat();
  }

  @override
  void didUpdateWidget(FolioRefreshIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning == oldWidget.spinning) return;
    if (widget.spinning) {
      _turns.repeat();
    } else {
      _turns.stop();
      _turns.value = 0;
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _turns,
      child: const Icon(Icons.refresh),
    );
  }
}

class _LoadingMarkPainter extends CustomPainter {
  _LoadingMarkPainter({required this.t});

  final double t;

  double _wave(double phase) {
    final x = ((t + phase) % 1.0) * math.pi * 2;
    return 0.35 + 0.65 * (0.5 + 0.5 * math.sin(x));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 4;
    const scale = 1.0;

    final glowStrength = 0.1 + 0.12 * _wave(0);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          FolioColors.copper.withValues(alpha: glowStrength),
          FolioColors.teal.withValues(alpha: glowStrength * 0.45),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 52 * scale));
    canvas.drawCircle(Offset(cx, cy), 52 * scale, glow);

    void frame(Offset center, Size frameSize, double angle, double phase, {bool accent = false}) {
      final lit = _wave(phase);
      final lift = (1 - lit) * 2.5 * scale;
      canvas.save();
      canvas.translate(center.dx, center.dy - lift);
      canvas.rotate(angle);
      final local = Rect.fromCenter(
        center: Offset.zero,
        width: frameSize.width,
        height: frameSize.height,
      );
      final rrect = RRect.fromRectAndRadius(local, Radius.circular(8 * scale));
      canvas.drawRRect(rrect, Paint()..color = Color.fromRGBO(18, 21, 28, 0.55 + 0.35 * lit));
      final stroke = accent
          ? Color.lerp(FolioColors.lineStrong, FolioColors.copper, lit)!
          : Color.lerp(FolioColors.line, FolioColors.teal.withValues(alpha: 0.65), lit)!;
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (accent ? 1.5 : 1.2) * scale
          ..color = stroke.withValues(alpha: 0.35 + 0.55 * lit),
      );
      final inset = local.deflate(10 * scale);
      final line = Paint()
        ..color = stroke.withValues(alpha: 0.15 + 0.35 * lit)
        ..strokeWidth = 1.2 * scale
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(inset.left, inset.center.dy - 6 * scale), Offset(inset.right, inset.center.dy - 6 * scale), line);
      canvas.drawLine(
        Offset(inset.left, inset.center.dy + 4 * scale),
        Offset(inset.left + inset.width * (0.4 + 0.3 * lit), inset.center.dy + 4 * scale),
        line,
      );
      canvas.restore();
    }

    final w = 44 * scale;
    final h = 62 * scale;
    final fw = 48 * scale;
    final fh = 66 * scale;
    frame(Offset(cx - 14 * scale, cy - 2 * scale), Size(w, h), -0.18, 0.0);
    frame(Offset(cx + 12 * scale, cy - 4 * scale), Size(w, h), 0.14, 0.33);
    frame(Offset(cx, cy), Size(fw, fh), -0.03, 0.66, accent: true);

    final dotLit = _wave(0.5);
    canvas.drawCircle(
      Offset(cx + 18 * scale, cy + 28 * scale),
      (1.6 + 1.2 * dotLit) * scale,
      Paint()..color = FolioColors.teal.withValues(alpha: 0.35 + 0.55 * dotLit),
    );
  }

  @override
  bool shouldRepaint(covariant _LoadingMarkPainter oldDelegate) => oldDelegate.t != t;
}

class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.text, this.error = false, this.loading = false});

  final String text;
  final bool error;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final color = error ? FolioColors.danger : FolioColors.inkMuted;
    return Row(
      children: [
        if (loading)
          const Padding(
            padding: EdgeInsets.only(right: 10),
            child: FolioSpinner(size: 16),
          ),
        Expanded(child: Text(text, style: TextStyle(color: color))),
      ],
    );
  }
}
