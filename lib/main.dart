import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'services/storage_service.dart';

/// App 入口。
///
/// 1. 确保 Flutter binding 初始化（异步存储依赖）
/// 2. 提前创建应用数据目录（flutter_secure_storage / 本地 embedding 都要用）
/// 3. 初始化存储服务（shared_preferences + flutter_secure_storage）
/// 4. ChatProvider 在创建时异步加载已存 API Key / 模型 / 会话
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await _ensureAppSupportDirectory();
  await StorageService().initialize();

  runApp(const MyApp());
}

/// 确保 `getApplicationSupportDirectory()` 返回的目录已存在。
///
/// Windows 上 flutter_secure_storage 会把 API Key 写在
/// `%APPDATA%\<company>\<product>\flutter_secure_storage.dat`，
/// 而该目录由 path_provider 惰性创建。首次启动时若创建失败
/// （并发创建竞态可能出现 `errno 5 拒绝访问`），
/// 会导致读取 API Key 抛异常 → 被误判为"未配置 Key"而强制重新输入。
///
/// 这里在启动最早期主动创建并做少量重试，从根上避免该问题。
Future<void> _ensureAppSupportDirectory() async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final dir = await getApplicationSupportDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return;
    } catch (e) {
      debugPrint('创建应用数据目录失败(第 ${attempt + 1} 次): $e');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
