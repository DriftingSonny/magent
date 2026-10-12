/// 应用级常量
///
/// 集中管理 DeepSeek baseUrl、可选模型、存储 key、超时等配置，
/// 便于后续统一修改。
class AppConstants {
  AppConstants._();

  /// DeepSeek API 入口（OpenAI 兼容路径）。
  /// 与官方 langchain_deepseek Python 包保持一致。
  static const String deepseekBaseUrl = 'https://api.deepseek.com/v1';

  /// 默认选中模型（速度快、成本低，适合多数对话）。
  static const String defaultModel = 'deepseek-flash';

  /// 可选模型列表，用于设置页下拉切换。
  static const List<String> availableModels = [
    'deepseek-flash',
    'deepseek-v4-pro',
  ];

  /// 申请 API Key 的官方地址（设置页展示给用户）。
  static const String deepseekApiKeyUrl =
      'https://platform.deepseek.com/api_keys';

  /// 默认 system message，强制 AI 用中文回答。
  static const String defaultSystemMessage =
      '你是一个有帮助的中文助手。请用中文回答用户的问题。';

  /// RAG 检索默认参数。
  static const int ragTopK = 3;
  static const double ragThreshold = 0.3;

  /// 文本切片参数（针对中文指引类文档的经验值）。
  static const int chunkSize = 500;
  static const int chunkOverlap = 50;

  /// Webhook 调用超时（秒）。业务系统响应慢时避免长时间卡住。
  static const int webhookTimeoutSeconds = 30;

  /// 存储相关 key。
  static const String keyApiKey = 'deepseek_api_key';
  static const String keyModel = 'selected_model';
  static const String keyRagEnabled = 'rag_enabled';
  static const String keySkills = 'skills_json';
  static const String keyKnowledgeDocs = 'knowledge_docs_json';

  /// 多会话：全部会话列表 + 当前选中的会话 id。
  static const String keyConversations = 'conversations_json';
  static const String keyCurrentConversationId = 'current_conversation_id';
}
