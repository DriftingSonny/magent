import 'package:flutter/material.dart';

/// 输入框 + 发送按钮。Enter 发送，Shift+Enter 换行。流式时禁用。
class ChatInput extends StatefulWidget {
  final bool disabled;
  final ValueChanged<String> onSend;
  const ChatInput({super.key, required this.disabled, required this.onSend});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

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
          IconButton.filled(
            onPressed: widget.disabled ? null : _send,
            icon: widget.disabled
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
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

// 桌面端 Enter 发送 / Shift+Enter 换行的快捷键，
// 通过 KeyboardListener 或 Shortcuts 实现。这里简化处理：
// TextField 默认 Enter 就是 submit，Shift+Enter 自然换行（multiline 模式下）。
