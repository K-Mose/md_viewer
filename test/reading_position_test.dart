import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/services/reading_position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ReadingPositionStore', () {
    test('저장한 위치를 그대로 읽는다', () async {
      final store = ReadingPositionStore();
      await store.save(
        'path:/a.md',
        const ReadingPosition(index: 12, offset: 40.5, length: 300),
      );
      final loaded = await store.load('path:/a.md', length: 300);
      expect(loaded?.index, 12);
      expect(loaded?.offset, 40.5);
    });

    test('저장된 적 없는 문서는 null', () async {
      final loaded =
          await ReadingPositionStore().load('path:/none.md', length: 10);
      expect(loaded, isNull);
    });

    test('문서 길이가 달라지면(파일이 바뀌면) 무시한다', () async {
      final store = ReadingPositionStore();
      await store.save(
        'path:/a.md',
        const ReadingPosition(index: 3, offset: 0, length: 300),
      );
      expect(await store.load('path:/a.md', length: 301), isNull);
    });

    test('문서마다 따로 저장하고, 지우면 그 문서만 없어진다', () async {
      final store = ReadingPositionStore();
      await store.save(
        'path:/a.md',
        const ReadingPosition(index: 1, offset: 0, length: 10),
      );
      await store.save(
        'path:/b.md',
        const ReadingPosition(index: 2, offset: 0, length: 20),
      );
      await store.remove('path:/a.md');
      expect(await store.load('path:/a.md', length: 10), isNull);
      expect((await store.load('path:/b.md', length: 20))?.index, 2);
    });

    test('30개를 넘으면 오래된 것부터 지운다', () async {
      final store = ReadingPositionStore();
      for (var i = 0; i < 31; i++) {
        await store.save(
          'path:/$i.md',
          ReadingPosition(index: i, offset: 0, length: 1),
        );
      }
      expect(await store.load('path:/0.md', length: 1), isNull);
      expect((await store.load('path:/1.md', length: 1))?.index, 1);
      expect((await store.load('path:/30.md', length: 1))?.index, 30);
    });
  });
}
