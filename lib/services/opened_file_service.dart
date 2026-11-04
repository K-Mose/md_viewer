import 'dart:io';

import 'package:flutter/services.dart';

import 'document_service.dart';

/// 외부 앱(파일 관리자, 파일 앱 등)의 "연결 프로그램"으로 md 파일이 열렸을 때 전달받는 서비스.
///
/// Android(MainActivity)와 iOS(SceneDelegate) 모두 네이티브에서 파일을 읽고,
/// 다시 열 수 있는 참조(ref)와 함께 MethodChannel로 전달한다.
/// - Android: 영구 권한을 받을 수 있으면 content:// URI, 아니면 앱 내부 사본 경로
/// - iOS: 원본 위치에서 열고 security-scoped bookmark 생성
class OpenedFileService {
  OpenedFileService._();

  static final instance = OpenedFileService._();

  static const _channel = MethodChannel('md_viewer/opened_file');

  /// 앱 실행 중 새 파일이 열렸을 때 호출된다.
  void Function(LoadedDocument document)? onFileOpened;

  /// 초기화하고, 콜드 스타트로 전달된 파일이 있으면 반환한다.
  Future<LoadedDocument?> init() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;

    _channel.setMethodCallHandler((call) async {
      if (call.method != 'fileOpened') return;
      final document = _fromArguments(call.arguments);
      if (document != null) onFileOpened?.call(document);
    });

    try {
      return _fromArguments(
        await _channel.invokeMapMethod<String, dynamic>('getInitialFile'),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }

  LoadedDocument? _fromArguments(Object? arguments) {
    if (arguments is! Map) return null;
    try {
      return DocumentService.instance.fromNativeMap(
        Map<String, dynamic>.from(arguments),
      );
    } on DocumentException {
      return null;
    }
  }
}
