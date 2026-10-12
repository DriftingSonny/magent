import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/skill.dart';
import '../providers/skill_provider.dart';
import 'skill_edit_screen.dart';

/// Skill 列表页。CRUD + 启用开关。
class SkillsScreen extends StatelessWidget {
  const SkillsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SkillProvider>();
    final skills = provider.skills;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('业务技能')),
      body: skills.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.extension, size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: 8),
                    const Text('还没有自定义技能'),
                    const SizedBox(height: 4),
                    Text(
                      'AI 会根据意图自动调用你定义的技能',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: skills.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final s = skills[i];
                return ListTile(
                  leading: const Icon(Icons.extension),
                  title: Text(s.name),
                  subtitle: Text(
                    s.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Switch(
                    value: s.enabled,
                    onChanged: (_) => provider.toggleEnabled(s.id),
                  ),
                  onTap: () => _edit(context, s),
                  onLongPress: () => _confirmDelete(context, provider, s),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('新增技能'),
      ),
    );
  }

  void _add(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SkillEditScreen()),
    );
  }

  void _edit(BuildContext context, Skill s) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SkillEditScreen(existing: s)),
    );
  }

  void _confirmDelete(
    BuildContext context,
    SkillProvider provider,
    Skill s,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除技能'),
        content: Text('确定删除「${s.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () {
              provider.remove(s.id);
              Navigator.of(ctx).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
