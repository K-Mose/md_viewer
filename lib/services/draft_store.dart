import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 에디터의 임시저장 문서. 앱 안(shared_preferences)에 한 개만 보관한다.
class Draft {
  const Draft({required this.text, required this.savedAt});

  final String text;
  final DateTime savedAt;
}

class DraftStore {
  static const _key = 'editor_draft';

  Future<Draft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final text = json['text'] as String;
      if (text.trim().isEmpty) return null;
      return Draft(
        text: text,
        savedAt: DateTime.fromMillisecondsSinceEpoch(json['savedAt'] as int),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String text) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'text': text,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
