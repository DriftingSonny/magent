import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/chat_message.dart';

/// 消息气泡：用户右对齐蓝色，AI 左对齐灰色+Markdown，错误红色。
class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == ChatRole.user;
    final isError = message.role == ChatRole.error;

    return Align(
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
            ? Text(message.content, style: TextStyle(color: theme.colorScheme.onErrorContainer))
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
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
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
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
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
