part of 'login_page.dart';

class _PosterStage extends StatefulWidget {
  const _PosterStage({required this.urls});

  final List<String> urls;

  @override
  State<_PosterStage> createState() => _PosterStageState();
}

class _PosterClock extends ChangeNotifier {
  Duration elapsed = Duration.zero;

  void tick(Duration next) {
    elapsed = next;
    notifyListeners();
  }

  double progress(int row) {
    final cycle = (70 + row * 12) * 1000;
    return (elapsed.inMilliseconds % cycle) / cycle;
  }

  /// 极慢呼吸缩放，给墙面一点景深。
  double get breath {
    final cycle = 14000;
    final t = (elapsed.inMilliseconds % cycle) / cycle;
    return 1.02 + 0.03 * math.sin(t * math.pi * 2);
  }
}

class _PosterStageState extends State<_PosterStage>
    with TickerProviderStateMixin {
  static const _rowCount = 8;

  final _clock = _PosterClock();
  late final Ticker _ticker;
  late final AnimationController _fadeIn;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_clock.tick)..start();
    _fadeIn = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      value: widget.urls.isEmpty ? 0 : 1,
    );
    if (widget.urls.isNotEmpty) {
      _fadeIn.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _PosterStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.urls.isEmpty && widget.urls.isNotEmpty) {
      _fadeIn.forward();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fadeIn.dispose();
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wallWidth = constraints.maxWidth * 1.28;
          final wallHeight = constraints.maxHeight * 1.22;
          return AnimatedBuilder(
            animation: Listenable.merge([_clock, _fadeIn]),
            builder: (context, _) {
              return Opacity(
                opacity: 0.35 + 0.65 * _fadeIn.value,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 1.2 * (1 - _fadeIn.value),
                    sigmaY: 1.2 * (1 - _fadeIn.value),
                  ),
                  child: OverflowBox(
                    alignment: Alignment.center,
                    minWidth: wallWidth,
                    maxWidth: wallWidth,
                    minHeight: wallHeight,
                    maxHeight: wallHeight,
                    child: Transform.rotate(
                      angle: -6 * math.pi / 180,
                      child: Transform.scale(
                        scale: _clock.breath,
                        child: Column(
                          children: List.generate(_rowCount, (row) {
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: _PosterRow(
                                  urls: widget.urls,
                                  row: row,
                                  clock: _clock,
                                  reverse: row.isOdd,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PosterRow extends StatelessWidget {
  const _PosterRow({
    required this.urls,
    required this.row,
    required this.clock,
    required this.reverse,
  });

  final List<String> urls;
  final int row;
  final _PosterClock clock;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 6.0;
          final tileWidth = constraints.maxHeight * 2 / 3;
          final slot = tileWidth + gap;
          final columns = (constraints.maxWidth / slot).ceil() + 2;
          final stripWidth = columns * slot;
          final strip = Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var copy = 0; copy < 2; copy++)
                for (var col = 0; col < columns; col++)
                  _tile(row * columns + col, tileWidth),
            ],
          );
          return OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: double.infinity,
            minHeight: constraints.maxHeight,
            maxHeight: constraints.maxHeight,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: clock,
                builder: (context, child) {
                  final progress = clock.progress(row);
                  final dx = reverse
                      ? -stripWidth * (1 - progress)
                      : -stripWidth * progress;
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: strip,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tile(int index, double width) {
    final url = urls.isEmpty ? null : urls[index % urls.length];
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: url == null
              ? ColoredBox(
                  color: HSLColor.fromAHSL(
                    1,
                    (index * 17 + row * 11) % 360,
                    0.25,
                    0.16,
                  ).toColor(),
                )
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) => ColoredBox(
                    color: HSLColor.fromAHSL(
                      1,
                      (index * 17 + row * 11) % 360,
                      0.25,
                      0.16,
                    ).toColor(),
                  ),
                ),
        ),
      ),
    );
  }
}
