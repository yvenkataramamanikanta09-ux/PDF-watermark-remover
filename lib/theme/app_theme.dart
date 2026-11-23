import 'package:material_ui/material_ui.dart';

/// Colour tokens of the Figma design (PDF Watermark Remover – UI/UX Design).
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
  static const success = Color(0xFF4FC08D);
  static const successContainer = Color(0xFF1B403B);
  static const errorContainer = Color(0xFF3A282B);
}

/// Bundled fonts (both SIL Open Font License, variable weight).
abstract final class AppFonts {
  /// Body, labels and buttons: a clean, friendly geometric sans serif.
  static const sans = 'Figtree';

  /// Headlines: a readable editorial serif, set for a document-oriented app.
  static const serif = 'Newsreader';
}

/// Named styles used where a widget needs a specific look. They are the same
/// styles as the Material 3 text theme roles below.
abstract final class AppText {
  /// Screen titles: 28 px serif. `opsz` picks Newsreader's display master.
  static const title = TextStyle(
    fontFamily: AppFonts.serif,
    fontVariations: [FontVariation.opticalSize(36)],
    color: AppColors.primaryText,
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 34 / 28,
    letterSpacing: -0.2,
  );

  /// Hero headline on Home.
  static const headline = TextStyle(
    fontFamily: AppFonts.serif,
    fontVariations: [FontVariation.opticalSize(32)],
    color: AppColors.primaryText,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    height: 32 / 26,
    letterSpacing: -0.2,
  );

  /// Card and section headings: 20 px serif.
  static const sectionTitle = TextStyle(
    fontFamily: AppFonts.serif,
    fontVariations: [FontVariation.opticalSize(24)],
    color: AppColors.primaryText,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 26 / 20,
  );

  static const bodyStrong = TextStyle(
    fontFamily: AppFonts.sans,
    color: AppColors.secondaryText,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.5,
  );

  static const body = TextStyle(
    fontFamily: AppFonts.sans,
    color: AppColors.secondaryText,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const caption = TextStyle(
    fontFamily: AppFonts.sans,
    color: AppColors.secondaryText,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
}

/// The design expressed as a Material 3 theme: Figma tokens map to
/// [ColorScheme] roles, the type scale uses the bundled fonts, and every
/// Material component (buttons, chips, segmented buttons, cards, dialogs,
/// progress, menus, text fields, snack bars) is themed here once.
abstract final class AppTheme {
  static TextTheme get _textTheme => const TextTheme(
    displaySmall: TextStyle(fontFamily: AppFonts.serif, fontSize: 36, fontWeight: FontWeight.w600, height: 44 / 36),
    headlineLarge: TextStyle(fontFamily: AppFonts.serif, fontSize: 32, fontWeight: FontWeight.w600, height: 40 / 32),
    headlineMedium: AppText.title,
    headlineSmall: AppText.headline,
    titleLarge: AppText.sectionTitle,
    titleMedium: TextStyle(fontFamily: AppFonts.sans, fontSize: 16, fontWeight: FontWeight.w600, height: 24 / 16),
    titleSmall: TextStyle(fontFamily: AppFonts.sans, fontSize: 14, fontWeight: FontWeight.w600, height: 20 / 14),
    bodyLarge: TextStyle(fontFamily: AppFonts.sans, fontSize: 16, fontWeight: FontWeight.w400, height: 24 / 16),
    bodyMedium: TextStyle(fontFamily: AppFonts.sans, fontSize: 14, fontWeight: FontWeight.w400, height: 21 / 14),
    bodySmall: TextStyle(fontFamily: AppFonts.sans, fontSize: 12, fontWeight: FontWeight.w400, height: 18 / 12),
    labelLarge: TextStyle(fontFamily: AppFonts.sans, fontSize: 16, fontWeight: FontWeight.w600, height: 20 / 16),
    labelMedium: TextStyle(fontFamily: AppFonts.sans, fontSize: 13, fontWeight: FontWeight.w600, height: 18 / 13),
    labelSmall: TextStyle(fontFamily: AppFonts.sans, fontSize: 12, fontWeight: FontWeight.w600, height: 16 / 12),
  );

  static ThemeData get dark {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: AppColors.buttonText,
          primaryContainer: AppColors.successContainer,
          onPrimaryContainer: AppColors.primaryText,
          secondaryContainer: AppColors.previewBorder,
          onSecondaryContainer: AppColors.primaryText,
          surface: AppColors.background,
          onSurface: AppColors.primaryText,
          onSurfaceVariant: AppColors.secondaryText,
          surfaceContainerLowest: AppColors.background,
          surfaceContainerLow: AppColors.preview,
          surfaceContainer: AppColors.preview,
          surfaceContainerHigh: AppColors.preview,
          surfaceContainerHighest: AppColors.previewBorder,
          outline: AppColors.previewBorder,
          outlineVariant: AppColors.previewBorder,
          errorContainer: AppColors.errorContainer,
          onErrorContainer: AppColors.accent,
        );
    final textTheme = _textTheme.apply(
      bodyColor: AppColors.primaryText,
      displayColor: AppColors.primaryText,
    );
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppFonts.sans,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.background,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.previewBorder),
          shape: buttonShape,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: textTheme.labelMedium,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          textStyle: textTheme.labelMedium,
          foregroundColor: AppColors.secondaryText,
          selectedForegroundColor: AppColors.buttonText,
          selectedBackgroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.previewBorder),
          visualDensity: VisualDensity.standard,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.preview,
        side: const BorderSide(color: AppColors.previewBorder),
        labelStyle: textTheme.labelMedium?.copyWith(color: AppColors.primaryText),
        iconTheme: const IconThemeData(color: AppColors.accent, size: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.preview,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.previewBorder),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.buttonText : AppColors.secondaryText,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.accent : AppColors.previewBorder,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.previewBorder,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.preview,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.preview,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: AppColors.secondaryText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.preview,
        behavior: SnackBarBehavior.floating,
        actionTextColor: AppColors.accent,
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.preview,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.previewBorder),
        ),
      ),
      listTileTheme: const ListTileThemeData(iconColor: AppColors.accent),
    );
  }
}
