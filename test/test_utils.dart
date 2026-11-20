import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 화면을 치우고 대기 중인 타이머를 모두 실행시킨다.
///
/// 마크다운 뷰어(markdown_widget)는 화면에 보이는지 감지하는 0.5초짜리 타이머를 쓰는데,
/// 테스트가 끝나는 시점에 남아 있으면 "A Timer is still pending even after the widget tree
/// was disposed."로 실패한다. 마크다운을 그리는 위젯 테스트는 끝에서 이걸 불러 준다.
Future<void> disposeAndFlush(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
