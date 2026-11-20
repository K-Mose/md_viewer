import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/app_info.dart';
import 'package:md_viewer/screens/settings_screen.dart';
import 'package:md_viewer/screens/viewer_screen.dart';
import 'package:md_viewer/services/app_settings.dart';
import 'package:md_viewer/services/draft_store.dart';
import 'package:md_viewer/services/reading_position_store.dart';
import 'package:md_viewer/services/recent_files.dart';
import 'package:md_viewer/services/text_decoder.dart';
import 'package:md_viewer/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

RecentFile _recent(String path) => RecentFile(
      name: path.split('/').last,
      ref: DocumentRef(kind: DocumentRefKind.path, value: path),
      location: path,
      openedAt: DateTime(2026, 11, 17),
    );

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
  });

  group('AppSettings', () {
    test('기본값', () {
      final settings = AppSettings();
      expect(settings.textScale, 1.0);
      expect(settings.lineSpacing, LineSpacing.normal);
      expect(settings.rememberPosition, isTrue);
      expect(settings.encoding, EncodingPreference.auto);
      expect(settings.txtViewMode, TxtViewMode.raw);
      expect(settings.autoDraft, isTrue);
    });

    test('바꾼 값이 저장되고 다시 읽힌다', () async {
      final settings = AppSettings();
      await settings.setTextScale(1.3);
      await settings.setLineSpacing(LineSpacing.wide);
      await settings.setRememberPosition(false);
      await settings.setEncoding(EncodingPreference.cp949);
      await settings.setTxtViewMode(TxtViewMode.markdown);
      await settings.setAutoDraft(false);

      final loaded = AppSettings();
      await loaded.load();
      expect(loaded.textScale, 1.3);
      expect(loaded.lineSpacing, LineSpacing.wide);
      expect(loaded.rememberPosition, isFalse);
      expect(loaded.encoding, EncodingPreference.cp949);
      expect(loaded.txtViewMode, TxtViewMode.markdown);
      expect(loaded.autoDraft, isFalse);
    });

    test('글자 크기는 0.8~1.6 안에서 0.1 단위로 맞춘다', () async {
      final settings = AppSettings();
      await settings.setTextScale(3.0);
      expect(settings.textScale, 1.6);
      await settings.setTextScale(0.1);
      expect(settings.textScale, 0.8);
      await settings.setTextScale(1.04);
      expect(settings.textScale, 1.0);
    });

    test('알 수 없는 저장 값은 기본값으로 읽는다', () async {
      SharedPreferences.setMockInitialValues({
        'settings.line_spacing': 'bogus',
        'settings.encoding': 'bogus',
        'settings.txt_view_mode': 'bogus',
      });
      final settings = AppSettings();
      await settings.load();
      expect(settings.lineSpacing, LineSpacing.normal);
      expect(settings.encoding, EncodingPreference.auto);
      expect(settings.txtViewMode, TxtViewMode.raw);
    });

    test('바뀔 때만 알린다', () async {
      final settings = AppSettings();
      var count = 0;
      settings.addListener(() => count++);
      await settings.setAutoDraft(false);
      await settings.setAutoDraft(false); // 같은 값
      expect(count, 1);
    });
  });

  group('decodeText 인코딩 지정', () {
    // CP949로 인코딩된 '아름다운'
    final cp949Bytes = Uint8List.fromList(
      [0xBE, 0xC6, 0xB8, 0xA7, 0xB4, 0xD9, 0xBF, 0xEE],
    );

    test('CP949로 지정하면 CP949로 읽는다', () {
      final result = decodeText(
        cp949Bytes,
        preference: EncodingPreference.cp949,
      );
      expect(result.text, '아름다운');
      expect(result.encoding, TextEncoding.cp949);
    });

    test('UTF-8로 지정했는데 UTF-8이 아니면 깨진 글자를 허용해 보여준다', () {
      final result = decodeText(
        cp949Bytes,
        preference: EncodingPreference.utf8,
      );
      expect(result.encoding, TextEncoding.utf8Lossy);
    });

    test('UTF-8 파일을 CP949로 지정해도 예외 없이 읽는다', () {
      // CP949로 해석할 수 없는 바이트면 깨진 글자를 허용해 UTF-8로 보여주고,
      // 해석할 수 있으면 CP949 결과가 나온다. 어느 쪽이든 예외는 던지지 않는다.
      final bytes = Uint8List.fromList(utf8.encode('안녕'));
      late DecodedText result;
      expect(
        () => result = decodeText(bytes, preference: EncodingPreference.cp949),
        returnsNormally,
      );
      expect(result.text, isNotEmpty);
      expect(
        [TextEncoding.cp949, TextEncoding.utf8Lossy],
        contains(result.encoding),
      );
    });

    test('자동은 기존과 같다', () {
      expect(decodeText(cp949Bytes).encoding, TextEncoding.cp949);
      expect(
        decodeText(Uint8List.fromList(utf8.encode('안녕'))).encoding,
        TextEncoding.utf8,
      );
    });
  });

  group('지우기', () {
    test('최근 파일을 모두 지우고 지워진 항목을 돌려준다', () async {
      final store = RecentFilesStore();
      await store.add(_recent('/a.md'));
      await store.add(_recent('/b.md'));

      final removed = await store.clear();
      expect(removed.map((f) => f.name), unorderedEquals(['a.md', 'b.md']));
      expect(await store.load(), isEmpty);
    });

    test('읽던 위치 기록을 모두 지운다', () async {
      final store = ReadingPositionStore();
      await store.save(
        'path:/a.md',
        const ReadingPosition(index: 1, offset: 0, length: 10),
      );
      await store.save(
        'path:/b.md',
        const ReadingPosition(index: 2, offset: 0, length: 10),
      );
      expect(await store.count(), 2);

      await store.clearAll();
      expect(await store.count(), 0);
    });
  });

  group('뷰어에 설정 적용', () {
    tearDown(() async {
      await AppSettings.instance.setTextScale(1.0);
      await AppSettings.instance.setLineSpacing(LineSpacing.normal);
    });

    testWidgets('글자 크기와 줄 간격', (tester) async {
      await AppSettings.instance.setTextScale(1.6);
      await AppSettings.instance.setLineSpacing(LineSpacing.wide);

      await tester.pumpWidget(
        const MaterialApp(
          home: ViewerScreen(
            title: 'a.txt',
            content: '안녕\n반가워',
            plainText: true,
          ),
        ),
      );
      await tester.pump();

      final finder = find.textContaining('안녕');
      expect(
        MediaQuery.textScalerOf(tester.element(finder)).scale(10),
        closeTo(16, 0.01),
      );
      expect(
        tester.widget<Text>(finder).style?.height,
        LineSpacing.wide.plainHeight,
      );
    });
  });

  group('SettingsScreen', () {
    Future<void> pumpSettings(WidgetTester tester) async {
      // 항목이 많아서 화면을 크게 해야 한 번에 다 그려진다.
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.dark, home: const SettingsScreen()),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('모든 항목이 보인다', (tester) async {
      await pumpSettings(tester);
      for (final label in [
        '읽기',
        '글자 크기',
        '줄 간격',
        '파일',
        '최근 파일 목록 지우기',
        '읽던 위치 기억',
        '읽던 위치 기록 지우기',
        '기본 인코딩',
        'txt 보기 방식',
        '에디터',
        '자동 임시저장',
        '임시저장 삭제',
        '정보',
        '버전',
        '오픈소스 라이선스',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text(appVersion), findsOneWidget);
    });

    testWidgets('스위치와 선택지가 설정에 반영된다', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('자동 임시저장'));
      await tester.pumpAndSettle();
      expect(AppSettings.instance.autoDraft, isFalse);

      await tester.tap(find.text('읽던 위치 기억'));
      await tester.pumpAndSettle();
      expect(AppSettings.instance.rememberPosition, isFalse);

      await tester.tap(find.text('CP949'));
      await tester.pumpAndSettle();
      expect(AppSettings.instance.encoding, EncodingPreference.cp949);

      await tester.tap(find.text('마크다운'));
      await tester.pumpAndSettle();
      expect(AppSettings.instance.txtViewMode, TxtViewMode.markdown);

      await tester.tap(find.text('넓게'));
      await tester.pumpAndSettle();
      expect(AppSettings.instance.lineSpacing, LineSpacing.wide);
    });

    testWidgets('최근 파일 목록 지우기', (tester) async {
      final store = RecentFilesStore();
      await store.add(_recent('/a.md'));
      await store.add(_recent('/b.md'));
      await pumpSettings(tester);
      expect(find.text('2개'), findsOneWidget);

      await tester.tap(find.text('최근 파일 목록 지우기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('지우기'));
      await tester.pumpAndSettle();

      expect(await store.load(), isEmpty);
      expect(find.text('0개'), findsOneWidget);
    });

    testWidgets('임시저장 삭제', (tester) async {
      await DraftStore().save('# 초안');
      await pumpSettings(tester);

      await tester.tap(find.text('임시저장 삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(await DraftStore().load(), isNull);
      expect(find.text('임시저장된 문서가 없어요'), findsOneWidget);
    });
  });
}
