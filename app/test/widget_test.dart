import 'package:flutter_test/flutter_test.dart';

import 'package:reader_app/main.dart';

void main() {
  testWidgets('骨架可启动并显示书架占位', (tester) async {
    await tester.pumpWidget(const ReaderApp());
    expect(find.text('书库'), findsOneWidget);
  });
}
