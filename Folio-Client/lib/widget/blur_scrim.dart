import 'dart:ui';

import 'package:material_ui/material_ui.dart';

/// 模糊弹层共用参数（Sheet / Dialog 遮罩）。
abstract final class BlurDialogMotion {
  static const duration = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;
  static const reverseCurve = Curves.easeInCubic;
  static const beginScale = 0.92;
  static const blurSigma = 10.0;
  static const scrimAlpha = 0.32;
}

/// 全屏高斯模糊 + 压暗，供 Dialog / Sheet 遮罩复用。
class BlurScrim extends StatelessWidget {
  const BlurScrim({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: BlurDialogMotion.blurSigma,
          sigmaY: BlurDialogMotion.blurSigma,
        ),
        child: ColoredBox(
          color: scheme.scrim.withValues(alpha: BlurDialogMotion.scrimAlpha),
        ),
      ),
    );
  }
}
