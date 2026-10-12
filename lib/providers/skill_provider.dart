import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/skill.dart';
import '../services/storage_service.dart';

/// Skill 状态管理。
///
/// 加载/保存 Skill 列表、CRUD、启用切换。
/// [ChatProvider] 会通过 [skills] 拿到当前列表用于 function calling。
class SkillProvider extends ChangeNotifier {
  SkillProvider() {
    _skills = StorageService().getSkills();
  }

  List<Skill> _skills = [];
  List<Skill> get skills => List.unmodifiable(_skills);

  /// 启用的 skills（暴露给 AI 的）。
  List<Skill> get enabled => _skills.where((s) => s.enabled).toList();

  /// 新增 skill。返回新 ID。
  Future<String> add({
    required String name,
    required String description,
    required Map<String, dynamic> parametersSchema,
    required String webhookUrl,
    bool linkKnowledgeBase = false,
    String? knowledgeQueryTemplate,
    bool enabled = true,
  }) async {
    final id = const Uuid().v4();
    final s = Skill(
      id: id,
      name: name,
      description: description,
      parametersSchema: parametersSchema,
      webhookUrl: webhookUrl,
      linkKnowledgeBase: linkKnowledgeBase,
      knowledgeQueryTemplate: knowledgeQueryTemplate,
      enabled: enabled,
    );
    _skills = [..._skills, s];
    await _persist();
    return id;
  }

  /// 更新 skill。
  Future<void> update(Skill updated) async {
    _skills = _skills.map((s) => s.id == updated.id ? updated : s).toList();
    await _persist();
  }

  /// 切换启用状态。
  Future<void> toggleEnabled(String id) async {
    _skills = _skills
        .map((s) => s.id == id ? s.copyWith(enabled: !s.enabled) : s)
        .toList();
    await _persist();
  }

  /// 删除 skill。
  Future<void> remove(String id) async {
    _skills = _skills.where((s) => s.id != id).toList();
    await _persist();
  }

  /// 按 name 查找（function calling 返回 name 时反查）。
  Skill? findByName(String name) {
    try {
      return _skills.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist() async {
    await StorageService().setSkills(_skills);
    notifyListeners();
  }
}
