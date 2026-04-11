import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// app_theme.dart
//
// All colour tokens, typography, spacing, and theme builders
// for the Godown Inventory app.
//
// Based on ui-design-spec.md:
//   Light bg : #F8FAFC   Dark bg  : #0F172A
//   Primary  : #2563EB            : #3B82F6
//   Surface  : #FFFFFF            : #1E293B
//   Text     : #0F172A            : #F1F5F9
//   Border   : #E2E8F0            : #334155
//   Success  : #16A34A            : #22C55E
//   Error    : #DC2626            : #EF4444
// ─────────────────────────────────────────────────────────────────────────────

// ─── Colour tokens ────────────────────────────────────────────────────────────
class AppColors {

  // ── Light theme (from spec) ────────────────────────────────────────────────
  static const lightBg       = Color(0xFFF8FAFC); // #F8FAFC
  static const lightSurface  = Color(0xFFFFFFFF); // #FFFFFF
  static const lightPrimary  = Color(0xFF2563EB); // #2563EB  blue
  static const lightSecond   = Color(0xFF64748B); // #64748B  slate
  static const lightText     = Color(0xFF0F172A); // #0F172A
  static const lightText2    = Color(0xFF64748B); // secondary text
  static const lightText3    = Color(0xFF94A3B8); // hint / label text
  static const lightBorder   = Color(0xFFE2E8F0); // #E2E8F0
  static const lightSuccess  = Color(0xFF16A34A); // #16A34A
  static const lightError    = Color(0xFFDC2626); // #DC2626

  // ── Dark theme (from spec) ─────────────────────────────────────────────────
  static const darkBg        = Color(0xFF0F172A); // #0F172A
  static const darkSurface   = Color(0xFF1E293B); // #1E293B
  static const darkPrimary   = Color(0xFF3B82F6); // #3B82F6  blue
  static const darkSecond    = Color(0xFF94A3B8); // #94A3B8  slate
  static const darkText      = Color(0xFFF1F5F9); // #F1F5F9
  static const darkText2     = Color(0xFF94A3B8); // secondary text
  static const darkText3     = Color(0xFF64748B); // hint / label text
  static const darkBorder    = Color(0xFF334155); // #334155
  static const darkSuccess   = Color(0xFF22C55E); // #22C55E
  static const darkError     = Color(0xFFEF4444); // #EF4444

  // ── Shared semantic colours ────────────────────────────────────────────────
  static const successBgLight  = Color(0xFFDCFCE7);
  static const successBgDark   = Color(0xFF052E16);
  static const errorBgLight    = Color(0xFFFEE2E2);
  static const errorBgDark     = Color(0xFF450A0A);
  static const warnBgLight     = Color(0xFFFEF9C3);
  static const warnBgDark      = Color(0xFF422006);
  static const warnFgLight     = Color(0xFF854D0E);
  static const warnFgDark      = Color(0xFFFBBF24);
  static const infoBgLight     = Color(0xFFDBEAFE);
  static const infoBgDark      = Color(0xFF1E3A5F);
  static const infoFgLight     = Color(0xFF1D4ED8);
  static const infoFgDark      = Color(0xFF93C5FD);
}

// ─── Typography (from spec: Inter / Segoe UI / monospace) ────────────────────
class AppFonts {

  // Font stack from spec: "Inter", "Segoe UI", monospace
  static const sans = 'Inter';
  static const mono = 'Courier New';

  // ── Heading: 18px / 600 ───────────────────────────────────────────────────
  static TextStyle heading({Color? color}) => TextStyle(
        fontFamily: sans,
        fontSize:   18,
        fontWeight: FontWeight.w600,
        color:      color,
        height:     1.3,
      );

  // ── Body: 14px / 400 ──────────────────────────────────────────────────────
  static TextStyle body({Color? color, double size = 14}) => TextStyle(
        fontFamily: sans,
        fontSize:   size,
        fontWeight: FontWeight.w400,
        color:      color,
        height:     1.5,
      );

  // ── Label: 12px / 500 ─────────────────────────────────────────────────────
  static TextStyle label({Color? color, double size = 12}) => TextStyle(
        fontFamily: sans,
        fontSize:   size,
        fontWeight: FontWeight.w500,
        color:      color,
      );

  // ── Monospace data style (for quantities, IDs, routes) ────────────────────
  static TextStyle monoStyle({
    double     size   = 13,
    FontWeight weight = FontWeight.w500,
    Color?     color,
  }) =>
      TextStyle(
        fontFamily:    mono,
        fontSize:      size,
        fontWeight:    weight,
        color:         color,
        letterSpacing: 0,
      );

  // ── Label style (uppercase, spaced — for section headers) ─────────────────
  static TextStyle labelStyle({double size = 10, Color? color}) => TextStyle(
        fontFamily:      sans,
        fontSize:        size,
        fontWeight:      FontWeight.w600,
        letterSpacing:   0.08,
        color:           color,
      );
}

// ─── Spacing (from spec) ──────────────────────────────────────────────────────
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;

  // Border radius from spec: 12px
  static const radius    = 12.0;
  static const radiusSm  = 8.0;
  static const radiusXs  = 6.0;
}

