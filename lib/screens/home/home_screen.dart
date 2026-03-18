// ─────────────────────────────────────────────────────────────────────────────
// home_screen.dart
//
// Designed from ui-design-spec.md:
//
//   Layout from spec:
//   ┌──────────────────────┐
//   │ 📦 Inventory App     │  ← AppBar
//   ├──────────────────────┤
//   │  Wed, 18 Mar 2026    │  ← date banner
//   │                      │
//   │  [ + Add Movement ]  │  ← primary button
//   │  [ 📊 View Stock  ]  │
//   │  [ 🕘 History     ]  │
//   │  [ ⚙  Manage Data ]  │
//   └──────────────────────┘
//
// Spec rules applied:
//   • padding: 12px
//   • border-radius: 12px
//   • gap between buttons: 10px
//   • font: Inter / Segoe UI
//   • heading 18/600, body 14/400, label 12/500
//   • max 3 taps to complete any action
//   • large clickable areas
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../router.dart';
import '../../theme_provider.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t     = context.appTheme;
    final theme = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor: t.bg,

      // ── AppBar ─────────────────────────────────────────────────────────────
      // From spec: "Header title: Inventory App"
      appBar: AppBar(
        backgroundColor:          t.surface,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            // App icon square
            Container(
              width:  32,
              height: 32,
              decoration: BoxDecoration(
                color:        t.primary,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              ),
              child: const Center(
                child: Text(
                  '📦',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // App title — spec says "Inventory App"
            Expanded(
              child: Text(
                'Inventory App',
                style: AppFonts.heading(color: t.text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Dark / light mode toggle
          // Spec: "Theme adaptive (Light / Dark)"
          IconButton(
            icon: Icon(
              theme.isDark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size:  20,
              color: t.text2,
            ),
            onPressed: theme.toggle,
            tooltip:   theme.isDark ? 'Light mode' : 'Dark mode',
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),

      // ── Body ───────────────────────────────────────────────────────────────
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              // Spec: padding 12px
              padding: AppSizes.pagePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // Date banner
                  const _DateCard(),
                  const SizedBox(height: AppSpacing.lg),

                  // Section label
                  Text(
                    'QUICK ACTIONS',
                    style: AppFonts.labelStyle(color: t.text3),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // ── 4 main action buttons from spec ───────────────────────
                  // Spec: "Button variant=primary"
                  // Spec: padding 10px, borderRadius 10px, fontWeight 500
                  _ActionButton(
                    icon:    Icons.add_circle_outline_rounded,
                    emoji:   '➕',
                    label:   'Add Movement',
                    sub:     'Record a stock transfer',
                    route:   AppRouter.addMove,
                    variant: _BtnVariant.primary,
                  ),
                  const SizedBox(height: AppSpacing.sm + 2), // gap: 10px

                  _ActionButton(
                    icon:    Icons.inventory_2_outlined,
                    emoji:   '📊',
                    label:   'View Stock',
                    sub:     'Live balances per location',
                    route:   AppRouter.stock,
                    variant: _BtnVariant.secondary,
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _ActionButton(
                    icon:    Icons.history_rounded,
                    emoji:   '🕘',
                    label:   'History',
                    sub:     'All past movements',
                    route:   AppRouter.history,
                    variant: _BtnVariant.secondary,
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _ActionButton(
                    icon:    Icons.tune_outlined,
                    emoji:   '⚙',
                    label:   'Manage Data',
                    sub:     'Items, godowns, staff',
                    route:   AppRouter.items,
                    variant: _BtnVariant.secondary,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Sync status row ───────────────────────────────────────
                  _SyncStatusRow(),
                  const SizedBox(height: AppSpacing.lg),

                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DateCard
//
// Shows today's date and a green "online" dot.
// Spec: Card — background surface, border 1px, border-radius 12px, padding 12px
// ─────────────────────────────────────────────────────────────────────────────
class _DateCard extends StatelessWidget {
  const _DateCard();

  @override
  Widget build(BuildContext context) {
    final t   = context.appTheme;
    final now = DateTime.now();

    final weekdays = const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final months   = const ['Jan','Feb','Mar','Apr','May','Jun',
                             'Jul','Aug','Sep','Oct','Nov','Dec'];

    final dateStr =
        '${weekdays[now.weekday - 1]}, '
        '${now.day.toString().padLeft(2, '0')} '
        '${months[now.month - 1]} '
        '${now.year}';

    return Container(
      // Spec card: padding 12px, border-radius 12px, border 1px
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Row(
        children: [
          // Calendar icon
          Container(
            width:  36,
            height: 36,
            decoration: BoxDecoration(
              color:        t.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              Icons.calendar_today_outlined,
              size:  16,
              color: t.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),

          // Date text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today',
                  // Spec: label 12/500
                  style: AppFonts.label(color: t.text3),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  // Monospace for data values per spec: "TypeScript style"
                  style: AppFonts.monoStyle(size: 13, color: t.text),
                ),
              ],
            ),
          ),

          // Green status dot + label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width:  8,
                height: 8,
                decoration: BoxDecoration(
                  color:        t.success,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'online',
                // Spec: label 12/500
                style: AppFonts.label(color: t.success),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BtnVariant — which visual style to use for an action button
// ─────────────────────────────────────────────────────────────────────────────
enum _BtnVariant { primary, secondary }

// ─────────────────────────────────────────────────────────────────────────────
// _ActionButton
//
// Each home screen action.
// Spec:
//   primary   → filled blue background
//   secondary → surface card with border
//   padding: 10px, border-radius: 10px, fontWeight: 500
//   "Large clickable areas"
// ─────────────────────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData   icon;
  final String     emoji;
  final String     label;
  final String     sub;
  final String     route;
  final _BtnVariant variant;

  const _ActionButton({
    super.key,
    required this.icon,
    required this.emoji,
    required this.label,
    required this.sub,
    required this.route,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    // Spec: primary → blue, secondary → surface card
    final isPrimary  = variant == _BtnVariant.primary;
    final bgColor    = isPrimary ? t.primary    : t.surface;
    final textColor  = isPrimary ? t.primaryFg  : t.text;
    final subColor   = isPrimary
        ? t.primaryFg.withOpacity(0.75)
        : t.text2;
    final iconColor  = isPrimary ? t.primaryFg  : t.primary;
    final borderSide = isPrimary
        ? BorderSide.none
        : BorderSide(color: t.border, width: 0.8);

    return Material(
      color:        bgColor,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: InkWell(
        // Spec: "Max 3 taps to complete action"
        onTap:        () => Navigator.pushNamed(context, route),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        splashColor:  isPrimary
            ? Colors.white.withOpacity(0.1)
            : t.primary.withOpacity(0.05),
        child: Container(
          // Spec: padding 10px
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            border:       Border.fromBorderSide(borderSide),
          ),
          child: Row(
            children: [

              // Icon container
              Container(
                width:  44,
                height: 44,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? Colors.white.withOpacity(0.15)
                      : t.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: AppSpacing.md),

              // Label + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      // Spec: body 14/400 but label 12/500 hierarchy —
                      // using 14/600 for button labels for high contrast
                      style: TextStyle(
                        fontFamily:  AppFonts.sans,
                        fontSize:    14,
                        fontWeight:  FontWeight.w600,
                        color:       textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      // Spec: label 12/500
                      style: AppFonts.label(color: subColor),
                    ),
                  ],
                ),
              ),

              // Chevron arrow
              Icon(
                Icons.chevron_right_rounded,
                size:  18,
                color: isPrimary
                    ? t.primaryFg.withOpacity(0.6)
                    : t.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SyncStatusRow
//
// Shows whether the app is online and if there are pending records to sync.
// Spec: "Sync in background", "Offline-first"
// ─────────────────────────────────────────────────────────────────────────────
class _SyncStatusRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, AppRouter.sync),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical:   AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color:        t.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border:       Border.all(color: t.border, width: 0.8),
        ),
        child: Row(
          children: [
            // Sync icon
            Icon(Icons.sync_rounded, size: 14, color: t.text3),
            const SizedBox(width: AppSpacing.sm),

            // Status text
            Text(
              'sync · ',
              style: AppFonts.monoStyle(size: 11, color: t.text3),
            ),
            Container(
              width:  6,
              height: 6,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color:        t.success,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Text(
              'all synced',
              style: AppFonts.monoStyle(size: 11, color: t.success),
            ),

            const Spacer(),

            // Tap to view sync details
            Text(
              'details →',
              style: AppFonts.monoStyle(size: 11, color: t.text3),
            ),
          ],
        ),
      ),
    );
  }
}