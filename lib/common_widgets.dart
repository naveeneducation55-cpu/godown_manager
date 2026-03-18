// ─────────────────────────────────────────────────────────────────────────────
// common_widgets.dart
//
// Reusable widgets used across all screens.
// Every widget reads from AppThemeExtension so it auto-adapts
// to light and dark mode.
//
// Spec: border-radius 12px, padding 12px, gap 10px
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../app_theme.dart';

// ─── Section label ─────────────────────────────────────────────────────────────
// Uppercase, spaced, muted — used as a group header above lists
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.xs + 2),
      child: Text(
        text.toUpperCase(),
        style: AppFonts.labelStyle(color: t.text3),
      ),
    );
  }
}

// ─── Data row (key + value in monospace) ──────────────────────────────────────
// Used inside DataCard for showing record fields
class AppDataRow extends StatelessWidget {
  final String  label;
  final String  value;
  final Widget? trailing;
  final bool    isLast;

  const AppDataRow({
    super.key,
    required this.label,
    required this.value,
    this.trailing,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: t.border, width: 0.8)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical:   AppSpacing.sm + 1,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: AppFonts.monoStyle(size: 11, color: t.text3),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppFonts.monoStyle(size: 12, color: t.text),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// ─── Data card ────────────────────────────────────────────────────────────────
// Spec: surface bg, 1px border, 12px border-radius, 12px padding
class DataCard extends StatelessWidget {
  final List<Widget> rows;
  const DataCard({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Column(children: rows),
    );
  }
}

// ─── Status badge ─────────────────────────────────────────────────────────────
enum BadgeType { ok, warn, info, error }

class StatusBadge extends StatelessWidget {
  final String    text;
  final BadgeType type;

  const StatusBadge(this.text, {super.key, this.type = BadgeType.ok});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    Color bg, fg;
    switch (type) {
      case BadgeType.ok:
        bg = t.successBg; fg = t.success;
      case BadgeType.warn:
        bg = t.warnBg;    fg = t.warnFg;
      case BadgeType.info:
        bg = t.infoBg;    fg = t.infoFg;
      case BadgeType.error:
        bg = t.errorBg;   fg = t.error;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: AppFonts.monoStyle(size: 10, color: fg, weight: FontWeight.w500),
      ),
    );
  }
}

// ─── Back button ──────────────────────────────────────────────────────────────
// Shown on every screen except Home
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        onTap:        () => Navigator.of(context).pop(),
        child: Container(
          width:  32,
          height: 32,
          decoration: BoxDecoration(
            border:       Border.all(color: t.border, width: 0.8),
            borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
          ),
          child: Icon(
            Icons.arrow_back_ios_new_rounded,
            size:  14,
            color: t.text,
          ),
        ),
      ),
    );
  }
}

// ─── Primary button ────────────────────────────────────────────────────────────
// Spec: primary → blue, padding 10px, border-radius 10px, fontWeight 500
class PrimaryButton extends StatelessWidget {
  final String       label;
  final VoidCallback? onTap;
  final bool         loading;
  final IconData?    icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return SizedBox(
      width:  double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:         t.primary,
          foregroundColor:         t.primaryFg,
          disabledBackgroundColor: t.border,
          elevation:               0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
        ),
        child: loading
            ? SizedBox(
                width:  18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color:       t.primaryFg,
                ),
              )
            : Row(
                mainAxisSize:    MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16),
                    const SizedBox(width: AppSpacing.xs + 2),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily:  AppFonts.sans,
                      fontSize:    14,
                      fontWeight:  FontWeight.w500,
                      color:       t.primaryFg,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Danger button ────────────────────────────────────────────────────────────
