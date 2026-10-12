import 'package:flutter/foundation.dart';

/// 应用层消息角色。
enum ChatRole { user, assistant, toolCall, toolResult, error }

/// 消息操作菜单项。
enum MessageAction { copy, rollback, delete }

/// 应用层消息数据类。
///
/// 与 langchain 的 [ChatMessage] 区分开，避免直接耦合序列化逻辑。
/// 在发送对话时由 [ChatProvider] 转换成 langchain 的 ChatMessage。
@immutable
class ChatMessageModel {
  final String id;
  final ChatRole role;
  final String content;

  /// 工具调用相关信息（仅 role=toolCall/toolResult 时有值）。
  final ToolCallInfo? toolCallInfo;

  final DateTime timestamp;

  /// 流式输出过程中标记是否仍在接收。
  final bool streaming;

  const ChatMessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCallInfo,
    this.streaming = false,
  });

  ChatMessageModel copyWith({
    String? id,
    ChatRole? role,
    String? content,
    ToolCallInfo? toolCallInfo,
    DateTime? timestamp,
    bool? streaming,
  }) =>
      ChatMessageModel(
        id: id ?? this.id,
        role: role ?? this.role,
        content: content ?? this.content,
        toolCallInfo: toolCallInfo ?? this.toolCallInfo,
        timestamp: timestamp ?? this.timestamp,
        streaming: streaming ?? this.streaming,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (toolCallInfo != null) 'toolCallInfo': toolCallInfo!.toJson(),
      };

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as String,
      role: ChatRole.values.byName(json['role'] as String),
      content: json['content'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
              DateTime.now(),
      toolCallInfo: json['toolCallInfo'] == null
          ? null
          : ToolCallInfo.fromJson(
              Map<String, dynamic>.from(json['toolCallInfo'] as Map),
            ),
      // 持久化恢复时一律视为非流式（重启后不应残留"正在输入"状态）。
      streaming: false,
    );
  }
}

/// 工具调用过程信息：状态、参数、结果。
@immutable
class ToolCallInfo {
  /// Skill 名称（function name）。
  final String skillName;

  /// AI 生成的参数（JSON 解码后的 Map）。
  final Map<String, dynamic> arguments;

  /// 执行状态：pending / running / success / failed。
  final ToolCallStatus status;

  /// 执行结果或错误信息。
  final String? result;

  const ToolCallInfo({
    required this.skillName,
    required this.arguments,
    required this.status,
    this.result,
  });

  ToolCallInfo copyWith({
    String? skillName,
    Map<String, dynamic>? arguments,
    ToolCallStatus? status,
    String? result,
  }) =>
      ToolCallInfo(
        skillName: skillName ?? this.skillName,
        arguments: arguments ?? this.arguments,
        status: status ?? this.status,
        result: result ?? this.result,
      );

  Map<String, dynamic> toJson() => {
        'skillName': skillName,
        'arguments': arguments,
        'status': status.name,
        if (result != null) 'result': result,
      };

  factory ToolCallInfo.fromJson(Map<String, dynamic> json) => ToolCallInfo(
        skillName: json['skillName'] as String? ?? '',
        arguments: Map<String, dynamic>.from(
          json['arguments'] as Map? ?? const {},
        ),
        status: ToolCallStatus.values.byName(
          json['status'] as String? ?? ToolCallStatus.failed.name,
        ),
        result: json['result'] as String?,
      );
}

enum ToolCallStatus { pending, running, success, failed }
