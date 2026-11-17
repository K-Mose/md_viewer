import 'package:flutter/material.dart';

import '../app_info.dart';
import '../services/app_settings.dart';
import '../services/document_service.dart';
import '../services/draft_store.dart';
import '../services/reading_position_store.dart';
import '../services/recent_files.dart';
import '../services/text_decoder.dart';
import '../theme/app_theme.dart';
import '../theme/text_scale_scope.dart';
import 'home_screen.dart' show formatRelativeTime;

/// 설정 화면. 바꾸는 즉시 저장되고, 뷰어와 에디터는 다음에 열 때부터 적용된다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = AppSettings.instance;
  final _recentStore = RecentFilesStore();
  final _positionStore = ReadingPositionStore();
  final _draftStore = DraftStore();
  final _documents = DocumentService.instance;

  int _recentCount = 0;
  int _positionCount = 0;
  Draft? _draft;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  /// "지우기" 항목에 보여줄 개수와 임시저장 상태를 다시 읽는다.
  Future<void> _refresh() async {
    final recents = await _recentStore.load();
    final positions = await _positionStore.count();
    final draft = await _draftStore.load();
    if (!mounted) return;
    setState(() {
      _recentCount = recents.length;
      _positionCount = positions;
      _draft = draft;
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String action = '지우기',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: title,
        message: message,
        action: action,
      ),
    );
    return result ?? false;
  }

  Future<void> _clearRecents() async {
    final ok = await _confirm(
      title: '최근 파일 목록을 지울까요?',
      message: '목록에서만 지워지고 원본 파일은 그대로예요. '
          '지워진 파일의 읽던 위치 기록도 함께 지워져요.',
    );
    if (!ok) return;
    final removed = await _recentStore.clear();
    for (final file in removed) {
      await _documents.release(file.ref);
      await _positionStore.remove(file.key);
    }
    await _refresh();
    _showMessage('최근 파일 목록을 지웠어요');
  }

  Future<void> _clearPositions() async {
    final ok = await _confirm(
      title: '읽던 위치 기록을 지울까요?',
      message: '모든 문서를 다시 맨 위부터 읽게 돼요.',
    );
    if (!ok) return;
    await _positionStore.clearAll();
    await _refresh();
    _showMessage('읽던 위치 기록을 지웠어요');
  }

  Future<void> _clearDraft() async {
    final ok = await _confirm(
      title: '임시저장을 삭제할까요?',
      message: '임시저장된 글은 복구할 수 없어요.',
      action: '삭제',
    );
    if (!ok) return;
    await _draftStore.clear();
    await _refresh();
    _showMessage('임시저장을 삭제했어요');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '설정',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _settings,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const _SectionLabel('읽기'),
              _SettingsGroup(
                children: [
                  _TextSizeTile(
                    value: _settings.textScale,
                    onChanged: _settings.setTextScale,
                  ),
                  _ChoiceTile<LineSpacing>(
                    title: '줄 간격',
                    value: _settings.lineSpacing,
                    labels: const {
                      LineSpacing.tight: '좁게',
                      LineSpacing.normal: '보통',
                      LineSpacing.wide: '넓게',
                    },
                    onChanged: _settings.setLineSpacing,
                  ),
                  _ReadingPreview(
                    scale: _settings.textScale,
                    lineHeight: _settings.lineSpacing.markdownHeight,
                  ),
                ],
              ),
              const _SectionLabel('파일'),
              _SettingsGroup(
                children: [
                  _ActionTile(
                    title: '최근 파일 목록 지우기',
                    subtitle: '$_recentCount개',
                    onTap: _recentCount > 0 ? _clearRecents : null,
                  ),
                  _SwitchTile(
                    title: '읽던 위치 기억',
                    subtitle: '문서를 다시 열면 마지막으로 읽던 곳에서 이어서 보여줘요',
                    value: _settings.rememberPosition,
                    onChanged: _settings.setRememberPosition,
                  ),
                  _ActionTile(
                    title: '읽던 위치 기록 지우기',
                    subtitle: '$_positionCount개 문서',
                    onTap: _positionCount > 0 ? _clearPositions : null,
                  ),
                  _ChoiceTile<EncodingPreference>(
                    title: '기본 인코딩',
                    description: '자동은 UTF-8, 안 되면 CP949 순서로 읽어요. '
                        '글자가 깨지면 직접 골라 보세요. 파일을 다시 열 때 적용돼요.',
                    value: _settings.encoding,
                    labels: const {
                      EncodingPreference.auto: '자동',
                      EncodingPreference.utf8: 'UTF-8',
                      EncodingPreference.cp949: 'CP949',
                    },
                    onChanged: _settings.setEncoding,
                  ),
                  _ChoiceTile<TxtViewMode>(
                    title: 'txt 보기 방식',
                    description: '원문은 # 나 * 같은 기호를 해석하지 않고 그대로 보여줘요.',
                    value: _settings.txtViewMode,
                    labels: const {
                      TxtViewMode.raw: '원문 그대로',
                      TxtViewMode.markdown: '마크다운',
                    },
                    onChanged: _settings.setTxtViewMode,
                  ),
                ],
              ),
              const _SectionLabel('에디터'),
              _SettingsGroup(
                children: [
                  _SwitchTile(
                    title: '자동 임시저장',
                    subtitle: '입력을 멈추고 1초 뒤 앱 안에 저장해요',
                    value: _settings.autoDraft,
                    onChanged: _settings.setAutoDraft,
                  ),
                  _ActionTile(
                    title: '임시저장 삭제',
                    subtitle: draft == null
                        ? '임시저장된 문서가 없어요'
                        : '임시저장: ${formatRelativeTime(draft.savedAt)}',
                    onTap: draft != null ? _clearDraft : null,
                  ),
                ],
              ),
              const _SectionLabel('정보'),
              _SettingsGroup(
                children: [
                  const _InfoTile(title: '버전', value: appVersion),
                  _ActionTile(
                    title: '오픈소스 라이선스',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'MD Viewer',
                      applicationVersion: appVersion,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// 항목들을 카드 하나로 묶고 사이에 구분선을 둔다.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _TextSizeTile extends StatelessWidget {
  const _TextSizeTile({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('글자 크기', style: TextStyle(fontSize: 15)),
              const Spacer(),
              Text(
                '${(value * 100).round()}%',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: AppSettings.minTextScale,
            max: AppSettings.maxTextScale,
            divisions: 8,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 고른 글자 크기와 줄 간격이 어떻게 보이는지 미리 보여준다.
class _ReadingPreview extends StatelessWidget {
  const _ReadingPreview({required this.scale, required this.lineHeight});

  final double scale;
  final double? lineHeight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: TextScaleScope(
          scale: scale,
          child: Text(
            '마크다운 파일을 열어 깔끔하게 읽어보세요.\n'
            '글자 크기와 줄 간격은 이렇게 보여요.',
            style: TextStyle(fontSize: 16, height: lineHeight),
          ),
        ),
      ),
    );
  }
}

/// 제목 + 선택지(가로 버튼 묶음).
class _ChoiceTile<T extends Enum> extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.value,
    required this.labels,
    required this.onChanged,
    this.description,
  });

  final String title;
  final String? description;
  final T value;
  final Map<T, String> labels;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final description = this.description;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15)),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [
                for (final entry in labels.entries)
                  ButtonSegment<T>(value: entry.key, label: Text(entry.value)),
              ],
              selected: {value},
              onSelectionChanged: (selection) => onChanged(selection.first),
              style: SegmentedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.textSecondary,
                selectedBackgroundColor: AppColors.accent,
                selectedForegroundColor: AppColors.onAccent,
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

/// 누르면 동작하는 항목. [onTap]이 null이면 흐리게 표시하고 누를 수 없다.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.title, this.subtitle, required this.onTap});

  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textTertiary,
              ),
            ),
      enabled: onTap != null,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      trailing: Text(
        value,
        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.action,
  });

  final String title;
  final String message;
  final String action;

  @override
  Widget build(BuildContext context) {
    // 앱 테마의 FilledButton은 가로로 꽉 차서(Size.fromHeight) 대화상자에는 TextButton을 쓴다.
    return AlertDialog(
      title: Text(title),
      content: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            action,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
