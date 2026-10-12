import 'package:flutter/material.dart';

/// 输入框 + 发送/停止按钮。
///
/// - Enter 发送，Shift+Enter 换行。
/// - 流式输出时输入框禁用，按钮变为"停止"（暂停并保留已产出内容）。
/// - [prefillText] 用于"回退"后把原用户消息回填，方便修改重发。
class ChatInput extends StatefulWidget {
  final bool disabled;

  /// 是否正在流式输出。为 true 时发送按钮切换为停止按钮。
  final bool isStreaming;

  /// 需要回填到输入框的文本（回退操作触发）。
  final String? prefillText;

  /// 回填完成后的回调，用于清除 provider 中的待回填状态。
  final VoidCallback? onPrefillConsumed;

  final ValueChanged<String> onSend;

  /// 点击停止按钮时调用。
  final VoidCallback? onStop;

  const ChatInput({
    super.key,
    required this.disabled,
    required this.isStreaming,
    required this.onSend,
    this.prefillText,
    this.onPrefillConsumed,
    this.onStop,
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.prefillText;
    // 新的回填请求：写入控制器并把光标放到末尾。
    if (text != null && text != oldWidget.prefillText) {
      _ctrl.text = text;
      _ctrl.selection = TextSelection.collapsed(offset: text.length);
      _focus.requestFocus();
      widget.onPrefillConsumed?.call();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty || widget.disabled) return;
    widget.onSend(text);
    _ctrl.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              enabled: !widget.disabled,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: '输入消息... (Enter 发送, Shift+Enter 换行)',
              ),
              onSubmitted: (_) => _send(),
              onEditingComplete: () {},
              // 桌面端键盘事件
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.send,
            ),
          ),
          const SizedBox(width: 8),
          // 流式中：显示"停止"按钮，点击暂停生成。
          if (widget.isStreaming)
            IconButton.filledTonal(
              onPressed: widget.onStop,
              tooltip: '停止生成',
              icon: const Icon(Icons.stop),
            )
          else
            IconButton.filled(
              onPressed: widget.disabled ? null : _send,
              icon: const Icon(Icons.send),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
        ],
      ),
    );
  }
}
