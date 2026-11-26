import 'package:material_ui/material_ui.dart';
import 'package:folio/theme/folio_theme.dart';
import 'package:folio/widget/dialog/blur_dialog_scaffold.dart';
import 'package:folio/widget/dialog/confirm_dialog.dart';

/// 单行输入对话框。点遮罩或取消返回 `null`。
/// 输入框控制器由对话框自己持有，在路由卸掉之后才释放。
abstract final class FolioPromptDialog {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String initialText = '',
    String hintText = '',
    int? maxLength,
    String cancelText = '取消',
    String confirmText = '保存',
    bool barrierDismissible = true,
  }) {
    return showFolioDialog<String>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx, animation) {
        return _PromptDialog(
          animation: animation,
          title: title,
          initialText: initialText,
          hintText: hintText,
          maxLength: maxLength,
          cancelText: cancelText,
          confirmText: confirmText,
          barrierDismissible: barrierDismissible,
        );
      },
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.animation,
    required this.title,
    required this.initialText,
    required this.hintText,
    required this.cancelText,
    required this.confirmText,
    required this.barrierDismissible,
    this.maxLength,
  });

  final Animation<double> animation;
  final String title;
  final String initialText;
  final String hintText;
  final int? maxLength;
  final String cancelText;
  final String confirmText;
  final bool barrierDismissible;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _cancel() => Navigator.of(context).pop();

  void _confirm() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return BlurDialogScaffold(
      animation: widget.animation,
      onBarrierTap: widget.barrierDismissible ? _cancel : null,
      panelConstraints: BoxConstraints.tightFor(width: MediaQuery.sizeOf(context).width * 0.86),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: folioDisplay(size: 20)),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: widget.maxLength,
            style: const TextStyle(color: FolioColors.ink),
            decoration: InputDecoration(
              hintText: widget.hintText.isEmpty ? null : widget.hintText,
              counterText: '',
            ),
            onSubmitted: (_) => _confirm(),
          ),
          const SizedBox(height: 20),
          FolioDialogActions(
            cancelText: widget.cancelText,
            confirmText: widget.confirmText,
            onCancel: _cancel,
            onConfirm: _confirm,
          ),
        ],
      ),
    );
  }
}
