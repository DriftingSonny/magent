import 'dart:async';

import 'package:flutter/foundation.dart';
// langchain_core 0.5.0 起顶层入口：package:langchain_core/chat_models.dart
// 直接导出 ChatMessage / ChatResult / AIChatMessageToolCall 等全部类型。
import 'package:langchain_core/chat_models.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../services/deepseek_service.dart';
import '../services/rag_service.dart';
import '../services/skill_service.dart';
import '../services/storage_service.dart';
import 'skill_provider.dart';

/// 对话状态管理。
///
/// 编排：用户消息 → RAG 检索（可选）→ 工具暴露 → DeepSeek 流式 →
/// 工具调用循环 → 最终回复。
///
/// 支持多会话：所有消息都归属于某个 [Conversation]，流式更新按会话 id 路由，
/// 因此流式过程中即使切换会话也不会写错对话。
class ChatProvider extends ChangeNotifier {
  ChatProvider({required this.skillProvider});

  final SkillProvider skillProvider;
  final _rag = RagService();
  final _skillService = SkillService();
  final _uuid = const Uuid();

  // ---- 会话状态 ----

  List<Conversation> _conversations = [];
  List<Conversation> get conversations => List.unmodifiable(_conversations);

  String? _currentId;
  String? get currentConversationId => _currentId;

