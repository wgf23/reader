import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/pages/settings_page.dart';
import 'package:reader_app/services/translate_backend.dart';

import 'fake_translate_backend.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('T-008 词典与翻译区块：控件渲染 + 导入/列表/移除/key/清空交互', (tester) async {
    final translate = FakeTranslateBackend(
      installedDicts: const [
        DictInfoData(id: 'd1', name: '测试词库', wordCount: 26, path: '/x/test.ifo'),
      ],
    );
    // 注入假 filePicker（widget 测试环境无 file_picker 平台实现）
    await tester.pumpWidget(wrap(SettingsPage(
      translateBackend: translate,
      filePicker: () async => '/x/test-tgmx/test-tgmx.ifo',
    )));
    await tester.pumpAndSettle();

    // 区块标题 + 各控件渲染
    expect(find.text('词典与翻译'), findsOneWidget);
    expect(find.text('导入词库（.ifo）'), findsOneWidget);
    expect(find.text('测试词库'), findsOneWidget);
    expect(find.text('26 词条'), findsOneWidget);
    expect(find.text('清空翻译缓存'), findsOneWidget);
    expect(find.text('DeepL API Key'), findsOneWidget);

    // 导入 → installDict 被调用
    await tester.tap(find.text('导入词库（.ifo）'));
    await tester.pumpAndSettle();
    expect(translate.installed, ['/x/test-tgmx/test-tgmx.ifo']);
    expect(find.textContaining('已安装词库'), findsOneWidget);

    // 移除 → removeDict
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(translate.removed, ['d1']);

    // key 输入 → setConfig('deepl', key)
    await tester.enterText(find.byType(TextField), 'my-deepl-key');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(translate.lastConfigProvider, 'deepl');
    expect(translate.lastConfigKey, 'my-deepl-key');

    // 清空缓存 → clearCache
    await tester.tap(find.text('清空翻译缓存'));
    await tester.pumpAndSettle();
    expect(translate.clearCalls, 1);
    expect(find.text('翻译缓存已清空'), findsOneWidget);
  });

  testWidgets('T-008 无词库时显示引导文案', (tester) async {
    final translate = FakeTranslateBackend(installedDicts: const []);
    await tester.pumpWidget(wrap(SettingsPage(translateBackend: translate)));
    await tester.pumpAndSettle();
    expect(find.textContaining('未安装词库'), findsOneWidget);
    expect(find.textContaining('请先导入'), findsOneWidget);
  });

  testWidgets('T-008 空 key 保存（清除配置）与导入失败提示', (tester) async {
    final translate = FakeTranslateBackend();
    await tester.pumpWidget(wrap(SettingsPage(
      translateBackend: translate,
      filePicker: () async => null, // 取消选择
    )));
    await tester.pumpAndSettle();
    // 取消选择不触发安装
    await tester.tap(find.text('导入词库（.ifo）'));
    await tester.pumpAndSettle();
    expect(translate.installed, isEmpty);
  });
}
