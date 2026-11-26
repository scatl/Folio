import 'package:material_ui/material_ui.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/blur_scrim.dart';

/// 与 [showModalBottomSheet] 相同的滑入 / 拖动手势，遮罩使用 [BlurScrim]。
Future<T?> showBlurModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool showDragHandle = true,
  bool useSafeArea = true,
  RouteSettings? routeSettings,
  AnimationController? transitionAnimationController,
  Offset? anchorPoint,
  AnimationStyle? sheetAnimationStyle,
  bool? requestFocus,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final localizations = MaterialLocalizations.of(context);
  return navigator.push(
    BlurModalBottomSheetRoute<T>(
      builder: builder,
      capturedThemes: InheritedTheme.capture(from: context, to: navigator.context),
      isScrollControlled: isScrollControlled,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(localizations.bottomSheetLabel),
      backgroundColor: backgroundColor,
      elevation: elevation,
      shape: shape,
      clipBehavior: clipBehavior,
      constraints: constraints,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: showDragHandle,
      settings: routeSettings,
      transitionAnimationController: transitionAnimationController,
      anchorPoint: anchorPoint,
      useSafeArea: useSafeArea,
      sheetAnimationStyle: sheetAnimationStyle,
      requestFocus: requestFocus,
    ),
  );
}

/// Folio 默认样式的模糊 bottom sheet（圆角面板 + 拖拽条 + 模糊遮罩）。
///
/// 默认按内容高度收缩，并用 [maxHeightFactor] 限制上限；超出部分由内容自行滚动。
Future<T?> showFolioSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  double maxHeightFactor = 0.75,
  BoxConstraints? constraints,
  bool showDragHandle = true,
  bool useSafeArea = true,
  Color? backgroundColor,
  ShapeBorder? shape,
}) {
  final screenH = MediaQuery.sizeOf(context).height;
  final maxH = screenH * maxHeightFactor.clamp(0.2, 1.0);
  final merged = BoxConstraints(
    minWidth: constraints?.minWidth ?? 0,
    maxWidth: constraints?.maxWidth ?? double.infinity,
    minHeight: constraints?.minHeight ?? 0,
    maxHeight: switch (constraints?.maxHeight) {
      final h? when h.isFinite => h < maxH ? h : maxH,
      _ => maxH,
    },
  );
  return showBlurModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    constraints: merged,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor ?? FolioColors.bgPanel,
    shape: shape ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
    builder: builder,
  );
}

/// 透明系统 barrier + 随 sheet [animation] 淡入的模糊遮罩。
class BlurModalBottomSheetRoute<T> extends ModalBottomSheetRoute<T> {
  BlurModalBottomSheetRoute({
    required super.builder,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.constraints,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    required super.isScrollControlled,
    super.scrollControlDisabledMaxHeightRatio,
    super.settings,
    super.requestFocus,
    super.transitionAnimationController,
    super.anchorPoint,
    super.useSafeArea,
    super.sheetAnimationStyle,
  }) : super(modalBarrierColor: Colors.transparent);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: FadeTransition(
            opacity: animation,
            child: const SizedBox.expand(child: BlurScrim()),
          ),
        ),
        super.buildPage(context, animation, secondaryAnimation),
      ],
    );
  }
}
