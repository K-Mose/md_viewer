import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 뷰어에서 마지막으로 읽던 위치.
///
/// 픽셀 위치는 화면 폭, 글자 크기, 이미지 로딩에 따라 달라지므로
/// 문서를 이루는 블록(제목, 문단, 코드 블록, 표 ...)의 번호와
/// 그 블록 안에서의 거리로 기억한다.
class ReadingPosition {
  const ReadingPosition({
    required this.index,
    required this.offset,
    required this.length,
  });

  /// 화면 맨 위에 걸친 블록의 번호 (MarkdownWidget 목록의 항목 번호)
  final int index;

  /// 그 블록의 시작점에서 화면 맨 위까지의 거리(px). 맨 위 블록은 음수일 수 있다.
  final double offset;

  /// 저장할 때의 문서 글자 수. 파일 내용이 바뀌었는지 판별하는 데 쓴다.
  final int length;

  Map<String, Object> toJson() => {
        'index': index,
        'offset': offset,
        'length': length,
      };

  factory ReadingPosition.fromJson(Map<String, dynamic> json) =>
      ReadingPosition(
        index: json['index'] as int,
        offset: (json['offset'] as num).toDouble(),
        length: json['length'] as int,
      );
}

/// 문서별 읽던 위치를 shared_preferences에 JSON으로 저장한다.
///
/// 문서 키는 [RecentFile.key]를 쓴다. 오래된 것부터 지워서 [_maxCount]개만 남긴다.
class ReadingPositionStore {
  static const _key = 'reading_positions';
  static const _maxCount = 30;

  /// 저장된 위치를 돌려준다. 없거나, 저장 때와 문서 길이가 달라졌으면(파일이 바뀜) null.
  Future<ReadingPosition?> load(
    String documentKey, {
    required int length,
  }) async {
    final all = await _loadAll();
    final raw = all[documentKey];
    if (raw == null) return null;
    try {
      final position = ReadingPosition.fromJson(raw as Map<String, dynamic>);
      return position.length == length ? position : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String documentKey, ReadingPosition position) async {
    final all = await _loadAll();
    // 지우고 다시 넣어서 가장 최근 항목으로 만든다.
    all.remove(documentKey);
    all[documentKey] = position.toJson();
    while (all.length > _maxCount) {
      all.remove(all.keys.first);
    }
    await _saveAll(all);
  }

  Future<void> remove(String documentKey) async {
    final all = await _loadAll();
    if (all.remove(documentKey) != null) await _saveAll(all);
  }

  Future<Map<String, dynamic>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      // Map.of는 저장 순서(오래된 것이 앞)를 그대로 유지한다.
      return Map<String, dynamic>.of(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveAll(Map<String, dynamic> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all));
  }
}
