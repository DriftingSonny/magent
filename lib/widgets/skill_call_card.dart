import 'package:flutter/material.dart';

import '../models/chat_message.dart';

/// 工具调用过程卡片：展示 skill 名、参数、状态、结果摘要。
class SkillCallCard extends StatelessWidget {
  final ToolCallInfo info;
  const SkillCallCard({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusInfo = _statusInfo(info.status, theme);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: statusInfo.bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusInfo.borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusInfo.icon, color: statusInfo.fgColor, size: 18),
                const SizedBox(width: 6),
                Text(
                  '调用技能: ${info.skillName}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '参数: ${info.arguments}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (info.result != null) ...[
              const SizedBox(height: 6),
              Text(
                '结果: ${info.result}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  ({IconData icon, Color bgColor, Color borderColor, Color fgColor})
  _statusInfo(ToolCallStatus s, ThemeData theme) {
    switch (s) {
      case ToolCallStatus.pending:
      case ToolCallStatus.running:
        return (
          icon: Icons.hourglass_top,
          // 3.27 起 withOpacity deprecated，用 withValues(alpha:)。
          bgColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
          borderColor: theme.colorScheme.secondary,
          fgColor: theme.colorScheme.onSecondaryContainer,
        );
      case ToolCallStatus.success:
        return (
          icon: Icons.check_circle,
          bgColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
          borderColor: theme.colorScheme.primary,
          fgColor: theme.colorScheme.onPrimaryContainer,
        );
      case ToolCallStatus.failed:
        return (
          icon: Icons.error,
          bgColor: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
          borderColor: theme.colorScheme.error,
          fgColor: theme.colorScheme.onErrorContainer,
        );
      }
  }
}
