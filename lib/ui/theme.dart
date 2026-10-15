import 'package:flutter/material.dart';

// Design tokens. Mood: a Sunday-morning kitchen table, a clay mug, soft daylight, a short handwritten list.
// Restrained color: one clay accent (OKLCH hue 34) on near-neutral surfaces; warmth lives in the accent and the type,
// not in a tinted page. Every text pair is >= 4.5:1 (checked in test/ui/theme_contrast_test.dart). See DESIGN.md.

const _light = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFFBC452B),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFFFDFD7),
  onPrimaryContainer: Color(0xFF672416),
  secondary: Color(0xFF625856),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFF3E8E6),
  onSecondaryContainer: Color(0xFF49403D),
  error: Color(0xFFB7191C),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFE3DF),
  onErrorContainer: Color(0xFF791A18),
  surface: Color(0xFFFFFFFF),
  onSurface: Color(0xFF27201E),
  onSurfaceVariant: Color(0xFF625856),
  outline: Color(0xFF7A6F6C),
  outlineVariant: Color(0xFFDED5D3),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFBF5F4),
  surfaceContainer: Color(0xFFF8F1F0),
  surfaceContainerHigh: Color(0xFFF5EEED),
  surfaceContainerHighest: Color(0xFFF0E7E5),
  inverseSurface: Color(0xFF27201E),
  onInverseSurface: Color(0xFFFFFFFF),
  inversePrimary: Color(0xFFF3947E),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Colors.transparent,
);

const _dark = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFF3947E),
  onPrimary: Color(0xFF250F09),
  primaryContainer: Color(0xFF58271C),
  onPrimaryContainer: Color(0xFFFEDCD3),
  secondary: Color(0xFFB5ABA9),
  onSecondary: Color(0xFF1E1816),
  secondaryContainer: Color(0xFF342C2A),
  onSecondaryContainer: Color(0xFFD5CBC9),
  error: Color(0xFFFF958A),
  onError: Color(0xFF2E0A08),
  errorContainer: Color(0xFF5E211D),
  onErrorContainer: Color(0xFFFEDBD6),
  surface: Color(0xFF161211),
  onSurface: Color(0xFFEDE6E4),
  onSurfaceVariant: Color(0xFFB5ABA9),
  outline: Color(0xFF8F8481),
  outlineVariant: Color(0xFF433B39),
  surfaceContainerLowest: Color(0xFF120E0D),
  surfaceContainerLow: Color(0xFF1B1615),
  surfaceContainer: Color(0xFF201A19),
  surfaceContainerHigh: Color(0xFF2B2523),
  surfaceContainerHighest: Color(0xFF342C2A),
  inverseSurface: Color(0xFFEDE6E4),
  onInverseSurface: Color(0xFF27201E),
  inversePrimary: Color(0xFFA9371D), // 5.2:1 on the light snackbar (the page accent is only 4.2:1 there)
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  surfaceTint: Colors.transparent,
);

/// One family, weights from the variable font's wght axis. Fixed scale (13 / 14 / 16 / 18 / 22 / 28), steps of ~1.15.
TextStyle _t(double size, double weight, {double height = 1.4, double spacing = 0}) => TextStyle(
      fontFamily: 'Figtree',
      fontSize: size,
      height: height,
      letterSpacing: spacing,
      fontWeight: FontWeight.values[(weight / 100).round() - 1],
      fontVariations: [FontVariation('wght', weight)],
    );

final _textTheme = TextTheme(
  displaySmall: _t(28, 650, height: 1.2, spacing: -0.2),
  headlineSmall: _t(24, 650, height: 1.25),
  titleLarge: _t(22, 650, height: 1.25),
  titleMedium: _t(16, 600),
  titleSmall: _t(14, 650, spacing: 0.1),
  bodyLarge: _t(16, 480, height: 1.4),
  bodyMedium: _t(14, 450, height: 1.45),
  bodySmall: _t(13, 450, height: 1.4),
  labelLarge: _t(14, 600, height: 1.2),
  labelMedium: _t(13, 550, height: 1.2),
  labelSmall: _t(12, 600, height: 1.2),
);

const _radius = 12.0;

ThemeData _build(ColorScheme c) {
  final dark = c.brightness == Brightness.dark;
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius));
  final field = OutlineInputBorder(borderRadius: BorderRadius.circular(_radius), borderSide: BorderSide(color: c.outlineVariant));

  return ThemeData(
    useMaterial3: true,
    colorScheme: c,
    fontFamily: 'Figtree',
    textTheme: _textTheme.apply(bodyColor: c.onSurface, displayColor: c.onSurface),
    scaffoldBackgroundColor: c.surface,
    splashFactory: InkRipple.splashFactory,
    hoverColor: c.primary.withOpacity(0.06),
    focusColor: c.primary.withOpacity(0.12),
    highlightColor: c.primary.withOpacity(0.08),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _textTheme.titleLarge!.copyWith(color: c.onSurface),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? c.surfaceContainer : c.surfaceContainerLowest,
      border: field,
      enabledBorder: field,
      disabledBorder: field,
      focusedBorder: field.copyWith(borderSide: BorderSide(color: c.primary, width: 2)),
      errorBorder: field.copyWith(borderSide: BorderSide(color: c.error)),
      focusedErrorBorder: field.copyWith(borderSide: BorderSide(color: c.error, width: 2)),
      labelStyle: _textTheme.bodyMedium!.copyWith(color: c.onSurfaceVariant),
      floatingLabelStyle: _textTheme.bodySmall!.copyWith(color: c.onSurfaceVariant),
      hintStyle: _textTheme.bodyLarge!.copyWith(color: c.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: shape,
        textStyle: _textTheme.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: c.onSurface,
        disabledForegroundColor: c.onSurfaceVariant.withOpacity(0.6),
        side: BorderSide(color: c.outlineVariant),
        shape: shape,
        textStyle: _textTheme.bodyLarge,
        alignment: Alignment.centerLeft,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), shape: shape, textStyle: _textTheme.labelLarge),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    // Round check circle: the one signature shape, still a standard checkbox underneath.
    checkboxTheme: CheckboxThemeData(
      shape: const CircleBorder(),
      side: WidgetStateBorderSide.resolveWith(
        (s) => BorderSide(color: s.contains(WidgetState.selected) ? c.primary : c.onSurfaceVariant, width: 1.6),
      ),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : Colors.transparent),
      checkColor: WidgetStatePropertyAll(c.onPrimary),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimary : c.outline),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceContainerHighest),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : c.outline),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.secondaryContainer,
      labelStyle: _textTheme.labelMedium!.copyWith(color: c.onSecondaryContainer),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      deleteIconColor: c.onSecondaryContainer,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.inverseSurface,
      contentTextStyle: _textTheme.bodyMedium!.copyWith(color: c.onInverseSurface),
      actionTextColor: c.inversePrimary,
      shape: shape,
      width: 560,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? c.surfaceContainerHigh : c.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: shape,
      textStyle: _textTheme.bodyLarge!.copyWith(color: c.onSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    dialogTheme: DialogTheme(backgroundColor: c.surfaceContainerLow, surfaceTintColor: Colors.transparent, shape: shape),
    dividerTheme: DividerThemeData(color: c.outlineVariant, space: 1, thickness: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
  );
}

final lightTheme = _build(_light);
final darkTheme = _build(_dark);
