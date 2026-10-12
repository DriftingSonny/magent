// 基础冒烟测试：仅验证 MyApp 能构建并渲染出 ChatScreen 标题。
// 原模板里 Counter increments smoke test 引用了不存在的 MyApp 计数逻辑，
// 已替换为符合本项目实际结构的 smoke test。

import 'package:flutter_test/flutter_test.dart';

import 'package:magent/app.dart';

void main() {
  testWidgets('App 启动后应渲染聊天标题', (WidgetTester tester) async {
    // 注意：MyApp 内部用 Provider + ChatProvider，
    // 启动时会触发 StorageService.initialize()，需要 binding 就绪。
    TestWidgetsFlutterBinding.ensureInitialized();

    await tester.pumpWidget(const MyApp());

    // 首帧 pump 后再 pump 一次让 Provider 完成首帧回调。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 仅断言标题文本存在（避免依赖 RAG/embedding 等异步初始化细节）。
    expect(find.textContaining('DeepSeek'), findsWidgets);
  });
}
