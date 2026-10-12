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
  /// - ChatProvider 加载已存配置（API Key、模型）
  Future<void> _bootstrap() async {
    // embedding 模型后台加载（首次约 23MB 下载）
    EmbeddingService().initialize().catchError((e) {
      // 失败时仅打印，不阻塞 UI；RAG 功能会自动降级
      debugPrint('EmbeddingService 初始化失败: $e');
    });

    // chat provider 加载配置需要在 build 后才能拿到 context，
    // 这里通过 ProviderContainer 引用：
    // 实际通过 postFrame 回调触发。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<ChatProvider>().loadConfig();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SkillProvider>(create: (_) => SkillProvider()),
        ChangeNotifierProvider<KnowledgeProvider>(
            create: (_) => KnowledgeProvider()),
        // ChatProvider 依赖 SkillProvider，用 ProxyProvider 注入
        ChangeNotifierProxyProvider<SkillProvider, ChatProvider>(
          create: (ctx) => ChatProvider(skillProvider: ctx.read<SkillProvider>()),
          update: (_, sp, prev) => prev ?? ChatProvider(skillProvider: sp),
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
