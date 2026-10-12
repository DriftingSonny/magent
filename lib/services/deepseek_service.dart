// langchain_core 0.5.0 做了 "block-native" 重构，public 入口改成顶层文件：
//   旧：package:langchain_core/chat_models/chat_message.dart  ❌（子路径不再暴露）
//   新：package:langchain_core/chat_models.dart               ✅
// 同理 prompts 也用顶层 prompts.dart。
import 'package:langchain_core/chat_models.dart';
import 'package:langchain_core/prompts.dart';
// ToolSpec 自 langchain_core 0.5.0 起取代了 langchain_openai 的 ChatOpenAIToolSpec。
// ChatOpenAIOptions.tools 现在接收 List<ToolSpec>?。
import 'package:langchain_core/tools.dart';
import 'package:langchain_openai/langchain_openai.dart';

import '../core/constants.dart';

/// DeepSeek 对话服务。
///
/// 封装 langchain_openai 的 [ChatOpenAI]，baseUrl 指 DeepSeek。
/// 支持流式输出 + function calling。
///
/// 注意：function calling 的循环编排放在 [ChatProvider]，
/// 这里只负责单轮流式调用。
class DeepSeekService {
  final String apiKey;
  final String model;
  late final ChatOpenAI _chat;

  DeepSeekService({required this.apiKey, required this.model}) {
    _chat = ChatOpenAI(
      apiKey: apiKey,
      baseUrl: AppConstants.deepseekBaseUrl,
      defaultOptions: ChatOpenAIOptions(
        model: model,
        temperature: 0.7,
      ),
    );
  }

  /// 流式对话。
  ///
  /// [history] 不含本轮 user 消息（[userPrompt] 单独传）。
  /// [ragContext] 检索到的知识库参考信息，拼进 system。
  /// [tools] OpenAI tools 协议的 schema 列表，空表示不启用 function calling。
  ///
  /// 返回的流可能包含：
  /// - 文本片段（chunk.output.contentAsString 非空）
  /// - tool_calls（chunk.output.toolCalls 非空，由调用方处理）
  Stream<ChatResult> streamChat({
    required List<ChatMessage> history,
    required String userPrompt,
    String? ragContext,
    List<Map<String, dynamic>> tools = const [],
  }) async* {
    final systemParts = <String>[AppConstants.defaultSystemMessage];
    if (ragContext != null && ragContext.isNotEmpty) {
      systemParts.add('以下是相关参考信息，回答时优先参考：\n\n$ragContext');
    }
    final messages = <ChatMessage>[
      ChatMessage.system(systemParts.join('\n\n')),
      ...history,
      ChatMessage.humanText(userPrompt),
    ];
    final prompt = PromptValue.chat(messages);

    // 注意：tools 通过 options 传入。DeepSeek 兼容 OpenAI tools 协议。
    // langchain_openai 0.9.0 起 tools 直接接收 List<ToolSpec>，
    // ToolSpec 字段：name / description / inputJsonSchema（即原 parameters）。
    final opts = tools.isEmpty
        ? null
        : ChatOpenAIOptions(
            model: model,
            temperature: 0.7,
            tools: tools
                .map((t) {
                  final fn = t['function'] as Map;
                  return ToolSpec(
                    name: fn['name'] as String,
                    description:
                        fn['description'] as String? ?? '',
                    inputJsonSchema:
                        fn['parameters'] as Map<String, dynamic>,
                  );
                })
                .toList(growable: false),
          );

    await for (final chunk in _chat.stream(prompt, options: opts)) {
      yield chunk;
    }
  }

  /// 非流式调用（降级方案）。
  ///
  /// 当流式解析 tool_calls 困难时，可用此方法一次性拿到完整响应。
  Future<ChatResult> invoke({
    required List<ChatMessage> history,
    required String userPrompt,
    String? ragContext,
    List<Map<String, dynamic>> tools = const [],
  }) async {
    final systemParts = <String>[AppConstants.defaultSystemMessage];
    if (ragContext != null && ragContext.isNotEmpty) {
      systemParts.add('以下是相关参考信息，回答时优先参考：\n\n$ragContext');
    }
    final messages = <ChatMessage>[
      ChatMessage.system(systemParts.join('\n\n')),
      ...history,
      ChatMessage.humanText(userPrompt),
    ];
    final prompt = PromptValue.chat(messages);
    final opts = tools.isEmpty
        ? null
        : ChatOpenAIOptions(
            model: model,
            temperature: 0.7,
            tools: tools
                .map((t) {
                  final fn = t['function'] as Map;
                  return ToolSpec(
                    name: fn['name'] as String,
                    description:
                        fn['description'] as String? ?? '',
                    inputJsonSchema:
                        fn['parameters'] as Map<String, dynamic>,
                  );
                })
                .toList(growable: false),
          );
    return await _chat.invoke(prompt, options: opts);
  }
}