// ─── Responsive helpers ───────────────────────────────────────────────────────
class AppSizes {
  static double screenWidth(BuildContext ctx)  => MediaQuery.sizeOf(ctx).width;
  static double screenHeight(BuildContext ctx) => MediaQuery.sizeOf(ctx).height;

  // Scales a base value to screen width (design base = 375px)
  static double scale(BuildContext ctx, double base) =>
      base * (screenWidth(ctx) / 375).clamp(0.8, 1.4);

  // Page padding — wider on tablets
  static EdgeInsets pagePadding(BuildContext ctx) {
    final w = screenWidth(ctx);
    final h = w > 600 ? 20.0 : AppSpacing.md;
    return EdgeInsets.symmetric(horizontal: h, vertical: AppSpacing.md);
  }
}

// ─── Theme builder ────────────────────────────────────────────────────────────
class AppTheme {

  static ThemeData light() => _build(
        brightness:      Brightness.light,
        bg:              AppColors.lightBg,
        surface:         AppColors.lightSurface,
        border:          AppColors.lightBorder,
        text:            AppColors.lightText,
        text2:           AppColors.lightText2,
        text3:           AppColors.lightText3,
        primary:         AppColors.lightPrimary,
        primaryFg:       Colors.white,
        success:         AppColors.lightSuccess,
        error:           AppColors.lightError,
        statusBarStyle:  SystemUiOverlayStyle.dark,
      );

  static ThemeData dark() => _build(
        brightness:      Brightness.dark,
        bg:              AppColors.darkBg,
        surface:         AppColors.darkSurface,
        border:          AppColors.darkBorder,
        text:            AppColors.darkText,
        text2:           AppColors.darkText2,
        text3:           AppColors.darkText3,
        primary:         AppColors.darkPrimary,
        primaryFg:       Colors.white,
        success:         AppColors.darkSuccess,
        error:           AppColors.darkError,
        statusBarStyle:  SystemUiOverlayStyle.light,
      );

  static ThemeData _build({
    required Brightness            brightness,
    required Color bg,
    required Color surface,
    required Color border,
    required Color text,
    required Color text2,
    required Color text3,
    required Color primary,
    required Color primaryFg,
    required Color success,
    required Color error,
    required SystemUiOverlayStyle  statusBarStyle,
  }) {
    return ThemeData(
      brightness:             brightness,
      scaffoldBackgroundColor: bg,
      fontFamily:             AppFonts.sans,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary:    primary,
        onPrimary:  primaryFg,
        secondary:  primary,
        onSecondary: primaryFg,
        error:      error,
        onError:    Colors.white,
        surface:    surface,
        onSurface:  text,
      ),
      // ── AppBar ────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor:       surface,
        foregroundColor:       text,
        elevation:             0,
        scrolledUnderElevation: 0,
        centerTitle:           false,
        titleTextStyle: TextStyle(
          fontFamily:  AppFonts.sans,
          color:       text,
          fontSize:    16,
          fontWeight:  FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: text, size: 20),
        systemOverlayStyle: statusBarStyle.copyWith(
          statusBarColor: surface,
        ),
        shape: Border(
          bottom: BorderSide(color: border, width: 0.8),
        ),
      ),
      // ── Card ──────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color:     surface,
        elevation: 0,
        margin:    EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side:         BorderSide(color: border, width: 0.8),
        ),
      ),
      // ── Divider ───────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color:     border,
        thickness: 0.8,
        space:     0,
      ),
      // ── Input fields ──────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled:          true,
        fillColor:       surface,
        contentPadding:  const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical:   AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide:   BorderSide(color: border, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide:   BorderSide(color: border, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide:   BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide:   BorderSide(color: error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide:   BorderSide(color: error, width: 1.5),
        ),
        labelStyle: TextStyle(color: text3, fontSize: 13),
        hintStyle:  TextStyle(color: text3, fontSize: 13),
        errorStyle: TextStyle(color: error,  fontSize: 11),
      ),
      // ── Elevated button ───────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: primaryFg,
          elevation:       0,
          minimumSize:     const Size.fromHeight(48),
          padding:         const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          textStyle: const TextStyle(
            fontFamily:  AppFonts.sans,
            fontSize:    14,
            fontWeight:  FontWeight.w500,
          ),
        ),
      ),
      // ── Outlined button ───────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side:            BorderSide(color: border, width: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          textStyle: const TextStyle(
            fontFamily:  AppFonts.sans,
            fontSize:    12,
            fontWeight:  FontWeight.w500,
          ),
          padding:         const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize:     Size.zero,
          tapTargetSize:   MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      // ── Snackbar ──────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface,
        contentTextStyle: TextStyle(color: text, fontSize: 13),
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          side:         BorderSide(color: border, width: 0.8),
        ),
      ),
      // ── Text theme ────────────────────────────────────────────────────────
      textTheme: TextTheme(
        headlineMedium: TextStyle(color: text,  fontSize: 18, fontWeight: FontWeight.w600),
        titleLarge:     TextStyle(color: text,  fontSize: 16, fontWeight: FontWeight.w600),
        titleMedium:    TextStyle(color: text,  fontSize: 14, fontWeight: FontWeight.w600),
        bodyLarge:      TextStyle(color: text,  fontSize: 14, height: 1.5),
        bodyMedium:     TextStyle(color: text,  fontSize: 13, height: 1.5),
        bodySmall:      TextStyle(color: text2, fontSize: 12, height: 1.4),
        labelLarge:     TextStyle(color: text,  fontSize: 14, fontWeight: FontWeight.w500),
        labelMedium:    TextStyle(color: text2, fontSize: 12, fontWeight: FontWeight.w500),
        labelSmall:     TextStyle(color: text3, fontSize: 10, letterSpacing: 0.08),
      ),
      useMaterial3: true,
    );
  }
}

