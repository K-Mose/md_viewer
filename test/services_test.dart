import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/services/recent_files.dart';
import 'package:md_viewer/services/text_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('decodeText', () {
    test('UTF-8 파일', () {
      final result = decodeText(Uint8List.fromList(utf8.encode('# 안녕')));
      expect(result.text, '# 안녕');
      expect(result.encoding, TextEncoding.utf8);
    });

    test('UTF-8 BOM 제거', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('abc')]);
      expect(decodeText(bytes).text, 'abc');
    });

    test('CP949(EUC-KR) 파일', () {
      // '아름다운'
      final bytes = Uint8List.fromList([0xBE, 0xC6, 0xB8, 0xA7, 0xB4, 0xD9, 0xBF, 0xEE]);
      final result = decodeText(bytes);
      expect(result.text, '아름다운');
      expect(result.encoding, TextEncoding.cp949);
    });
  });

  group('RecentFilesStore', () {
    test('이전 포맷 {name, path, openedAt}을 읽는다', () async {
      SharedPreferences.setMockInitialValues({
        'recent_files': jsonEncode([
          {'name': 'a.md', 'path': '/tmp/a.md', 'openedAt': 0},
        ]),
      });
      final files = await RecentFilesStore().load();
      expect(files.single.ref.kind, DocumentRefKind.path);
      expect(files.single.ref.value, '/tmp/a.md');
    });

    test('같은 문서는 중복되지 않고, 10개를 넘으면 밀려난 항목을 돌려준다', () async {
      SharedPreferences.setMockInitialValues({});
      final store = RecentFilesStore();
      RecentFile file(int i) => RecentFile(
            name: '$i.md',
            ref: DocumentRef(kind: DocumentRefKind.uri, value: 'content://doc/$i'),
            location: '$i.md',
            openedAt: DateTime(2026),
          );

      for (var i = 0; i < 10; i++) {
        await store.add(file(i));
      }
      final again = await store.add(file(3));
      expect(again.files.length, 10);
      expect(again.files.first.name, '3.md');
      expect(again.evicted, isEmpty);

      final overflow = await store.add(file(99));
      expect(overflow.files.length, 10);
      expect(overflow.evicted.single.name, '0.md');
    });
  });
}
