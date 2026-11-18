import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:markdown_widget/markdown_widget.dart';

import '../services/image_resolver.dart';

/// 문서 옆의 이미지(상대 경로)까지 읽는 마크다운 생성기.
/// [baseDirectory]는 문서가 들어 있는 폴더이며, 모르면 null이다.
MarkdownGenerator buildMarkdownGenerator({String? baseDirectory}) {
  return MarkdownGenerator(
    generators: [
      SpanNodeGeneratorWithTag(
        tag: MarkdownTag.img.name,
        generator: (e, config, visitor) =>
            MarkdownImageNode(e.attributes, config, visitor, baseDirectory),
      ),
    ],
  );
}

/// markdown_widget 기본 ImageNode 대신 쓰는 이미지 노드.
/// 기본 노드는 http가 아니면 앱 에셋으로 읽으려 해서 로컬 파일을 못 보여준다.
class MarkdownImageNode extends SpanNode {
  MarkdownImageNode(
    this.attributes,
    this.config,
    this.visitor,
    this.baseDirectory,
  );

  final Map<String, String> attributes;
  final MarkdownConfig config;
  final WidgetVisitor visitor;
  final String? baseDirectory;

  @override
  InlineSpan build() {
    final src = attributes['src'] ?? '';
    final alt = attributes['alt'] ?? '';
    final width = double.tryParse(attributes['width'] ?? '');
    final height = double.tryParse(attributes['height'] ?? '');
    final source = resolveImageSource(src, baseDirectory: baseDirectory);

    final Widget child;
    if (source == null) {
      child = _BrokenImage(alt: alt, style: parentStyle ?? config.p.textStyle);
    } else {
      final image = _buildImage(source, width, height, alt);
      // 링크 안의 이미지(배지 등)는 링크 탭을 가로채지 않도록 확대 기능을 붙이지 않는다.
      child = parent is LinkNode ? image : _ZoomableImage(child: image);
    }
    return WidgetSpan(child: child);
  }

  Widget _buildImage(ImageSource source, double? width, double? height, String alt) {
    Widget error(BuildContext context, Object error, StackTrace? stack) =>
        _BrokenImage(alt: alt, style: parentStyle ?? config.p.textStyle);
    if (source.isSvg) return _buildSvg(source, width, height, error);
    final path = source.filePath;
    if (path != null) {
      return Image.file(
        File(path),
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: error,
      );
    }
    final url = source.networkUrl;
    if (url != null) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: error,
      );
    }
    return Image.memory(
      source.bytes!,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: error,
    );
  }

  Widget _buildSvg(
    ImageSource source,
    double? width,
    double? height,
    Widget Function(BuildContext, Object, StackTrace?) error,
  ) {
    Widget errorBuilder(BuildContext context, Object e, StackTrace s) =>
        error(context, e, s);
    final path = source.filePath;
    if (path != null) {
      return SvgPicture.file(
        File(path),
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: errorBuilder,
      );
    }
    final url = source.networkUrl;
    if (url != null) {
      return SvgPicture.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const _SvgPlaceholder(),
        errorBuilder: errorBuilder,
      );
    }
    return SvgPicture.memory(
      source.bytes!,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: errorBuilder,
    );
  }
}

class _SvgPlaceholder extends StatelessWidget {
  const _SvgPlaceholder();

  @override
  Widget build(BuildContext context) => const SizedBox(width: 24, height: 24);
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage({required this.alt, required this.style});

  final String alt;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image, color: Colors.redAccent, size: style.fontSize ?? 16),
        if (alt.isNotEmpty) ...[
          const SizedBox(width: 4),
          Flexible(child: Text(alt, style: style)),
        ],
      ],
    );
  }
}

/// 탭하면 전체 화면으로 확대해서 보여준다.
class _ZoomableImage extends StatelessWidget {
  const _ZoomableImage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          PageRouteBuilder<void>(
            opaque: false,
            pageBuilder: (_, _, _) => ImageViewer(child: child),
          ),
        ),
        child: child,
      ),
    );
  }
}
