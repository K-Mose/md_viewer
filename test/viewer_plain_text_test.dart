import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:md_viewer/screens/viewer_screen.dart';

void main() {
  testWidgets('txt는 마크다운으로 해석하지 않고 원문 그대로 보여준다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ViewerScreen(
          title: 'a.txt',
          content: '# 제목\r\n*별* 그대로\r\n\r\n끝',
          plainText: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(MarkdownWidget), findsNothing);
    // 기호가 지워지지 않고 그대로 남아 있다.
    expect(find.textContaining('# 제목'), findsOneWidget);
    expect(find.textContaining('*별* 그대로'), findsOneWidget);
  });

  testWidgets('긴 txt도 열리고 아래쪽 줄은 필요할 때 그려진다', (tester) async {
    final lines = [for (var i = 1; i <= 500; i++) '줄 $i'];
    await tester.pumpWidget(
      MaterialApp(
        home: ViewerScreen(
          title: 'long.txt',
          content: lines.join('\n'),
          plainText: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('줄 1\n'), findsOneWidget);
    expect(find.textContaining('줄 500'), findsNothing);
  });
}
