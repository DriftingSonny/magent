import 'package:flutter/foundation.dart';
// langchain_core 0.5.0 起顶层入口：package:langchain_core/chat_models.dart
// 直接导出 ChatMessage / ChatResult / AIChatMessageToolCall 等全部类型。
import 'package:langchain_core/chat_models.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/deepseek_service.dart';
import '../services/rag_service.dart';
import '../services/skill_service.dart';
import '../services/storage_service.dart';
import 'skill_provider.dart';

/// 对话状态管理。
///
/// 编排：用户消息 → RAG 检索（可选）→ 工具暴露 → DeepSeek 流式 →
/// 工具调用循环 → 最终回复。
class ChatProvider extends ChangeNotifier {
  ChatProvider({required this.skillProvider});

  final SkillProvider skillProvider;
  final _rag = RagService();
  final _skillService = SkillService();
  final _uuid = const Uuid();

  List<ChatMessageModel> _messages = [];
  List<ChatMessageModel> get messages => List.unmodifiable(_messages);

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  String? _error;
  String? get error => _error;

  bool _ragEnabled = false;
  bool get ragEnabled => _ragEnabled;

  DeepSeekService? _service;
  DeepSeekService? get service => _service;

  /// 是否已配置 API Key。
  bool _configured = false;
  bool get isConfigured => _configured;

  // ---- 配置管理 ----

  /// App 启动后调用，加载已存的 API Key 和模型选择。
  Future<void> loadConfig() async {
    final apiKey = await StorageService().getApiKey();
    final model = StorageService().getModel();
    _ragEnabled = StorageService().isRagEnabled();
    if (apiKey != null && apiKey.isNotEmpty) {
      _service = DeepSeekService(apiKey: apiKey, model: model);
      _configured = true;
    }
    notifyListeners();
  }

  /// API Key 或模型变更后调用。
  Future<void> resetService(String apiKey, String model) async {
    _service = DeepSeekService(apiKey: apiKey, model: model);
    _configured = true;
    _ragEnabled = StorageService().isRagEnabled();
    notifyListeners();
  }

  Future<void> setRagEnabled(bool value) async {
    _ragEnabled = value;
    await StorageService().setRagEnabled(value);
    notifyListeners();
  }

  // ---- 对话 ----

  Future<void> send(String userPrompt) async {
    if (_isStreaming) return;
    if (!_configured || _service == null) {
      _error = '请先在设置中配置 API Key';
      notifyListeners();
      return;
    }

    _error = null;
    _isStreaming = true;

    // 1. 追加用户消息。
    final userMsg = ChatMessageModel(
      id: _uuid.v4(),
      role: ChatRole.user,
      content: userPrompt,
      timestamp: DateTime.now(),
    );
    _messages = [..._messages, userMsg];

    // 2. 创建 AI 占位消息（流式累积）。
    final aiMsgId = _uuid.v4();
    _messages = [
      ..._messages,
      ChatMessageModel(
        id: aiMsgId,
        role: ChatRole.assistant,
        content: '',
        timestamp: DateTime.now(),
        streaming: true,
      ),
    ];
    notifyListeners();

    try {
      // 3. RAG 检索（若启用）。
      String? ragContext;
      if (_ragEnabled && embeddingServiceReady()) {
        ragContext = await _rag.retrieveContext(userPrompt);
      }

      // 4. 工具 schema。
      final tools = _skillService.toToolSpecs(skillProvider.skills);

      // 5. 把已有历史（除当前用户/AI 占位）转成 langchain ChatMessage。
      final history = _toLangchainHistory(
        _messages.sublist(
          0,
          _messages.length - 2, // 去掉最后一条 user 和 AI 占位
        ),
      );

      // 6. 第一轮流式。
      final firstRound = await _runStreamRound(
        aiMsgId: aiMsgId,
        history: history,
        userPrompt: userPrompt,
        ragContext: ragContext,
        tools: tools,
      );

      // 7. 若 AI 触发了 tool_calls，执行 + 第二轮流式。
      if (firstRound.toolCalls != null && firstRound.toolCalls!.isNotEmpty) {
        await _handleToolCalls(
          toolCalls: firstRound.toolCalls!,
          history: history,
          userPrompt: userPrompt,
          ragContext: ragContext,
          tools: tools,
          aiMsgId: aiMsgId,
          assistantText: firstRound.text,
        );
      }

      // 8. 结束流式。
      _updateMessage(aiMsgId, (m) => m.copyWith(streaming: false));
    } catch (e) {
      _error = '对话失败: $e';
      // 把占位 AI 消息标记为错误。
      _updateMessage(
        aiMsgId,
        (m) => m.copyWith(
          role: ChatRole.error,
          content: '请求失败: $e',
          streaming: false,
        ),
      );
    } finally {
      _isStreaming = false;
      notifyListeners();
    }
  }

