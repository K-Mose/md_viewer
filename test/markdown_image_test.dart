import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/screens/viewer_screen.dart';

import 'test_utils.dart';

// 1x1 투명 PNG
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  testWidgets('문서 옆 상대 경로 이미지를 표시하고, 없으면 대체 아이콘을 보인다', (tester) async {
    final dir = Directory.systemTemp.createTempSync('md_img');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}pic.png').writeAsBytesSync(_png);

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        title: 't',
        content: '![ok](pic.png)\n\n![missing](none.png)',
        baseDirectory: dir.path,
      ),
    ));
    await tester.pump();

    expect(find.byType(Image), findsWidgets);
    expect(find.byIcon(Icons.broken_image), findsOneWidget);
    await disposeAndFlush(tester);
  });

  testWidgets('SVG 이미지도 표시한다', (tester) async {
    final dir = Directory.systemTemp.createTempSync('md_svg');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}${Platform.pathSeparator}d.svg').writeAsStringSync(
        '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="20">'
        '<rect width="40" height="20" fill="red"/></svg>');

    await tester.pumpWidget(MaterialApp(
      home: ViewerScreen(
        title: 't',
        content: '![d](d.svg)',
        baseDirectory: dir.path,
      ),
    ));
    await tester.pump();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.byIcon(Icons.broken_image), findsNothing);
    await disposeAndFlush(tester);
  });
}
