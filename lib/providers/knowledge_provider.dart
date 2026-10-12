import 'package:flutter/foundation.dart';

import '../models/knowledge_doc.dart';
import '../services/knowledge_indexer.dart';
import '../services/storage_service.dart';

/// 知识库状态管理。
///
/// 文档列表加载、上传索引、删除。
/// 上传是耗时操作（解析→切片→embedding），用 [_indexing] 标记状态，
/// UI 显示进度。
class KnowledgeProvider extends ChangeNotifier {
  KnowledgeProvider() {
    _docs = StorageService().getKnowledgeDocs();
  }

  List<KnowledgeDoc> _docs = [];
  List<KnowledgeDoc> get docs => List.unmodifiable(_docs);

  bool _indexing = false;
  bool get isIndexing => _indexing;

  String? _error;
  String? get error => _error;

  /// 上传并索引一个文件。
  /// 返回 true 表示成功，false 表示失败（[error] 含原因）。
  Future<bool> uploadAndIndex(String filePath) async {
    _indexing = true;
    _error = null;
    notifyListeners();

    try {
      final doc = await KnowledgeIndexer().indexFile(filePath);
      _docs = [..._docs, doc];
      await StorageService().setKnowledgeDocs(_docs);
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _indexing = false;
      notifyListeners();
    }
  }

  /// 删除一个文档（同时从向量库移除）。
  Future<void> delete(String docId) async {
    try {
      await KnowledgeIndexer().deleteDoc(docId);
      _docs = _docs.where((d) => d.id != docId).toList();
      await StorageService().setKnowledgeDocs(_docs);
    } catch (e) {
      _error = '删除失败: $e';
    } finally {
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
