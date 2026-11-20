import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// 마크다운 이미지 src가 가리키는 실제 이미지.
/// [filePath], [networkUrl], [bytes] 중 하나만 채워진다.
class ImageSource {
  const ImageSource.file(String this.filePath, {this.isSvg = false})
      : networkUrl = null,
        bytes = null;
  const ImageSource.network(String this.networkUrl, {this.isSvg = false})
      : filePath = null,
        bytes = null;
  const ImageSource.memory(Uint8List this.bytes, {this.isSvg = false})
      : filePath = null,
        networkUrl = null;

  /// SVG(벡터) 이미지인지. PNG/JPG 등과 그리는 방법이 다르다.
  final bool isSvg;

  final String? filePath;
  final String? networkUrl;
  final Uint8List? bytes;
}

/// 마크다운의 이미지 [src]를 실제 이미지로 바꾼다. 찾을 수 없으면 null.
///
/// - http(s): 네트워크 이미지
/// - data: base64 이미지
/// - file:// 와 절대 경로: 그대로 사용
/// - 그 외 상대 경로: [baseDirectory](문서가 있는 폴더) 기준으로 해석
///
/// [context]와 [exists]는 테스트에서 바꿔 끼울 수 있다.
ImageSource? resolveImageSource(
  String src, {
  String? baseDirectory,
  p.Context? context,
  bool Function(String path)? exists,
}) {
  final ctx = context ?? p.context;
  final fileExists = exists ?? (path) => File(path).existsSync();
  final value = src.trim();
  if (value.isEmpty) return null;

  final lower = value.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return ImageSource.network(value, isSvg: _isSvgPath(Uri.tryParse(value)?.path ?? value));
  }
  if (lower.startsWith('data:')) return _decodeDataUri(value);

  final candidates = <String>[];
  if (lower.startsWith('file:')) {
    try {
      candidates.add(Uri.parse(value).toFilePath(
        windows: ctx.style == p.Style.windows,
      ));
    } on Object {
      return null;
    }
  } else {
    final decoded = _safeDecode(value);
    candidates.add(decoded);
    // "image.png?raw=1", "image.png#x" 같은 꼬리표가 붙은 경우.
    final cut = decoded.indexOf(RegExp(r'[?#]'));
    if (cut > 0) candidates.add(decoded.substring(0, cut));
  }

  final base = baseDirectory;
  for (final candidate in candidates) {
    final String path;
    if (ctx.isAbsolute(candidate)) {
      path = ctx.normalize(candidate);
    } else if (base != null && base.isNotEmpty) {
      path = ctx.normalize(ctx.join(base, candidate));
    } else {
      continue;
    }
    if (fileExists(path)) {
      return ImageSource.file(path, isSvg: _isSvgPath(path));
    }
  }
  return null;
}

String _safeDecode(String value) {
  try {
    return Uri.decodeFull(value);
  } on Object {
    return value;
  }
}

bool _isSvgPath(String path) => path.toLowerCase().endsWith('.svg');

ImageSource? _decodeDataUri(String value) {
  final comma = value.indexOf(',');
  if (comma < 0) return null;
  final header = value.substring(0, comma).toLowerCase();
  final body = value.substring(comma + 1).trim();
  final svg = header.contains('image/svg+xml');
  try {
    if (header.contains(';base64')) {
      return ImageSource.memory(base64Decode(body), isSvg: svg);
    }
    // base64가 아닌 SVG 텍스트(data:image/svg+xml,<svg ...>)
    if (svg) {
      return ImageSource.memory(
        Uint8List.fromList(utf8.encode(Uri.decodeComponent(body))),
        isSvg: true,
      );
    }
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
  return null;
}

/// 마크다운 본문에 상대 경로 이미지(문서 옆 파일)가 있는지.
/// http(s), data:, file:, 절대 경로 이미지는 세지 않는다.
bool hasRelativeImages(String markdown) {
  for (final match in _imageDestination.allMatches(markdown)) {
    final value = (match.group(1) ?? match.group(2) ?? '').trim();
    if (value.isEmpty) continue;
    final lower = value.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('data:') ||
        lower.startsWith('file:') ||
        lower.startsWith('/') ||
        RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value)) {
      continue;
    }
    return true;
  }
  return false;
}

// ![alt](dest) 또는 ![alt](<dest with spaces>) — 제목("title")은 목적지 뒤에 오므로 무시한다.
final _imageDestination = RegExp(r'!\[[^\]]*\]\((?:<([^>]*)>|([^\s)]*))');
