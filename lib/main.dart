import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MdViewerApp());
}

class MdViewerApp extends StatelessWidget {
  const MdViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MD Viewer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      themeMode: .dark,
      home: const HomeScreen(),
    );
  }
}
