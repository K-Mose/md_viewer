import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:md_viewer/main.dart';

void main() {
  testWidgets('Home screen smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MdViewerApp());
    await tester.pumpAndSettle();

    expect(find.text('파일 열기'), findsOneWidget);
    expect(find.text('최근 파일'), findsOneWidget);
  });
}
