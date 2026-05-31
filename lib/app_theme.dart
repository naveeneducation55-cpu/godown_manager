import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// app_theme.dart  —  v2.7.3
//
// ARCHITECTURE:
//   AppTypeScale   — ONE place to change font sizes. All sizes derived
//                    from a single `base` constant via fixed ratios.
//                    Change base → entire app rescales proportionally.
//
//   AppResponsive  — Screen-aware helpers. Reads MediaQuery once and
//                    exposes scaled spacing, font size, and layout values.
//                    Screens call AppResponsive.of(context) to get a
//                    pre-computed snapshot — zero repeated MediaQuery calls.
//
//   AppColors      — All colour tokens (light + dark)
//   AppFonts       — All text styles — sizes come from AppTypeScale
//   AppSpacing     — Static spacing constants (non-responsive)
//   AppSizes       — Responsive layout helpers (context-dependent)
//   AppTheme       — ThemeData builders (light/dark)
//   AppThemeExtension — Custom tokens injected into Flutter theme
//
// HOW TO CHANGE FONT SIZE:
//   Change AppTypeScale.base — everything scales automatically.
//   Compact: 13.0 | Default: 14.0 | Comfortable: 15.0 | Large: 16.0
//
// HOW TO CHANGE SPACING:
//   Change AppTypeScale.spaceBase — all spacing scales with it.
//
// ─────────────────────────────────────────────────────────────────────────────


// ─── Type scale — single source of truth for ALL font sizes ──────────────────
//
// All sizes are ratios of `base`. Change base → everything rescales.
// Ratios follow Material Design 3 type scale (Minor Third: ×1.125).
//
// DEFAULT SCALE (base = 14):
//   xs      10    section labels, badges
//   sm      12    captions, helper text, error text
//   md      14    body text (base)
//   lg      16    body large, AppBar title
//   xl      18    headings, card titles
//   xxl     20    display, screen titles
//   mono*         slightly smaller than sans for visual balance
//
class AppTypeScale {

  // ── CHANGE THIS ONE VALUE to rescale the entire app ───────────────────────
  static const double base = 14.0;

  // ── Safety fallback — used if base is ever 0 or negative ─────────────────
  static const double _fallback = 14.0;
  static double get _b => base > 0 ? base : _fallback;

  // ── Derived sans-serif sizes ───────────────────────────────────────────────
  static double get xs   => _round(_b * 0.714); // ~10 — labels, badges
  static double get sm   => _round(_b * 0.857); // ~12 — captions, hints
  static double get md   => _round(_b * 1.000); // 14  — body (base)
  static double get lg   => _round(_b * 1.143); // ~16 — body large, AppBar
  static double get xl   => _round(_b * 1.286); // ~18 — headings
  static double get xxl  => _round(_b * 1.429); // ~20 — display

  // ── Derived mono sizes — slightly smaller for visual balance ──────────────
  static double get monoXs => _round(_b * 0.714); // ~10
  static double get monoSm => _round(_b * 0.786); // ~11
  static double get monoMd => _round(_b * 0.929); // ~13 — quantities, IDs
  static double get monoLg => _round(_b * 1.071); // ~15 — prominent data

  // ── Spacing scale — derived from base for proportional layouts ────────────
  // Keeps spacing visually balanced relative to text size.
  static double get spaceXs => _round(_b * 0.286); // ~4
  static double get spaceSm => _round(_b * 0.571); // ~8
  static double get spaceMd => _round(_b * 0.857); // ~12
  static double get spaceLg => _round(_b * 1.143); // ~16
  static double get spaceXl => _round(_b * 1.714); // ~24

  // ── Rounds to nearest 0.5 for pixel-perfect rendering ────────────────────
  static double _round(double v) => (v * 2).roundToDouble() / 2;
}


// ─── Responsive layout — screen-aware values ─────────────────────────────────
//
// Call AppResponsive.of(context) ONCE at the top of build().
// Returns a pre-computed snapshot — no repeated MediaQuery calls.
//
// Device tiers (by shortest screen dimension):
//   compact  < 360px  — very small phones (older budget devices)
//   small    < 400px  — standard small phones (most Indian budget phones)
//   medium   < 600px  — large phones, phablets
//   tablet   ≥ 600px  — tablets, admin screen
//
class AppResponsive {
  final double width;
  final double height;
  final double pixelRatio;
  final double textScaleFactor;

