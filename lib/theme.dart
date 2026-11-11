import 'package:material_ui/material_ui.dart';

class AppColors {
  static const ink = Color(0xFF050407);
  static const night = Color(0xFF0B090E);
  static const surface = Color(0xFF141016);
  static const surfaceHigh = Color(0xFF1D171E);
  static const line = Color(0xFF3A2E30);
  static const blood = Color(0xFF7E1414);
  static const bloodBright = Color(0xFFB0261C);
  static const ember = Color(0xFFC0773C);
  static const bone = Color(0xFFE4DACA);
  static const ash = Color(0xFF8C847B);
  static const moon = Color(0xFFD8D0BC);
  static const frost = Color(0xFFB9C6D0);
}

class AppText {
  static const display = 'Cinzel';
  static const body = 'Cormorant';
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.bloodBright,
    onPrimary: AppColors.bone,
    secondary: AppColors.ember,
    surface: AppColors.surface,
    onSurface: AppColors.bone,
    error: AppColors.bloodBright,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.ink,
    fontFamily: AppText.body,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme
        .apply(bodyColor: AppColors.bone, displayColor: AppColors.bone, fontFamily: AppText.body)
        .copyWith(
          displayLarge: const TextStyle(
              fontFamily: AppText.display, fontWeight: FontWeight.w900, letterSpacing: 8, color: AppColors.bone),
          headlineMedium: const TextStyle(
              fontFamily: AppText.display, fontWeight: FontWeight.w700, letterSpacing: 3, color: AppColors.bone),
          titleLarge: const TextStyle(
              fontFamily: AppText.display, fontWeight: FontWeight.w700, letterSpacing: 2, color: AppColors.bone),
          titleMedium: const TextStyle(
              fontFamily: AppText.display, fontWeight: FontWeight.w400, letterSpacing: 1.5, color: AppColors.bone),
          bodyLarge: const TextStyle(fontFamily: AppText.body, fontSize: 19, height: 1.35, color: AppColors.bone),
          bodyMedium: const TextStyle(fontFamily: AppText.body, fontSize: 17, height: 1.35, color: AppColors.bone),
          bodySmall: const TextStyle(fontFamily: AppText.body, fontSize: 15, color: AppColors.ash),
        ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xCC0B090E),
      labelStyle: TextStyle(color: AppColors.ash, fontFamily: AppText.display, letterSpacing: 2, fontSize: 13),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero, borderSide: BorderSide(color: AppColors.bloodBright)),
      border: OutlineInputBorder(borderRadius: BorderRadius.zero),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.bone, fontFamily: AppText.body, fontSize: 17),
      shape: RoundedRectangleBorder(side: BorderSide(color: AppColors.blood)),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: AppColors.line)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(side: BorderSide(color: AppColors.line)),
    ),
    iconTheme: const IconThemeData(color: AppColors.bone),
  );
}
