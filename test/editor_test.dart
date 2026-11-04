import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/main.dart';
import 'package:md_viewer/screens/editor_screen.dart';
import 'package:md_viewer/services/draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('suggestFileName', () {
    test('첫 줄 제목을 파일명으로', () {
      expect(suggestFileName('# 회의록: 11/4\n\n본문'), '회의록 114.md');
    });

    test('빈 문서는 기본 이름', () {
      expect(suggestFileName('\n\n  '), '새 문서.md');
    });
  });

  testWidgets('새 문서 → 미리보기 → 나갈 때 임시저장', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MdViewerApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('새 문서'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '# 안녕\n\n테스트');
    await tester.pump();

    // 미리보기
    await tester.tap(find.byTooltip('미리보기'));
    await tester.pumpAndSettle();
    expect(find.text('테스트', findRichText: true), findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // 저장하지 않고 나가면 3가지 선택지
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('저장 안 함'), findsOneWidget);
    expect(find.text('임시저장'), findsOneWidget);
    expect(find.text('저장'), findsOneWidget);

    await tester.tap(find.text('임시저장'));
    await tester.pumpAndSettle();
    expect(find.byType(EditorScreen), findsNothing);
    expect((await DraftStore().load())?.text, '# 안녕\n\n테스트');

    // 다시 새 문서를 누르면 이어서 쓸지 묻는다
    await tester.tap(find.text('새 문서'));
    await tester.pumpAndSettle();
    expect(find.text('이어서 쓰기'), findsOneWidget);
  });
}
