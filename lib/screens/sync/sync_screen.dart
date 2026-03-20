import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// sync_screen.dart
//
// From inventory_app_spec.md sections 11, 12, 13:
//
// Sync process:
//   create movement → save locally → sync queue → push to server → mark synced
//
// Each movement has sync_status: 'pending' | 'synced'
//
// Conflict handling: latest updated_at wins
//
// Phase 1 (now):  UI shows pending/synced counts, manual sync button
//                 Simulates sync with a delay — no real network call yet
//
// Phase 2 (next): Replace _simulateSync() with real Supabase push
//                 Wire connectivity_plus to auto-sync on network restore
// ─────────────────────────────────────────────────────────────────────────────

// Sync state enum
enum _SyncState { idle, syncing, done, error }

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {

  _SyncState _syncState  = _SyncState.idle;
  String?    _lastSyncTime;
  String?    _errorMsg;
  int        _syncedThisSession = 0;

  // ── Simulate sync ─────────────────────────────────────────────────────────
  // Phase 2: replace this with real Supabase push
  // Steps mirror spec section 12:
  //   pending → push to server → mark synced
  Future<void> _startSync() async {
    final data = context.read<AppDataProvider>();

    if (data.pendingSyncCount == 0) {
      showSuccess(context, 'Everything is already synced');
      return;
    }

    setState(() {
      _syncState = _SyncState.syncing;
      _errorMsg  = null;
    });

    try {
      // TODO Phase 2: replace delay with actual Supabase batch upsert
      // final pending = data.movements
      //     .where((m) => m.syncStatus == 'pending').toList();
      // for (final m in pending) {
      //   await supabase.from('movements').upsert(m.toJson());
      //   data.markMovementSynced(m.id);
      // }
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!mounted) return;

      final count = data.pendingSyncCount;
      data.markAllSynced();

      setState(() {
        _syncState          = _SyncState.done;
        _syncedThisSession  = count;
        _lastSyncTime       = _fmtTime(DateTime.now());
      });

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncState = _SyncState.error;
        _errorMsg  = 'Sync failed. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t    = context.appTheme;
    final data = context.watch<AppDataProvider>();

    final pending = data.pendingSyncCount;
    final synced  = data.syncedCount;
    final total   = data.totalMovements;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        leading: const AppBackButton(),
        title: Text(
          'Sync Status',
          style: AppFonts.heading(color: t.text).copyWith(fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSizes.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              const SizedBox(height: AppSpacing.sm),

              // ── Status card ──────────────────────────────────────────────
              _StatusCard(
                syncState:    _syncState,
                pending:      pending,
                synced:       synced,
                total:        total,
                lastSyncTime: _lastSyncTime,
                syncedCount:  _syncedThisSession,
                errorMsg:     _errorMsg,
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Stats row ────────────────────────────────────────────────
              Row(children: [
                _StatCard(
                  label: 'Total records',
                  value: '$total',
                  icon:  Icons.receipt_long_outlined,
                ),
                const SizedBox(width: AppSpacing.sm),
                _StatCard(
                  label: 'Pending',
                  value: '$pending',
                  icon:  Icons.pending_outlined,
                  warn:  pending > 0,
                ),
                const SizedBox(width: AppSpacing.sm),
                _StatCard(
                  label: 'Synced',
                  value: '$synced',
                  icon:  Icons.cloud_done_outlined,
                  good:  synced > 0,
                ),
              ]),

              const SizedBox(height: AppSpacing.lg),

              // ── Sync button ──────────────────────────────────────────────
              _SyncButton(
                syncState: _syncState,
                pending:   pending,
                onTap:     _startSync,
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── How sync works section ───────────────────────────────────
              const SectionLabel('How sync works'),
              _InfoCard(steps: const [
                (
                  icon:  Icons.add_circle_outline_rounded,
                  title: 'Movement recorded',
                  desc:  'Every entry is saved to this device instantly.',
                  done:  true,
                ),
                (
                  icon:  Icons.pending_outlined,
                  title: 'Added to sync queue',
                  desc:  'Marked as "pending" until sent to server.',
                  done:  true,
                ),
                (
                  icon:  Icons.cloud_upload_outlined,
                  title: 'Pushed to cloud',
                  desc:  'Sent to Supabase when internet is available.',
                  done:  false, // Phase 2
                ),
                (
                  icon:  Icons.devices_outlined,
                  title: 'Other devices update',
                  desc:  'All phones see the latest data.',
                  done:  false, // Phase 2
                ),
              ]),

              const SizedBox(height: AppSpacing.lg),

              // ── Pending records list ─────────────────────────────────────
              if (pending > 0) ...[
                const SectionLabel('Pending records'),
                _PendingList(data: data),
              ],

              const SizedBox(height: AppSpacing.lg),

              // ── Phase 2 note ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color:        t.warnBg,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                      color: t.warnFg.withOpacity(0.3), width: 0.8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: t.warnFg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Cloud sync (Supabase) will be enabled in Phase 2. '
                        'All data is currently stored on this device only.',
                        style: AppFonts.label(color: t.warnFg),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtTime(DateTime d) {
    final h    = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min  = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }
}

// ─── Status card ──────────────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final _SyncState syncState;
  final int        pending;
  final int        synced;
  final int        total;
  final String?    lastSyncTime;
  final int        syncedCount;
  final String?    errorMsg;

  const _StatusCard({
    required this.syncState,
    required this.pending,
    required this.synced,
    required this.total,
    required this.lastSyncTime,
    required this.syncedCount,
    required this.errorMsg,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    // Determine status display
    Color  dotColor;
    String statusText;
    String subText;

    switch (syncState) {
      case _SyncState.idle:
        if (pending == 0) {
          dotColor   = t.success;
          statusText = 'All synced';
          subText    = '$total records on this device';
        } else {
          dotColor   = t.warnFg;
          statusText = '$pending record${pending == 1 ? '' : 's'} pending';
          subText    = 'Tap "Sync Now" to push to cloud';
        }
      case _SyncState.syncing:
        dotColor   = t.primary;
        statusText = 'Syncing...';
        subText    = 'Pushing records to cloud';
      case _SyncState.done:
        dotColor   = t.success;
        statusText = 'Sync complete';
        subText    = '$syncedCount record${syncedCount == 1 ? '' : 's'} '
            'synced at ${lastSyncTime ?? ''}';
      case _SyncState.error:
        dotColor   = t.error;
        statusText = 'Sync failed';
        subText    = errorMsg ?? 'Unknown error';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Row(children: [

        // Animated dot
        _AnimatedDot(
          color:     dotColor,
          animating: syncState == _SyncState.syncing,
        ),
        const SizedBox(width: AppSpacing.md),

        // Status text
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontFamily:  AppFonts.sans,
                  fontSize:    14,
                  fontWeight:  FontWeight.w600,
                  color:       t.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(subText, style: AppFonts.label(color: t.text3)),
            ],
          ),
        ),

        // Progress indicator while syncing
        if (syncState == _SyncState.syncing)
          SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color:       t.primary,
            ),
          ),

        // Check icon when done
        if (syncState == _SyncState.done)
          Icon(Icons.check_circle_outline_rounded,
              size: 20, color: t.success),

        // Error icon
        if (syncState == _SyncState.error)
          Icon(Icons.error_outline_rounded,
              size: 20, color: t.error),
      ]),
    );
  }
}