  /// 执行单轮流式，边收边更新 AI 消息。
  /// 返回该轮的完整文本 + tool_calls（若有）。
  Future<_RoundResult> _runStreamRound({
    required String aiMsgId,
    required List<ChatMessage> history,
    required String userPrompt,
    String? ragContext,
    required List<Map<String, dynamic>> tools,
  }) async {
    final buf = StringBuffer();
    List<Map<String, dynamic>>? toolCalls;

    await for (final chunk in _service!.streamChat(
      history: history,
      userPrompt: userPrompt,
      ragContext: ragContext,
      tools: tools,
    )) {
      // 文本片段：0.5.0 起 AIChatMessage.content 是 List<AIChatMessageContentBlock>，
      // 不再是 String。要用 contentAsString 取拼接后的纯文本。
      final text = chunk.output.contentAsString;
      if (text.isNotEmpty) {
        buf.write(text);
        _updateMessage(aiMsgId, (m) => m.copyWith(content: buf.toString()));
      }
      // tool_calls（流式中可能分段累积，这里取最后一帧的完整列表）
      // 0.5.0 起 AIChatMessageToolCall 自带 arguments（Map），无需再 jsonDecode。
      final tc = chunk.output.toolCalls;
      if (tc.isNotEmpty) {
        toolCalls = tc
            .map(
              (t) => <String, dynamic>{
                'name': t.name,
                'arguments': t.arguments,
              },
            )
            .toList();
      }
    }

    return _RoundResult(text: buf.toString(), toolCalls: toolCalls);
  }

