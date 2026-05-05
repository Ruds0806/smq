import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Futuristic Hospital Palette ──────────────────────────────────────────────
const Color kPrimary        = Color(0xFF0057FF);
const Color kPrimaryDark    = Color(0xFF4D94FF);
const Color kAccent         = Color(0xFF00C2FF);
const Color kBackground     = Color(0xFFF0F4FF);
const Color kBackgroundDark = Color(0xFF080C18);
const Color kSurface        = Color(0xFFFFFFFF);
const Color kSurfaceDark    = Color(0xFF111827);
const Color kSurface2       = Color(0xFFF8FAFF);
const Color kSurface2Dark   = Color(0xFF1A2235);
const Color kLabel          = Color(0xFF0F172A);
const Color kLabelDark      = Color(0xFFF1F5FF);
const Color kSecondaryLabel     = Color(0xFF64748B);
const Color kSecondaryLabelDark = Color(0xFF8B9CC8);
const Color kSeparator      = Color(0xFFE2E8F8);
const Color kSeparatorDark  = Color(0xFF1E2D45);
const Color kGreen          = Color(0xFF10B981);
const Color kOrange         = Color(0xFFF59E0B);
const Color kRed            = Color(0xFFEF4444);
const Color kPurple         = Color(0xFF8B5CF6);

// Gradient helpers
const LinearGradient kPrimaryGradient = LinearGradient(
  colors: [kPrimary, kAccent],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

BoxDecoration glassCard({bool dark = false}) => BoxDecoration(
  color: dark ? kSurfaceDark : kSurface,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: dark ? kSeparatorDark : kSeparator),
  boxShadow: dark
      ? []
      : [BoxShadow(color: kPrimary.withValues(alpha: 0.06), blurRadius: 24, offset: const Offset(0, 6))],
);

ThemeData lightTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPrimary,
    brightness: Brightness.light,
    surface: kSurface,
    primary: kPrimary,
  ),
  scaffoldBackgroundColor: kBackground,
  fontFamily: 'Inter',
  appBarTheme: const AppBarTheme(
    backgroundColor: kBackground,
    foregroundColor: kLabel,
    elevation: 0,
    scrolledUnderElevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.dark,
    titleTextStyle: TextStyle(
      color: kLabel,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      fontFamily: 'Inter',
    ),
    iconTheme: IconThemeData(color: kPrimary),
  ),
  cardTheme: CardThemeData(
    color: kSurface,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: EdgeInsets.zero,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kSeparator),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kSeparator),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kPrimary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    labelStyle: const TextStyle(color: kSecondaryLabel, fontSize: 15),
    hintStyle: const TextStyle(color: kSecondaryLabel, fontSize: 15),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      elevation: 0,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: const BorderSide(color: kSeparator),
      foregroundColor: kLabel,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  dividerTheme: const DividerThemeData(color: kSeparator, thickness: 0.5, space: 0),
  tabBarTheme: const TabBarThemeData(
    labelColor: kPrimary,
    unselectedLabelColor: kSecondaryLabel,
    indicatorColor: kPrimary,
    labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    backgroundColor: kLabel,
    contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
  ),
);

ThemeData darkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: kPrimaryDark,
    brightness: Brightness.dark,
    surface: kSurfaceDark,
    primary: kPrimaryDark,
  ),
  scaffoldBackgroundColor: kBackgroundDark,
  fontFamily: 'Inter',
  appBarTheme: const AppBarTheme(
    backgroundColor: kBackgroundDark,
    foregroundColor: kLabelDark,
    elevation: 0,
    scrolledUnderElevation: 0,
    systemOverlayStyle: SystemUiOverlayStyle.light,
    titleTextStyle: TextStyle(
      color: kLabelDark,
      fontSize: 17,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      fontFamily: 'Inter',
    ),
    iconTheme: IconThemeData(color: kPrimaryDark),
  ),
  cardTheme: CardThemeData(
    color: kSurfaceDark,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: EdgeInsets.zero,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurface2Dark,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kSeparatorDark),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kSeparatorDark),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kPrimaryDark, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    labelStyle: const TextStyle(color: kSecondaryLabelDark, fontSize: 15),
    hintStyle: const TextStyle(color: kSecondaryLabelDark, fontSize: 15),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: kPrimaryDark,
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      elevation: 0,
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: const BorderSide(color: kSeparatorDark),
      foregroundColor: kLabelDark,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    ),
  ),
  dividerTheme: const DividerThemeData(color: kSeparatorDark, thickness: 0.5, space: 0),
  tabBarTheme: const TabBarThemeData(
    labelColor: kPrimaryDark,
    unselectedLabelColor: kSecondaryLabelDark,
    indicatorColor: kPrimaryDark,
    labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    backgroundColor: kSurface2Dark,
    contentTextStyle: const TextStyle(color: kLabelDark, fontSize: 14),
  ),
);
