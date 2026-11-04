import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/document_service.dart';
import '../services/draft_store.dart';
import '../services/recent_files.dart';
import '../theme/app_theme.dart';
import 'viewer_screen.dart';

/// 첫 번째 줄(제목)로 저장 파일명을 제안한다. 없으면 '새 문서.md'.
String suggestFileName(String text) {
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    var name = line
        .replaceFirst(RegExp(r'^#+\s*'), '')
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .trim();
    if (name.length > 40) name = name.substring(0, 40).trim();
    if (name.isNotEmpty) return '$name.md';
    break;
  }
  return '새 문서.md';
}

/// 새 마크다운 문서 작성 화면.
///
/// - 상단: 미리보기(뷰어로 보기), 저장(처음엔 다른 이름으로 저장, 이후 덮어쓰기)
/// - 입력이 멈추고 1초 뒤 앱 안에 자동 임시저장
/// - 저장하지 않은 채 나가면 저장 / 임시저장 / 저장 안 함 선택
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.initialText = ''});

  /// 임시저장에서 이어 쓸 때의 내용
  final String initialText;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _ExitChoice { save, draft, discard }

class _EditorScreenState extends State<EditorScreen> {
  static const _autosaveDelay = Duration(seconds: 1);

  final _draftStore = DraftStore();
  final _recentStore = RecentFilesStore();
  final _documents = DocumentService.instance;
  late final _controller = TextEditingController(text: widget.initialText);

  Timer? _autosaveTimer;

  /// 파일로 저장한 문서 (아직 저장 안 했으면 null)
  SavedDocument? _saved;

  /// 마지막으로 파일에 저장한 내용. 이것과 다르면 "변경됨".
  String _savedText = '';
  bool _dirty = false;
  bool _saving = false;

  String get _title => _saved?.name ?? '새 문서';

  @override
  void initState() {
    super.initState();
    _dirty = _controller.text != _savedText;
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final dirty = _controller.text != _savedText;
    // 키 입력마다 화면 전체를 다시 그리지 않도록 상태가 바뀔 때만 setState
    if (dirty != _dirty) setState(() => _dirty = dirty);

    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(_autosaveDelay, _autosave);
  }

  Future<void> _autosave() async {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      await _draftStore.clear();
    } else if (text != _savedText) {
      await _draftStore.save(text);
    }
  }

  void _openPreview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewerScreen(title: _title, content: _controller.text),
      ),
    );
  }

  /// 파일로 저장한다. 성공하면 true.
  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    _autosaveTimer?.cancel();
    final text = _controller.text;

    try {
      final saved = await _writeOrSaveAs(text);
      if (saved == null) return false; // 사용자가 취소

      _saved = saved;
      _savedText = text;
      await _draftStore.clear();
      final update = await _recentStore.add(saved.toRecent());
      for (final evicted in update.evicted) {
        _documents.release(evicted.ref);
      }
      _showMessage('저장했어요');
      return true;
    } on DocumentException {
      _showMessage('저장하지 못했어요. 다른 위치에 저장해 보세요.');
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = _controller.text != _savedText;
        });
      }
    }
  }

  /// 이미 저장한 파일이 있으면 덮어쓰고, 없거나 사라졌으면 다른 이름으로 저장한다.
  Future<SavedDocument?> _writeOrSaveAs(String text) async {
    final saved = _saved;
    if (saved != null) {
      try {
        final ref = await _documents.write(saved.ref, text);
        return SavedDocument(name: saved.name, ref: ref, location: saved.location);
      } on DocumentException catch (e) {
        if (e.kind == DocumentErrorKind.unknown) rethrow;
        // 원본이 삭제됐거나 쓰기 권한이 없어지면 새 위치를 고르게 한다.
      }
    }
    return _documents.saveAs(suggestedName: suggestFileName(text), text: text);
  }

  Future<void> _confirmExit() async {
    final choice = await showDialog<_ExitChoice>(
      context: context,
      builder: (_) => const _ExitDialog(),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _ExitChoice.save:
        if (!await _save()) return;
      case _ExitChoice.draft:
        _autosaveTimer?.cancel();
        await _draftStore.save(_controller.text);
      case _ExitChoice.discard:
        _autosaveTimer?.cancel();
        await _draftStore.clear();
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // 변경 없이 나갈 때: 빈 문서였다면 임시저장도 남기지 않는다.
          _autosaveTimer?.cancel();
          if (_controller.text.trim().isEmpty) _draftStore.clear();
          return;
        }
        _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _EditorTitle(title: _title, dirty: _dirty),
          actions: [
            _AppBarAction(
              tooltip: '미리보기',
              icon: Icons.visibility_outlined,
              onPressed: _openPreview,
            ),
            _AppBarAction(
              tooltip: '저장',
              icon: Icons.save_outlined,
              onPressed: _saving ? null : _save,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          top: false,
          child: _EditorField(controller: _controller),
        ),
      ),
    );
  }
}

class _EditorTitle extends StatelessWidget {
  const _EditorTitle({required this.title, required this.dirty});

  final String title;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    return Text(
      dirty ? '$title •' : title,
      style: const TextStyle(fontSize: 16, fontWeight: .w600),
      overflow: .ellipsis,
    );
  }
}

/// 앱바 아이콘 버튼. 테마의 onSurface(본문 글자색)를 써서 배경과 최대 대비로 보이게 한다.
/// 색을 상수로 박지 않아 라이트 테마를 추가해도 자동으로 대비가 맞는다.
class _AppBarAction extends StatelessWidget {
  const _AppBarAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: onSurface,
      disabledColor: onSurface.withValues(alpha: 0.38),
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      expands: true,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: const TextStyle(
        fontSize: 15,
        height: 1.6,
        color: AppColors.textPrimary,
      ),
      decoration: const InputDecoration(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.fromLTRB(20, 12, 20, 40),
        hintText: '# 제목\n\n마크다운으로 작성해 보세요.',
        hintStyle: TextStyle(color: AppColors.textTertiary),
      ),
    );
  }
}

class _ExitDialog extends StatelessWidget {
  const _ExitDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('저장하지 않은 내용이 있어요'),
      content: const Text(
        '임시저장하면 앱 안에 보관되고, 다음에 "새 문서"에서 이어서 쓸 수 있어요.',
        style: TextStyle(color: AppColors.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ExitChoice.discard),
          child: const Text('저장 안 함'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ExitChoice.draft),
          child: const Text('임시저장'),
        ),
        // 앱 테마의 FilledButton은 가로로 꽉 차서(Size.fromHeight) 대화상자에는 TextButton을 쓴다.
        TextButton(
          onPressed: () => Navigator.of(context).pop(_ExitChoice.save),
          child: const Text('저장', style: TextStyle(fontWeight: .w700)),
        ),
      ],
    );
  }
}
