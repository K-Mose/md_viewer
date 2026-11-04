import 'package:flutter/material.dart';

/// 다크 그레이 ~ 블랙 계열의 모노크롬 팔레트.
abstract final class AppColors {
  static const background = Color(0xFF0E0E10); // 거의 블랙
  static const surface = Color(0xFF1A1A1D); // 카드/시트
  static const surfaceHigh = Color(0xFF232327); // 호버/눌림, 아이콘 배경
  static const border = Color(0xFF2A2A2E); // 미세한 구분선

  static const textPrimary = Color(0xFFF2F2F3);
  static const textSecondary = Color(0xFF9A9AA1);
  static const textTertiary = Color(0xFF5C5C63);

  // 모노크롬 컨셉: 주요 액션은 화이트 버튼(블랙 텍스트)으로 대비를 줌
  static const accent = Color(0xFFF2F2F3);
  static const onAccent = Color(0xFF111113);
}

abstract final class AppTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      surface: AppColors.background,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceHigh,
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.textSecondary,
      outline: AppColors.border,
    );

    final base = ThemeData(
      brightness: .dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkSparkle.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: .w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size.fromHeight(56),
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: .w500),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
