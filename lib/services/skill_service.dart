import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../models/skill.dart';
import 'rag_service.dart';

/// Skill 管理与执行服务。
///
/// - [toToolSpecs]：把启用的 skills 转成 function calling 的 tool schema。
/// - [execute]：执行单个 skill。发起 HTTP POST 到 [Skill.webhookUrl]，
///   若 [Skill.linkKnowledgeBase] 为 true，先检索知识库拼进 body。
class SkillService {
  SkillService._();
  static final SkillService _instance = SkillService._();
  factory SkillService() => _instance;

  final _rag = RagService();

  /// 当前启用的 skills。
  List<Skill> enabled(List<Skill> all) =>
      all.where((s) => s.enabled).toList();

  /// 转成 function calling 工具规格（OpenAI tools 协议）。
  List<Map<String, dynamic>> toToolSpecs(List<Skill> all) =>
      enabled(all)
          .map((s) => {
                'type': 'function',
                'function': {
                  'name': s.name,
                  'description': s.description,
                  'parameters': s.parametersSchema,
                },
              })
          .toList();

  /// 执行 skill。返回 tool result 文本（回填给 AI）。
  ///
  /// 任何异常都被捕获，返回错误信息字符串（不抛异常给上层，
  /// 因为 AI 需要看到失败原因才能向用户解释）。
  Future<String> execute(
    Skill skill,
    Map<String, dynamic> arguments,
  ) async {
    try {
      final body = <String, dynamic>{...arguments};

      // 联动知识库：先检索，把结果作为额外字段塞进 webhook body。
      if (skill.linkKnowledgeBase) {
        final query = _renderQuery(skill.knowledgeQueryTemplate, arguments);
        final context = await _rag.retrieveContext(query);
        if (context.isNotEmpty) {
          body['__knowledge_context__'] = context;
        }
      }

      final res = await http
          .post(
            Uri.parse(skill.webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(
            Duration(seconds: AppConstants.webhookTimeoutSeconds),
          );

      if (res.statusCode < 200 || res.statusCode >= 300) {
        return '工具调用失败 (HTTP ${res.statusCode}): ${res.body}';
      }
      // 业务系统返回的内容（可能是 JSON 或纯文本）。
      // 直接把响应体作为 tool result 返回，AI 会自己解析。
      return res.body;
    } catch (e) {
      return '工具调用异常: $e';
    }
  }

  /// 渲染检索 query 模板。
  /// 模板形如 "表单审核指引 {form_type}"，用 arguments 中的值替换 {key}。
  /// 无模板时用所有 arguments 值拼接。
  String _renderQuery(String? template, Map<String, dynamic> args) {
    if (template == null || template.isEmpty) {
      return args.values.map((v) => v.toString()).join(' ');
    }
    return template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (m) => args[m.group(1)]?.toString() ?? '',
    );
  }
}