// ─── Animated status dot ──────────────────────────────────────────────────────
class _AnimatedDot extends StatefulWidget {
  final Color color;
  final bool  animating;
  const _AnimatedDot({required this.color, required this.animating});
  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 900),
    );
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.animating) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AnimatedDot old) {
    super.didUpdateWidget(old);
    if (widget.animating && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.animating && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 10, height: 10,
        decoration: BoxDecoration(
          color:        widget.color,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

// ─── Stat card ────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String   label;
  final String   value;
  final IconData icon;
  final bool     warn;
  final bool     good;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.warn = false,
    this.good = false,
  });

  @override
  Widget build(BuildContext context) {
    final t     = context.appTheme;
    final color = warn ? t.error
                : good ? t.success
                : t.text2;
    final bg    = warn ? t.errorBg
                : good ? t.successBg
                : t.surface;
    final border = warn ? t.error.withOpacity(0.3)
                 : good ? t.success.withOpacity(0.3)
                 : t.border;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm + 2),
        decoration: BoxDecoration(
          color:        bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border:       Border.all(color: border, width: 0.8),
        ),
        child: Column(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: AppSpacing.xs),
          Text(value,
              style: AppFonts.monoStyle(
                  size: 18, weight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: AppFonts.labelStyle(color: t.text3),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

// ─── Sync button ──────────────────────────────────────────────────────────────
class _SyncButton extends StatelessWidget {
  final _SyncState   syncState;
  final int          pending;
  final VoidCallback onTap;

  const _SyncButton({
    required this.syncState,
    required this.pending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t         = context.appTheme;
    final isSyncing = syncState == _SyncState.syncing;
    final label     = isSyncing
        ? 'Syncing...'
        : pending > 0
            ? 'Sync Now  ($pending pending)'
            : 'All Synced';

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: isSyncing ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: pending > 0 ? t.primary : t.success,
          foregroundColor: t.primaryFg,
          disabledBackgroundColor: t.border,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSyncing)
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: t.primaryFg),
              )
            else if (pending == 0)
              Icon(Icons.check_rounded, size: 16, color: t.primaryFg)
            else
              Icon(Icons.sync_rounded, size: 16, color: t.primaryFg),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              fontFamily:  AppFonts.sans,
              fontSize:    14,
              fontWeight:  FontWeight.w600,
              color:       t.primaryFg,
            )),
          ],
        ),
      ),
    );
  }
}

