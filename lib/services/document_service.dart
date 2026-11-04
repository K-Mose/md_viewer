import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'recent_files.dart';
import 'text_decoder.dart';

/// 문서를 열지 못한 이유.
enum DocumentErrorKind {
  /// 파일이 삭제되었거나 이동됨 → 최근 목록에서 지워도 됨
  notFound,

  /// 다시 열 권한이 없음 → 다시 선택해야 함
  permissionDenied,

  /// 그 밖의 오류 (일시적일 수 있으므로 목록에 남긴다)
  unknown,
}

class DocumentException implements Exception {
  const DocumentException(this.kind, [this.message]);

  final DocumentErrorKind kind;
  final String? message;

  @override
  String toString() => 'DocumentException($kind, $message)';
}

/// 열린 문서. [ref]는 최근 목록에 저장해 두었다가 [DocumentService.open]에 다시 넘긴다.
class LoadedDocument {
  const LoadedDocument({
    required this.name,
    required this.ref,
    required this.location,
    required this.text,
  });

  final String name;
  final DocumentRef ref;
  final String location;
  final DecodedText text;

  RecentFile toRecent() => RecentFile(
        name: name,
        ref: ref,
        location: location,
        openedAt: DateTime.now(),
      );
}

/// 새로 저장한 문서. 다음 저장부터는 [ref]에 덮어쓴다.
class SavedDocument {
  const SavedDocument({
    required this.name,
    required this.ref,
    required this.location,
  });

  final String name;
  final DocumentRef ref;
  final String location;

  RecentFile toRecent() => RecentFile(
        name: name,
        ref: ref,
        location: location,
        openedAt: DateTime.now(),
      );
}

/// 플랫폼별 문서 선택/읽기를 감싼다.
///
/// - Android: 시스템 파일 선택기(ACTION_OPEN_DOCUMENT) + 영구 읽기 권한(content:// URI)
/// - iOS: UIDocumentPicker(원본 위치에서 열기) + security-scoped bookmark
/// - 그 밖(Windows 등): file_picker가 돌려주는 실제 경로
class DocumentService {
  DocumentService._();

  static final instance = DocumentService._();

  static const _channel = MethodChannel('md_viewer/documents');
  static const allowedExtensions = ['md', 'markdown', 'txt'];

  bool get _usesNativePicker => Platform.isAndroid || Platform.isIOS;

  /// 파일 선택기를 띄운다. 취소하면 null.
  Future<LoadedDocument?> pick() async {
    if (_usesNativePicker) {
      final Map<String, dynamic>? result;
      try {
        result = await _channel.invokeMapMethod<String, dynamic>('pickDocument');
      } on PlatformException catch (e) {
        throw _fromPlatform(e);
      }
      if (result == null) return null;
      return fromNativeMap(result);
    }

    // file_picker 12.3+는 FilePickerResult 대신 List<PlatformFile>을 돌려준다 (취소 시 빈 리스트).
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    final path = picked.firstOrNull?.path;
    if (path == null) return null;
    return open(DocumentRef(kind: DocumentRefKind.path, value: path));
  }

  /// 저장해 둔 참조로 문서를 다시 연다. 실패하면 [DocumentException].
  Future<LoadedDocument> open(DocumentRef ref, {String? name}) async {
    switch (ref.kind) {
      case DocumentRefKind.path:
      case DocumentRefKind.copy:
        final bytes = await _readPath(ref.value);
        return LoadedDocument(
          name: name ?? p.basename(ref.value),
          ref: ref,
          location: ref.value,
          text: decodeText(bytes),
        );
      case DocumentRefKind.uri:
      case DocumentRefKind.bookmark:
        final Map<String, dynamic>? result;
        try {
          result = await _channel.invokeMapMethod<String, dynamic>(
            'readDocument',
            ref.toJson(),
          );
        } on PlatformException catch (e) {
          throw _fromPlatform(e);
        } on MissingPluginException {
          throw const DocumentException(DocumentErrorKind.unknown);
        }
        if (result == null) {
          throw const DocumentException(DocumentErrorKind.unknown);
        }
        return fromNativeMap(result, fallbackRef: ref, fallbackName: name);
    }
  }

