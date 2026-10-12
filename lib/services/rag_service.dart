import 'embedding_service.dart';

/// RAG 检索服务。
///
/// 薄封装：把 query 向量化后从 [EmbeddingService] 取 top-K chunks，
/// 再格式化为可注入 system message 的参考文本。
class RagService {
  RagService._();
  static final RagService _instance = RagService._();
  factory RagService() => _instance;

  final _embedding = EmbeddingService();

  /// 检索并格式化返回。无结果时返回空字符串。
  Future<String> retrieveContext(String query) async {
    if (!_embedding.isInitialized) {
      return '';
    }
    try {
      final hits = await _embedding.retrieve(query);
      if (hits.isEmpty) return '';
      final parts = <String>[];
      for (var i = 0; i < hits.length; i++) {
        parts.add('[${i + 1}] ${hits[i].text}');
      }
      return parts.join('\n\n');
    } catch (_) {
      // RAG 失败不应阻塞对话，降级为无上下文。
      return '';
    }
  }

  /// 直接返回原始检索结果（带相似度分数，用于调试/展示）。
  Future<List<({String text, double score})>> retrieve(
    String query, {
    int k = 3,
  }) async {
    if (!_embedding.isInitialized) return [];
    try {
      return await _embedding.retrieve(query, k: k);
    } catch (_) {
      return [];
    }
  }
}
