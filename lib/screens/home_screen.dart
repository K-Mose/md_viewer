import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/document_service.dart';
import '../services/draft_store.dart';
import '../services/image_resolver.dart';
import '../services/opened_file_service.dart';
import '../services/reading_position_store.dart';
import '../services/recent_files.dart';
import '../services/storage_access.dart';
import '../services/text_decoder.dart';
import '../theme/app_theme.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({this.initialFile, super.key});

  final String? initialFile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _store = RecentFilesStore();
  final _positions = ReadingPositionStore();
  final _documents = DocumentService.instance;
  List<RecentFile> _recentFiles = [];

  /// 시스템 설정(모든 파일 접근)에 갔다가 앱으로 돌아오기를 기다리는 중이면 값이 있다.
  Completer<void>? _resumeWaiter;
  bool _sawPause = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initOpenedFileService();
    _loadRecents().then((_) => _loadInitialFile());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OpenedFileService.instance
      ..onFileOpened = null
      ..dispose();
    super.dispose();
  }

  Future<void> _loadInitialFile() async {
    final path = widget.initialFile;
    if (path == null || !mounted) return;
    final LoadedDocument document;
    try {
      document = await _documents.open(
        DocumentRef(kind: DocumentRefKind.path, value: path),
      );
    } on DocumentException catch (e) {
      if (!mounted) return;
      _showMessage(switch (e.kind) {
        DocumentErrorKind.notFound => '파일을 찾을 수 없어요.',
        DocumentErrorKind.permissionDenied => '이 파일을 열 권한이 없어요.',
        DocumentErrorKind.unknown => '파일을 여는 중 문제가 생겼어요.',
      });
      return;
    }
    await _showDocument(document);
  }

  Future<void> _loadRecents() async {
    final files = await _store.load();
    if (!mounted) return;
    setState(() => _recentFiles = files);
  }

  Future<void> _initOpenedFileService() async {
    final service = OpenedFileService.instance;
    service.onFileOpened = _showDocument;
    final initial = await service.init();
    if (initial != null) {
      _showDocument(initial);
    } else {
      // 외부에서 문서를 열며 시작한 게 아닐 때만 처음 안내를 보여준다.
      await _askAllFilesAccessOnFirstRun();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _sawPause = true;
    // 설정 화면에 다녀온 뒤에만 기다림을 끝낸다.
    if (state == AppLifecycleState.resumed && _sawPause) {
      final waiter = _resumeWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
  }

  /// 시스템 설정의 "모든 파일 접근" 화면을 열고, 사용자가 앱으로 돌아올 때까지 기다린다.
  Future<void> _openAllFilesSettingsAndWait() async {
    final waiter = Completer<void>();
    _resumeWaiter = waiter;
    _sawPause = false;
    await StorageAccessService.instance.openAllFilesSettings();
    await waiter.future.timeout(const Duration(minutes: 3), onTimeout: () {});
    _resumeWaiter = null;
  }

  /// 앱을 처음 켰을 때 한 번만 "모든 파일 접근" 허용을 안내한다 (Android 11 이상).
  /// 거절해도 설정 화면과 이미지가 있는 문서를 열 때 다시 안내한다.
  Future<void> _askAllFilesAccessOnFirstRun() async {
    final access = StorageAccessService.instance;
    final promptStore = AllFilesAccessPromptStore();
    if (!await access.canRequestAllFilesAccess() ||
        await access.hasAllFilesAccess() ||
        await promptStore.wasShown()) {
      return;
    }
    if (!mounted) return;
    await promptStore.markShown();
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (_) => const _AllFilesAccessDialog(
        message: '마크다운 문서와 같은 폴더에 있는 이미지를 바로 보여주려면 '
            '"모든 파일 접근"이 필요해요. 설정 화면에서 이 앱을 허용해 주세요.\n'
            '나중에 설정 화면에서도 바꿀 수 있어요.',
      ),
    );
    if (open == true) await StorageAccessService.instance.openAllFilesSettings();
  }

  Future<void> _pickAndOpenFile() async {
    final LoadedDocument? document;
    try {
      document = await _documents.pick();
    } on DocumentException {
      _showMessage('파일을 열 수 없어요. 다른 파일을 선택해 주세요.');
      return;
    }
    if (document != null) await _showDocument(document);
  }

  /// 새 문서. 임시저장된 글이 있으면 이어서 쓸지 먼저 묻는다.
  Future<void> _newDocument() async {
    final draftStore = DraftStore();
    final draft = await draftStore.load();
    if (!mounted) return;

    var initialText = '';
    if (draft != null) {
      final choice = await showDialog<_DraftChoice>(
        context: context,
        builder: (_) => _DraftDialog(savedAt: draft.savedAt),
      );
      if (choice == null || !mounted) return;
      if (choice == _DraftChoice.resume) {
        initialText = draft.text;
      } else {
        await draftStore.clear();
        if (!mounted) return;
      }
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EditorScreen(initialText: initialText)),
    );
    // 에디터에서 저장한 파일이 최근 목록에 추가됐을 수 있다.
    await _loadRecents();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    // 설정에서 최근 파일을 지웠을 수 있다.
    await _loadRecents();
  }

  Future<void> _openRecent(RecentFile file) async {
    final LoadedDocument document;
    try {
      document = await _documents.open(file.ref, name: file.name);
    } on DocumentException catch (e) {
      await _handleOpenError(file, e.kind);
      return;
    }
    await _showDocument(document);
  }

  /// 최근 목록에 기록하고 뷰어로 이동한다. 앱 안에서 연 파일과 외부 앱에서 연 파일 모두 여기로 온다.
  Future<void> _showDocument(LoadedDocument document) async {
    final recent = document.toRecent();
    final update = await _store.add(recent);
    for (final evicted in update.evicted) {
      _documents.release(evicted.ref);
      await _positions.remove(evicted.key);
    }
    final settings = AppSettings.instance;
    // 마지막으로 읽던 위치. 파일 내용이 바뀌었으면 null이라 맨 위부터 읽는다.
    // 설정에서 기억을 끄면 불러오지도, 저장하지도 않는다.
    final position = settings.rememberPosition
        ? await _positions.load(
            recent.key,
            length: document.text.text.length,
          )
        : null;
    if (!mounted) return;
    setState(() => _recentFiles = update.files);

    if (document.text.encoding == TextEncoding.utf8Lossy) {
      _showMessage('인코딩을 알 수 없어 일부 글자가 깨져 보일 수 있어요.');
    }
    // 문서 옆 이미지를 읽을 폴더. 일반 경로면 바로 알 수 있고, Android는 "모든 파일 접근"이
    // 허용돼 있으면 문서 주소에서 계산한다.
    final access = StorageAccessService.instance;
    var baseDirectory =
        documentDirectory(document.ref) ?? await access.documentDirectory(document.ref);
    final plainText = document.name.toLowerCase().endsWith('.txt') &&
        settings.txtViewMode == TxtViewMode.raw;
    // 이미지가 있는데 권한이 없어 읽지 못하는 문서는 열 때마다 허용을 안내한다.
    if (baseDirectory == null &&
        !plainText &&
        document.ref.kind != DocumentRefKind.path &&
        hasRelativeImages(document.text.text) &&
        await access.canRequestAllFilesAccess() &&
        !await access.hasAllFilesAccess()) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (_) => const _AllFilesAccessDialog(
          message: '이 문서에는 같은 폴더의 이미지가 있어요. '
              '"모든 파일 접근"을 허용하면 이미지를 바로 볼 수 있어요.\n'
              '허용하고 돌아오면 이 문서가 이어서 열려요.',
        ),
      );
      if (open == true) {
        await _openAllFilesSettingsAndWait();
        baseDirectory = await access.documentDirectory(document.ref);
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViewerScreen(
          title: document.name,
          content: document.text.text,
          positionKey: settings.rememberPosition ? recent.key : null,
          initialPosition: position,
          // .txt는 설정에 따라 원문 그대로(기본) 또는 마크다운으로 보여준다.
          plainText: plainText,
          baseDirectory: baseDirectory,
          document: SavedDocument(
            name: document.name,
            ref: document.ref,
            location: document.location,
          ),
        ),
      ),
    );
  }

  Future<void> _handleOpenError(RecentFile file, DocumentErrorKind kind) async {
    switch (kind) {
      case DocumentErrorKind.notFound:
        _showMessage('파일을 찾을 수 없어요. 삭제되었거나 이동됐을 수 있어요.');
      case DocumentErrorKind.permissionDenied:
        _showMessage('이 파일을 다시 열 권한이 없어요. "파일 열기"로 다시 선택해 주세요.');
      case DocumentErrorKind.unknown:
        // 일시적인 문제일 수 있으므로 목록에서 지우지 않는다.
        _showMessage('파일을 여는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.');
        return;
    }
    final updated = await _store.remove(file);
    _documents.release(file.ref);
    await _positions.remove(file.key);
    if (mounted) setState(() => _recentFiles = updated);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              sliver: SliverList.list(
                children: [
                  _Header(onOpenSettings: _openSettings),
                  const SizedBox(height: 40),
                  _ActionButtons(
                    onOpenFile: _pickAndOpenFile,
                    onNewDocument: _newDocument,
                  ),
                  const SizedBox(height: 44),
                  const _RecentFilesLabel(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              sliver: _recentFiles.isEmpty
                  ? const SliverToBoxAdapter(child: _EmptyRecentFiles())
                  : SliverList.separated(
                      itemCount: _recentFiles.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final file = _recentFiles[index];
                        return _RecentFileTile(
                          name: file.name,
                          path: file.ref.kind == DocumentRefKind.copy
                              ? '앱에 저장된 사본'
                              : file.location,
                          time: formatRelativeTime(file.openedAt),
                          onTap: () => _openRecent(file),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// '오늘 14:02', '어제', '8월 3일' 형태의 상대 시각 문자열.
String formatRelativeTime(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diffDays = today.difference(day).inDays;

  if (diffDays == 0) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '오늘 $hh:$mm';
  }
  if (diffDays == 1) return '어제';
  if (time.year == now.year) return '${time.month}월 ${time.day}일';
  return '${time.year}.${time.month}.${time.day}';
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: .center,
              child: const Text(
                'M↓',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: .w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: onOpenSettings,
              tooltip: '설정',
              icon: const Icon(Icons.settings_outlined),
              color: AppColors.textSecondary,
            ),
          ],
        ),
        const SizedBox(height: 36),
        const Text(
          'Markdown\nViewer',
          style: TextStyle(
            fontSize: 40,
            height: 1.15,
            fontWeight: .w700,
            letterSpacing: -1.0,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          '마크다운 파일을 열어 깔끔하게 읽어보세요.',
          style: TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({required this.onOpenFile, required this.onNewDocument});

  final VoidCallback onOpenFile;
  final VoidCallback onNewDocument;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FilledButton.icon(
          onPressed: onOpenFile,
          icon: const Icon(Icons.folder_open_rounded, size: 20),
          label: const Text('파일 열기'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onNewDocument,
          icon: const Icon(Icons.edit_note_rounded, size: 22),
          label: const Text('새 문서'),
        ),
      ],
    );
  }
}

enum _DraftChoice { resume, fresh }

class _DraftDialog extends StatelessWidget {
  const _DraftDialog({required this.savedAt});

  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('임시저장된 문서가 있어요'),
      content: Text(
        '임시저장: ${formatRelativeTime(savedAt)}\n'
        '이어서 쓸까요? '
        '새로 쓰면 임시저장된 글은 지워져요.',
        style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
      ),
      // 앱 테마의 FilledButton은 가로로 꽉 차서(Size.fromHeight) 대화상자에는 TextButton을 쓴다.
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_DraftChoice.fresh),
          child: const Text('새로 쓰기'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_DraftChoice.resume),
          child: const Text('이어서 쓰기', style: TextStyle(fontWeight: .w700)),
        ),
      ],
    );
  }
}

class _AllFilesAccessDialog extends StatelessWidget {
  const _AllFilesAccessDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('모든 파일 접근을 허용할까요?'),
      content: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
      ),
      // 앱 테마의 FilledButton은 가로로 꽉 차서(Size.fromHeight) 대화상자에는 TextButton을 쓴다.
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('나중에'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('설정 열기', style: TextStyle(fontWeight: .w700)),
        ),
      ],
    );
  }
}

class _RecentFilesLabel extends StatelessWidget {
  const _RecentFilesLabel();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Text(
          '최근 파일',
          style: TextStyle(
            fontSize: 13,
            fontWeight: .w600,
            color: AppColors.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _RecentFileTile extends StatelessWidget {
  const _RecentFileTile({
    required this.name,
    required this.path,
    required this.time,
    required this.onTap,
  });

  final String name;
  final String path;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: .w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      path,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecentFiles extends StatelessWidget {
  const _EmptyRecentFiles();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.history_rounded,
            size: 32,
            color: AppColors.textTertiary,
          ),
          SizedBox(height: 12),
          Text(
            '최근에 연 파일이 없어요',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
          SizedBox(height: 4),
          Text(
            '파일을 열면 여기에 표시됩니다',
            style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