  /// "다른 이름으로 저장": 저장 위치와 파일명을 고르는 창을 띄우고 UTF-8로 저장한다. 취소하면 null.
  ///
  /// - Android: ACTION_CREATE_DOCUMENT + 영구 읽기/쓰기 권한
  /// - iOS: UIDocumentPicker(내보내기) + bookmark
  /// - 데스크톱: file_picker 저장 대화상자
  Future<SavedDocument?> saveAs({
    required String suggestedName,
    required String text,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(text));

    if (_usesNativePicker) {
      final Map<String, dynamic>? result;
      try {
        result = await _channel.invokeMapMethod<String, dynamic>(
          'createDocument',
          {'name': suggestedName, 'bytes': bytes},
        );
      } on PlatformException catch (e) {
        throw _fromPlatform(e);
      }
      if (result == null) return null;
      final ref = result['ref'];
      if (ref is! Map) throw const DocumentException(DocumentErrorKind.unknown);
      final name = result['name'] as String? ?? suggestedName;
      return SavedDocument(
        name: name,
        ref: DocumentRef.fromJson(Map<String, dynamic>.from(ref)),
        location: result['location'] as String? ?? name,
      );
    }

    final uri = await FilePicker.saveFile(
      dialogTitle: '마크다운 저장',
      fileName: suggestedName,
      bytes: bytes,
      mimeType: 'text/markdown',
    );
    if (uri == null) return null;
    final path = uri.isScheme('file') ? uri.toFilePath() : uri.toString();
    // 플랫폼 구현에 따라 bytes를 직접 쓰지 않을 수 있어 한 번 더 확실히 쓴다.
    await _writePath(path, bytes);
    return SavedDocument(
      name: p.basename(path),
      ref: DocumentRef(kind: DocumentRefKind.path, value: path),
      location: path,
    );
  }

  /// 이미 저장한 문서에 덮어쓴다. bookmark가 갱신되면 새 참조를 돌려준다.
  Future<DocumentRef> write(DocumentRef ref, String text) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    switch (ref.kind) {
      case DocumentRefKind.path:
      case DocumentRefKind.copy:
        await _writePath(ref.value, bytes);
        return ref;
      case DocumentRefKind.uri:
      case DocumentRefKind.bookmark:
        final Map<String, dynamic>? result;
        try {
          result = await _channel.invokeMapMethod<String, dynamic>(
            'writeDocument',
            {...ref.toJson(), 'bytes': bytes},
          );
        } on PlatformException catch (e) {
          throw _fromPlatform(e);
        }
        final newRef = result?['ref'];
        return newRef is Map
            ? DocumentRef.fromJson(Map<String, dynamic>.from(newRef))
            : ref;
    }
  }

  Future<void> _writePath(String path, Uint8List bytes) async {
    try {
      await File(path).writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (e) {
      final code = e.osError?.errorCode;
      if (code == 13 || (Platform.isWindows && code == 5)) {
        throw DocumentException(DocumentErrorKind.permissionDenied, e.message);
      }
      if (code == 2 || code == 3) {
        throw DocumentException(DocumentErrorKind.notFound, e.message);
      }
      throw DocumentException(DocumentErrorKind.unknown, e.message);
    }
  }

  /// 최근 목록에서 빠진 문서의 권한/사본을 정리한다. 실패해도 무시한다.
  Future<void> release(DocumentRef ref) async {
    try {
      switch (ref.kind) {
        case DocumentRefKind.copy:
          final file = File(ref.value);
          if (await file.exists()) await file.delete();
        case DocumentRefKind.uri:
          await _channel.invokeMethod<void>('releaseDocument', ref.toJson());
        case DocumentRefKind.path:
        case DocumentRefKind.bookmark:
          break; // 정리할 것 없음
      }
    } catch (_) {}
  }

  /// 네이티브가 돌려준 {name, bytes, ref:{kind,value}, location} 맵을 변환한다.
  LoadedDocument fromNativeMap(
    Map<String, dynamic> map, {
    DocumentRef? fallbackRef,
    String? fallbackName,
  }) {
    final bytes = map['bytes'];
    if (bytes is! Uint8List) {
      throw const DocumentException(DocumentErrorKind.unknown);
    }
    final rawRef = map['ref'];
    final ref = rawRef is Map
        ? DocumentRef.fromJson(Map<String, dynamic>.from(rawRef))
        : fallbackRef;
    if (ref == null) {
      throw const DocumentException(DocumentErrorKind.unknown);
    }
    final name = map['name'] as String? ?? fallbackName ?? 'document.md';
    return LoadedDocument(
      name: name,
      ref: ref,
      location: map['location'] as String? ?? name,
      text: decodeText(bytes),
    );
  }

  Future<Uint8List> _readPath(String path) async {
    final file = File(path);
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (e) {
      if (!await file.exists()) {
        throw DocumentException(DocumentErrorKind.notFound, e.message);
      }
      // EACCES(13, POSIX) / ERROR_ACCESS_DENIED(5, Windows)
      final code = e.osError?.errorCode;
      if (code == 13 || (Platform.isWindows && code == 5)) {
        throw DocumentException(DocumentErrorKind.permissionDenied, e.message);
      }
      throw DocumentException(DocumentErrorKind.unknown, e.message);
    }
  }

  DocumentException _fromPlatform(PlatformException e) {
    final kind = switch (e.code) {
      'not_found' => DocumentErrorKind.notFound,
      'permission_denied' => DocumentErrorKind.permissionDenied,
      _ => DocumentErrorKind.unknown,
    };
    return DocumentException(kind, e.message);
  }
}
