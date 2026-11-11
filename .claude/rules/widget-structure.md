# 위젯 구조 규칙

## Widget class 우선

위젯을 분리할 때 helper method보다 **widget class**로 만드는 것을 우선한다.

```dart
// ✅ 권장: private widget class
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) { ... }
}

// ❌ 지양: helper method
Widget _buildHeader(BuildContext context) { ... }
```

- 부득이하게 helper method로 만들 경우, **왜 그렇게 했는지 설명을 남겨야 한다** (코드 주석 또는 리뷰/응답에서).
- 이유: widget class는 `const` 생성자로 리빌드 범위를 좁힐 수 있고, Element 트리에 독립된 위젯으로 잡혀 성능·디버깅에 유리하다. Flutter 팀 공식 권장 패턴.