  /// 处理 tool_calls：执行每个 skill → 追加 tool_call/tool_result 消息
  /// → 再发一轮让 AI 用结果总结。
  Future<void> _handleToolCalls({
    required List<Map<String, dynamic>> toolCalls,
    required List<ChatMessage> history,
    required String userPrompt,
    String? ragContext,
    required List<Map<String, dynamic>> tools,
    required String aiMsgId,
    required String assistantText,
  }) async {
    // 1. 在 langchain history 中追加 assistant 的 tool_call 消息。
    //    OpenAI 协议要求 tool_call_id 关联请求与结果。
    final toolResults = <ChatMessage>[];
    final toolCallInfos = <ToolCallInfo>[];

    for (var i = 0; i < toolCalls.length; i++) {
      final tc = toolCalls[i];
      final name = tc['name'] as String;
      final args = Map<String, dynamic>.from(tc['arguments'] as Map);

      // 在 UI 添加 tool_call 卡片消息。
      final callMsgId = _uuid.v4();
      _messages = [
        ..._messages,
        ChatMessageModel(
          id: callMsgId,
          role: ChatRole.toolCall,
          content: '',
          timestamp: DateTime.now(),
          toolCallInfo: ToolCallInfo(
            skillName: name,
            arguments: args,
            status: ToolCallStatus.running,
          ),
        ),
      ];
      notifyListeners();

      // 执行 skill。
      final skill = skillProvider.findByName(name);
      String resultText;
      ToolCallStatus status;
      if (skill == null) {
        resultText = '未找到名为 $name 的技能';
        status = ToolCallStatus.failed;
      } else {
        resultText = await _skillService.execute(skill, args);
        status =
            resultText.startsWith('工具调用') || resultText.startsWith('工具调用异常')
            ? ToolCallStatus.failed
            : ToolCallStatus.success;
      }

      // 更新 tool_call 卡片为完成状态。
      _updateMessage(
        callMsgId,
        (m) => m.copyWith(
          toolCallInfo: m.toolCallInfo!.copyWith(
            status: status,
            result: resultText,
          ),
        ),
      );

      toolCallInfos.add(
        ToolCallInfo(
          skillName: name,
          arguments: args,
          status: status,
          result: resultText,
        ),
      );

      // 把 tool result 加入 langchain history。
      // 0.5.0 起 ChatMessage.tool 命名参数是 name（不再是 toolName）。
      toolResults.add(
        ChatMessage.tool(
          content: resultText,
          toolCallId: 'call_$i',
          name: name,
        ),
      );
    }

    // 2. 在 AI 占位消息中追加"正在总结"提示。
    _updateMessage(
      aiMsgId,
      (m) => m.copyWith(content: '$assistantText\n\n（已调用工具，正在总结结果...）'),
    );

    // 3. 把 assistant 的 tool_call 也加入 history（OpenAI 协议要求）。
    // 0.5.0 起 ChatMessage.ai 接收 List<AIChatMessageContentBlock>，
    // 想直接给 String 文本要用 aiText 工厂。
    final newHistory = [
      ...history,
      ChatMessage.aiText(assistantText), // 简化处理：把 assistant 文本作为上一轮 AI 消息
      ...toolResults,
    ];

    // 4. 第二轮流式，让 AI 用 tool result 总结最终回复。
    //    第二轮用空 userPrompt（让 AI 自行总结），history 包含 tool results。
    //    实际 OpenAI 协议中，AI 看到 tool results 后会自动产出总结回复。
    final secondBuf = StringBuffer();
    try {
      await for (final chunk in _service!.streamChat(
        history: newHistory,
        userPrompt: '', // 第二轮无新用户输入
        ragContext: null,
        tools: const [], // 第二轮不再调工具，强制 AI 输出文本
      )) {
        final text = chunk.output.contentAsString;
        if (text.isNotEmpty) {
          secondBuf.write(text);
          _updateMessage(
            aiMsgId,
            (m) => m.copyWith(content: secondBuf.toString()),
          );
        }
      }
    } catch (e) {
      // 第二轮失败时，至少保留 tool 结果展示给用户。
      _updateMessage(
        aiMsgId,
        (m) => m.copyWith(content: '$assistantText\n\n工具调用完成，但总结失败: $e'),
      );
    }
  }

  // ---- 辅助 ----

  /// 把应用层消息转成 langchain ChatMessage 列表。
  /// 跳过 toolCall/toolResult/error 等特殊角色（这些通过单独的 history 项管理）。
  List<ChatMessage> _toLangchainHistory(List<ChatMessageModel> msgs) {
    final result = <ChatMessage>[];
    for (final m in msgs) {
      switch (m.role) {
        case ChatRole.user:
          result.add(ChatMessage.humanText(m.content));
          break;
        case ChatRole.assistant:
          if (m.content.isNotEmpty) {
            // 0.5.0 起 aiText 工厂替代 ai(String) 用法。
            result.add(ChatMessage.aiText(m.content));
          }
          break;
        case ChatRole.toolCall:
        case ChatRole.toolResult:
        case ChatRole.error:
          // 这些通过 _handleToolCalls 单独构造 history，这里跳过。
          break;
      }
    }
    return result;
  }

  void _updateMessage(
    String id,
    ChatMessageModel Function(ChatMessageModel) update,
  ) {
    _messages = _messages.map((m) => m.id == id ? update(m) : m).toList();
    notifyListeners();
  }

  void clearHistory() {
    _messages = [];
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

/// 一轮流式的结果。
class _RoundResult {
  final String text;
  final List<Map<String, dynamic>>? toolCalls;
  _RoundResult({required this.text, this.toolCalls});
}

/// 占位：检查 EmbeddingService 是否就绪。
/// 实际由 App 启动时异步初始化，这里通过尝试调用判断。
bool embeddingServiceReady() {
  // RagService 内部会判断 isInitialized，这里返回 true 让 RagService 自行降级。
  return true;
}
