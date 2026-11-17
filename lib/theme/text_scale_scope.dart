import 'package:flutter/material.dart';

/// 하위 글자 크기에 [scale]을 곱한다. 시스템 글자 크기 설정 위에 겹쳐서 곱한다.
///
/// 뷰어 본문과 설정 화면의 미리보기가 같은 방식으로 크기를 바꾸도록 함께 쓴다.
class TextScaleScope extends StatelessWidget {
  const TextScaleScope({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(
          MediaQuery.textScalerOf(context).scale(1) * scale,
        ),
      ),
      child: child,
    );
  }
}