  const AppResponsive._({
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.textScaleFactor,
  });

  factory AppResponsive.of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AppResponsive._(
      width:           mq.size.width,
      height:          mq.size.height,
      pixelRatio:      mq.devicePixelRatio,
      textScaleFactor: mq.textScaler.scale(1.0),
    );
  }

  // ── Device tier ───────────────────────────────────────────────────────────
  bool get isCompact => width < 360;
  bool get isSmall   => width < 400 && !isCompact;
  bool get isMedium  => width < 600 && !isSmall && !isCompact;
  bool get isTablet  => width >= 600;

  // ── Responsive font size ──────────────────────────────────────────────────
  // Scales AppTypeScale sizes to screen. Clamped to prevent extreme values.
  // compact: 0.90× | small: 0.95× | medium: 1.00× | tablet: 1.08×
  double get _fontScale {
    if (isCompact) return 0.90;
    if (isSmall)   return 0.95;
    if (isTablet)  return 1.08;
    return 1.00;
  }

  double fontSize(double base) =>
      (base * _fontScale).clamp(base * 0.85, base * 1.25);

  // ── Responsive spacing ────────────────────────────────────────────────────
  double get _spaceScale {
    if (isCompact) return 0.85;
    if (isTablet)  return 1.15;
    return 1.00;
  }

  double space(double base) => (base * _spaceScale).clamp(2.0, base * 1.5);

  // ── Named spacing shorthands ──────────────────────────────────────────────
  double get xs => space(AppTypeScale.spaceXs);
  double get sm => space(AppTypeScale.spaceSm);
  double get md => space(AppTypeScale.spaceMd);
  double get lg => space(AppTypeScale.spaceLg);
  double get xl => space(AppTypeScale.spaceXl);

  // ── Page padding — wider on tablets, tighter on compact ──────────────────
  EdgeInsets get pagePadding => EdgeInsets.symmetric(
    horizontal: isTablet  ? 24.0
               : isCompact ? 10.0
               : 12.0,
    vertical: md,
  );

  // ── Tap target size — larger on tablets for pointer precision ────────────
  double get tapTarget  => isTablet ? 52.0 : 48.0;
  double get iconSize   => isTablet ? 22.0 : 20.0;
  double get iconSizeSm => isTablet ? 18.0 : 16.0;

  // ── Card radius — consistent with AppSpacing but overrideable ────────────
  double get radius   => AppSpacing.radius;
  double get radiusSm => AppSpacing.radiusSm;

  // ── Max content width — prevents over-wide layouts on tablets ────────────
  double get maxContentWidth => isTablet ? 560.0 : double.infinity;
}


// ─── Colour tokens ────────────────────────────────────────────────────────────
class AppColors {

  // ── Light theme ────────────────────────────────────────────────────────────
  static const lightBg       = Color(0xFFF8FAFC);
  static const lightSurface  = Color(0xFFFFFFFF);
  static const lightPrimary  = Color(0xFF2563EB);
  static const lightSecond   = Color(0xFF64748B);
  static const lightText     = Color(0xFF0F172A);
  static const lightText2    = Color(0xFF64748B);
  static const lightText3    = Color(0xFF94A3B8);
  static const lightBorder   = Color(0xFFE2E8F0);
  static const lightSuccess  = Color(0xFF16A34A);
  static const lightError    = Color(0xFFDC2626);

  // ── Dark theme ─────────────────────────────────────────────────────────────
  static const darkBg        = Color(0xFF0F172A);
  static const darkSurface   = Color(0xFF1E293B);
  static const darkPrimary   = Color(0xFF3B82F6);
  static const darkSecond    = Color(0xFF94A3B8);
  static const darkText      = Color(0xFFF1F5F9);
  static const darkText2     = Color(0xFF94A3B8);
  static const darkText3     = Color(0xFF64748B);
  static const darkBorder    = Color(0xFF334155);
  static const darkSuccess   = Color(0xFF22C55E);
  static const darkError     = Color(0xFFEF4444);

