import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:md_viewer/services/recent_files.dart';
import 'package:md_viewer/services/storage_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('md_viewer/documents');

const _uriRef = DocumentRef(
  kind: DocumentRefKind.uri,
  value: 'content://com.android.externalstorage.documents/document/primary%3ADownload%2Fdocs%2Fa.md',
);

void _mock({required bool allowed, String? path}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
    switch (call.method) {
      case 'canRequestAllFilesAccess':
        return true;
      case 'hasAllFilesAccess':
        return allowed;
      case 'resolveDocumentPath':
        return path;
    }
    return null;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, null));

  test('권한이 허용되고 경로를 알 수 있으면 문서가 있는 폴더를 돌려준다', () async {
    _mock(allowed: true, path: '/storage/emulated/0/Download/docs/a.md');
    final dir = await StorageAccessService(isAndroid: true).documentDirectory(_uriRef);
    expect(dir, '/storage/emulated/0/Download/docs');
  });

  test('권한이 없으면 null', () async {
    _mock(allowed: false, path: '/storage/emulated/0/Download/docs/a.md');
    expect(await StorageAccessService(isAndroid: true).documentDirectory(_uriRef), isNull);
  });

  test('경로를 알 수 없는 문서(클라우드 등)는 null', () async {
    _mock(allowed: true, path: null);
    expect(await StorageAccessService(isAndroid: true).documentDirectory(_uriRef), isNull);
  });

  test('uri가 아닌 문서와 Android가 아닌 기기는 null', () async {
    _mock(allowed: true, path: '/x/a.md');
    const pathRef = DocumentRef(kind: DocumentRefKind.path, value: r'C:\a\b.md');
    expect(await StorageAccessService(isAndroid: true).documentDirectory(pathRef), isNull);
    expect(await StorageAccessService(isAndroid: false).documentDirectory(_uriRef), isNull);
    expect(await StorageAccessService(isAndroid: false).hasAllFilesAccess(), isFalse);
  });

  test('권한이 있는 기기인지 확인한다 (Android만)', () async {
    _mock(allowed: false);
    expect(await StorageAccessService(isAndroid: true).canRequestAllFilesAccess(), isTrue);
    expect(await StorageAccessService(isAndroid: false).canRequestAllFilesAccess(), isFalse);
  });

  test('처음 안내를 보여줬는지 기억한다', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AllFilesAccessPromptStore();
    expect(await store.wasShown(), isFalse);
    await store.markShown();
    expect(await store.wasShown(), isTrue);
  });

  test('네이티브가 없으면(MissingPlugin) 안전하게 false/null', () async {
    final service = StorageAccessService(isAndroid: true);
    expect(await service.hasAllFilesAccess(), isFalse);
    expect(await service.documentDirectory(_uriRef), isNull);
  });
}