  Conversation? get currentConversation {
    final id = _currentId;
    if (id == null) return null;
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 当前会话的消息列表。
  List<ChatMessageModel> get messages =>
      List.unmodifiable(currentConversation?.messages ?? const []);

  /// 当前会话标题（用于 AppBar 展示）。
  String get currentTitle =>
      currentConversation?.title ?? Conversation.defaultTitle;

  // ---- 流式状态 ----

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  /// 当前正在进行的流订阅（用户点"暂停"时取消它）。
  StreamSubscription<ChatResult>? _activeSub;

  /// 当前轮的完成信号。取消订阅不会触发 onDone，
  /// 所以暂停时需要手动 complete，避免 send() 永久挂起。
  Completer<void>? _roundDone;

  /// 本轮是否已被用户暂停。
  bool _stopRequested = false;

  /// 回退操作要把文本回填到输入框的内容（由 UI 消费后清空）。
  String? _pendingInput;
  String? get pendingInput => _pendingInput;

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

  /// App 启动后调用，加载已存的 API Key、模型选择与会话列表。
  ///
  /// 读取 API Key 走 flutter_secure_storage（Windows 落在
  /// `%APPDATA%\<company>\<product>\flutter_secure_storage.dat`），
  /// 这里做容错：即使读取失败也只在内存中降级，不抛异常中断启动，
  /// 避免出现"明明存过 Key 却被要求重新输入"的情况。
  Future<void> loadConfig() async {
    _ragEnabled = StorageService().isRagEnabled();

    String? apiKey;
    // 个别环境首次访问应用数据目录会偶发失败，读取失败时少量重试。
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        apiKey = await StorageService().getApiKey();
        break; // 读取成功（即使为空）即结束重试
      } catch (e) {
        debugPrint('读取 API Key 失败(第 ${attempt + 1} 次): $e');
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }

    if (apiKey != null && apiKey.isNotEmpty) {
      _service = DeepSeekService(
        apiKey: apiKey,
        model: StorageService().getModel(),
      );
      _configured = true;
    }

    _loadConversations();
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

  // ---- 会话管理 ----

  /// 新建会话并切换过去。
  void newConversation() {
    final c = _newConversationObject();
    _conversations = [c, ..._conversations];
    _currentId = c.id;
    notifyListeners();
    unawaited(_persist());
  }

  /// 切换会话。流式过程中允许切换（流更新按会话 id 路由，不会串台）。
  void openConversation(String id) {
    if (!_conversations.any((c) => c.id == id)) return;
    if (_currentId == id) return;
    _currentId = id;
    notifyListeners();
    unawaited(_persist());
  }

  /// 删除会话。若删的是正在流式输出的会话，先暂停。
  Future<void> deleteConversation(String id) async {
    if (_isStreaming && id == _currentId) {
      await stopStreaming();
    }
    _conversations = _conversations.where((c) => c.id != id).toList();
    if (_conversations.isEmpty) {
      final c = _newConversationObject();
      _conversations = [c];
      _currentId = c.id;
    } else if (_currentId == id) {
      _currentId = _conversations.first.id;
    }
    notifyListeners();
    await _persist();
  }

  /// 重命名会话。
  Future<void> renameConversation(String id, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    final cur = _find(id);
    if (cur == null) return;
    _replaceConversation(cur.copyWith(title: trimmed));
    notifyListeners();
    await _persist();
  }

  /// 清空当前会话的消息（保留会话本身）。
  Future<void> clearHistory() async {
    if (_isStreaming) await stopStreaming();
    final cur = currentConversation;
    if (cur == null) return;
    _replaceConversation(
      cur.copyWith(messages: const [], updatedAt: DateTime.now()),
    );
    _error = null;
    notifyListeners();
    await _persist();
  }

  // ---- 对话 ----

  Future<void> send(String userPrompt) async {
    if (_isStreaming) return;
    if (!_configured || _service == null) {
      _error = '请先在设置中配置 API Key';
      notifyListeners();
      return;
    }
    final conv = currentConversation;
    if (conv == null) return;

    final convId = conv.id;
    // 发送前的历史（不含本轮 user / AI 占位）。
    final priorMessages = List<ChatMessageModel>.from(conv.messages);

    _error = null;
    _isStreaming = true;
    _stopRequested = false;

    // 1. 追加用户消息 + AI 占位消息。
    final aiMsgId = _uuid.v4();
    final appended = <ChatMessageModel>[
      ...priorMessages,
      ChatMessageModel(
        id: _uuid.v4(),
        role: ChatRole.user,
        content: userPrompt,
        timestamp: DateTime.now(),
      ),
      ChatMessageModel(
        id: aiMsgId,
        role: ChatRole.assistant,
        content: '',
        timestamp: DateTime.now(),
        streaming: true,
      ),
    ];
    // 首次对话时用首条用户输入生成标题。
    final newTitle = priorMessages.isEmpty ? _titleFrom(userPrompt) : null;
    _setMessagesIn(convId, appended, title: newTitle);
    notifyListeners();

    try {
      // 2. RAG 检索（若启用）。
      String? ragContext;
      if (_ragEnabled) {
        final ctx = await _rag.retrieveContext(userPrompt);
        ragContext = ctx.isEmpty ? null : ctx;
      }

      // 3. 工具 schema。
      final tools = _skillService.toToolSpecs(skillProvider.skills);

      // 4. 把已有历史转成 langchain ChatMessage。
      final history = _toLangchainHistory(priorMessages);

      // 5. 第一轮流式。
      final firstRound = await _streamRound(
        convId: convId,
        aiMsgId: aiMsgId,
        history: history,
        userPrompt: userPrompt,
        ragContext: ragContext,
        tools: tools,
      );

      // 6. 若 AI 触发了 tool_calls（且未被暂停），执行 + 第二轮流式。
      if (!_stopRequested &&
          firstRound.toolCalls != null &&
          firstRound.toolCalls!.isNotEmpty) {
        await _handleToolCalls(
          convId: convId,
          toolCalls: firstRound.toolCalls!,
          history: history,
          aiMsgId: aiMsgId,
          assistantText: firstRound.text,
        );
      }

      // 7. 结束流式。
      _updateMessageIn(convId, aiMsgId, (m) => m.copyWith(streaming: false));
    } catch (e) {
      _error = '对话失败: $e';
      _updateMessageIn(
        convId,
        aiMsgId,
        (m) => m.copyWith(
          role: ChatRole.error,
          content: '请求失败: $e',
          streaming: false,
        ),
      );
    } finally {
      _isStreaming = false;
      _stopRequested = false;
      _activeSub = null;
      _roundDone = null;
      notifyListeners();
      await _persist();
    }
  }

  /// 暂停：立即取消当前流式订阅，保留已产出的部分内容。
  Future<void> stopStreaming() async {
    if (!_isStreaming) return;
    _stopRequested = true;

    final sub = _activeSub;
    _activeSub = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {
        // 取消失败不阻塞后续状态恢复。
      }
    }
    final done = _roundDone;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }

  /// 删除单条消息。
  Future<void> deleteMessage(String messageId) async {
    if (_isStreaming) return;
    final cur = currentConversation;
    if (cur == null) return;
    _setMessages(
      cur.messages.where((m) => m.id != messageId).toList(),
      persist: true,
    );
    notifyListeners();
  }

