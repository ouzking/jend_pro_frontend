import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/jp_colors.dart';
import '../tokens/jp_metrics.dart';
import '../tokens/jp_palette.dart';
import '../tokens/jp_typography.dart';

/// Thèmes Material construits **uniquement** à partir des jetons.
abstract final class AppTheme {
  static ThemeData light() => _build(JpPalette.light, Brightness.light);

  static ThemeData dark() => _build(JpPalette.dark, Brightness.dark);

  static ThemeData _build(JpPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: p.brand,
      onPrimary: p.textOnBrand,
      primaryContainer: p.brandSoft,
      onPrimaryContainer: p.brandStrong,
      secondary: p.accent,
      onSecondary: JpColors.forest975,
      secondaryContainer: p.accentSoft,
      onSecondaryContainer: isDark ? JpColors.brass400 : JpColors.brass700,
      tertiary: p.info,
      onTertiary: Colors.white,
      error: p.danger,
      onError: Colors.white,
      errorContainer: p.dangerSoft,
      onErrorContainer: p.danger,
      surface: p.surface,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceMuted,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.border,
      outline: p.borderStrong,
      outlineVariant: p.border,
      shadow: p.shadow,
      scrim: JpColors.forest975,
      inverseSurface: isDark ? JpColors.neutral50 : JpColors.forest900,
      onInverseSurface: isDark ? JpColors.forest900 : JpColors.neutral50,
      inversePrimary: isDark ? JpColors.forest700 : JpColors.mint300,
    );
    final text = JpTypography.textTheme(p.textPrimary, p.textSecondary);
    final inputRadius = JpRadius.all(JpRadius.md);

    OutlineInputBorder outline(Color color, [double width = 1]) => OutlineInputBorder(
      borderRadius: inputRadius,
      borderSide: BorderSide(color: color, width: width),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: JpTypography.family,
      textTheme: text,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      dividerColor: p.border,
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      extensions: [p],
      appBarTheme: AppBarThemeData(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: JpSpacing.gutter,
        titleTextStyle: JpTypography.title.copyWith(color: p.textPrimary),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: JpRadius.all(JpRadius.lg),
          side: BorderSide(color: p.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textSecondary, size: JpSize.iconMd),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: p.surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg, vertical: 16),
        hintStyle: JpTypography.body.copyWith(color: p.textMuted),
        labelStyle: JpTypography.body.copyWith(color: p.textSecondary),
        floatingLabelStyle: JpTypography.label.copyWith(color: p.brand),
        helperStyle: JpTypography.bodySmall.copyWith(color: p.textMuted),
        errorStyle: JpTypography.bodySmall.copyWith(color: p.danger),
        prefixIconColor: p.textMuted,
        suffixIconColor: p.textMuted,
        border: outline(p.borderStrong),
        enabledBorder: outline(p.borderStrong),
        focusedBorder: outline(p.brand, 1.6),
        errorBorder: outline(p.danger),
        focusedErrorBorder: outline(p.danger, 1.6),
        disabledBorder: outline(p.border),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.brand,
        selectionColor: p.brand.withValues(alpha: 0.2),
        selectionHandleColor: p.brand,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: p.textOnBrand,
          minimumSize: const Size(64, JpSize.buttonMd),
          textStyle: JpTypography.label,
          shape: RoundedRectangleBorder(borderRadius: JpRadius.all(JpRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          minimumSize: const Size(64, JpSize.buttonMd),
          side: BorderSide(color: p.borderStrong),
          textStyle: JpTypography.label,
          shape: RoundedRectangleBorder(borderRadius: JpRadius.all(JpRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.brand,
          minimumSize: const Size(48, JpSize.touchTarget),
          textStyle: JpTypography.label,
          shape: RoundedRectangleBorder(borderRadius: JpRadius.all(JpRadius.sm)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: p.textPrimary, minimumSize: const Size.square(JpSize.touchTarget)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surface,
        selectedColor: p.brandSoft,
        side: BorderSide(color: p.border),
        labelStyle: JpTypography.label.copyWith(color: p.textSecondary),
        secondaryLabelStyle: JpTypography.label.copyWith(color: p.brandStrong),
        shape: RoundedRectangleBorder(borderRadius: JpRadius.all(JpRadius.pill)),
        padding: const EdgeInsets.symmetric(horizontal: JpSpacing.md, vertical: JpSpacing.sm),
        showCheckmark: false,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: p.surface,
        showDragHandle: true,
        dragHandleColor: p.borderStrong,
        dragHandleSize: const Size(40, 4),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(JpRadius.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: JpRadius.all(JpRadius.xl)),
        titleTextStyle: JpTypography.title.copyWith(color: p.textPrimary),
        contentTextStyle: JpTypography.body.copyWith(color: p.textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? JpColors.neutral50 : JpColors.forest900,
        contentTextStyle: JpTypography.bodyStrong.copyWith(color: isDark ? JpColors.forest900 : Colors.white),
        actionTextColor: isDark ? JpColors.forest700 : JpColors.mint400,
        shape: RoundedRectangleBorder(borderRadius: JpRadius.all(JpRadius.md)),
        insetPadding: const EdgeInsets.fromLTRB(JpSpacing.lg, 0, JpSpacing.lg, JpSpacing.lg),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.brand,
        linearTrackColor: p.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : p.borderStrong,
        ),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.brand : p.surfaceMuted),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.brand : p.borderStrong,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: JpSpacing.lg),
        minVerticalPadding: JpSpacing.md,
        iconColor: p.textSecondary,
        titleTextStyle: JpTypography.bodyStrong.copyWith(color: p.textPrimary),
        subtitleTextStyle: JpTypography.bodySmall.copyWith(color: p.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: JpRadius.all(JpRadius.md)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.textPrimary,
        unselectedLabelColor: p.textMuted,
        labelStyle: JpTypography.label,
        unselectedLabelStyle: JpTypography.label,
        indicatorColor: p.brand,
        dividerColor: p.border,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          selectedBackgroundColor: p.brandSoft,
          selectedForegroundColor: p.brandStrong,
          foregroundColor: p.textSecondary,
          side: BorderSide(color: p.border),
          textStyle: JpTypography.label,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? JpColors.neutral50 : JpColors.forest900,
          borderRadius: JpRadius.all(JpRadius.sm),
        ),
        textStyle: JpTypography.caption.copyWith(color: isDark ? JpColors.forest900 : Colors.white),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Accès rapide aux jetons depuis un `BuildContext`.
extension JpThemeContext on BuildContext {
  JpPalette get palette => Theme.of(this).extension<JpPalette>()!;

  TextTheme get textTheme => Theme.of(this).textTheme;
}
