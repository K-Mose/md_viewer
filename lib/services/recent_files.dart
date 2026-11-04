import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 최근 파일을 다시 열 때 쓰는 참조의 종류.
enum DocumentRefKind {
  /// 일반 파일 경로 (Windows 등 데스크톱, Android file://)
  path,

  /// Android content:// URI (영구 읽기 권한을 받아 둔 것)
  uri,

  /// iOS security-scoped bookmark (base64)
  bookmark,

  /// 원본에 다시 접근할 권한이 없어 앱 내부에 저장한 사본의 경로
  copy,
}

/// 문서를 다시 열 수 있는 참조. 플랫폼마다 내용이 다르다.
class DocumentRef {
  const DocumentRef({required this.kind, required this.value});

  final DocumentRefKind kind;
  final String value;

  Map<String, Object> toJson() => {'kind': kind.name, 'value': value};

  factory DocumentRef.fromJson(Map<String, dynamic> json) => DocumentRef(
        kind: DocumentRefKind.values.byName(json['kind'] as String),
        value: json['value'] as String,
      );
}

class RecentFile {
  const RecentFile({
    required this.name,
    required this.ref,
    required this.location,
    required this.openedAt,
  });

  final String name;
  final DocumentRef ref;

  /// 목록에 보여줄 위치 문자열 (예: "Download/notes.md"). 중복 판별에도 쓴다.
  final String location;
  final DateTime openedAt;

  /// 같은 문서인지 판별하는 키. iOS 북마크는 열 때마다 값이 달라지므로 위치로 비교한다.
  String get key => ref.kind == DocumentRefKind.bookmark
      ? 'bookmark:$location'
      : '${ref.kind.name}:${ref.value}';

  Map<String, Object> toJson() => {
        'name': name,
        'ref': ref.toJson(),
        'location': location,
        'openedAt': openedAt.millisecondsSinceEpoch,
      };

  factory RecentFile.fromJson(Map<String, dynamic> json) {
    final openedAt =
        DateTime.fromMillisecondsSinceEpoch(json['openedAt'] as int);
    // 이전 버전 포맷 {name, path, openedAt} 호환
    if (json['ref'] == null) {
      final path = json['path'] as String;
      return RecentFile(
        name: json['name'] as String,
        ref: DocumentRef(kind: DocumentRefKind.path, value: path),
        location: path,
        openedAt: openedAt,
      );
    }
    return RecentFile(
      name: json['name'] as String,
      ref: DocumentRef.fromJson(json['ref'] as Map<String, dynamic>),
      location: json['location'] as String,
      openedAt: openedAt,
    );
  }
}

/// [RecentFilesStore.add]의 결과. 목록에서 밀려난 항목은 권한 해제 등을 위해 함께 돌려준다.
class RecentFilesUpdate {
  const RecentFilesUpdate(this.files, this.evicted);

  final List<RecentFile> files;
  final List<RecentFile> evicted;
}

/// 최근 파일 목록을 shared_preferences에 JSON으로 저장한다.
class RecentFilesStore {
  static const _key = 'recent_files';
  static const _maxCount = 10;

  Future<List<RecentFile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    final files = <RecentFile>[];
    try {
      for (final entry in jsonDecode(raw) as List) {
        try {
          files.add(RecentFile.fromJson(entry as Map<String, dynamic>));
        } catch (_) {
          // 손상된 항목 하나 때문에 전체를 버리지 않는다.
        }
      }
    } catch (_) {
      // 저장 데이터 자체가 손상된 경우 목록을 비운다.
    }
    return files;
  }

  Future<RecentFilesUpdate> add(RecentFile file) async {
    final list = await load();
    list.removeWhere((f) => f.key == file.key);
    list.insert(0, file);
    final capped = list.take(_maxCount).toList();
    final evicted = list.skip(_maxCount).toList();
    await _save(capped);
    return RecentFilesUpdate(capped, evicted);
  }

  Future<List<RecentFile>> remove(RecentFile file) async {
    final list = await load();
    list.removeWhere((f) => f.key == file.key);
    await _save(list);
    return list;
  }

  Future<void> _save(List<RecentFile> list) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final f in list) f.toJson()]),
    );
  }
}
