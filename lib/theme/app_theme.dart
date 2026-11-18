import 'package:material_ui/material_ui.dart';

abstract final class AppColors {
  static const background = Color(0xFF151515);
  static const navy = Color(0xFF172838);
  static const teal = Color(0xFF1B403B);
  static const preview = Color(0xFF252631);
  static const previewBorder = Color(0xFF41424D);
  static const accent = Color(0xFFF4B9BD);
  static const primaryText = Color(0xFFFFFFFF);
  static const secondaryText = Color(0xFFB5B5BC);
  static const buttonText = Color(0xFF17171D);
}

abstract final class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: AppColors.background,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.buttonText,
          surface: AppColors.preview,
          onSurface: AppColors.primaryText,
          onSurfaceVariant: AppColors.secondaryText,
        ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.preview,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.preview,
      contentTextStyle: TextStyle(
        fontFamily: 'Inter',
        color: AppColors.primaryText,
        fontSize: 14,
        height: 1.5,
      ),
    ),
  );
}
