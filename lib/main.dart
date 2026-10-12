import 'package:flutter/material.dart';

import 'app.dart';
import 'services/storage_service.dart';

/// App 入口。
///
/// 1. 确保 Flutter binding 初始化（异步存储依赖）
/// 2. 初始化存储服务（shared_preferences + flutter_secure_storage）
/// 3. 加载已存的 API Key/模型配置到 ChatProvider
/// 4. 后台异步初始化 embedding 模型（不阻塞 UI，知识库功能就绪前 RAG 自动降级）
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await StorageService().initialize();

  runApp(const MyApp());
}
