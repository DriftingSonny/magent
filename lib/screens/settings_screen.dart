import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../providers/chat_provider.dart';
import '../services/storage_service.dart';

/// 设置页：API Key、模型切换、RAG 开关。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _keyCtrl = TextEditingController();
  String _model = AppConstants.defaultModel;
  bool _ragEnabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await StorageService().getApiKey();
    _keyCtrl.text = key ?? '';
    _model = StorageService().getModel();
    _ragEnabled = StorageService().isRagEnabled();
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final key = _keyCtrl.text.trim();
      if (key.isEmpty) {
        await StorageService().deleteApiKey();
      } else {
        await StorageService().setApiKey(key);
      }
      await StorageService().setModel(_model);
      await StorageService().setRagEnabled(_ragEnabled);
      // 通知 ChatProvider 重建 service。
      // 注意：await 之后再访问 context 必须先做 mounted 检查。
      if (key.isNotEmpty) {
        if (!mounted) return;
        await context.read<ChatProvider>().resetService(key, _model);
        if (!mounted) return;
        await context.read<ChatProvider>().setRagEnabled(_ragEnabled);
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置已保存')));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('DeepSeek API Key', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          MarkdownBody(
            data: '从 [platform.deepseek.com](https://platform.deepseek.com/api_keys) 申请。仅本地保存（DPAPI 加密），不上传。',
            onTapLink: (text, href, title) async {
              if (href != null) {
                await Clipboard.setData(ClipboardData(text: href));
                // 在 build context 上检查 mounted，而不是 State.mounted。
                // Flutter 3.7+ 起 BuildContext 自带 mounted getter。
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制链接，请在浏览器打开')),
                  );
                }
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              hintText: 'sk-...',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            inputFormatters: [
              // 禁止首尾空白
              FilteringTextInputFormatter.deny(RegExp(r'^\s+|\s+$')),
            ],
          ),
          const SizedBox(height: 24),
          Text('模型', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _model,
            items: AppConstants.availableModels
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => _model = v);
            },
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('启用知识库 RAG'),
            subtitle: const Text('对话时自动检索知识库作为参考上下文'),
            value: _ragEnabled,
            onChanged: (v) => setState(() => _ragEnabled = v),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('保存'),
          ),
        ],
      ),
    );
  }
}

// url_launcher 未加入依赖，这里使用 launchUrlString 通过条件引入。
// 实际项目可改为：依赖 url_launcher ^6.3.0 或用flutter_markdown自带的link回调。
// 简化：暂时用占位实现（点击不打开），用户可手动复制。
