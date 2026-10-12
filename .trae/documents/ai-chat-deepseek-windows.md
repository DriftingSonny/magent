# AI 对话软件 - DeepSeek + Windows 桌面端（含 RAG 知识库 + 自定义 Skills）

## Summary

做一个 Windows 桌面 AI 对话软件：
- **对话**：调 DeepSeek API（OpenAI 兼容），流式输出，多轮上下文
- **知识库（RAG）**：本地 embedding 模型 + 向量检索，把公司指引类文档作为上下文注入
- **Skills（业务技能）**：用户在 App 内自定义技能，AI 通过 function calling 调用，执行方式为 HTTP Webhook，可选联动知识库
- **文件格式**：知识库支持 Markdown / TXT / PDF / Word(.docx) / Excel(.xlsx) / CSV
- **先做 Windows 端**

## Current State Analysis

当前项目（[pubspec.yaml](file:///c:/Users/19221/Desktop/magent/pubspec.yaml)）是标准 Flutter 模板：
- [lib/main.dart](file:///c:/Users/19221/Desktop/magent/lib/main.dart) 是默认计数器示例
- 依赖只有 `flutter` 和 `cupertino_icons`
- [analysis_options.yaml](file:///c:/Users/19221/Desktop/magent/analysis_options.yaml) 用默认 `flutter_lints`
- Windows 平台目录已存在（`windows/runner`），桌面默认有网络权限，无需改 runner
- SDK 约束：`sdk: ^3.11.5`（满足 langchain 0.9.0 要求的 Dart ≥3.8.0）

## 关键技术决策（已通过 Phase 1 探索确认）

| 决策点 | 选定方案 | 理由 |
|---|---|---|
| LLM 调用层 | `langchain_openai 0.9.0` 的 `ChatOpenAI`，`baseUrl='https://api.deepseek.com/v1'` | DeepSeek 是 OpenAI 兼容 API；langchain_openai 平台声明包含 Windows；原生支持 function calling（DeepSeek 兼容 OpenAI tools 协议） |
| Embedding 方案 | `ai_core_codespark 0.2.0`（量化 all-MiniLM-L6-V2，384 维，纯 Dart 离线） | DeepSeek 不提供 embeddings API；codespark 纯 Dart、Windows 支持、模型自动下载（~23MB）并 SHA-256 验证缓存、自带 VectorStore + JSON 持久化 + cosine/topK/MMR |
| RAG 编排 | `langchain 0.9.0` 的 `RecursiveCharacterTextSplitter` + 自实现 Retriever 适配 codespark | langchain 提供 TextSplitter 抽象，codespark 提供底层向量能力，二者职责清晰 |
| 文件解析 | MD/TXT 直接读字符串；PDF 用 `pdf_text`；DOCX 自解 zip+XML；XLSX 用 `excel`；CSV 用 `csv` | 各格式用最轻量可靠的纯 Dart 方案 |
| Skill 执行 | HTTP Webhook：用户填 URL，AI 调用时 App 发 POST，结果回填给 AI | 业务系统只需暴露 HTTP API，无需改 App 代码 |
| Skill 与知识库联动 | Skill 可选 `linkKnowledgeBase=true`，执行前先检索知识库拼进 webhook body | 满足"业务技能 + 公司指引"联动场景 |
| API Key 存储 | `flutter_secure_storage 11.0.0`（Windows 用 DPAPI） | 敏感数据加密 |
| 非敏感配置 | `shared_preferences` | 模型选择、主题等 |
| 知识库持久化 | `path_provider` 拿到本地目录 + codespark VectorStore JSON 持久化 | 重启后索引不丢 |
| 状态管理 | `provider`（ChangeNotifier） | 轻量、Flutter 原生风格 |
| UI 渲染 | `flutter_markdown` 渲染 AI 回复 | 支持代码块等 |

## 依赖添加

修改 [pubspec.yaml](file:///c:/Users/19221/Desktop/magent/pubspec.yaml) 的 `dependencies` 段：

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  # LLM 与 RAG 编排
  langchain: ^0.9.0               # TextSplitter、Retriever 抽象、Agent 框架
  langchain_core: ^0.9.0          # ChatMessage / PromptValue / Document 等核心类型
  langchain_openai: ^0.9.0        # ChatOpenAI（调 DeepSeek，OpenAI 兼容 + function calling）
  # 本地 Embedding（RAG）
  ai_core_codespark: ^0.2.0       # 量化 MiniLM ONNX，纯 Dart 离线，Windows 支持
  # 文件解析
  pdf_text: ^0.6.0                # PDF 文本提取
  excel: ^4.0.6                   # XLSX 解析
  csv: ^6.0.0                     # CSV 解析
  archive: ^4.0.0                 # DOCX = zip+xml，用 archive 解压
  xml: ^6.5.0                     # 解析 DOCX 的 word/document.xml
  # 存储
  flutter_secure_storage: ^11.0.0 # API Key 加密（Windows DPAPI）
  shared_preferences: ^2.3.0      # 模型选择等非敏感配置
  path_provider: ^2.1.4           # 知识库文档/向量索引本地存储路径
  # UI
  flutter_markdown: ^0.7.6+2      # AI 回复 Markdown 渲染
  file_picker: ^8.1.2             # 知识库上传文件选择
  # 通用
  uuid: ^4.5.1                    # 消息/Skill/文档 ID
  provider: ^6.1.2                # ChangeNotifier 状态管理
  http: ^1.2.0                    # Skill Webhook 调用
```

**说明**：
- `langchain_openai` 0.9.0 平台声明包含 Windows，依赖 `openai_dart`（纯 Dart + http），Windows 完全可用
- `ai_core_codespark` 平台声明包含 Windows，模型首次运行自动下载并缓存，包体积不变大
- DOCX 用 `archive` + `xml` 自解，避免依赖不维护的 docx 包
- Windows 桌面默认有网络权限，无需改 `windows/runner`

## 文件结构

```
lib/
  main.dart                          # 启动入口
  app.dart                           # MaterialApp + 主题 + Provider 注入
  core/
    constants.dart                   # DeepSeek baseUrl、默认模型、存储 key 等常量
    theme.dart                       # 蓝色调主题
  models/
    chat_message.dart                # 应用层消息（id/role/content/timestamp/toolCallInfo）
    skill.dart                       # Skill 数据类（id/name/description/parametersSchema/webhookUrl/linkKnowledgeBase/knowledgeQueryTemplate/enabled）
    knowledge_doc.dart               # 知识库文档元数据（id/fileName/type/chunkCount/uploadedAt）
  services/
    deepseek_service.dart            # ChatOpenAI 封装：流式对话 + function calling 循环
    storage_service.dart             # API Key + 模型偏好 + Skill 列表 持久化
    embedding_service.dart           # ai_core_codespark 封装：embed / embedBatch / VectorStore
    rag_service.dart                 # 检索：query→向量→topK chunks
    skill_service.dart               # Skill 注册表 + 执行（HTTP Webhook，可选联动 RAG）
    document_loader.dart             # 多格式文件 → 纯文本（MD/TXT/PDF/DOCX/XLSX/CSV）
    text_splitter.dart               # 调 langchain RecursiveCharacterTextSplitter 切片
    knowledge_indexer.dart           # 编排：文档→切片→embedding→入库→元数据记录
  providers/
    chat_provider.dart               # 对话状态 + RAG 注入 + Skill 调用循环
    skill_provider.dart              # Skill CRUD + 启用状态
    knowledge_provider.dart          # 文档上传/列表/删除/重建索引
  screens/
    chat_screen.dart                  # 主聊天页
    settings_screen.dart             # API Key + 模型切换
    skills_screen.dart               # Skill 列表
    skill_edit_screen.dart           # 单个 Skill 新增/编辑
    knowledge_screen.dart            # 知识库文档列表 + 上传
  widgets/
    message_bubble.dart              # 消息气泡（用户/AI/工具调用提示）
    chat_input.dart                  # 输入框 + 发送
    typing_indicator.dart            # AI 正在回复
    skill_call_card.dart             # 工具调用过程的可视化卡片
```

## 核心实现要点

### 1. `lib/services/storage_service.dart`
单例。封装：
- `flutter_secure_storage`：API Key、（可选）Webhook 鉴权 token
- `shared_preferences`：选中模型名、是否启用 RAG、Skill 列表的 JSON（Skill 本身不含敏感数据，可存 preferences；若 webhook 需鉴权 token 则放 secure_storage）
- 方法：`getApiKey/setApiKey`、`getModel/setModel`、`getSkills/setSkills`、`isRagEnabled/setRagEnabled`

### 2. `lib/services/embedding_service.dart`
封装 `ai_core_codespark`：

```dart
import 'package:ai_core_codespark/ai_core_codespark.dart';

class EmbeddingService {
  static final EmbeddingService _instance = EmbeddingService._();
  factory EmbeddingService() => _instance;
  EmbeddingService._();

  CodesparkEngine? _engine;
  VectorStore? _store;  // codespark 自带，内存 + JSON 持久化

  Future<void> initialize() async {
    if (_engine != null) return;
    _engine = CodesparkEngine(model: ModelCatalog.miniLmL6V2);
    await _engine!.initialize();  // 首次自动下载 ~23MB 模型
    _store = VectorStore();
    await _loadPersistedIndex();  // 从 path_provider 目录加载 JSON
  }

  Future<Float32List> embed(String text) => _engine!.embed(text);
  Future<List<Float32List>> embedBatch(List<String> texts) => _engine!.embedBatch(texts);

  Future<void> addDocuments(List<String> chunks, String docId) async {
    final vectors = await embedBatch(chunks);
    for (var i = 0; i < chunks.length; i++) {
      _store!.add(VectorRecord(
        id: '$docId-$i',
        vector: vectors[i],
        metadata: {'docId': docId, 'text': chunks[i], 'index': i},
      ));
    }
    await _persistIndex();
  }

  Future<List<({String text, double score})>> retrieve(String query, {int k = 3, double threshold = 0.3}) async {
    final q = await embed(query);
    final hits = _store!.search(q, k: k, threshold: threshold);
    return hits.map((h) => (text: h.record.metadata['text'] as String, score: h.score)).toList();
  }

  Future<void> removeByDocId(String docId) async { /* 过滤 _store 后持久化 */ }
  Future<void> _persistIndex() async { /* JSON 写入 path_provider 目录 */ }
  Future<void> _loadPersistedIndex() async { /* 从 JSON 恢复 _store */ }
}
```

**关键点**：codespark 的 `VectorStore` 支持 JSON 持久化（README 明确），用 `path_provider` 拿 `getApplicationSupportDirectory()` 存 `index.json`。重启后 `_loadPersistedIndex` 恢复，无需重新 embedding。

### 3. `lib/services/document_loader.dart`
按扩展名分发：

```dart
class DocumentLoader {
  Future<String> extractText(String path) async {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'txt':
      case 'md':
        return await File(path).readAsString();
      case 'pdf':
        return await _extractPdf(path);      // pdf_text: PDFTextExtractor(path).text
      case 'docx':
        return await _extractDocx(path);     // archive 解 zip → word/document.xml → xml 解析 → 取所有 <w:t> 文本
      case 'xlsx':
        return await _extractXlsx(path);     // excel: ExcelDecoder.decode(bytes) → 遍历 sheets/cells 拼文本
      case 'csv':
        return await File(path).readAsString();  // 直接读，CSV 本身就是文本
      default:
        throw UnsupportedError('不支持的格式: $ext');
    }
  }
}
```

**DOCX 解析细节**：`.docx` 是 zip 包，主文本在 `word/document.xml`，文本节点是 `<w:t>`。用 `archive` 解压取该文件，用 `xml` 包解析，遍历所有 `<w:t>` 拼成纯文本。表格单元格也走相同机制。

### 4. `lib/services/text_splitter.dart`
用 langchain 的 `RecursiveCharacterTextSplitter`：

```dart
import 'package:langchain/text_splitter.dart';

class TextSplitterService {
  final _splitter = RecursiveCharacterTextSplitter(
    chunkSize: 500,
    chunkOverlap: 50,
  );

  List<String> split(String text) => _splitter.splitText(text);
}
```

**参数**：chunkSize=500 字符（中文指引类文档经验值），overlap=50 保证上下文连续。后续可配置化。

### 5. `lib/services/knowledge_indexer.dart`
编排上传 → 解析 → 切片 → embedding → 入库：

```dart
class KnowledgeIndexer {
  Future<KnowledgeDoc> indexFile(String path) async {
    final text = await DocumentLoader().extractText(path);
    final chunks = TextSplitterService().split(text);
    final docId = uuid();
    await EmbeddingService().addDocuments(chunks, docId);
    return KnowledgeDoc(id: docId, fileName: basename(path), type: ext, chunkCount: chunks.length, uploadedAt: DateTime.now());
  }

  Future<void> deleteDoc(String docId) async {
    await EmbeddingService().removeByDocId(docId);
  }
}
```

### 6. `lib/services/deepseek_service.dart`
封装 `ChatOpenAI`，支持 function calling 循环：

```dart
class DeepSeekService {
  final String apiKey;
  final String model;
  late final ChatOpenAI _chat;

  DeepSeekService({required this.apiKey, required this.model}) {
    _chat = ChatOpenAI(
      apiKey: apiKey,
      baseUrl: 'https://api.deepseek.com/v1',
      defaultOptions: ChatOpenAIOptions(model: model, temperature: 0.7),
    );
  }

  /// 流式对话。toolsSchema 为空时不传 tools。
  /// onToolCall 回调在收到 tool_call 时触发，由调用方执行 skill 后把结果塞回 history 再继续流式。
  Stream<ChatResult> streamChat({
    required List<ChatMessage> history,
    required String userPrompt,
    String? ragContext,                  // RAG 检索到的参考信息，拼进 system
    List<ToolSpec> tools = const [],
  }) async* {
    final systemParts = <String>['你是一个有帮助的中文助手。请用中文回答用户的问题。'];
    if (ragContext != null && ragContext.isNotEmpty) {
      systemParts.add('以下是相关参考信息，回答时优先参考：\n\n$ragContext');
    }
    final messages = <ChatMessage>[
      ChatMessage.system(systemParts.join('\n\n')),
      ...history,
      ChatMessage.humanText(userPrompt),
    ];
    final prompt = PromptValue.chat(messages);
    await for (final chunk in _chat.stream(prompt, options: tools.isEmpty ? null : ChatOpenAIOptions(tools: tools))) {
      yield chunk;
    }
  }
}
```

**function calling 流程在 `chat_provider` 编排**：
1. 第一轮 streamChat 携带 tools schema
2. 收到 `tool_calls` → 暂停流式 → 调 `skill_service.execute(name, args)` → 拿结果
3. 把 tool result 作为 `ChatMessage.tool` 追加到 history，再发一轮 streamChat（不带 tools 或带但 AI 一般直接回答）
4. 第二轮流式文本作为最终回复输出
5. 如果 skill 配置 `linkKnowledgeBase=true`，在 execute 内部先调 `rag_service.retrieve` 拼进 webhook body

### 7. `lib/services/skill_service.dart`
管理 Skill 注册表 + 执行 HTTP Webhook：

```dart
class SkillService {
  final List<Skill> _skills = [];

  List<Skill> get enabled => _skills.where((s) => s.enabled).toList();

  List<ToolSpec> toToolSpecs() => enabled.map((s) => ToolSpec(
    name: s.name,
    description: s.description,
    parametersJsonSchema: s.parametersSchema,
  )).toList();

  Future<String> execute(Skill skill, Map<String, dynamic> args) async {
    Map<String, dynamic> body = {...args};
    if (skill.linkKnowledgeBase) {
      final query = _renderQuery(skill.knowledgeQueryTemplate, args);
      final hits = await RagService().retrieve(query, k: 3);
      body['__knowledge_context__'] = hits.map((h) => h.text).join('\n---\n');
    }
    final res = await http.post(
      Uri.parse(skill.webhookUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      return '工具调用失败: ${res.statusCode} ${res.body}';
    }
    return res.body;
  }

  String _renderQuery(String? template, Map args) {
    if (template == null) return args.values.join(' ');
    // 简单 {key} 占位替换
    return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => args[m.group(1)]?.toString() ?? '');
  }
}
```

### 8. `lib/models/skill.dart`
```dart
class Skill {
  final String id;
  final String name;                    // 函数名，英文 snake_case，如 form_review
  final String description;             // 中文描述，AI 据此判断何时调用
  final Map<String, dynamic> parametersSchema;  // JSON Schema
  final String webhookUrl;
  final bool linkKnowledgeBase;
  final String? knowledgeQueryTemplate; // 如 "表单审核指引 {form_type}"
  final bool enabled;

  // copyWith / fromJson / toJson
}
```

### 9. `lib/providers/chat_provider.dart`
`ChangeNotifier`，编排整个对话流程：

状态字段：
- `List<ChatMessageModel> _messages`
- `bool _isStreaming`
- `String? _error`
- `DeepSeekService? _service`（API Key 配置后懒加载）
- `bool _ragEnabled`

方法 `Future<void> send(String userPrompt)`：
1. 追加用户消息，创建空 AI 占位消息
2. 检查 `_ragEnabled`：若是，调 `RagService.retrieve(userPrompt, k=3)` 得 chunks
3. 取 `SkillService.toToolSpecs()` 作为 tools
4. 调 `deepseek_service.streamChat(history, userPrompt, ragContext: chunks, tools: tools)`
5. 流式累积到 AI 占位消息，`notifyListeners()`
6. 若收到 `tool_calls`：
   - 在消息列表追加一条"工具调用中"卡片消息（`skill_call_card` 展示）
   - 对每个 tool_call：`skill_service.execute(skill, args)` → 拿结果
   - 把 AI 的 tool_call 消息 + tool result 消息追加到 langchain history
   - 再发一轮 `streamChat`（history 含 tool result，不带 tools 或带），流式输出最终回复
7. `notifyListeners()` 持续更新 UI

方法：`clearHistory()`、`resetService()`（API Key/模型变更后重建）

### 10. UI 屏幕

- **`chat_screen.dart`**：Scaffold + AppBar（标题、设置入口、知识库入口、Skills 入口、清空按钮）。body 是 Column：Expanded(ListView 渲染 message_bubble + skill_call_card) + 底部 chat_input。未配置 API Key 时显示提示并跳设置页。
- **`settings_screen.dart`**：TextField(obscureText) 输入 API Key + Dropdown 选模型（deepseek-flash / deepseek-v4-pro）+ Switch 开关 RAG + 保存按钮。显示获取 Key 链接 `https://platform.deepseek.com/api_keys`。
- **`skills_screen.dart`**：ListView 展示所有 Skill，每条有启用开关、编辑、删除。FAB 新增。
- **`skill_edit_screen.dart`**：表单——name、description、parametersSchema（用 JSON 编辑器文本框，带校验）、webhookUrl、linkKnowledgeBase 开关、knowledgeQueryTemplate（联动时才显示）。
- **`knowledge_screen.dart`**：ListView 展示已索引文档（文件名/类型/chunk 数/上传时间），每条可删除。FAB 调 `file_picker` 选文件上传，上传时显示进度（解析→切片→embedding），完成后刷新列表。
- **`widgets/skill_call_card.dart`**：工具调用过程的可视化，展示 skill 名、参数、执行状态（调用中/成功/失败）、结果摘要。

### 11. `lib/main.dart` + `lib/app.dart`
main.dart：
```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}
```
app.dart：`MaterialApp` + 主题，用 `MultiProvider` 注入 `ChatProvider`、`SkillProvider`、`KnowledgeProvider`，首页 `ChatScreen`。App 启动时异步初始化 `EmbeddingService.initialize()`（不阻塞 UI，知识库相关功能就绪前显示"加载中"）。

## windows/runner 无需改动
Windows 桌面默认有网络权限。`flutter_secure_storage` 用 DPAPI，`ai_core_codespark` 的 ONNX 在 Windows 上 CPU 推理，均无需额外原生配置。

## Assumptions & Decisions

1. **不引入 firebase_ai / flutter_ai_toolkit**：firebase_ai 不支持 Windows。自建 UI + langchain_openai。
2. **不引入 langchain 主链 AgentExecutor**：自己编排 function calling 循环，更可控、更易可视化工具调用过程。
3. **Embedding 用 ai_core_codespark 而非 langchain 的 Embeddings 抽象**：codespark 一站式提供 engine + VectorStore + 持久化，无需再适配 langchain VectorStore 接口（适配反而引入复杂度）。
4. **DOCX 用 archive+xml 自解**：pub.dev 上 docx 解析包要么不维护要么重，自解 zip+xml 最稳。
5. **Skill 列表存 shared_preferences（JSON）**：Skill 本身不含敏感数据；若 webhook 需鉴权 token，token 单独存 secure_storage，Skill 配置只存 webhookUrl。当前 MVP 不做 webhook 鉴权，后续按需加。
6. **RAG 检索参数固定 k=3, threshold=0.3**：MVP 不做 UI 配置化，后续可加。
7. **执行阶段不自动运行 `flutter pub get` / `flutter run`**：用户规则，所有验证由用户手动执行。
8. **本地 embedding 模型首次下载需联网**：codespark 自动从其源下载 ~23MB 模型并 SHA-256 校验缓存。企业内网可自托管（README 提供覆盖 URL 机制），MVP 用默认源。

## Verification Steps（用户手动执行）

1. **拉取依赖**：`flutter pub get`
2. **运行 Windows 应用**：`flutter run -d windows`
3. **首次启动**：观察控制台，确认 codespark 模型下载完成（首次约 23MB，后续从缓存加载）
4. **配置 API Key**：设置页输入 DeepSeek Key，选模型，保存
5. **基础对话**：发"你好"，确认流式逐字显示；发需要 Markdown 的提问，确认代码块渲染
6. **知识库流程**：
   - 上传一个 .md 文件（如公司指引），观察控制台日志：解析 → 切片 → embedding → 入库
   - 开启 RAG 开关，发相关问题，确认 AI 回答引用了文档内容
   - 删除该文档，重发同一问题，确认回答不再引用
7. **Skills 流程**：
   - 在 Skills 页新增一个测试 skill：name=`get_form_status`，description="查询表单审核状态"，parametersSchema=`{"type":"object","properties":{"form_id":{"type":"string","description":"表单ID"}},"required":["form_id"]}`，webhookUrl 指向一个测试 endpoint（如 `https://httpbin.org/post` 或本地 mock）
   - 发"帮我查一下表单 FORM123 的状态"，确认 AI 触发 tool_call，UI 显示 skill_call_card，webhook 被调用，AI 用返回结果总结回复
   - 测试 `linkKnowledgeBase=true` 的 skill，确认 webhook body 含 `__knowledge_context__` 字段
8. **持久化**：重启 App，确认 API Key、模型选择、Skill 列表、知识库索引均保留
9. **错误路径**：故意填错 API Key、填错 webhookUrl、上传不支持的文件格式，确认 UI 有错误提示且不崩溃

## 风险与备注

- **langchain_openai 0.9.0 API 签名**：`ChatOpenAI` 构造器、`stream(PromptValue)` 返回 `Stream<ChatResult>`、`chunk.output.content` 取文本、`ChatOpenAIOptions(tools: ...)` 传 ToolSpec 列表，均来自官方文档站。若执行时发现字段名微调（如 `tools` 参数位置），按 IDE 提示修正。
- **DeepSeek function calling 兼容性**：DeepSeek API 兼容 OpenAI tools 协议（已在 platform.deepseek.com 文档确认），但流式返回 tool_calls 的 chunk 格式需实测；若流式难解析 tool_call，可降级为非流式调用（`_chat.invoke(prompt)`）拿到完整 response 再判断。
- **ai_core_codespark 0.2.0 较新**：API 可能仍在迭代。若 `VectorRecord`/`VectorStore` API 与示例不符，按实际包内 API 调整。
- **DOCX 表格/图片**：MVP 只提取正文 `<w:t>`，表格文本会提取但结构丢失，图片忽略。后续若需保留表格结构再增强。
- **PDF 扫描件**：`pdf_text` 只提取文本层，扫描件 PDF 无文本层会得到空字符串。MVP 不做 OCR，后续若需可加 `tesseract` 集成。
- **知识库规模**：codespark VectorStore 是内存 brute-force 搜索，适合数千 chunks 级别。若公司指引文档超万级 chunks，需换 FAISS/HNSW 等近似检索（后续优化项）。
- **不引入 Agent/RAG 的完整 langchain 链**：自己编排更清晰可视化，符合"自建 UI"方向。
