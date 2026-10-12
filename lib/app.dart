import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'providers/chat_provider.dart';
import 'providers/knowledge_provider.dart';
import 'providers/skill_provider.dart';
import 'screens/chat_screen.dart';
import 'services/embedding_service.dart';

/// 应用根 widget。
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // 当前代码未提供切换主题的 UI，直接 final 锁定 system。
  // 后续接入设置页切换主题时去掉 final 即可。
  final ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// 启动后异步初始化：
  /// - EmbeddingService（首次会下载模型，后台进行，不阻塞 UI）
  ///
  /// 注意：ChatProvider 的配置加载（API Key / 模型 / 会话）
  /// 改到 Provider 的 create 回调里触发——那里能拿到正确的 Provider 树，
  /// 不再依赖 postFrameCallback + context 层级，避免取不到 Provider 或漏加载。
  void _bootstrap() {
    // embedding 模型后台加载（首次约 23MB 下载）
    EmbeddingService().initialize().catchError((Object e) {
      // 失败时仅打印，不阻塞 UI；RAG 功能会自动降级
      debugPrint('EmbeddingService 初始化失败: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SkillProvider>(create: (_) => SkillProvider()),
        ChangeNotifierProvider<KnowledgeProvider>(
          create: (_) => KnowledgeProvider(),
        ),
        // ChatProvider 依赖 SkillProvider，用 ProxyProvider 注入。
        // 创建即加载已存配置，保证"只要存过 Key 就直接可用"。
        ChangeNotifierProxyProvider<SkillProvider, ChatProvider>(
          create: (ctx) {
            final provider = ChatProvider(
              skillProvider: ctx.read<SkillProvider>(),
            );
            provider.loadConfig();
            return provider;
          },
          update: (_, sp, prev) {
            if (prev != null) return prev;
            final created = ChatProvider(skillProvider: sp);
            created.loadConfig();
            return created;
          },
        ),
      ],
      child: MaterialApp(
        title: 'DeepSeek 对话 · 知识库 · Skills',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        home: const ChatScreen(),
      ),
    );
  }
}
