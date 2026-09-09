import 'package:flutter_test/flutter_test.dart';
import 'package:reader_app/engines/paged_js_result.dart';

void main() {
  group('parseJsBool', () {
    test('Dart bool 原值返回', () {
      expect(parseJsBool(true), isTrue);
      expect(parseJsBool(false), isFalse);
    });

    test('num：非 0 为 true，0 为 false', () {
      expect(parseJsBool(1), isTrue);
      expect(parseJsBool(2), isTrue);
      expect(parseJsBool(1.5), isTrue);
      expect(parseJsBool(0), isFalse);
      expect(parseJsBool(0.0), isFalse);
    });

    test("字符串：'true'/'1'（大小写/空白容忍）为 true，其余为 false", () {
      expect(parseJsBool('true'), isTrue);
      expect(parseJsBool('TRUE'), isTrue);
      expect(parseJsBool(' true '), isTrue);
      expect(parseJsBool('1'), isTrue);
      expect(parseJsBool('false'), isFalse);
      expect(parseJsBool('FALSE'), isFalse);
      expect(parseJsBool('0'), isFalse);
      expect(parseJsBool('yes'), isFalse);
    });

    test('null / 其它类型 → false（不抛错）', () {
      expect(parseJsBool(null), isFalse);
      expect(parseJsBool(<String, dynamic>{}), isFalse);
      expect(parseJsBool(<dynamic>[]), isFalse);
      expect(parseJsBool(Object()), isFalse);
    });
  });

  group('PagedJsExecutor', () {
    test('runBool 解析 bool 与字符串路径', () async {
      final js = PagedJsExecutor((source) async {
        expect(source, 'readerPager.next()');
        return true;
      });
      expect(await js.runBool('readerPager.next()'), isTrue);

      final jsStr = PagedJsExecutor((_) async => 'true');
      expect(await jsStr.runBool('readerPager.prev()'), isTrue);
    });

    test('runBool 对 false/\'false\'/null/非布尔 → false 且不抛错', () async {
      for (final v in <dynamic>[false, 'false', null, <String, dynamic>{}]) {
        final js = PagedJsExecutor((_) async => v);
        expect(await js.runBool('readerPager.next()'), isFalse, reason: 'v=$v');
      }
    });

    test('runInt：num / 字符串 / 非法值 fallback', () async {
      expect(await PagedJsExecutor((_) async => 3).runInt('x'), 3);
      expect(await PagedJsExecutor((_) async => 3.0).runInt('x'), 3);
      expect(await PagedJsExecutor((_) async => '4').runInt('x'), 4);
      expect(await PagedJsExecutor((_) async => null).runInt('x'), 1);
      expect(await PagedJsExecutor((_) async => 'abc').runInt('x'), 1);
      expect(await PagedJsExecutor((_) async => 0).runInt('x'), 1);
      expect(await PagedJsExecutor((_) async => -2).runInt('x'), 1);
      expect(await PagedJsExecutor((_) async => null).runInt('x', fallback: 5), 5);
    });
  });
}
