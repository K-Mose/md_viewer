import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/app_info.dart';

void main() {
  test('설정 화면에 보이는 버전이 pubspec.yaml의 version과 같다', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9.]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(
      match?.group(1),
      appVersion,
      reason: 'pubspec.yaml의 version을 바꾸면 lib/app_info.dart도 같이 바꿔 주세요.',
    );
  });
}