// Spec: danger variant → red
class DangerButton extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;

  const DangerButton({super.key, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return SizedBox(
      width:  double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: t.error,
          foregroundColor: Colors.white,
          elevation:       0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily:  AppFonts.sans,
            fontSize:    14,
            fontWeight:  FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ─── Small outlined action button (edit / delete) ─────────────────────────────
// Spec: secondary → gray outlined
class ActionButton extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  final bool         danger;
  final IconData?    icon;

  const ActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t     = context.appTheme;
    final color = danger ? t.error : t.text2;
    return InkWell(
      onTap:        onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(
            color: danger ? t.error : t.border,
            width: 0.8,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: AppFonts.label(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── App text field ────────────────────────────────────────────────────────────
// Spec: Input — border 1px, border-radius 10px, padding 10px, surface bg
class AppTextField extends StatelessWidget {
  final String                label;
  final TextEditingController controller;
  final String?               errorText;
  final TextInputType         keyboardType;
  final bool                  useMono;
  final int?                  maxLines;
  final String?               hint;
  final bool                  readOnly;
  final Widget?               suffix;

  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    this.errorText,
    this.keyboardType = TextInputType.text,
    this.useMono      = false,
    this.maxLines     = 1,
    this.hint,
    this.readOnly     = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return TextFormField(
      controller:   controller,
      keyboardType: keyboardType,
      maxLines:     maxLines,
      readOnly:     readOnly,
      style: useMono
          ? AppFonts.monoStyle(size: 13, color: t.text)
          : AppFonts.body(color: t.text),
      decoration: InputDecoration(
        labelText:   label,
        hintText:    hint,
        errorText:   errorText,
        suffixIcon:  suffix,
      ),
    );
  }
}

// ─── App dropdown field ────────────────────────────────────────────────────────
class AppDropdownField<T> extends StatelessWidget {
  final String                   label;
  final T?                       value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>         onChanged;
  final String?                  errorText;

  const AppDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return DropdownButtonFormField<T>(
      value:         value,
      items:         items,
      onChanged:     onChanged,
      style:         AppFonts.body(color: t.text),
      dropdownColor: t.surface,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
      ),
    );
  }
}

// ─── Empty state ───────────────────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final String    message;
  final IconData  icon;
  final String?   actionLabel;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.message,
    this.icon        = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: t.text3),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              style: AppFonts.body(color: t.text2, size: 13),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(label: actionLabel!, onTap: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Error state ───────────────────────────────────────────────────────────────
// Spec: ErrorMessage — color theme.error, font-size 12px
class ErrorState extends StatelessWidget {
  final String       message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width:  48,
              height: 48,
              decoration: BoxDecoration(
                color:        t.errorBg,
                borderRadius: BorderRadius.circular(AppSpacing.radius),
              ),
              child: Icon(Icons.error_outline_rounded, size: 24, color: t.error),
            ),
            const SizedBox(height: AppSpacing.md),
            // Spec: ErrorMessage — color theme.error, font-size 12px
            Text(
              message,
              style: AppFonts.label(color: t.error, size: 12),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Loading state ─────────────────────────────────────────────────────────────
// Spec: Loader — "Loading..."
class AppLoader extends StatelessWidget {
  final String? message;
  const AppLoader({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color:       t.primary,
            strokeWidth: 2,
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              style: AppFonts.label(color: t.text3),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Loading placeholder rows ──────────────────────────────────────────────────
class LoadingList extends StatelessWidget {
  final int count;
  const LoadingList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Column(
      children: List.generate(count, (i) {
        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          height: 60,
          decoration: BoxDecoration(
            color:        t.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            border:       Border.all(color: t.border, width: 0.8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical:   AppSpacing.sm,
            ),
            child: Row(
              children: [
                _shimmer(context, 36, 36, radius: AppSpacing.radiusSm),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _shimmer(context, 120, 12),
                      const SizedBox(height: 6),
                      _shimmer(context, 80, 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _shimmer(BuildContext context, double w, double h, {double radius = 4}) {
    final t = context.appTheme;
    return Container(
      width:  w,
      height: h,
      decoration: BoxDecoration(
        color:        t.border,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ─── Confirm delete dialog ─────────────────────────────────────────────────────
Future<bool> showDeleteConfirm(BuildContext context, String itemName) async {
  final t = context.appTheme;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            side:         BorderSide(color: t.border, width: 0.8),
          ),
          title: Text(
            'Delete $itemName?',
            style: AppFonts.heading(color: t.text).copyWith(fontSize: 16),
          ),
          content: Text(
            'This record will be soft-deleted and hidden from lists. '
            'Stock calculations will update automatically.',
            style: AppFonts.body(color: t.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: AppFonts.label(color: t.text2),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Delete',
                style: AppFonts.label(color: t.error).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ) ??
      false;
}

// ─── Snackbar helpers ──────────────────────────────────────────────────────────
void showSuccess(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: AppFonts.body(size: 13)),
      duration: const Duration(seconds: 2),
    ),
  );
}

void showError(BuildContext context, String msg) {
  final t = context.appTheme;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: AppFonts.body(color: Colors.white, size: 13)),
      backgroundColor: t.error,
      duration:        const Duration(seconds: 3),
    ),
  );
}

// ─── Responsive layout wrapper ─────────────────────────────────────────────────
// On tablets, constrains width to 420px and centres the content
class ResponsiveLayout extends StatelessWidget {
  final Widget child;
  const ResponsiveLayout({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width > 600) {
      return Center(child: SizedBox(width: 420, child: child));
    }
    return child;
  }
}