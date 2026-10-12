import 'package:flutter/foundation.dart';

/// 用户自定义的业务技能。
///
/// AI 通过 function calling 调用时，App 会发起 HTTP POST 到 [webhookUrl]。
/// 若 [linkKnowledgeBase] 为 true，调用前会先用 [knowledgeQueryTemplate]
/// 渲染检索 query，把知识库检索结果作为 `__knowledge_context__` 字段
/// 一并 POST 给业务系统。
@immutable
class Skill {
  /// 唯一 ID（uuid）。
  final String id;

  /// 函数名，英文 snake_case，如 `form_review`。AI 据此调用。
  final String name;

  /// 中文描述，AI 据此判断何时调用本技能。
  final String description;

  /// 参数 JSON Schema。AI 据此生成调用参数。
  /// 示例：
  /// ```
  /// {
  ///   "type": "object",
  ///   "properties": {
  ///     "form_id": {"type": "string", "description": "表单ID"}
  ///   },
  ///   "required": ["form_id"]
  /// }
  /// ```
  final Map<String, dynamic> parametersSchema;

  /// Webhook 接收地址。
  final String webhookUrl;

  /// 是否在执行前先检索知识库。
  final bool linkKnowledgeBase;

  /// 联动知识库时的检索模板，支持 {key} 占位。
  /// 如 `"表单审核指引 {form_type}"`，会用 arguments 中的值替换。
  /// 为空时用 arguments 所有值拼接作为检索 query。
  final String? knowledgeQueryTemplate;

  /// 是否启用（关闭后该 skill 不暴露给 AI）。
  final bool enabled;

  const Skill({
    required this.id,
    required this.name,
    required this.description,
    required this.parametersSchema,
    required this.webhookUrl,
    this.linkKnowledgeBase = false,
    this.knowledgeQueryTemplate,
    this.enabled = true,
  });

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    Map<String, dynamic>? parametersSchema,
    String? webhookUrl,
    bool? linkKnowledgeBase,
    String? knowledgeQueryTemplate,
    bool? enabled,
  }) =>
      Skill(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        parametersSchema: parametersSchema ?? this.parametersSchema,
        webhookUrl: webhookUrl ?? this.webhookUrl,
        linkKnowledgeBase: linkKnowledgeBase ?? this.linkKnowledgeBase,
        knowledgeQueryTemplate: knowledgeQueryTemplate ?? this.knowledgeQueryTemplate,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'parametersSchema': parametersSchema,
        'webhookUrl': webhookUrl,
        'linkKnowledgeBase': linkKnowledgeBase,
        'knowledgeQueryTemplate': knowledgeQueryTemplate,
        'enabled': enabled,
      };

  factory Skill.fromJson(Map<String, dynamic> json) => Skill(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        parametersSchema:
            Map<String, dynamic>.from(json['parametersSchema'] as Map),
        webhookUrl: json['webhookUrl'] as String,
        linkKnowledgeBase: (json['linkKnowledgeBase'] as bool?) ?? false,
        knowledgeQueryTemplate: json['knowledgeQueryTemplate'] as String?,
        enabled: (json['enabled'] as bool?) ?? true,
      );
}