// ─── Theme extension — injects custom tokens into Flutter's theme system ──────
// This lets every screen call context.appTheme to get all custom colours.
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color  bg;
  final Color  surface;
  final Color  border;
  final Color  text;
  final Color  text2;
  final Color  text3;
  final Color  primary;
  final Color  primaryFg;
  final Color  success;
  final Color  error;
  final bool   isDark;

  // Derived semantic colours (computed from isDark)
  Color get successBg  => isDark ? AppColors.successBgDark  : AppColors.successBgLight;
  Color get errorBg    => isDark ? AppColors.errorBgDark    : AppColors.errorBgLight;
  Color get warnBg     => isDark ? AppColors.warnBgDark     : AppColors.warnBgLight;
  Color get warnFg     => isDark ? AppColors.warnFgDark     : AppColors.warnFgLight;
  Color get infoBg     => isDark ? AppColors.infoBgDark     : AppColors.infoBgLight;
  Color get infoFg     => isDark ? AppColors.infoFgDark     : AppColors.infoFgLight;

  // Keep accent / accentFg as aliases so existing code still compiles
  Color get accent     => primary;
  Color get accentFg   => primaryFg;

  const AppThemeExtension({
    required this.bg,
    required this.surface,
    required this.border,
    required this.text,
    required this.text2,
    required this.text3,
    required this.primary,
    required this.primaryFg,
    required this.success,
    required this.error,
    required this.isDark,
  });

  factory AppThemeExtension.light() => const AppThemeExtension(
        bg:        AppColors.lightBg,
        surface:   AppColors.lightSurface,
        border:    AppColors.lightBorder,
        text:      AppColors.lightText,
        text2:     AppColors.lightText2,
        text3:     AppColors.lightText3,
        primary:   AppColors.lightPrimary,
        primaryFg: Colors.white,
        success:   AppColors.lightSuccess,
        error:     AppColors.lightError,
        isDark:    false,
      );

  factory AppThemeExtension.dark() => const AppThemeExtension(
        bg:        AppColors.darkBg,
        surface:   AppColors.darkSurface,
        border:    AppColors.darkBorder,
        text:      AppColors.darkText,
        text2:     AppColors.darkText2,
        text3:     AppColors.darkText3,
        primary:   AppColors.darkPrimary,
        primaryFg: Colors.white,
        success:   AppColors.darkSuccess,
        error:     AppColors.darkError,
        isDark:    true,
      );

  @override
  AppThemeExtension copyWith({
    Color? bg, Color? surface, Color? border,
    Color? text, Color? text2, Color? text3,
    Color? primary, Color? primaryFg,
    Color? success, Color? error, bool? isDark,
  }) =>
      AppThemeExtension(
        bg:        bg        ?? this.bg,
        surface:   surface   ?? this.surface,
        border:    border    ?? this.border,
        text:      text      ?? this.text,
        text2:     text2     ?? this.text2,
        text3:     text3     ?? this.text3,
        primary:   primary   ?? this.primary,
        primaryFg: primaryFg ?? this.primaryFg,
        success:   success   ?? this.success,
        error:     error     ?? this.error,
        isDark:    isDark    ?? this.isDark,
      );

  @override
  AppThemeExtension lerp(AppThemeExtension? other, double t) {
    if (other == null) return this;
    return AppThemeExtension(
      bg:        Color.lerp(bg,        other.bg,        t)!,
      surface:   Color.lerp(surface,   other.surface,   t)!,
      border:    Color.lerp(border,    other.border,    t)!,
      text:      Color.lerp(text,      other.text,      t)!,
      text2:     Color.lerp(text2,     other.text2,     t)!,
      text3:     Color.lerp(text3,     other.text3,     t)!,
      primary:   Color.lerp(primary,   other.primary,   t)!,
      primaryFg: Color.lerp(primaryFg, other.primaryFg, t)!,
      success:   Color.lerp(success,   other.success,   t)!,
      error:     Color.lerp(error,     other.error,     t)!,
      isDark:    isDark,
    );
  }
}

// ─── Convenience extension — context.appTheme ─────────────────────────────────
// Uses ?? fallback instead of ! to prevent crash during route transitions
// when the theme extension may not yet be available on the new context.
extension AppThemeContext on BuildContext {
  AppThemeExtension get appTheme =>
      Theme.of(this).extension<AppThemeExtension>() ??
      AppThemeExtension.light();
}