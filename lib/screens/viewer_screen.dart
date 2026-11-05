import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../theme/thin_scrollbar.dart';

class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key, required this.title, required this.content});

  final String title;
  final String content;

  static const _padding = EdgeInsets.fromLTRB(20, 8, 20, 40);

  static final _config = MarkdownConfig.darkConfig.copy(
    configs: [
      LinkConfig(
        style: const TextStyle(
          color: Color(0xFF8AB4F8),
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF8AB4F8),
        ),
        onTap: (url) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ),
      TableConfig(
        // 칸 폭 = 그 칸에서 가장 긴 내용의 폭 (화면에 맞춰 좁아지지 않음)
        defaultColumnWidth: const IntrinsicColumnWidth(),
        // 화면보다 넓은 표는 표만 좌우로 스크롤
        wrapper: (table) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: table,
        ),
        border: TableBorder.all(color: AppColors.border),
        headerRowDecoration: const BoxDecoration(color: AppColors.surfaceHigh),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    // 모바일만 핀치 확대. 데스크톱은 InteractiveViewer가 마우스 휠을 확대로 써서
    // 스크롤이 안 되므로 기존 스크롤 뷰를 그대로 쓴다.
    final zoomable = Platform.isAndroid || Platform.isIOS;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: .w600),
          overflow: .ellipsis,
        ),
      ),
      body: ThinScrollbars(
        child: zoomable
            ? _ZoomableMarkdown(
                content: content,
                config: _config,
                padding: _padding,
              )
            : MarkdownWidget(data: content, padding: _padding, config: _config),
      ),
    );
  }
}

/// 핀치로 화면 전체를 확대/축소(1~4배)하고, 한 손가락으로 위아래·좌우로 이동한다.
///
/// 스크롤 뷰를 InteractiveViewer로 감싸면 드래그 제스처가 서로 충돌하므로,
/// 문서 전체를 스크롤 없는 MarkdownBlock으로 그리고 이동은 InteractiveViewer가 맡는다.
/// 이 방식은 기본 스크롤바가 붙지 않아서 [_PositionIndicator]로 위치 막대를 직접 그린다.
/// 확대 정도는 기억하지 않는다 (화면을 닫으면 원래 크기).
class _ZoomableMarkdown extends StatefulWidget {
  const _ZoomableMarkdown({
    required this.content,
    required this.config,
    required this.padding,
  });

  final String content;
  final MarkdownConfig config;
  final EdgeInsets padding;

  @override
  State<_ZoomableMarkdown> createState() => _ZoomableMarkdownState();
}

class _ZoomableMarkdownState extends State<_ZoomableMarkdown> {
  final _transform = TransformationController();
  final _contentKey = GlobalKey();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          InteractiveViewer(
            transformationController: _transform,
            // constrained: false → 자식이 화면보다 길어도 되고, 그만큼 위아래로 이동 가능
            constrained: false,
            minScale: 1,
            maxScale: 4,
            boundaryMargin: EdgeInsets.zero,
            child: SizedBox(
              key: _contentKey,
              width: constraints.maxWidth,
              child: Padding(
                padding: widget.padding,
                child: MarkdownBlock(data: widget.content, config: widget.config),
              ),
            ),
          ),
          // 위치 막대는 따로 다시 그려서, 이동할 때마다 문서(MarkdownBlock)를 다시 만들지 않는다.
          _PositionIndicator(
            transform: _transform,
            contentKey: _contentKey,
            viewportHeight: constraints.maxHeight,
          ),
        ],
      ),
    );
  }
}

/// 확대 화면의 세로 위치 막대. 움직이는 동안만 보이고, 멈추면 잠시 뒤 사라진다.
class _PositionIndicator extends StatefulWidget {
  const _PositionIndicator({
    required this.transform,
    required this.contentKey,
    required this.viewportHeight,
  });

  final TransformationController transform;
  final GlobalKey contentKey;
  final double viewportHeight;

  @override
  State<_PositionIndicator> createState() => _PositionIndicatorState();
}

class _PositionIndicatorState extends State<_PositionIndicator> {
  static const _hideDelay = Duration(milliseconds: 800);
  static const _minThumbHeight = 24.0;

  Timer? _hideTimer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    widget.transform.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(covariant _PositionIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transform != widget.transform) {
      oldWidget.transform.removeListener(_onTransformChanged);
      widget.transform.addListener(_onTransformChanged);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.transform.removeListener(_onTransformChanged);
    super.dispose();
  }

  void _onTransformChanged() {
    setState(() => _visible = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final contentHeight = widget.contentKey.currentContext?.size?.height ?? 0;
    final matrix = widget.transform.value;
    final scale = matrix.getMaxScaleOnAxis();
    final scaledHeight = contentHeight * scale;
    final viewport = widget.viewportHeight;

    // 화면보다 짧으면 위치 막대가 필요 없다.
    if (scaledHeight <= viewport || viewport <= 0) return const SizedBox.shrink();

    final thumbHeight = (viewport * viewport / scaledHeight)
        .clamp(_minThumbHeight, viewport)
        .toDouble();
    final offset = -matrix.getTranslation().y; // 위로 이동한 거리
    final progress = (offset / (scaledHeight - viewport)).clamp(0.0, 1.0);
    final top = progress * (viewport - thumbHeight);

    return Positioned(
      right: 2,
      top: top,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            width: ThinScrollbarStyle.thickness,
            height: thumbHeight,
            decoration: const BoxDecoration(
              color: ThinScrollbarStyle.color,
              borderRadius: BorderRadius.all(ThinScrollbarStyle.radius),
            ),
          ),
        ),
      ),
    );
  }
}