  // ── Shared semantic colours ────────────────────────────────────────────────
  static const successBgLight = Color(0xFFDCFCE7);
  static const successBgDark  = Color(0xFF052E16);
  static const errorBgLight   = Color(0xFFFEE2E2);
  static const errorBgDark    = Color(0xFF450A0A);
  static const warnBgLight    = Color(0xFFFEF9C3);
  static const warnBgDark     = Color(0xFF422006);
  static const warnFgLight    = Color(0xFF854D0E);
  static const warnFgDark     = Color(0xFFFBBF24);
  static const infoBgLight    = Color(0xFFDBEAFE);
  static const infoBgDark     = Color(0xFF1E3A5F);
  static const infoFgLight    = Color(0xFF1D4ED8);
  static const infoFgDark     = Color(0xFF93C5FD);
}


// ─── Typography — all sizes from AppTypeScale ─────────────────────────────────
//
// USAGE:
//   AppFonts.heading(color: t.text)              — uses scale default
//   AppFonts.body(color: t.text2, size: 13)      — explicit override (rare)
//   AppFonts.heading(color: t.text).copyWith(...) — extend as needed
//
// NOTE: never use const on these — AppTypeScale values are not const.
//
class AppFonts {
  static const sans = 'Inter';
  static const mono = 'Courier New';

  // ── Display — screen titles, empty states ─────────────────────────────────
  static TextStyle display({Color? color}) => TextStyle(
    fontFamily: sans,
    fontSize:   AppTypeScale.xxl,
    fontWeight: FontWeight.w700,
    color:      color,
    height:     1.2,
  );

  // ── Heading — card titles, section headers, dialog titles ─────────────────
  static TextStyle heading({Color? color}) => TextStyle(
    fontFamily: sans,
    fontSize:   AppTypeScale.xl,
    fontWeight: FontWeight.w600,
    color:      color,
    height:     1.3,
  );

  // ── Body large — prominent body text ──────────────────────────────────────
  static TextStyle bodyLg({Color? color}) => TextStyle(
    fontFamily: sans,
    fontSize:   AppTypeScale.lg,
    fontWeight: FontWeight.w400,
    color:      color,
    height:     1.5,
  );

  // ── Body — standard body text ──────────────────────────────────────────────
  // size param is an OVERRIDE — use only for exceptional one-off cases.
  static TextStyle body({Color? color, double? size}) => TextStyle(
    fontFamily: sans,
    fontSize:   size ?? AppTypeScale.md,
    fontWeight: FontWeight.w400,
    color:      color,
    height:     1.5,
  );

  // ── Label — captions, chips, badges, helper text ──────────────────────────
  static TextStyle label({Color? color, double? size}) => TextStyle(
    fontFamily: sans,
    fontSize:   size ?? AppTypeScale.sm,
    fontWeight: FontWeight.w500,
    color:      color,
    height:     1.4,
  );

  // ── Section label — uppercase spaced headers (e.g. "WHAT MOVED?") ─────────
  static TextStyle labelStyle({Color? color, double? size}) => TextStyle(
    fontFamily:    sans,
    fontSize:      size ?? AppTypeScale.xs,
    fontWeight:    FontWeight.w600,
    letterSpacing: 0.08,
    color:         color,
  );

  // ── Mono — quantities, IDs, movement routes, bale numbers ─────────────────
  // size param is an OVERRIDE — use only for exceptional one-off cases.
  static TextStyle monoStyle({
    double?    size,
    FontWeight weight = FontWeight.w500,
    Color?     color,
  }) => TextStyle(
    fontFamily:    mono,
    fontSize:      size ?? AppTypeScale.monoMd,
    fontWeight:    weight,
    color:         color,
    letterSpacing: 0,
  );

  // ── Mono large — prominent data values ────────────────────────────────────
  static TextStyle monoLg({Color? color, FontWeight? weight}) => TextStyle(
    fontFamily:    mono,
    fontSize:      AppTypeScale.monoLg,
    fontWeight:    weight ?? FontWeight.w700,
    color:         color,
    letterSpacing: 0,
  );
}


