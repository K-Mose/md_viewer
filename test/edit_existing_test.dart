import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/screens/viewer_screen.dart';
import 'package:md_viewer/services/document_service.dart';
import 'package:md_viewer/services/recent_files.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('편집 버튼으로 기존 파일을 고치고 저장하면 뷰어가 바로 바뀐다', (tester) async {
    final dir = Directory.systemTemp.createTempSync('md_edit');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}${Platform.pathSeparator}note.md')
      ..writeAsStringSync('# 원본');

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        title: 'note.md',
        content: '# 원본',
        document: SavedDocument(
          name: 'note.md',
          ref: DocumentRef(kind: DocumentRefKind.path, value: file.path),
          location: file.path,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('원본'), findsOneWidget);

    await tester.tap(find.byTooltip('편집'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '# 수정됨');
    await tester.pump();

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('저장'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(file.readAsStringSync(), '# 수정됨');

    // 에디터에서 나오면 뷰어에는 수정된 내용이 보인다.
    Navigator.of(tester.element(find.byType(TextField))).pop();
    await tester.pumpAndSettle();
    expect(find.text('수정됨'), findsOneWidget);
  });

  testWidgets('document가 없으면(에디터 미리보기) 편집 버튼이 없다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: ViewerScreen(title: 't', content: '# a'),
    ));
    await tester.pump();
    expect(find.byTooltip('편집'), findsNothing);
  });
}
