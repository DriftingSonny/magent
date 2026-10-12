import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/knowledge_provider.dart';

/// 知识库管理页：上传文档、列表、删除。
class KnowledgeScreen extends StatelessWidget {
  const KnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KnowledgeProvider>();
    final docs = provider.docs;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('知识库')),
      body: Column(
        children: [
          if (provider.isIndexing)
            Container(
              // withOpacity 自 Flutter 3.27 起标记 deprecated，
              // 推荐用 withValues(alpha:) 避免精度损失。
              color: theme.colorScheme.secondaryContainer.withValues(
                alpha: 0.5,
              ),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '正在解析、切片、生成向量并入库…',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          if (provider.error != null)
            Material(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.error,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        provider.error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: provider.clearError,
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: docs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 8),
                          const Text('知识库为空'),
                          const SizedBox(height: 4),
                          Text(
                            '上传公司指引类文档，AI 回答时自动参考',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          const Text('支持: md / txt / pdf / docx / xlsx / csv'),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: docs.length,
                    // 多个未使用形参时 lint 建议 '_' 而非 '__'。
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      return ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(d.fileName),
                        subtitle: Text(
                          '${d.type.toUpperCase()} · ${d.chunkCount} chunks · ${d.uploadedAt.toLocal()}',
                          style: theme.textTheme.bodySmall,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _confirmDelete(
                            context,
                            provider,
                            d.id,
                            d.fileName,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: provider.isIndexing
            ? null
            : () => _pickAndUpload(context, provider),
        icon: const Icon(Icons.upload_file),
        label: const Text('上传文档'),
      ),
    );
  }

  Future<void> _pickAndUpload(
    BuildContext context,
    KnowledgeProvider provider,
  ) async {
    // file_picker 13.x 起 FilePicker.platform getter 移除，
    // pickFiles 改为静态方法直接调用，返回 List<PlatformFile>（不再是 FilePickerResult）。
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['md', 'txt', 'pdf', 'docx', 'xlsx', 'csv'],
    );
    if (result.isEmpty) return;
    final path = result.single.path;
    if (path == null) return;

    final ok = await provider.uploadAndIndex(path);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败: ${provider.error ?? "未知错误"}')),
      );
    }
  }

  void _confirmDelete(
    BuildContext context,
    KnowledgeProvider provider,
    String id,
    String name,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从知识库删除'),
        content: Text('确定删除「$name」？向量索引也会一并移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () {
              provider.delete(id);
              Navigator.of(ctx).pop();
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
