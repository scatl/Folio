import 'package:material_ui/material_ui.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/blur_scrim.dart';

/// 背景模糊 + 淡入压暗 + 内容淡入缩放。动画参数与 Sheet 共用 [BlurDialogMotion]。
class BlurDialogScaffold extends StatelessWidget {
  const BlurDialogScaffold({
    super.key,
    required this.animation,
    required this.child,
    this.onBarrierTap,
    this.panelConstraints,
    this.panelPadding = const EdgeInsets.fromLTRB(24, 22, 24, 16),
  });

  final Animation<double> animation;
  final Widget child;
  final VoidCallback? onBarrierTap;
  final BoxConstraints? panelConstraints;
  final EdgeInsetsGeometry panelPadding;

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: BlurDialogMotion.curve,
      reverseCurve: BlurDialogMotion.reverseCurve,
    );
    final scale = Tween<double>(begin: BlurDialogMotion.beginScale, end: 1).animate(curved);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxPanelHeight = MediaQuery.sizeOf(context).height -
        viewInsets.bottom -
        MediaQuery.paddingOf(context).vertical -
        24;
    final constraints = (panelConstraints ?? const BoxConstraints(minWidth: 280, maxWidth: 360))
        .copyWith(maxHeight: maxPanelHeight);

    return Stack(
      fit: StackFit.expand,
      children: [
        FadeTransition(
          opacity: curved,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBarrierTap,
            child: const BlurScrim(),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Center(
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: scale,
                child: ConstrainedBox(
                  constraints: constraints,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x2E000000),
                          blurRadius: 24,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Material(
                      color: FolioColors.bgPanel.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(padding: panelPadding, child: child),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

Future<T?> showFolioDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, Animation<double> animation) builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: BlurDialogMotion.duration,
    pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx, animation),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) => child,
  );
}