// ─── Spacing — static constants ───────────────────────────────────────────────
// For context-dependent responsive spacing, use AppResponsive.of(context).
class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;

  static const radius   = 12.0;
  static const radiusSm =  8.0;
  static const radiusXs =  6.0;
}


// ─── AppSizes — backwards-compatible responsive helpers ───────────────────────
// Kept for existing callers. New code should use AppResponsive.of(context).
class AppSizes {
  static double screenWidth(BuildContext ctx)  => MediaQuery.sizeOf(ctx).width;
  static double screenHeight(BuildContext ctx) => MediaQuery.sizeOf(ctx).height;

  static double scale(BuildContext ctx, double base) =>
      base * (screenWidth(ctx) / 375).clamp(0.85, 1.25);

  static EdgeInsets pagePadding(BuildContext ctx) =>
      AppResponsive.of(ctx).pagePadding;
}


// ─── Theme builder ────────────────────────────────────────────────────────────
class AppTheme {

  static ThemeData light() => _build(
    brightness:     Brightness.light,
    bg:             AppColors.lightBg,
    surface:        AppColors.lightSurface,
    border:         AppColors.lightBorder,
    text:           AppColors.lightText,
    text2:          AppColors.lightText2,
    text3:          AppColors.lightText3,
    primary:        AppColors.lightPrimary,
    primaryFg:      Colors.white,
    success:        AppColors.lightSuccess,
    error:          AppColors.lightError,
    statusBarStyle: SystemUiOverlayStyle.dark,
  );

  static ThemeData dark() => _build(
    brightness:     Brightness.dark,
    bg:             AppColors.darkBg,
    surface:        AppColors.darkSurface,
    border:         AppColors.darkBorder,
    text:           AppColors.darkText,
    text2:          AppColors.darkText2,
    text3:          AppColors.darkText3,
    primary:        AppColors.darkPrimary,
    primaryFg:      Colors.white,
    success:        AppColors.darkSuccess,
    error:          AppColors.darkError,
    statusBarStyle: SystemUiOverlayStyle.light,
  );

  static ThemeData _build({
    required Brightness           brightness,
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
    required SystemUiOverlayStyle statusBarStyle,
  }) {
    return ThemeData(
      brightness:              brightness,
      scaffoldBackgroundColor: bg,
      fontFamily:              AppFonts.sans,
      colorScheme: ColorScheme(
        brightness:  brightness,
        primary:     primary,
        onPrimary:   primaryFg,
        secondary:   primary,
        onSecondary: primaryFg,
        error:       error,
        onError:     Colors.white,
        surface:     surface,
        onSurface:   text,
      ),

      // ── AppBar ─────────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor:        surface,
        foregroundColor:        text,
        elevation:              0,
        scrolledUnderElevation: 0,
        centerTitle:            false,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.sans,
          color:      text,
          fontSize:   AppTypeScale.lg,     // ~16 — scales with base
          fontWeight: FontWeight.w600,
        ),
        iconTheme:           IconThemeData(color: text, size: 20),
        systemOverlayStyle:  statusBarStyle.copyWith(statusBarColor: surface),
        shape: Border(bottom: BorderSide(color: border, width: 0.8)),
      ),

