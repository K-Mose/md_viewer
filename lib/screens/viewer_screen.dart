import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/reading_position_store.dart';
import '../theme/app_theme.dart';
import '../theme/thin_scrollbar.dart';

class ViewerScreen extends StatefulWidget {
  const ViewerScreen({
    super.key,
    required this.title,
    required this.content,
    this.positionKey,
    this.initialPosition,
    this.plainText = false,
  });

  final String title;
  final String content;

  /// 읽던 위치를 기억할 문서의 키. null이면 위치를 저장하지 않는다 (예: 에디터 미리보기).
  final String? positionKey;

  /// 처음 열 때 이동할 위치. null이면 맨 위에서 시작한다.
  final ReadingPosition? initialPosition;

  /// true면 마크다운으로 해석하지 않고 원문 그대로 보여준다 (.txt).
  final bool plainText;

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
  State<ViewerScreen> createState() => _ViewerScreenState();
}

/// 읽던 위치 기억/복원.
///
/// MarkdownWidget은 문서를 블록 단위 ListView로 그리고, 블록마다 AutoScrollTag를 붙여 둔다.
/// 그래서 "화면 맨 위에 걸친 블록 번호 + 그 블록 안에서의 거리"를 저장하고,
/// 열 때 scrollToIndex로 그 블록까지 이동한 뒤 거리만큼 더 이동한다.
/// 픽셀 위치만 저장하면 아직 그려지지 않은 아래쪽 블록 높이가 추정치라 어긋난다.
class _ViewerScreenState extends State<ViewerScreen>
    with WidgetsBindingObserver {
  final _markdownKey = GlobalKey<MarkdownWidgetState>();
  final _positions = ReadingPositionStore();

  /// 원문(.txt) 보기의 스크롤 컨트롤러. 마크다운 보기는 MarkdownWidget이 자기 것을 가진다.
  final _plainController = AutoScrollController();

  AutoScrollController? get _scrollController => widget.plainText
      ? _plainController
      : _markdownKey.currentState?.controller;

  /// 복원 이동이 끝날 때까지 본문을 투명하게 둬서, 맨 위가 잠깐 보였다 점프하는 모습을 막는다.
  /// (레이아웃은 그대로 일어나므로 이동에는 영향이 없다.)
  late bool _restoring = widget.initialPosition != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = widget.initialPosition;
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restore(initial));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _plainController.dispose();
    super.dispose();
  }

  /// 앱이 백그라운드로 가면 (모바일에서는 이대로 종료될 수 있다) 지금 위치를 저장한다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _savePosition();
  }

  Future<void> _restore(ReadingPosition position) async {
    try {
      final controller = _scrollController;
      if (controller == null) return;
      await controller
          .scrollToIndex(
            position.index,
            // 0보다 커야 한다. 사실상 즉시 이동.
            duration: const Duration(milliseconds: 1),
            preferPosition: AutoScrollPosition.begin,
          )
          // 이동이 끝나지 않아도 본문이 계속 숨겨져 있지 않게 한다.
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      if (!mounted || !controller.hasClients) return;
      final blockStart = _blockStart(controller, position.index);
      if (blockStart == null) return;
      final metrics = controller.position;
      controller.jumpTo(
        (blockStart + position.offset)
            .clamp(metrics.minScrollExtent, metrics.maxScrollExtent)
            .toDouble(),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  void _savePosition() {
    final key = widget.positionKey;
    // 복원 이동 중의 중간 위치를 저장하면 안 된다.
    if (key == null || _restoring) return;
    final position = _currentPosition();
    if (position != null) unawaited(_positions.save(key, position));
  }

  /// 화면 맨 위에 걸친 블록과 그 블록 안에서의 거리.
  ReadingPosition? _currentPosition() {
    final controller = _scrollController;
    if (controller == null || !controller.hasClients) return null;
    final scrollOffset = controller.offset;

    // 지금 그려져 있는 블록(화면 + 앞뒤 여분)만 tagMap에 있다.
    int? topIndex; // 시작점이 화면 맨 위 이상인 블록 중 가장 아래 것 = 맨 위에 걸친 블록
    double? topStart;
    int? firstIndex; // 그런 블록이 없을 때(맨 위 여백 구간)를 위한 가장 앞 블록
    double? firstStart;
    for (final index in controller.tagMap.keys) {
      final start = _blockStart(controller, index);
      if (start == null) continue;
      if (firstIndex == null || index < firstIndex) {
        firstIndex = index;
        firstStart = start;
      }
      final startsAboveTop = start <= scrollOffset + 0.5;
      if (startsAboveTop && (topIndex == null || index > topIndex)) {
        topIndex = index;
        topStart = start;
      }
    }
    final index = topIndex ?? firstIndex;
    final start = topStart ?? firstStart;
    if (index == null || start == null) return null;
    return ReadingPosition(
      index: index,
      offset: scrollOffset - start,
      length: widget.content.length,
    );
  }

  /// [index] 블록의 시작점이 화면 맨 위에 오게 하는 스크롤 위치. 블록이 아직 그려지지 않았으면 null.
  double? _blockStart(AutoScrollController controller, int index) {
    final tagContext = controller.tagMap[index]?.context;
    if (tagContext == null || !tagContext.mounted) return null;
    final renderObject = tagContext.findRenderObject();
    if (renderObject == null) return null;
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    return viewport?.getOffsetToReveal(renderObject, 0).offset;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 뒤로 가기(버튼, 제스처, 앱바)로 나갈 때 저장
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _savePosition();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: .w600),
            overflow: .ellipsis,
          ),
        ),
        body: ThinScrollbars(
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              // 본문 세로 스크롤만 (표 가로 스크롤은 depth가 다르다)
              if (notification.depth == 0) _savePosition();
              return false;
            },
            child: Opacity(
              opacity: _restoring ? 0 : 1,
              child: widget.plainText
                  ? _PlainTextView(
                      content: widget.content,
                      controller: _plainController,
                    )
                  : MarkdownWidget(
                      key: _markdownKey,
                      data: widget.content,
                      padding: ViewerScreen._padding,
                      config: ViewerScreen._config,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// .txt 원문 보기. 마크다운으로 해석하지 않고 줄바꿈과 공백을 그대로 보여준다.
///
/// 긴 파일도 가볍게 그리려고 [_linesPerChunk]줄씩 묶어 ListView 항목으로 만들고,
/// 항목마다 AutoScrollTag를 붙여 읽던 위치 저장/복원이 마크다운 보기와 같은 방식으로 동작한다.
class _PlainTextView extends StatefulWidget {
  const _PlainTextView({required this.content, required this.controller});

  final String content;
  final AutoScrollController controller;

  @override
  State<_PlainTextView> createState() => _PlainTextViewState();
}

class _PlainTextViewState extends State<_PlainTextView> {
  static const _linesPerChunk = 40;

  late List<String> _chunks = _split(widget.content);

  @override
  void didUpdateWidget(covariant _PlainTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content) {
      _chunks = _split(widget.content);
    }
  }

  static List<String> _split(String content) {
    final lines =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final chunks = <String>[];
    for (var start = 0; start < lines.length; start += _linesPerChunk) {
      final end = start + _linesPerChunk;
      chunks.add(
        lines.sublist(start, end < lines.length ? end : lines.length).join('\n'),
      );
    }
    return chunks;
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 14,
      height: 1.6,
      fontFamily: 'monospace',
      // Windows, iOS/macOS에는 'monospace'가 없어서 대신 쓸 고정폭 글꼴
      fontFamilyFallback: const ['Consolas', 'Menlo', 'Courier New'],
    );
    return SelectionArea(
      child: ListView.builder(
        controller: widget.controller,
        padding: ViewerScreen._padding,
        itemCount: _chunks.length,
        itemBuilder: (context, index) => AutoScrollTag(
          key: ValueKey(index),
          controller: widget.controller,
          index: index,
          child: Text(_chunks[index], style: style),
        ),
      ),
    );
  }
}
