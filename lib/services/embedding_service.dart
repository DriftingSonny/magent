import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_core_codespark/ai_core_codespark.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';

/// 本地 embedding 服务（单例）。
///
/// 封装 [ai_core_codespark]：
/// - 首次调用 [initialize] 自动下载 ~23MB 量化 MiniLM 模型并 SHA-256 校验缓存。
/// - 持有内存 [VectorStore]，并通过 JSON 文件持久化到 [getApplicationSupportDirectory]。
/// - 重启后 [_loadPersistedIndex] 恢复，无需重新 embedding。
class EmbeddingService {
  EmbeddingService._();
  static final EmbeddingService _instance = EmbeddingService._();
  factory EmbeddingService() => _instance;

  CodesparkEngine? _engine;
  VectorStore? _store;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// 必须在 App 启动后调用一次。首次会下载模型（耗时取决于网络）。
  Future<void> initialize() async {
    if (_initialized) return;
    _engine = CodesparkEngine(model: ModelCatalog.miniLmL6V2);
    await _engine!.initialize();
    _store = VectorStore();
    await _loadPersistedIndex();
    _initialized = true;
  }

  // ---- 编码 ----

  Future<Float32List> embed(String text) async {
    _ensureReady();
    return _engine!.embed(text);
  }

  Future<List<Float32List>> embedBatch(List<String> texts) async {
    _ensureReady();
    return _engine!.embedBatch(texts);
  }

  // ---- 索引管理 ----

  /// 添加文档的 chunks 到向量库。
  /// [docId] 用于后续按文档删除。
  Future<void> addDocuments(List<String> chunks, String docId) async {
    _ensureReady();
    final vectors = await embedBatch(chunks);
    for (var i = 0; i < chunks.length; i++) {
      _store!.add(
        VectorRecord(
          id: '$docId-$i',
          vector: vectors[i],
          metadata: {'docId': docId, 'text': chunks[i], 'index': i},
        ),
      );
    }
    await _persistIndex();
  }

  /// 检索与 [query] 最相关的 top-K chunks。
  /// 返回 `(text, score)` 元组列表。
  Future<List<({String text, double score})>> retrieve(
    String query, {
    int k = AppConstants.ragTopK,
    double threshold = AppConstants.ragThreshold,
  }) async {
    _ensureReady();
    final q = await embed(query);
    final hits = _store!.search(q, k: k, threshold: threshold);
    return hits
        .map((h) => (text: h.record.metadata['text'] as String, score: h.score))
        .toList();
  }

  /// 按文档 ID 删除其所有 chunks。
  Future<void> removeByDocId(String docId) async {
    _ensureReady();
    // codespark 的 VectorStore 没有内置按 metadata 过滤删除，
    // 这里通过重建 store 实现：保留不属于该 docId 的记录。
    final all = _store!.records;
    _store!.clear();
    for (final r in all) {
      if (r.metadata['docId'] != docId) {
        _store!.add(r);
      }
    }
    await _persistIndex();
  }

  /// 清空整个索引（用于调试或全部重置）。
  Future<void> clear() async {
    _ensureReady();
    _store!.clear();
    await _persistIndex();
  }

  // ---- 持久化 ----

  Future<String> _indexPath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}${Platform.pathSeparator}vector_index.json';
  }

  Future<void> _persistIndex() async {
    final path = await _indexPath();
    final file = File(path);
    // codespark 的 VectorStore 没有标准 toList() 方法，
    // 这里通过 records 遍历自行序列化。
    final records = _store!.records
        .map((r) => {'id': r.id, 'vector': r.vector, 'metadata': r.metadata})
        .toList();
    await file.writeAsString(jsonEncode({'records': records}));
  }

  Future<void> _loadPersistedIndex() async {
    final path = await _indexPath();
    final file = File(path);
    if (!await file.exists()) return;
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final records = decoded['records'] as List;
      for (final r in records) {
        final map = r as Map<String, dynamic>;
        _store!.add(
          VectorRecord(
            id: map['id'] as String,
            vector: List<double>.from(map['vector'] as List).toFloat32(),
            metadata: Map<String, dynamic>.from(map['metadata'] as Map),
          ),
        );
      }
    } catch (e) {
      // 持久化文件损坏时不阻塞启动，仅清空内存索引。
      _store!.clear();
    }
  }

  void _ensureReady() {
    if (!_initialized || _engine == null || _store == null) {
      throw StateError('EmbeddingService 未初始化，请先调用 initialize()');
    }
  }
}

/// 把 `List<double>` 转 `Float32List`。
extension _Float32Extension on List<double> {
  Float32List toFloat32() {
    final buf = Float32List(length);
    for (var i = 0; i < length; i++) {
      buf[i] = this[i];
    }
    return buf;
  }
}
