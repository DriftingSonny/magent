import 'package:flutter/foundation.dart';

import 'chat_message.dart';

/// 一次会话（对话）。
///
/// 每个会话拥有独立的标题与消息列表，可并行保存多组对话，
/// 通过 [StorageService] 以 JSON 形式持久化到 SharedPreferences。
@immutable
class Conversation {
  final String id;

  /// 会话标题。首次发送消息时由首条用户消息自动生成，也可手动重命名。
  final String title;

  final DateTime createdAt;

  /// 最近一次更新时间，用于会话列表排序。
  final DateTime updatedAt;

  final List<ChatMessageModel> messages;

  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messages = const [],
  });

  /// 新会话的默认标题。
  static const String defaultTitle = '新对话';

  Conversation copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ChatMessageModel>? messages,
  }) => Conversation(
    id: id ?? this.id,
    title: title ?? this.title,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    messages: messages ?? this.messages,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] as List? ?? const [];
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String? ?? defaultTitle,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: rawMessages
          .map(
            (e) =>
                ChatMessageModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
    );
  }
}
