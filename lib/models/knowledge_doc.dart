import 'package:flutter/foundation.dart';

/// 知识库文档元数据。
///
/// 记录每个上传到知识库的文件信息，与底层向量索引通过 [id] 关联。
@immutable
class KnowledgeDoc {
  /// 唯一 ID（uuid），用于关联向量索引中的 chunk。
  final String id;

  /// 文件名（含扩展名）。
  final String fileName;

  /// 文件类型（扩展名，小写）：md / txt / pdf / docx / xlsx / csv。
  final String type;

  /// 切片数量。
  final int chunkCount;

  /// 上传时间。
  final DateTime uploadedAt;

  /// 原始文件路径（便于后续重新索引；可选，用户删源文件后可能失效）。
  final String? sourcePath;

  const KnowledgeDoc({
    required this.id,
    required this.fileName,
    required this.type,
    required this.chunkCount,
    required this.uploadedAt,
    this.sourcePath,
  });

  KnowledgeDoc copyWith({
    String? id,
    String? fileName,
    String? type,
    int? chunkCount,
    DateTime? uploadedAt,
    String? sourcePath,
  }) =>
      KnowledgeDoc(
        id: id ?? this.id,
        fileName: fileName ?? this.fileName,
        type: type ?? this.type,
        chunkCount: chunkCount ?? this.chunkCount,
        uploadedAt: uploadedAt ?? this.uploadedAt,
        sourcePath: sourcePath ?? this.sourcePath,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'type': type,
        'chunkCount': chunkCount,
        'uploadedAt': uploadedAt.toIso8601String(),
        'sourcePath': sourcePath,
      };

  factory KnowledgeDoc.fromJson(Map<String, dynamic> json) => KnowledgeDoc(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        type: json['type'] as String,
        chunkCount: (json['chunkCount'] as num).toInt(),
        uploadedAt: DateTime.parse(json['uploadedAt'] as String),
        sourcePath: json['sourcePath'] as String?,
      );
}