      // ── Card ───────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color:     surface,
        elevation: 0,
        margin:    EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          side:         BorderSide(color: border, width: 0.8),
        ),
      ),

      // ── Divider ────────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color:     border,
        thickness: 0.8,
        space:     0,
      ),

      // ── Input fields ───────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled:         true,
        fillColor:      surface,
        contentPadding: const EdgeInsets.symmetric(
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
          borderSide:   BorderSide(color: error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          borderSide:   BorderSide(color: error, width: 1.5),
        ),
        // Sizes from AppTypeScale — scale with base
        labelStyle: TextStyle(color: text3, fontSize: AppTypeScale.sm),
        hintStyle:  TextStyle(color: text3, fontSize: AppTypeScale.sm),
        errorStyle: TextStyle(color: error,  fontSize: AppTypeScale.xs),
      ),

      // ── Elevated button ────────────────────────────────────────────────────
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
          textStyle: TextStyle(
            fontFamily: AppFonts.sans,
            fontSize:   AppTypeScale.md,   // scales with base
            fontWeight: FontWeight.w500,
          ),
        ),
      ),

      // ── Outlined button ────────────────────────────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side:            BorderSide(color: border, width: 0.8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          textStyle: TextStyle(
            fontFamily: AppFonts.sans,
            fontSize:   AppTypeScale.sm,   // scales with base
            fontWeight: FontWeight.w500,
          ),
          padding:       const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize:   Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),

      // ── Snackbar ───────────────────────────────────────────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor:  surface,
        contentTextStyle: TextStyle(color: text, fontSize: AppTypeScale.sm),
        behavior:         SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          side:         BorderSide(color: border, width: 0.8),
        ),
      ),

      // ── Text theme — all sizes from AppTypeScale ───────────────────────────
      textTheme: TextTheme(
        headlineMedium: TextStyle(color: text,  fontSize: AppTypeScale.xl,  fontWeight: FontWeight.w600),
        titleLarge:     TextStyle(color: text,  fontSize: AppTypeScale.lg,  fontWeight: FontWeight.w600),
        titleMedium:    TextStyle(color: text,  fontSize: AppTypeScale.md,  fontWeight: FontWeight.w600),
        bodyLarge:      TextStyle(color: text,  fontSize: AppTypeScale.md,  height: 1.5),
        bodyMedium:     TextStyle(color: text,  fontSize: AppTypeScale.sm,  height: 1.5),
        bodySmall:      TextStyle(color: text2, fontSize: AppTypeScale.sm,  height: 1.4),
        labelLarge:     TextStyle(color: text,  fontSize: AppTypeScale.md,  fontWeight: FontWeight.w500),
        labelMedium:    TextStyle(color: text2, fontSize: AppTypeScale.sm,  fontWeight: FontWeight.w500),
        labelSmall:     TextStyle(color: text3, fontSize: AppTypeScale.xs,  letterSpacing: 0.08),
      ),

      // ── Theme extension — injected so context.appTheme works everywhere ────
      extensions: [
        brightness == Brightness.light
            ? AppThemeExtension.light()
            : AppThemeExtension.dark(),
      ],

      useMaterial3: true,
    );
  }
}


// ─── Theme extension — custom tokens via context.appTheme ─────────────────────
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color bg;
  final Color surface;
  final Color border;
  final Color text;
  final Color text2;
  final Color text3;
  final Color primary;
  final Color primaryFg;
  final Color success;
  final Color error;
  final bool  isDark;

  // ── Derived semantic colours ───────────────────────────────────────────────
  Color get successBg => isDark ? AppColors.successBgDark : AppColors.successBgLight;
  Color get errorBg   => isDark ? AppColors.errorBgDark   : AppColors.errorBgLight;
  Color get warnBg    => isDark ? AppColors.warnBgDark    : AppColors.warnBgLight;
  Color get warnFg    => isDark ? AppColors.warnFgDark    : AppColors.warnFgLight;
  Color get infoBg    => isDark ? AppColors.infoBgDark    : AppColors.infoBgLight;
  Color get infoFg    => isDark ? AppColors.infoFgDark    : AppColors.infoFgLight;

  // ── Aliases — keeps existing code compiling ────────────────────────────────
  Color get accent   => primary;
  Color get accentFg => primaryFg;

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
  }) => AppThemeExtension(
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


// ─── Convenience extensions ───────────────────────────────────────────────────

// context.appTheme — custom colour tokens
// Falls back to light theme during route transitions (never crashes)
extension AppThemeContext on BuildContext {
  AppThemeExtension get appTheme =>
      Theme.of(this).extension<AppThemeExtension>() ??
      AppThemeExtension.light();
}

// context.responsive — screen-aware layout values
// Usage: final r = context.responsive;
//        padding: EdgeInsets.all(r.md)
//        style:   AppFonts.body(color: t.text)
//        fontSize: r.fontSize(AppTypeScale.md)   ← screen-scaled
extension AppResponsiveContext on BuildContext {
  AppResponsive get responsive => AppResponsive.of(this);
}