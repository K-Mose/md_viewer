import 'package:flutter/material.dart';

import 'app_theme.dart';

/// 얇은 스크롤바: 두께 2, 둥근 모서리, 옅은 회색. 스크롤할 때만 나타났다 사라진다.
abstract final class ThinScrollbarStyle {
  static const thickness = 2.0;
  static const radius = Radius.circular(1);
  static const color = AppColors.scrollbar;

  static const theme = ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(thickness),
    radius: radius,
    thumbColor: WidgetStatePropertyAll(color),
    thumbVisibility: WidgetStatePropertyAll(false),
    trackVisibility: WidgetStatePropertyAll(false),
    interactive: false,
  );
}

/// 하위의 모든 스크롤(세로·가로)에 얇은 스크롤바를 붙인다.
///
/// Flutter는 기본적으로 데스크톱에서만 스크롤바를 붙이므로, 모바일에서도 붙도록
/// ScrollBehavior를 바꾸고 스크롤바 테마를 덮어쓴다. 뷰어·에디터에서만 쓴다.
class ThinScrollbars extends StatelessWidget {
  const ThinScrollbars({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(scrollbarTheme: ThinScrollbarStyle.theme),
      child: ScrollConfiguration(
        behavior: const _ThinScrollbarBehavior(),
        child: child,
      ),
    );
  }
}

class _ThinScrollbarBehavior extends MaterialScrollBehavior {
  const _ThinScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return Scrollbar(controller: details.controller, child: child);
  }
}
