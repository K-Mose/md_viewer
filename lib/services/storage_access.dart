import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'recent_files.dart';

/// Android "모든 파일 접근"(MANAGE_EXTERNAL_STORAGE) 권한과, 이 권한으로 문서가 있는 폴더를 알아내는 기능.
///
/// Android는 문서 선택기로 연 파일에 대해 그 파일 하나의 읽기 권한만 준다. 그래서 문서 옆의
/// 이미지(상대 경로)를 읽을 수 없다. 이 권한을 허용하면 문서 주소(content://)에서 실제 폴더
/// 경로를 계산해 일반 파일처럼 바로 읽을 수 있다.
/// iOS에는 같은 권한이 없어서 이 서비스는 항상 "사용 불가"로 동작한다.
class StorageAccessService {
  StorageAccessService({bool? isAndroid}) : _isAndroid = isAndroid ?? Platform.isAndroid;

  static final instance = StorageAccessService();

  static const _channel = MethodChannel('md_viewer/documents');

  final bool _isAndroid;

  /// 이 기기에서 "모든 파일 접근"이라는 권한이 있는지 (Android 11 이상). 아니면 false.
  Future<bool> canRequestAllFilesAccess() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canRequestAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// "모든 파일 접근"이 지금 허용돼 있는지. 권한이 없는 기기(Android 10 이하, iOS)도 false.
  Future<bool> hasAllFilesAccess() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 이 앱의 "모든 파일 접근" 설정 화면을 연다. 허용 여부는 돌아온 뒤 [hasAllFilesAccess]로 다시 확인한다.
  Future<void> openAllFilesSettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openAllFilesSettings');
    } on PlatformException {
      // 설정 화면을 열 수 없으면 무시한다.
    } on MissingPluginException {
      // 위와 같다.
    }
  }

  /// 권한이 허용돼 있고 문서 주소에서 실제 경로를 알 수 있으면 문서가 있는 폴더. 아니면 null.
  ///
  /// 내장 저장소와 SD 카드 같은 로컬 문서만 가능하고, 드라이브 같은 클라우드 문서나
  /// 다운로드 앱이 만든 주소(msf:…)는 null이다.
  Future<String?> documentDirectory(DocumentRef ref) async {
    if (!_isAndroid || ref.kind != DocumentRefKind.uri) return null;
    if (!await hasAllFilesAccess()) return null;
    try {
      final path = await _channel.invokeMethod<String>(
        'resolveDocumentPath',
        {'value': ref.value},
      );
      return path == null ? null : p.dirname(path);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// 앱을 처음 켰을 때 "모든 파일 접근" 안내를 이미 보여줬는지 기억한다 (한 번만 보여주기 위해).
class AllFilesAccessPromptStore {
  static const _key = 'prompt.allFilesAccessShown';

  Future<bool> wasShown() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
