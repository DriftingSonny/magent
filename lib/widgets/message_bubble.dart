import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat_message.dart';

/// 消息气泡：用户右对齐蓝色，AI 左对齐灰色+Markdown，错误红色。
///
/// 交互：右键（桌面）或长按（触屏）弹出操作菜单——复制 / 回退 / 删除。
class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;

  /// 菜单是否可用（流式输出中禁用，避免与会话状态冲突）。
  final bool actionsEnabled;

  /// 菜单动作回调。
  final ValueChanged<MessageAction>? onAction;

  const MessageBubble({
    super.key,
    required this.message,
    this.actionsEnabled = true,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final isError = message.role == ChatRole.error;
    final enabled = actionsEnabled && onAction != null;

    return GestureDetector(
      // 默认为 deferToChild，保证 Markdown 内的链接点击仍可用。
      onLongPressStart: enabled
          ? (d) => _showActions(context, d.globalPosition)
          : null,
      onSecondaryTapUp: enabled
          ? (d) => _showActions(context, d.globalPosition)
          : null,
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: isError
                ? theme.colorScheme.errorContainer
                : isUser
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: isError
              ? Text(
                  message.content,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                )
              : isUser
              ? Text(message.content, style: theme.textTheme.bodyMedium)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.content.isEmpty && message.streaming)
                      const _TypingDots()
                    else
                      MarkdownBody(
                        data: message.content,
                        styleSheet: MarkdownStyleSheet(
                          p: theme.textTheme.bodyMedium,
                          code: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                    if (message.streaming && message.content.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: _Cursor(),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    // 只有用户消息支持"回退"：
    // AI 回复不应被回退（回退语义是"撤回这次提问、改完重发"），
    // 需要去掉 AI 回复时用"删除此条"即可。
    final canRollback = message.role == ChatRole.user;

    final selected = await showMenu<MessageAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<MessageAction>>[
        const PopupMenuItem(
          value: MessageAction.copy,
          height: 40,
          child: _MenuRow(icon: Icons.copy, label: '复制'),
        ),
        if (canRollback)
          const PopupMenuItem(
            value: MessageAction.rollback,
            height: 40,
            child: _MenuRow(icon: Icons.undo, label: '回退到此（删除此条及之后）'),
          ),
        const PopupMenuItem(
          value: MessageAction.delete,
          height: 40,
          child: _MenuRow(icon: Icons.delete_outline, label: '删除此条'),
        ),
      ],
    );
    if (selected != null) onAction?.call(selected);
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [Icon(icon, size: 18), const SizedBox(width: 8), Text(label)],
  );
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(
    duration: const Duration(milliseconds: 800),
    vsync: this,
  )..repeat();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.5, end: 1.0).animate(
              CurvedAnimation(
                parent: _ctrl,
                curve: Interval(i * 0.2, 1.0, curve: Curves.easeInOut),
              ),
            ),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _Cursor extends StatelessWidget {
  const _Cursor();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 16,
      margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
