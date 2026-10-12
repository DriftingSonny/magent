import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';
import '../widgets/skill_call_card.dart';
import '../widgets/typing_indicator.dart';
import 'knowledge_screen.dart';
import 'settings_screen.dart';
import 'skills_screen.dart';

/// 主聊天页。
///
/// 左侧抽屉管理多会话，正文区展示当前会话消息。
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      // 多会话列表抽屉。
      drawer: _ConversationDrawer(chat: chat),
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(chat.currentTitle, overflow: TextOverflow.ellipsis),
            ),
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
          if (chat.isStreaming)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: '停止生成',
              onPressed: chat.stopStreaming,
            ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: '新建对话',
            onPressed: () => chat.newConversation(),
          ),
          IconButton(
            icon: const Icon(Icons.extension_outlined),
            tooltip: '业务技能',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SkillsScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: '知识库',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const KnowledgeScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空当前对话',
            onPressed: chat.isStreaming
                ? null
                : () => _confirmClear(context, chat),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
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
                    Icon(
                      Icons.error,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        chat.error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
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
                    Icon(
                      Icons.info,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '尚未配置 API Key，配置后即可对话',
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
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
                          Icon(
                            Icons.chat_bubble_outline,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          Text('开始对话吧', style: theme.textTheme.titleMedium),
                          if (chat.ragEnabled) ...[
                            const SizedBox(height: 4),
                            Text(
                              'RAG 已启用，AI 会参考知识库回答',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            '提示：右键或长按消息可复制 / 回退 / 删除',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: false,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount:
                        chat.messages.length + (chat.isStreaming ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == chat.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(8),
                          child: TypingIndicator(),
                        );
                      }
                      final m = chat.messages[i];
                      if (m.role == ChatRole.toolCall &&
                          m.toolCallInfo != null) {
                        return SkillCallCard(info: m.toolCallInfo!);
                      }
                      return MessageBubble(
                        message: m,
                        actionsEnabled: !chat.isStreaming,
                        onAction: (action) =>
                            _onMessageAction(context, chat, m, action),
                      );
                    },
                  ),
          ),
          ChatInput(
            disabled: chat.isStreaming || !chat.isConfigured,
            isStreaming: chat.isStreaming,
            prefillText: chat.pendingInput,
            onPrefillConsumed: chat.consumePendingInput,
            onSend: (text) => chat.send(text),
            onStop: chat.stopStreaming,
          ),
        ],
      ),
    );
  }

  /// 消息操作菜单的分发。
  Future<void> _onMessageAction(
    BuildContext context,
    ChatProvider chat,
    ChatMessageModel message,
    MessageAction action,
  ) async {
    switch (action) {
      case MessageAction.copy:
        await Clipboard.setData(ClipboardData(text: message.content));
        if (context.mounted) {
          _toast(context, '已复制');
        }
        break;
      case MessageAction.delete:
        await chat.deleteMessage(message.id);
        break;
      case MessageAction.rollback:
        // 回退仅对用户消息开放：撤回该提问及其后的所有消息，
        // 并把原文回填到输入框，方便修改后重新发送。
        await chat.rollbackTo(message.id);
        if (context.mounted) {
          _toast(context, '已回退，原文已填入输入框');
        }
        break;
    }
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
      );
  }

  void _confirmClear(BuildContext context, ChatProvider chat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空当前对话'),
        content: const Text('确定清空当前会话的所有消息？（会话本身保留）'),
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

/// 会话列表抽屉：新建 / 切换 / 重命名 / 删除。
class _ConversationDrawer extends StatelessWidget {
  final ChatProvider chat;
  const _ConversationDrawer({required this.chat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conversations = chat.conversations;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    chat.newConversation();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('新建对话'),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: conversations.length,
                itemBuilder: (_, i) {
                  final c = conversations[i];
                  final selected = c.id == chat.currentConversationId;
                  return ListTile(
                    selected: selected,
                    selectedTileColor: theme.colorScheme.secondaryContainer
                        .withValues(alpha: 0.4),
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _formatTime(c.updatedAt),
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () {
                      chat.openConversation(c.id);
                      Navigator.of(context).pop();
                    },
                    trailing: PopupMenuButton<String>(
                      tooltip: '更多',
                      onSelected: (value) {
                        if (value == 'rename') {
                          _rename(context, c);
                        } else if (value == 'delete') {
                          _confirmDeleteConversation(context, c);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _rename(BuildContext context, Conversation c) {
    final ctrl = TextEditingController(text: c.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '输入新标题'),
          onSubmitted: (_) {
            chat.renameConversation(c.id, ctrl.text);
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () {
              chat.renameConversation(c.id, ctrl.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteConversation(BuildContext context, Conversation c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定删除「${c.title}」？该对话的全部消息将一并移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () {
              chat.deleteConversation(c.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  /// 简单的相对时间展示（避免引入 intl 依赖）。
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    final t = time.toLocal();
    return '${t.year}-${_two(t.month)}-${_two(t.day)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}
