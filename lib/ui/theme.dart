import 'package:flutter/material.dart';

/// Identidade visual GMN BOOK: azul-petroleo, branco, tons escuros e
/// verde-agua para detalhes. Contrastes escolhidos para WCAG AA.
class Brand {
  static const petrol = Color(0xFF0B4F5C);
  static const petrolDark = Color(0xFF07343D);
  static const petrolDeep = Color(0xFF0D1B1F);
  static const aqua = Color(0xFF2EC4B6);
  static const aquaSoft = Color(0xFFBFF0EA);
  static const ok = Color(0xFF1E8E5A);
  static const warn = Color(0xFFB7791F);
  static const danger = Color(0xFFC0392B);
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: Brand.petrol,
    brightness: b,
  ).copyWith(
    primary: dark ? const Color(0xFF7FD3DF) : Brand.petrol,
    onPrimary: dark ? Brand.petrolDeep : Colors.white,
    secondary: dark ? Brand.aqua : const Color(0xFF137A70),
    tertiary: Brand.aqua,
    surface: dark ? const Color(0xFF111A1D) : const Color(0xFFF7FAFA),
    error: dark ? const Color(0xFFFF8A80) : Brand.danger,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  final radius = BorderRadius.circular(14);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.apply(fontFamily: 'Segoe UI'),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF172327) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1A272B) : Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: dark ? const Color(0xFF0C1518) : Brand.petrolDark,
      selectedIconTheme: const IconThemeData(color: Brand.petrolDeep),
      unselectedIconTheme: const IconThemeData(color: Color(0xFFB9D6DA)),
      selectedLabelTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: const TextStyle(color: Color(0xFFB9D6DA)),
      indicatorColor: Brand.aqua,
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
    }),
  );
}
