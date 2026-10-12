import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/skill.dart';
import '../providers/skill_provider.dart';

/// Skill 新增/编辑页。
class SkillEditScreen extends StatefulWidget {
  /// 传入 null 表示新增，否则编辑已有 skill。
  final Skill? existing;
  const SkillEditScreen({super.key, this.existing});

  @override
  State<SkillEditScreen> createState() => _SkillEditScreenState();
}

class _SkillEditScreenState extends State<SkillEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _params; // JSON Schema 文本
  late final TextEditingController _webhook;
  late final TextEditingController _tmpl;
  bool _linkKb = false;
  bool _enabled = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = widget.existing;
    _name = TextEditingController(text: s?.name ?? '');
    _desc = TextEditingController(text: s?.description ?? '');
    _params = TextEditingController(
      text: s == null
          ? '''{
  "type": "object",
  "properties": {
    "form_id": {"type": "string", "description": "表单ID"}
  },
  "required": ["form_id"]
}'''
          : const JsonEncoder.withIndent('  ').convert(s.parametersSchema),
    );
    _webhook = TextEditingController(text: s?.webhookUrl ?? '');
    _tmpl = TextEditingController(text: s?.knowledgeQueryTemplate ?? '');
    _linkKb = s?.linkKnowledgeBase ?? false;
    _enabled = s?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _params.dispose();
    _webhook.dispose();
    _tmpl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      // 解析 JSON Schema
      Map<String, dynamic> schema;
      try {
        final decoded = jsonDecode(_params.text);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('JSON Schema 必须是对象');
        }
        schema = decoded;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('参数 Schema JSON 解析失败: $e')),
          );
        }
        setState(() => _saving = false);
        return;
      }

      final provider = context.read<SkillProvider>();
      final existing = widget.existing;
      if (existing == null) {
        await provider.add(
          name: _name.text.trim(),
          description: _desc.text.trim(),
          parametersSchema: schema,
          webhookUrl: _webhook.text.trim(),
          linkKnowledgeBase: _linkKb,
          knowledgeQueryTemplate: _tmpl.text.trim().isEmpty ? null : _tmpl.text.trim(),
          enabled: _enabled,
        );
      } else {
        await provider.update(existing.copyWith(
          name: _name.text.trim(),
          description: _desc.text.trim(),
          parametersSchema: schema,
          webhookUrl: _webhook.text.trim(),
          linkKnowledgeBase: _linkKb,
          knowledgeQueryTemplate: _tmpl.text.trim().isEmpty ? null : _tmpl.text.trim(),
          enabled: _enabled,
        ));
      }
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 移除未使用的 theme 变量（原代码引入但 build 体内未引用）。
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? '编辑技能' : '新增技能')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称 (英文 snake_case)',
                hintText: 'form_review',
              ),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return '不能为空';
                if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(s)) {
                  return '只能小写字母/数字/下划线，且字母开头';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              decoration: const InputDecoration(
                labelText: '描述 (中文，告诉 AI 何时调用此技能)',
                hintText: '查询表单审核状态',
              ),
              maxLines: 2,
              validator: (v) => (v?.trim().isEmpty ?? true) ? '不能为空' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _params,
              decoration: const InputDecoration(
                labelText: '参数 Schema (JSON)',
                helperText: 'OpenAI tools 协议格式',
              ),
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              validator: (v) {
                try {
                  final d = jsonDecode(v ?? '');
                  if (d is! Map) return '必须是 JSON 对象';
                  return null;
                } catch (e) {
                  return 'JSON 解析失败: $e';
                }
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _webhook,
              decoration: const InputDecoration(
                labelText: 'Webhook URL',
                hintText: 'https://your-business-system/api/skill',
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return '不能为空';
                final uri = Uri.tryParse(s);
                if (uri == null || !uri.hasScheme) return '无效 URL';
                return null;
              },
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('联动知识库'),
              subtitle: const Text('执行前检索知识库，把结果作为 __knowledge_context__ 字段 POST'),
              value: _linkKb,
              onChanged: (v) => setState(() => _linkKb = v),
            ),
            if (_linkKb) ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _tmpl,
                decoration: const InputDecoration(
                  labelText: '检索模板 (可选)',
                  helperText: '支持 {key} 占位，如 "表单审核指引 {form_type}"',
                  hintText: '留空则用所有参数值拼接',
                ),
              ),
            ],
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('启用'),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(isEdit ? '保存' : '创建'),
          ),
        ),
      ),
    );
  }
}
