import 'dart:io';

import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/app_settings.dart';
import 'services/document_service.dart';
import 'theme/app_theme.dart';

/// 명령줄 인자(파일 탐색기에서 문서를 열었을 때) 중 열 수 있는 첫 번째 파일의 절대 경로.
/// 옵션(`--...`), 지원하지 않는 확장자, 없는 파일은 건너뛴다.
String? pickInitialFile(List<String> args) {
  for (final arg in args) {
    if (arg.startsWith('--')) continue;
    final ext = arg.split('.').last.toLowerCase();
    if (!DocumentService.allowedExtensions.contains(ext)) continue;
    final file = File(arg).absolute;
    if (file.existsSync()) return file.path;
  }
  return null;
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final initialFile = Platform.isWindows ? pickInitialFile(args) : null;
  await AppSettings.instance.load();
  runApp(MdViewerApp(initialFile: initialFile));
}

class MdViewerApp extends StatelessWidget {
  const MdViewerApp({this.initialFile, super.key});

  final String? initialFile;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MD Viewer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: .dark,
      home: HomeScreen(initialFile: initialFile),
    );
  }
}
