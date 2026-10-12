import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/knowledge_doc.dart';
import 'document_loader.dart';
import 'embedding_service.dart';
import 'text_splitter.dart';

/// 知识库索引编排器。
///
/// 串联：文件 → 文本提取 → 切片 → embedding → 入库 → 元数据记录。
class KnowledgeIndexer {
  KnowledgeIndexer._();
  static final KnowledgeIndexer _instance = KnowledgeIndexer._();
  factory KnowledgeIndexer() => _instance;

  final _loader = DocumentLoader();
  final _splitter = TextSplitterService();
  final _embedding = EmbeddingService();
  final _uuid = const Uuid();

  /// 索引一个文件，返回元数据。
  ///
  /// 抛出 [UnsupportedError] 当格式不支持；抛出其他异常时调用方应展示错误。
  Future<KnowledgeDoc> indexFile(String path) async {
    final text = await _loader.extractText(path);
    if (text.trim().isEmpty) {
      throw StateError('文件内容为空或无法解析: $path');
    }
    final chunks = _splitter.split(text);
    if (chunks.isEmpty) {
      throw StateError('切片后无内容: $path');
    }
    final docId = _uuid.v4();
    await _embedding.addDocuments(chunks, docId);
    return KnowledgeDoc(
      id: docId,
      fileName: p.basename(path),
      type: path.toLowerCase().split('.').last,
      chunkCount: chunks.length,
      uploadedAt: DateTime.now(),
      sourcePath: path,
    );
  }

  /// 删除一个文档（同时从向量库移除其 chunks）。
  Future<void> deleteDoc(String docId) async {
    await _embedding.removeByDocId(docId);
  }
}
