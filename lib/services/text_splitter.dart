// langchain 0.9.0 起只有一个顶层入口 package:langchain/langchain.dart，
// 旧的 package:langchain/text_splitter.dart 路径不存在。
// RecursiveCharacterTextSplitter 通过这个顶层入口导出。
import 'package:langchain/langchain.dart';

import '../core/constants.dart';

/// 文本切片服务。
///
/// 用 langchain 的 [RecursiveCharacterTextSplitter] 切片：
/// - chunkSize = 500 字符（中文指引文档经验值）
/// - overlap = 50 保证跨边界内容不丢
///
/// RecursiveCharacterTextSplitter 会先用 ["\n\n", "\n", "。", " "] 等分隔符
/// 递归切，尽量保持语义完整性。
class TextSplitterService {
  TextSplitterService._();
  static final TextSplitterService _instance = TextSplitterService._();
  factory TextSplitterService() => _instance;

  late final _splitter = RecursiveCharacterTextSplitter(
    chunkSize: AppConstants.chunkSize,
    chunkOverlap: AppConstants.chunkOverlap,
  );

  /// 把长文本切成 chunks 列表。
  List<String> split(String text) => _splitter.splitText(text);
}
