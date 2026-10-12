import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/skill.dart';
import '../models/knowledge_doc.dart';

/// 持久化存储服务（单例）。
///
/// 分两层：
/// - [FlutterSecureStorage]：敏感数据（API Key），Windows 用 DPAPI 加密。
/// - [SharedPreferences]：非敏感配置（模型选择、Skill 列表、文档元数据等）。
class StorageService {
  StorageService._();
  static final StorageService _instance = StorageService._();
  factory StorageService() => _instance;

  final _secure = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  /// 必须在 App 启动时调用一次。
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    if (_prefs == null) {
      throw StateError('StorageService 未初始化，请先调用 initialize()');
    }
    return _prefs!;
  }

  // ---- API Key ----

  Future<String?> getApiKey() => _secure.read(key: AppConstants.keyApiKey);

  Future<void> setApiKey(String value) =>
      _secure.write(key: AppConstants.keyApiKey, value: value);

  Future<void> deleteApiKey() => _secure.delete(key: AppConstants.keyApiKey);

  // ---- 模型选择 ----

  String getModel() => _p.getString(AppConstants.keyModel) ?? AppConstants.defaultModel;

  Future<void> setModel(String value) =>
      _p.setString(AppConstants.keyModel, value);

  // ---- RAG 开关 ----

  bool isRagEnabled() => _p.getBool(AppConstants.keyRagEnabled) ?? false;

  Future<void> setRagEnabled(bool value) =>
      _p.setBool(AppConstants.keyRagEnabled, value);

  // ---- Skill 列表 ----

  List<Skill> getSkills() {
    final raw = _p.getString(AppConstants.keySkills);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => Skill.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> setSkills(List<Skill> skills) async {
    final raw = jsonEncode(skills.map((s) => s.toJson()).toList());
    await _p.setString(AppConstants.keySkills, raw);
  }

  // ---- 知识库文档元数据列表 ----

  List<KnowledgeDoc> getKnowledgeDocs() {
    final raw = _p.getString(AppConstants.keyKnowledgeDocs);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => KnowledgeDoc.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> setKnowledgeDocs(List<KnowledgeDoc> docs) async {
    final raw = jsonEncode(docs.map((d) => d.toJson()).toList());
    await _p.setString(AppConstants.keyKnowledgeDocs, raw);
  }
}
