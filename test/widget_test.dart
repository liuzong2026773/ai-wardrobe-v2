// 启动冒烟测试：App 能正常打开、首页显示“我的衣橱”。
// 不测相机/抠图（那些只在对应页面打开时才初始化）。

import 'package:ai_wardrobe_v2/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App launches and shows wardrobe tab', (tester) async {
    await tester.pumpWidget(const AiWardrobeApp());
    await tester.pump();
    expect(find.text('我的衣橱'), findsOneWidget);
    expect(find.text('穿搭'), findsOneWidget);
    expect(find.text('AR试衣'), findsOneWidget);
  });
}
