import 'package:material_ui/material_ui.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/dialog/blur_dialog_scaffold.dart';

/// 确认对话框。点遮罩关闭时返回 `false`。
abstract final class ConfirmDialog {
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    String? message,
    String cancelText = '取消',
    String confirmText = '确定',
    bool destructive = false,
    bool barrierDismissible = true,
  }) {
    return showFolioDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx, animation) {
        return BlurDialogScaffold(
          animation: animation,
          onBarrierTap: barrierDismissible ? () => Navigator.of(ctx).pop(false) : null,
          panelConstraints: BoxConstraints.tightFor(width: MediaQuery.sizeOf(ctx).width * 0.86),
          child: _ConfirmBody(
            title: title,
            message: message,
            cancelText: cancelText,
            confirmText: confirmText,
            destructive: destructive,
          ),
        );
      },
    );
  }
}

class _ConfirmBody extends StatelessWidget {
  const _ConfirmBody({
    required this.title,
    required this.cancelText,
    required this.confirmText,
    required this.destructive,
    this.message,
  });

  final String title;
  final String? message;
  final String cancelText;
  final String confirmText;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: folioDisplay(size: 20)),
        if (message != null) ...[
          const SizedBox(height: 12),
          Text(message!, style: const TextStyle(color: FolioColors.inkMuted, height: 1.4)),
        ],
        const SizedBox(height: 20),
        FolioDialogActions(
          cancelText: cancelText,
          confirmText: confirmText,
          destructive: destructive,
          onCancel: () => Navigator.of(context).pop(false),
          onConfirm: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

class FolioDialogActions extends StatelessWidget {
  const FolioDialogActions({
    super.key,
    required this.cancelText,
    required this.confirmText,
    required this.onCancel,
    required this.onConfirm,
    this.destructive = false,
    this.busy = false,
  });

  final String cancelText;
  final String confirmText;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final bool destructive;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(88, 40)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const WidgetStatePropertyAll(StadiumBorder()),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          style: buttonStyle,
          onPressed: busy ? null : onCancel,
          child: Text(cancelText),
        ),
        const SizedBox(width: 8),
        FilledButton(
          style: buttonStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(destructive ? FolioColors.danger : FolioColors.copper),
            foregroundColor: const WidgetStatePropertyAll(Color(0xFF1A1208)),
          ),
          onPressed: busy ? null : onConfirm,
          child: Text(confirmText),
        ),
      ],
    );
  }
}
