import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';
import '../widgets/skill_call_card.dart';
import '../widgets/typing_indicator.dart';
import 'knowledge_screen.dart';
import 'settings_screen.dart';
import 'skills_screen.dart';

/// 主聊天页。
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('DeepSeek 对话'),
            const SizedBox(width: 8),
            if (chat.ragEnabled)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'RAG',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.extension_outlined),
            tooltip: '业务技能',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SkillsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: '知识库',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KnowledgeScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空对话',
            onPressed: chat.isStreaming
                ? null
                : () => _confirmClear(context, chat),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (chat.error != null)
            Material(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Icon(Icons.error, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chat.error!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: chat.clearError,
                    ),
                  ],
                ),
              ),
            ),
          if (!chat.isConfigured)
            Material(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info, color: theme.colorScheme.onSecondaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '请先在设置中配置 API Key',
                        style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                      child: const Text('去设置'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: chat.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 48, color: theme.colorScheme.outline),
                          const SizedBox(height: 8),
                          Text(
                            '开始对话吧',
                            style: theme.textTheme.titleMedium,
                          ),
                          if (chat.ragEnabled) ...[
                            const SizedBox(height: 4),
                            Text(
                              'RAG 已启用，AI 会参考知识库回答',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: false,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: chat.messages.length + (chat.isStreaming ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == chat.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: TypingIndicator(),
                        );
                      }
                      final m = chat.messages[i];
                      return m.role == ChatRole.toolCall && m.toolCallInfo != null
                          ? SkillCallCard(info: m.toolCallInfo!)
                          : MessageBubble(message: m);
                    },
                  ),
          ),
          ChatInput(
            disabled: chat.isStreaming || !chat.isConfigured,
            onSend: (text) => chat.send(text),
          ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, ChatProvider chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空对话'),
        content: const Text('确定清空所有消息？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () {
              chat.clearHistory();
              Navigator.of(ctx).pop();
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}
