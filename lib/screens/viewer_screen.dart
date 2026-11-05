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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: .w600),
          overflow: .ellipsis,
        ),
      ),
      body: ThinScrollbars(
        child: MarkdownWidget(data: content, padding: _padding, config: _config),
      ),
    );
  }
}
