import 'package:flutter/material.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:url_launcher/url_launcher.dart';

class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key, required this.title, required this.content});

  final String title;
  final String content;

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
      body: MarkdownWidget(
        data: content,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        config: MarkdownConfig.darkConfig.copy(
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
          ],
        ),
      ),
    );
  }
}
