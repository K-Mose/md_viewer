import 'package:flutter/material.dart';

import '../services/document_service.dart';
import '../services/opened_file_service.dart';
import '../services/recent_files.dart';
import '../services/text_decoder.dart';
import '../theme/app_theme.dart';
import 'viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _store = RecentFilesStore();
  final _documents = DocumentService.instance;
  List<RecentFile> _recentFiles = [];

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _initOpenedFileService();
  }

  @override
  void dispose() {
    OpenedFileService.instance
      ..onFileOpened = null
      ..dispose();
    super.dispose();
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
    if (initial != null) _showDocument(initial);
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
    final update = await _store.add(document.toRecent());
    for (final evicted in update.evicted) {
      _documents.release(evicted.ref);
    }
    if (!mounted) return;
    setState(() => _recentFiles = update.files);

    if (document.text.encoding == TextEncoding.utf8Lossy) {
      _showMessage('인코딩을 알 수 없어 일부 글자가 깨져 보일 수 있어요.');
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ViewerScreen(title: document.name, content: document.text.text),
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
                  const _Header(),
                  const SizedBox(height: 40),
                  _ActionButtons(onOpenFile: _pickAndOpenFile),
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
  const _Header();

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
              onPressed: () {},
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
  const _ActionButtons({required this.onOpenFile});

  final VoidCallback onOpenFile;

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
          onPressed: () {
            // TODO: 에디터 모드 (추후)
          },
          icon: const Icon(Icons.edit_note_rounded, size: 22),
          label: const Text('새 문서'),
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