// ─── How sync works info card ─────────────────────────────────────────────────
typedef _Step = ({IconData icon, String title, String desc, bool done});

class _InfoCard extends StatelessWidget {
  final List<_Step> steps;
  const _InfoCard({required this.steps});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Column(
        children: steps.asMap().entries.map((e) {
          final step   = e.value;
          final isLast = e.key == steps.length - 1;
          return Container(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(color: t.border, width: 0.6)),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm + 3),
            child: Row(children: [

              // Step icon
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: step.done
                      ? t.primary.withOpacity(0.08)
                      : t.border.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                ),
                child: Icon(
                  step.icon,
                  size:  16,
                  color: step.done ? t.primary : t.text3,
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),

              // Step text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.title, style: TextStyle(
                      fontFamily:  AppFonts.sans,
                      fontSize:    13,
                      fontWeight:  FontWeight.w600,
                      color:       step.done ? t.text : t.text3,
                    )),
                    const SizedBox(height: 1),
                    Text(step.desc,
                        style: AppFonts.label(color: t.text3)),
                  ],
                ),
              ),

              // Phase badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: step.done
                      ? t.successBg
                      : t.warnBg,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  step.done ? 'live' : 'phase 2',
                  style: AppFonts.monoStyle(
                    size:  10,
                    color: step.done ? t.success : t.warnFg,
                  ),
                ),
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Pending records list ─────────────────────────────────────────────────────
class _PendingList extends StatelessWidget {
  final AppDataProvider data;
  const _PendingList({required this.data});

  @override
  Widget build(BuildContext context) {
    final t       = context.appTheme;
    final pending = data.sortedMovements
        .where((m) => m.syncStatus == 'pending')
        .take(10) // show max 10
        .toList();

    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Column(
        children: pending.asMap().entries.map((e) {
          final m      = e.value;
          final isLast = e.key == pending.length - 1;
          final item   = data.getItemById(m.itemId);
          final to     = data.getLocationById(m.toLocationId);
          final staff  = data.staff.firstWhere(
            (s) => s.id == m.staffId,
            orElse: () => StaffModel(
                id: 0, name: 'Unknown', pin: '', createdAt: DateTime.now()),
          );

          final qty = m.quantity == m.quantity.truncateToDouble()
              ? m.quantity.toInt().toString()
              : m.quantity.toStringAsFixed(1);

          return Container(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom: BorderSide(color: t.border, width: 0.5)),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
            child: Row(children: [

              // Pending dot
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color:        t.warnFg,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Movement summary
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '$qty ${item?.unit ?? ''} ',
                    style: AppFonts.monoStyle(
                        size: 12, color: t.primary,
                        weight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '${item?.name ?? '—'}  ·  ',
                    style: AppFonts.monoStyle(size: 12, color: t.text),
                  ),
                  TextSpan(
                    text: '→ ${to?.name ?? '—'}',
                    style: AppFonts.monoStyle(size: 12, color: t.text2),
                  ),
                ])),
              ),

              // Staff + time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(staff.name,
                      style: AppFonts.monoStyle(size: 10, color: t.text3)),
                  Text(_fmtTime(m.createdAt),
                      style: AppFonts.monoStyle(size: 10, color: t.text3)),
                ],
              ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  static String _fmtTime(DateTime d) {
    final h    = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min  = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }
}