  /// 回退：删除 [messageId] 及其之后的所有消息。
  ///
  /// 若目标是一条用户消息，会把它的文本回填到输入框，方便修改后重新发送。
  Future<void> rollbackTo(String messageId) async {
    if (_isStreaming) return;
    final cur = currentConversation;
    if (cur == null) return;
    final index = cur.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;

    final target = cur.messages[index];
    if (target.role == ChatRole.user) {
      _pendingInput = target.content;
    }
    _setMessages(cur.messages.sublist(0, index), persist: true);
    notifyListeners();
  }

  /// UI 已把 [pendingInput] 应用到输入框后调用，清空待回填内容。
  void consumePendingInput() {
    _pendingInput = null;
  }

  // ---- 流式实现 ----

  /// 执行单轮流式，边收边更新目标会话的 AI 消息。
  ///
  /// 用 [StreamSubscription] + [Completer] 而非 `await for`，
  /// 这样用户点"暂停"时可以真正取消底层 HTTP 流。
  Future<_RoundResult> _streamRound({
    required String convId,
    required String aiMsgId,
    required List<ChatMessage> history,
    required String userPrompt,
    String? ragContext,
    required List<Map<String, dynamic>> tools,
  }) async {
    final buf = StringBuffer();
    List<Map<String, dynamic>>? toolCalls;
    final done = Completer<void>();
    _roundDone = done;

    final sub = _service!
        .streamChat(
          history: history,
          userPrompt: userPrompt,
          ragContext: ragContext,
          tools: tools,
        )
        .listen(
          (chunk) {
            // 文本片段：0.5.0 起 content 是 List<AIChatMessageContentBlock>，
            // 用 contentAsString 取拼接后的纯文本。
            final text = chunk.output.contentAsString;
            if (text.isNotEmpty) {
              buf.write(text);
              _updateMessageIn(
                convId,
                aiMsgId,
                (m) => m.copyWith(content: buf.toString()),
              );
            }
            // tool_calls：0.5.0 起 AIChatMessageToolCall 自带 arguments（Map）。
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
          },
          onError: (Object e, StackTrace st) {
            if (!done.isCompleted) done.completeError(e, st);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    _activeSub = sub;

    try {
      await done.future;
    } finally {
      if (identical(_roundDone, done)) _roundDone = null;
      if (identical(_activeSub, sub)) _activeSub = null;
      // 正常结束时订阅已 done，这里是 no-op；被暂停取消时确保资源释放。
      await sub.cancel();
    }

    return _RoundResult(text: buf.toString(), toolCalls: toolCalls);
  }

  /// 处理 tool_calls：执行每个 skill → 追加 tool_call 卡片消息
  /// → 再发一轮让 AI 用结果总结。
  Future<void> _handleToolCalls({
    required String convId,
    required List<Map<String, dynamic>> toolCalls,
    required List<ChatMessage> history,
    required String aiMsgId,
    required String assistantText,
  }) async {
    final toolResults = <ChatMessage>[];

    for (var i = 0; i < toolCalls.length; i++) {
      if (_stopRequested) break;

      final tc = toolCalls[i];
      final name = tc['name'] as String;
      final args = Map<String, dynamic>.from(tc['arguments'] as Map);

      // 在 UI 添加 tool_call 卡片消息。
      final callMsgId = _uuid.v4();
      _appendMessageIn(
        convId,
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
      );
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
      _updateMessageIn(
        convId,
        callMsgId,
        (m) => m.copyWith(
          toolCallInfo: m.toolCallInfo!.copyWith(
            status: status,
            result: resultText,
          ),
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

    if (_stopRequested) return;

    // 在 AI 占位消息中追加"正在总结"提示。
    _updateMessageIn(
      convId,
      aiMsgId,
      (m) => m.copyWith(content: '$assistantText\n\n（已调用工具，正在总结结果...）'),
    );

    // 把 assistant 文本 + tool results 加入 history（OpenAI 协议要求）。
    // 0.5.0 起 ChatMessage.ai 接收 List<AIChatMessageContentBlock>，
    // 直接给 String 用 aiText 工厂。
    final newHistory = <ChatMessage>[
      ...history,
      ChatMessage.aiText(assistantText),
      ...toolResults,
    ];

    // 第二轮流式，让 AI 用 tool result 总结最终回复。
    final secondBuf = StringBuffer();
    try {
      await _streamInto(
        convId: convId,
        aiMsgId: aiMsgId,
        history: newHistory,
        userPrompt: '', // 第二轮无新用户输入
        ragContext: null,
        tools: const [], // 第二轮不再调工具，强制 AI 输出文本
        buf: secondBuf,
      );
    } catch (e) {
      // 第二轮失败时，至少保留 tool 结果展示给用户。
      _updateMessageIn(
        convId,
        aiMsgId,
        (m) => m.copyWith(content: '$assistantText\n\n工具调用完成，但总结失败: $e'),
      );
    }
  }

  /// [_streamRound] 的简化变体：把文本累积到外部传入的 [buf]，忽略 tool_calls。
  Future<void> _streamInto({
    required String convId,
    required String aiMsgId,
    required List<ChatMessage> history,
    required String userPrompt,
    String? ragContext,
    required List<Map<String, dynamic>> tools,
    required StringBuffer buf,
  }) async {
    final done = Completer<void>();
    _roundDone = done;

    final sub = _service!
        .streamChat(
          history: history,
          userPrompt: userPrompt,
          ragContext: ragContext,
          tools: tools,
        )
        .listen(
          (chunk) {
            final text = chunk.output.contentAsString;
            if (text.isNotEmpty) {
              buf.write(text);
              _updateMessageIn(
                convId,
                aiMsgId,
                (m) => m.copyWith(content: buf.toString()),
              );
            }
          },
          onError: (Object e, StackTrace st) {
            if (!done.isCompleted) done.completeError(e, st);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    _activeSub = sub;

    try {
      await done.future;
    } finally {
      if (identical(_roundDone, done)) _roundDone = null;
      if (identical(_activeSub, sub)) _activeSub = null;
      await sub.cancel();
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

  // ---- 会话/消息的底层读写 ----

  Conversation? _find(String convId) {
    for (final c in _conversations) {
      if (c.id == convId) return c;
    }
    return null;
  }

  void _replaceConversation(Conversation c) {
    _conversations = _conversations.map((e) => e.id == c.id ? c : e).toList();
  }

  Conversation _newConversationObject() {
    final now = DateTime.now();
    return Conversation(
      id: _uuid.v4(),
      title: Conversation.defaultTitle,
      createdAt: now,
      updatedAt: now,
    );
  }

  void _loadConversations() {
    _conversations = StorageService().getConversations();
    final savedId = StorageService().getCurrentConversationId();
    if (_conversations.isEmpty) {
      final c = _newConversationObject();
      _conversations = [c];
      _currentId = c.id;
      unawaited(_persist());
    } else {
      _currentId = _conversations.any((c) => c.id == savedId)
          ? savedId
          : _conversations.first.id;
    }
  }

  /// 更新指定会话的消息列表（可选同时改标题）。
  void _setMessagesIn(
    String convId,
    List<ChatMessageModel> list, {
    bool touch = true,
    String? title,
  }) {
    final cur = _find(convId);
    if (cur == null) return;
    _replaceConversation(
      cur.copyWith(
        messages: list,
        title: title ?? cur.title,
        updatedAt: touch ? DateTime.now() : cur.updatedAt,
      ),
    );
  }

  /// 更新当前会话的消息列表。
  void _setMessages(
    List<ChatMessageModel> list, {
    bool persist = false,
    bool touch = true,
  }) {
    final cur = currentConversation;
    if (cur == null) return;
    _setMessagesIn(cur.id, list, touch: touch);
    if (persist) unawaited(_persist());
  }

  void _appendMessageIn(String convId, ChatMessageModel msg) {
    final cur = _find(convId);
    if (cur == null) return;
    _replaceConversation(cur.copyWith(messages: [...cur.messages, msg]));
  }

  void _updateMessageIn(
    String convId,
    String messageId,
    ChatMessageModel Function(ChatMessageModel) update,
  ) {
    final cur = _find(convId);
    if (cur == null) return;
    _replaceConversation(
      cur.copyWith(
        messages: cur.messages
            .map((m) => m.id == messageId ? update(m) : m)
            .toList(),
      ),
    );
    notifyListeners();
  }

  /// 用首条用户消息生成会话标题（取首行，截断到 20 字）。
  String _titleFrom(String text) {
    final firstLine = text.split('\n').first.trim();
    if (firstLine.isEmpty) return Conversation.defaultTitle;
    return firstLine.length <= 20
        ? firstLine
        : '${firstLine.substring(0, 20)}…';
  }

  Future<void> _persist() async {
    try {
      await StorageService().setConversations(_conversations);
      final id = _currentId;
      if (id != null) {
        await StorageService().setCurrentConversationId(id);
      }
    } catch (e) {
      // 磁盘写入失败（权限/沙箱等）不应中断对话流程，仅记录日志。
      debugPrint('保存会话失败: $e');
    }
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
