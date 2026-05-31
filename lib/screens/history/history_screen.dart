import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';

enum _DateFilter { all, today, week }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}
// ─── Transaction row — one card per groupId ──────────────────────────────────
class _TxnRow extends StatefulWidget {
  final List<MovementModel> movements; // all lines in this transaction
  final AppDataProvider     data;
  final bool                isLast;
  const _TxnRow({
    required this.movements,
    required this.data,
    required this.isLast,
  });
  @override
  State<_TxnRow> createState() => _TxnRowState();
}

class _TxnRowState extends State<_TxnRow> {

  // Use first movement as the anchor for header info and delete
  MovementModel get _anchor => widget.movements.first;

  Future<void> _confirmDelete(BuildContext context) async {
    final t   = context.appTheme;
    final m   = _anchor;
    final today   = DateTime.now();
    final sameDay = m.createdAt.toLocal().year  == today.year  &&
                    m.createdAt.toLocal().month == today.month &&
                    m.createdAt.toLocal().day   == today.day;

    if (!sameDay) {
      await showDialog(context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius)),
          title: Text('Cannot Delete', style: AppFonts.heading(color: t.text)),
          content: Text(
            'Movements can only be deleted on the same day they were created.',
            style: AppFonts.body(color: t.text2)),
          actions: [TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: AppFonts.body(color: t.primary)))],
        ));
      return;
    }

    if (m.fromLocationId == 'SUPPLIER') {
      await showDialog(context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius)),
          title: Text('Cannot Delete', style: AppFonts.heading(color: t.text)),
          content: Text(
            'Opening stock entries cannot be deleted.',
            style: AppFonts.body(color: t.text2)),
          actions: [TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: AppFonts.body(color: t.primary)))],
        ));
      return;
    }

    // Stock check for all lines in group
    final stock = widget.data.getStock();
    for (final mv in widget.movements) {
      final toEntry = stock.where((s) =>
          s.item.id     == mv.itemId &&
          s.location.id == mv.toLocationId).toList();
      final available = toEntry.isEmpty ? 0.0 : toEntry.first.balance;
      if (available < mv.quantity) {
        final item  = widget.data.getItemById(mv.itemId);
        final toLoc = widget.data.getLocationById(mv.toLocationId);
        await showDialog(context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: t.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSpacing.radius)),
            title: Text('Cannot Delete', style: AppFonts.heading(color: t.text)),
            content: Text(
              '${item?.name ?? 'Item'} has insufficient stock in '
              '${toLoc?.name ?? 'destination'} to revert this movement.',
              style: AppFonts.body(color: t.text2)),
            actions: [TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: AppFonts.body(color: t.primary)))],
          ));
        return;
      }
    }

    final confirmed = await showDialog<bool>(context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius)),
        title: Text(
          widget.movements.length > 1
              ? 'Delete transaction? (${widget.movements.length} items)'
              : 'Delete movement?',
          style: AppFonts.heading(color: t.text)),
        content: Text(
          'This will remove all items in this movement and update stock '
          'on all devices. This cannot be undone.',
          style: AppFonts.body(color: t.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppFonts.body(color: t.text3))),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: AppFonts.body(color: t.error)
                    .copyWith(fontWeight: FontWeight.w700))),
        ],
      ));

    if (confirmed != true || !mounted) return;
    // Delete entire group via anchor movement_id
    final ok = await widget.data.deleteMovement(_anchor.id);
    if (!mounted) return;
    if (!ok) showError(context, 'Failed to delete. Try again.');
  }

  void _showCannotEditDialog(BuildContext context, bool sameDay) {
    final t = context.appTheme;
    final message = !sameDay
        ? 'Movements can only be edited on the same day they were created.'
        : 'This movement has already been corrected once.\n\n'
          'Contact admin if a further change is needed.';
    showDialog(context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius)),
        title: Text('Cannot Edit', style: AppFonts.heading(color: t.text)),
        content: Text(message, style: AppFonts.body(color: t.text2)),
        actions: [TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('OK', style: AppFonts.body(color: t.primary)))],
      ));
  }

  @override
  Widget build(BuildContext context) {
    final t       = context.appTheme;
    final isAdmin = widget.data.isAdmin;
    final anchor  = _anchor;

    final from  = widget.data.getLocationById(anchor.fromLocationId);
    final to    = widget.data.getLocationById(anchor.toLocationId);
    final staff = widget.data.staff.firstWhere(
      (s) => s.id == anchor.staffId,
      orElse: () => StaffModel(
          id: '', name: 'Unknown', pin: '', createdAt: DateTime.now()),
    );

    final fromName = anchor.fromLocationId == 'SUPPLIER'
        ? 'Supplier' : (from?.name ?? '—');

    final today   = DateTime.now();
    final sameDay = anchor.createdAt.toLocal().year  == today.year &&
                    anchor.createdAt.toLocal().month == today.month &&
                    anchor.createdAt.toLocal().day   == today.day;
    final canEdit   = sameDay && (isAdmin || !anchor.edited);
    final canDelete = sameDay && isAdmin;
    final isSupplier = anchor.fromLocationId == 'SUPPLIER';

    final rowContent = GestureDetector(
      onTap: canEdit
          ? () => _showEditSheet(context, widget.movements, widget.data,
                supplierOnly: isSupplier)
          : () => _showCannotEditDialog(context, sameDay),
      child: Container(
        decoration: widget.isLast
            ? null
            : BoxDecoration(border: Border(
                bottom: BorderSide(color: t.border, width: 2.0))),
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — time · staff · from → to
            Text.rich(TextSpan(children: [
              TextSpan(
                text:  _fmtTime(anchor.createdAt),
                style: AppFonts.monoStyle(size: 13, color: t.text, weight: FontWeight.w500)),
              TextSpan(
                text:  '  ·  ',
                style: AppFonts.monoStyle(size: 13, color: t.border, weight: FontWeight.w500)),
              TextSpan(
                text:  staff.name,
                style: AppFonts.monoStyle(
                    size: 13, color: t.text, weight: FontWeight.w600)),
              TextSpan(
                text:  '  ·  ',
                style: AppFonts.monoStyle(size: 13, color: t.border)),
              TextSpan(
                text:  '$fromName → ${to?.name ?? '—'}',
                style: AppFonts.monoStyle(size: 13, color: t.text,weight: FontWeight.w500)),
            ]), softWrap: true),
            const SizedBox(height: 6),
            // Item lines
            ...widget.movements.map((mv) {
              final item = widget.data.getItemById(mv.itemId);
              final qty  = mv.quantity == mv.quantity.truncateToDouble()
                  ? mv.quantity.toInt().toString()
                  : mv.quantity.toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(TextSpan(children: [
                      TextSpan(
                        text:  '$qty ${item?.unit ?? ''}  ',
                        style: AppFonts.monoStyle(
                            size: 15, color: t.primary,
                            weight: FontWeight.w700)),
                      TextSpan(
                        text:  item?.name ?? '—',
                        style: AppFonts.monoStyle(
                            size: 15, color: t.text,
                            weight: FontWeight.w700)),
                    ])),
                    if (mv.baleNo != null && mv.baleNo!.isNotEmpty)
                      Text.rich(TextSpan(children: [
                        TextSpan(text: '# ',
                            style: AppFonts.monoStyle(
                                size: 12, color: t.text3)),
                        TextSpan(text: mv.baleNo!,
                            style: AppFonts.monoStyle(
                                size: 12, color: t.text2,
                                weight: FontWeight.w600)),
                      ])),
                  ],
                ),
              );
            }),
            // Remark
            if (anchor.remark != null && anchor.remark!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                TextSpan(text: 'Note: ',
                    style: AppFonts.monoStyle(
                        size: 13, color: t.text)),
                TextSpan(text: anchor.remark!,
                    style: AppFonts.monoStyle(
                        size: 13, color: t.text)),
              ])),
            ],
            // Edited tag
            if (anchor.edited) ...[
              const SizedBox(height: 5),
              Text.rich(TextSpan(children: [
                TextSpan(text: '✎ ',
                    style: AppFonts.monoStyle(size: 13, color: t.primaryFg,weight: FontWeight.w500)),
                TextSpan(text: 'edited',
                    style: AppFonts.monoStyle(size: 13, color: t.warnFg,weight: FontWeight.w500)),
              ])),
            ],
          ],
        ),
      ),
    );

    if (!isAdmin || !canDelete) return rowContent;
    return Dismissible(
      key:       ValueKey(anchor.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmDelete(context);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: AppSpacing.lg),
        decoration: BoxDecoration(
          color: t.error,
          border: widget.isLast
              ? null
              : Border(bottom: BorderSide(color: t.error, width: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 22),
            const SizedBox(height: 3),
            Text('Delete',
                style: AppFonts.monoStyle(size: 11, color: Colors.white)),
          ],
        ),
      ),
      child: rowContent,
    );
  }

  static String _fmtTime(DateTime d) {
    final local = d.toLocal();
    final h     = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final min   = local.minute.toString().padLeft(2, '0');
    final ampm  = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }
}

class _HistoryScreenState extends State<HistoryScreen> {
  String      _search     = '';
  _DateFilter _dateFilter = _DateFilter.all;
  final _searchCtrl = TextEditingController();

  // Cached filter+group result — recomputed only when inputs change
  List<MovementModel>?                                    _cachedFiltered;
  List<MapEntry<String, List<List<MovementModel>>>>?      _cachedGrouped;
  int    _lastMovementVersion = -1; // tracks edits AND adds (not just count)
  String _lastSearch          = '';
  _DateFilter _lastFilter     = _DateFilter.all;

   List<MapEntry<String, List<List<MovementModel>>>> _getGrouped(AppDataProvider data) {
    final version = data.movementVersion;
    if (_cachedGrouped != null &&
        version     == _lastMovementVersion &&
        _search     == _lastSearch &&
        _dateFilter == _lastFilter) {
      return _cachedGrouped!;
    }
    _cachedFiltered      = _filter(data);
    _cachedGrouped       = _group(_cachedFiltered!);
    _lastMovementVersion = version;
    _lastSearch          = _search;
    _lastFilter          = _dateFilter;
    return _cachedGrouped!;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<MovementModel> _filter(AppDataProvider data) {
    final now       = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);
    final weekStart = today.subtract(const Duration(days: 7));

    return data.sortedMovements.where((m) {
      // Date filter
      if (_dateFilter == _DateFilter.today) {
        final local = m.createdAt.toLocal();
        final d = DateTime(local.year, local.month, local.day);
        if (d != today) return false;
      }
      if (_dateFilter == _DateFilter.week &&
          m.createdAt.isBefore(weekStart)) return false;

      // Search filter
      
      if (_search.isNotEmpty) {
        final q    = _search.toLowerCase();
        final item = data.getItemById(m.itemId);
        final from = data.getLocationById(m.fromLocationId);
        final to   = data.getLocationById(m.toLocationId);
         final stf = data.staffById(m.staffId); 
        return (item?.name.toLowerCase().contains(q) ?? false) ||
               (data.staffById(m.staffId)?.name.toLowerCase().contains(q) ?? false) ||
               (from?.name.toLowerCase().contains(q) ?? false) ||
               (to?.name.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();
  }

  // Group movements by date label
  // Returns date-grouped list where each entry is a transaction group
  // Each transaction group contains all movements with same groupId
  // Groups by date, then within each date groups by groupId
  // Returns: date label → list of transaction groups
  // Each transaction group = list of movements with same groupId
  List<MapEntry<String, List<List<MovementModel>>>> _group(
      List<MovementModel> list) {
    final now       = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // Step 1 — group by date
    final dateMap = <String, List<MovementModel>>{};
    for (final m in list) {
      final local = m.createdAt.toLocal();
      final d     = DateTime(local.year, local.month, local.day);
      final label = d == today
          ? 'Today'
          : d == yesterday
              ? 'Yesterday'
              : _fmtDate(m.createdAt);
      dateMap.putIfAbsent(label, () => []).add(m);
    }

    // Step 2 — within each date group by groupId
    final result = <MapEntry<String, List<List<MovementModel>>>>[];
    for (final entry in dateMap.entries) {
      final txnMap = <String, List<MovementModel>>{};
      for (final m in entry.value) {
        final gid = (m.groupId.isEmpty) ? m.id : m.groupId;
        txnMap.putIfAbsent(gid, () => []).add(m);
      }
      result.add(MapEntry(entry.key, txnMap.values.toList()));
    }
    return result;
  }

  static String _fmtDate(DateTime d) {
    final local = d.toLocal();
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${local.day} ${mo[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t        = context.appTheme;
   final data     = context.read<AppDataProvider>();
    // Watch movementVersion — catches edits (qty change) AND adds/deletes.
  // totalMovements (count) misses edits since count stays the same.
  context.select<AppDataProvider, int>((p) => p.movementVersion);
    final grouped  = _getGrouped(data); // now List<MapEntry<String, List<List<MovementModel>>>>
    // Total transaction count for header badge
    final txnCount = grouped.fold<int>(0, (sum, e) => sum + e.value.length);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        leading: const AppBackButton(),
        title: Text(
          'History',
          style: AppFonts.heading(color: t.text).copyWith(fontSize: 16),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  
                  color: t.primary.withValues(alpha: .1),
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  '$txnCount transactions',
                  style: AppFonts.monoStyle(size: 12, color: t.primary,weight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [

            // Search + date filter
            Padding(
              padding:
                  AppSizes.pagePadding(context).copyWith(bottom: 8),
              child: Column(children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged:  (v) => setState(() => _search = v),
                  style:      AppFonts.body(color: t.text),
                  decoration: InputDecoration(
                    hintText:   'Search...',
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: t.text3),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 16, color: t.text3),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical:   AppSpacing.sm),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(children: [
                  _Chip(
                    label:    'All',
                    selected: _dateFilter == _DateFilter.all,
                    onTap:    () => setState(
                        () => _dateFilter = _DateFilter.all),
                  ),
                  const SizedBox(width: 6),
                  _Chip(
                    label:    'Today',
                    selected: _dateFilter == _DateFilter.today,
                    onTap:    () => setState(
                        () => _dateFilter = _DateFilter.today),
                  ),
                  const SizedBox(width: 6),
                  _Chip(
                    label:    'This week',
                    selected: _dateFilter == _DateFilter.week,
                    onTap:    () => setState(
                        () => _dateFilter = _DateFilter.week),
                  ),
                ]),
              ]),
            ),

            // Movement list
           Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: grouped.isEmpty
                    ? EmptyState(
                        key:     const ValueKey('empty'),
                        icon:    Icons.history_rounded,
                        message: _search.isNotEmpty
                            ? 'No records match "$_search"'
                            : 'No movements recorded yet.',
                      )
                    : _buildFlatList(context, grouped, data, t),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlatList(
  BuildContext context,
  List<MapEntry<String, List<List<MovementModel>>>> grouped,
  AppDataProvider data,
  AppThemeExtension t,
) {
  // Flatten: [header, txn, txn, header, txn, ...] as a single item list
  final items = <Object>[];
  for (final group in grouped) {
    items.add(group.key);              // String = date header
    items.addAll(group.value);         // List<MovementModel> = txn row
  }

   return ListView.builder(
    key: const ValueKey('history-list'),
    padding: AppSizes.pagePadding(context).copyWith(top: 4, bottom: AppSpacing.lg),
    itemCount: items.length,
    itemBuilder: (_, i) {
      final item = items[i];
      if (item is String) {
        // Date header
        final txnCount = grouped
            .firstWhere((e) => e.key == item).value.length;
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Row(children: [
            Text(item.toUpperCase(),
                style: AppFonts.labelStyle(color: t.text3)),
            const SizedBox(width: 8),
            Expanded(child: Container(height: 0.5, color: t.border)),
            const SizedBox(width: 8),
            Text('$txnCount',
                style: AppFonts.monoStyle(size: 10, color: t.text3)),
          ]),
        );
      }
      final txn  = item as List<MovementModel>;
      final isLast = i == items.length - 1 || items[i + 1] is String;
      return _TxnRow(movements: txn, data: data, isLast: isLast);
    },
  );
}

}

// ─── Single log row ───────────────────────────────────────────────────────────
class _LogRow extends StatefulWidget {
  final MovementModel   movement;
  final AppDataProvider data;
  final bool            isLast;

  const _LogRow({
    required this.movement,
    required this.data,
    required this.isLast,
  });

  @override
  State<_LogRow> createState() => _LogRowState();
}

class _LogRowState extends State<_LogRow> {

    Future<void> _confirmDelete(BuildContext context) async {
    final t     = context.appTheme;
     final today = DateTime.now();
    final m     = widget.movement;
    final sameDay = m.createdAt.toLocal().year  == today.year  &&
                    m.createdAt.toLocal().month == today.month &&
                    m.createdAt.toLocal().day   == today.day;
  debugPrint('DEBUG confirmDelete '
    'createdAt=${m.createdAt} '
    'createdAtLocal=${m.createdAt.toLocal()} '
    'today=$today '
    'isUtc=${m.createdAt.isUtc} '
    'sameDay=$sameDay');
    // Block edit/delete of movements not from today
    if (!sameDay) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius)),
          title: Text('Cannot Delete',
              style: AppFonts.heading(color: t.text)),
          content: Text(
            'Movements can only be deleted on the same day they were created.\n\n'
            'This movement was created on '
            '${m.createdAt.day}/${m.createdAt.month}/${m.createdAt.year}.',
            style: AppFonts.body(color: t.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: AppFonts.body(color: t.primary)),
            ),
          ],
        ),
      );
      return;
    }

    // Block delete of SUPPLIER movements
    if (widget.movement.fromLocationId == 'SUPPLIER') {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius)),
          title: Text('Cannot Delete',
              style: AppFonts.heading(color: t.text)),
          content: Text(
            'Opening stock entries cannot be deleted — they are the '
            'base for all stock calculations.\n\n'
            'To correct an error, edit the quantity directly.',
            style: AppFonts.body(color: t.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: AppFonts.body(color: t.primary)),
            ),
          ],
        ),
      );
      return;
    }

    // Stock consistency check for regular movements
    // Deleting a movement that took stock FROM a location
    // effectively adds that qty back — safe.
    // Deleting a movement that brought stock TO a location
    // removes that qty — could make dependent locations go negative.
    final stock = widget.data.getStock();

    // Check if destination location has enough stock to absorb this deletion
    final toEntry = stock.where((s) =>
        s.item.id     == m.itemId &&
        s.location.id == m.toLocationId,
    ).toList();

    final availableAtDest = toEntry.isEmpty ? 0.0 : toEntry.first.balance;

    if (availableAtDest < m.quantity) {
      final item   = widget.data.getItemById(m.itemId);
      final toLoc  = widget.data.getLocationById(m.toLocationId);
      final qtyStr = m.quantity == m.quantity.truncateToDouble()
          ? m.quantity.toInt().toString()
          : m.quantity.toStringAsFixed(1);
      final availStr = availableAtDest == availableAtDest.truncateToDouble()
          ? availableAtDest.toInt().toString()
          : availableAtDest.toStringAsFixed(1);

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: t.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius)),
          title: Text('Cannot Delete',
              style: AppFonts.heading(color: t.text)),
          content: Text(
            '${item?.name ?? 'Item'} has only $availStr ${item?.unit ?? ''} '
            'remaining in ${toLoc?.name ?? 'destination'}.\n\n'
            'Deleting this movement would remove $qtyStr ${item?.unit ?? ''} '
            'and make the stock negative.\n\n'
            'Move or edit later movements first.',
            style: AppFonts.body(color: t.text2),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: AppFonts.body(color: t.primary)),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius)),
        title: Text('Delete movement?',
            style: AppFonts.heading(color: t.text)),
        content: Text(
          'This will remove the movement and update stock on all devices. '
          'This cannot be undone.',
          style: AppFonts.body(color: t.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppFonts.body(color: t.text3)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete',
                style: AppFonts.body(color: t.error)
                    .copyWith(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await widget.data.deleteMovement(widget.movement.id);
    if (!mounted) return;
    if (!ok) showError(context, 'Failed to delete. Try again.');
  }

  void _showCannotEditDialog(BuildContext context, bool sameDay) {
  final t = context.appTheme;
  final message = !sameDay
      ? 'Movements can only be edited on the same day they were created.'
      : 'This movement has already been corrected once.\n\n'
        'Contact admin if a further change is needed.';
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radius)),
      title: Text('Cannot Edit',
          style: AppFonts.heading(color: t.text)),
      content: Text(message, style: AppFonts.body(color: t.text2)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('OK', style: AppFonts.body(color: t.primary)),
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final t       = context.appTheme;
    final m       = widget.movement;
    final isAdmin = widget.data.isAdmin;

    // Resolve names safely
    final item  = widget.data.getItemById(m.itemId);
    final from  = widget.data.getLocationById(m.fromLocationId);
    final to    = widget.data.getLocationById(m.toLocationId);
    final staff = widget.data.staff.firstWhere(
      (s) => s.id == m.staffId,
      orElse: () => StaffModel(
          id: '', name: 'Unknown', pin: '', createdAt: DateTime.now()),
    );
    final editedByStaff = m.editedBy != null
        ? widget.data.staff.firstWhere(
            (s) => s.id == m.editedBy,
            orElse: () => StaffModel(
                id: '', name: 'Unknown', pin: '',
                createdAt: DateTime.now()),
          )
        : null;

    final qty = m.quantity == m.quantity.truncateToDouble()
        ? m.quantity.toInt().toString()
        : m.quantity.toStringAsFixed(1);

    final fromName = m.fromLocationId == 'SUPPLIER'
        ? 'Supplier'
        : (from?.name ?? '—');
// SUPPLIER movements: allow edit (qty/item only, no location change)
    // Regular movements: allow edit only if not from supplier
    
    final isSupplierMovement = m.fromLocationId == 'SUPPLIER';
    final today   = DateTime.now();
    final sameDay = m.createdAt.toLocal().year  == today.year  &&
                    m.createdAt.toLocal().month == today.month &&
                    m.createdAt.toLocal().day   == today.day;
    final canEdit   = sameDay && (isAdmin || !m.edited);
    final canDelete = sameDay && isAdmin;

    // ── Row content ──────────────────────────────────────────────────────────
    final rowContent = GestureDetector(
      onTap: canEdit
           ? () => _showEditSheet(
                context, [widget.movement], widget.data,
                supplierOnly: isSupplierMovement,
              )
          : () => _showCannotEditDialog(context, sameDay),

      child: Container(
        decoration: widget.isLast
            ? null
            : BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: t.border, width: 0.5))),
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text:  _fmtTime(m.createdAt),
                  style: AppFonts.monoStyle(size: 13, color: t.text3),
                ),
                TextSpan(
                  text:  '  ·  ',
                  style: AppFonts.monoStyle(size: 13, color: t.border),
                ),
                TextSpan(
                  text:  staff.name,
                  style: AppFonts.monoStyle(
                      size:   13,
                      color:  t.text2,
                      weight: FontWeight.w600),
                ),
                TextSpan(
                  text:  '  ·  ',
                  style: AppFonts.monoStyle(size: 13, color: t.border),
                ),
                TextSpan(
                  text:  '$qty ${item?.unit ?? ''}',
                  style: AppFonts.monoStyle(
                      size:   15,
                      color:  t.primary,
                      weight: FontWeight.w700),
                ),
                TextSpan(
                  text:  ' ${item?.name ?? '—'}',
                  style: AppFonts.monoStyle(
                      size:   15,
                      color:  t.text,
                      weight: FontWeight.w700),
                ),
                TextSpan(
                  text:  '  ·  ',
                  style: AppFonts.monoStyle(size: 13, color: t.border),
                ),
                TextSpan(
                  text:  '$fromName → ${to?.name ?? '—'}',
                  style: AppFonts.monoStyle(size: 13, color: t.text2),
                ),
              ]),
              softWrap: true,
            ),
            if (m.baleNo != null && m.baleNo!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                TextSpan(
                  text:  '# ',
                  style: AppFonts.monoStyle(size: 13, color: t.text3),
                ),
                TextSpan(
                  text:  m.baleNo!,
                  style: AppFonts.monoStyle(
                      size: 13, color: t.text2,
                      weight: FontWeight.w600),
                ),
              ])),
            ],
            if (m.remark != null && m.remark!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text.rich(TextSpan(children: [
                TextSpan(
                  text: 'Note: ',
                  style: AppFonts.monoStyle(size: 13, color: t.text3, weight: FontWeight.w600),
                ),
                TextSpan(
                  text: m.remark!,
                  style: AppFonts.monoStyle(size: 13, color: t.text, weight: FontWeight.w600),
                ),
              ])),
            ],
            if (m.edited) ...[
              const SizedBox(height: 5),
              Text.rich(TextSpan(children: [
                TextSpan(
                  text:  '✎ ',
                  style: AppFonts.monoStyle(size: 13, color: t.warnFg),
                ),
                TextSpan(
                  text: editedByStaff != null
                      ? 'edited by ${editedByStaff.name}'
                      : 'edited',
                  style: AppFonts.monoStyle(size: 13, color: t.warnFg),
                ),
              ])),
            ],
          ],
        ),
      ),
    );

    // ── Wrap with Dismissible for admin only ─────────────────────────────────
    if (!isAdmin || !canDelete) return rowContent;
    return Dismissible(
      key:       ValueKey(m.id),
      direction: DismissDirection.endToStart,
      // confirmDismiss handles dialog + deletion — always return false
      // so the widget is removed only via provider (state-driven, not widget-driven)
      confirmDismiss: (_) async {
        await _confirmDelete(context);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding:   const EdgeInsets.only(right: AppSpacing.lg),
        decoration: BoxDecoration(
          color: t.error,
          border: widget.isLast
              ? null
              : Border(bottom: BorderSide(color: t.error, width: 0.5)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_outline_rounded,
                color: Colors.white, size: 22),
            const SizedBox(height: 3),
            Text('Delete',
                style: AppFonts.monoStyle(size: 11, color: Colors.white)),
          ],
        ),
      ),
      child: rowContent,
    );
  }

  static String _fmtTime(DateTime d) {
    final local = d.toLocal();
    final h     = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final min   = local.minute.toString().padLeft(2, '0');
    final ampm  = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }
}

// ─── Edit movement sheet ─────────────────────────────────────────────────────
void _showEditSheet(
  BuildContext          context,
  List<MovementModel>   movements,
  AppDataProvider       data, {
  bool supplierOnly = false,
}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    useSafeArea:        true,
    backgroundColor:    Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize:     0.4,
      maxChildSize:     0.95,
      expand:           false,
      builder: (_, scrollCtrl) => _EditSheet(
        movement:         movements.first,
        allMovements:     movements,
        data:             data,
        supplierOnly:     supplierOnly,
        scrollController: scrollCtrl,
      ),
    ),
  );
}

class _EditLineState {
  final MovementModel         movement;
  ItemModel                   selectedItem;
  final TextEditingController qtyCtrl;
  final TextEditingController baleCtrl;
  bool                        removed;

  _EditLineState({
    required this.movement,
    required this.selectedItem,
    required this.qtyCtrl,
    required this.baleCtrl,
    this.removed = false,
  });

  void dispose() {
    qtyCtrl.dispose();
    baleCtrl.dispose();
  }
}


class _EditSheet extends StatefulWidget {
  final MovementModel      movement;        // anchor — always first
  final List<MovementModel> allMovements;   // all lines in transaction
  final AppDataProvider    data;
  final bool               supplierOnly;
  final ScrollController?  scrollController;
  const _EditSheet({
    required this.movement,
    required this.allMovements,
    required this.data,
    this.supplierOnly    = false,
    this.scrollController,
  });

  bool get isMulti => allMovements.length > 1;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  // Shared fields
  final TextEditingController _remarkCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  LocationModel?  _fromLoc;
  LocationModel?  _toLoc;
  bool            _isSaving = false;

  // Single movement fields (used when isMulti=false)
  final TextEditingController _qtyCtrl    = TextEditingController();
  final TextEditingController _baleNoCtrl = TextEditingController();
  ItemModel? _selectedItem;

  // Multi-movement per-line state
  final List<_EditLineState> _editLines = [];

  @override
  void initState() {
    super.initState();
    final m    = widget.movement;
    final locs = widget.data.locations;

    // Shared fields — from anchor movement
    _remarkCtrl.text = m.remark ?? '';
    _fromLoc = widget.supplierOnly
        ? null
        : locs.firstWhere((l) => l.id == m.fromLocationId,
            orElse: () => locs.first);
    _toLoc = locs.firstWhere((l) => l.id == m.toLocationId,
        orElse: () => locs.first);

    if (!widget.isMulti) {
      // Single movement
      _qtyCtrl.text    = m.quantity == m.quantity.truncateToDouble()
          ? m.quantity.toInt().toString()
          : m.quantity.toStringAsFixed(1);
      _baleNoCtrl.text = m.baleNo ?? '';
      _selectedItem    = widget.data.getItemById(m.itemId);
    } else {
      // Multi-item — initialise per-line state
      for (final mv in widget.allMovements) {
        final item = widget.data.getItemById(mv.itemId);
        if (item == null) continue;
        _editLines.add(_EditLineState(
          movement:    mv,
          selectedItem: item,
          qtyCtrl:     TextEditingController(
            text: mv.quantity == mv.quantity.truncateToDouble()
                ? mv.quantity.toInt().toString()
                : mv.quantity.toStringAsFixed(1),
          ),
          baleCtrl: TextEditingController(text: mv.baleNo ?? ''),
        ));
      }
    }
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    _qtyCtrl.dispose();
    _baleNoCtrl.dispose();
    for (final l in _editLines) l.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_toLoc == null) { showError(context, 'Select To location'); return; }
    if (!widget.supplierOnly && _fromLoc == null) {
      showError(context, 'Select From location'); return;
    }
    if (!widget.supplierOnly && _fromLoc!.id == _toLoc!.id) {
      showError(context, 'From and To cannot be the same'); return;
    }

    setState(() => _isSaving = true);

    if (!widget.isMulti) {
      // ── Single movement ──────────────────────────────────────────
      if (_selectedItem == null) {
        showError(context, 'Select an item');
        setState(() => _isSaving = false);
        return;
      }
      final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
      if (qty <= 0) {
        showError(context, 'Enter valid quantity');
        setState(() => _isSaving = false);
        return;
      }
      // Stock validation
      final fromId = widget.supplierOnly ? 'SUPPLIER' : _fromLoc!.id;
      if (fromId != 'SUPPLIER') {
        final stockList    = widget.data.getStock();
        final stockEntry   = stockList.where((s) =>
            s.item.id     == _selectedItem!.id &&
            s.location.id == fromId).toList();
        final currentBal   = stockEntry.isEmpty ? 0.0 : stockEntry.first.balance;
        final sameItem     = _selectedItem!.id == widget.movement.itemId;
        final sameFrom     = fromId == widget.movement.fromLocationId;
        final originalQty  = (sameItem && sameFrom) ? widget.movement.quantity : 0.0;
        final available    = currentBal + originalQty;
        if (qty > available) {
          showError(context,
            'Not enough stock. Available: '
            '${available % 1 == 0 ? available.toInt() : available.toStringAsFixed(1)} '
            '${_selectedItem!.unit} in ${_fromLoc!.name}');
          setState(() => _isSaving = false);
          return;
        }
      }
      final ok = await widget.data.editMovement(
        movementId:     widget.movement.id,
        itemId:         _selectedItem!.id,
        quantity:       qty,
        fromLocationId: fromId,
        toLocationId:   _toLoc!.id,
        baleNo:         _baleNoCtrl.text.trim().isEmpty
            ? null : _baleNoCtrl.text.trim(),
        remark:         _remarkCtrl.text.trim().isEmpty
            ? null : _remarkCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (ok) { showSuccess(context, 'Movement updated'); Navigator.of(context).pop(); }
      else    { showError(context, 'Failed to update. Try again.'); }

    } else {
      // ── Multi-item transaction ───────────────────────────────────
      final activeLines = _editLines.where((l) => !l.removed).toList();
      if (activeLines.isEmpty) {
        showError(context, 'Cannot remove all items. Delete the transaction instead.');
        setState(() => _isSaving = false);
        return;
      }
      bool allOk = true;
      for (final line in activeLines) {
        final qty = double.tryParse(line.qtyCtrl.text.trim()) ?? 0;
        if (qty <= 0) {
          showError(context, 'Enter valid quantity for ${line.selectedItem.name}');
          setState(() => _isSaving = false);
          return;
        }
        final ok = await widget.data.editMovement(
          movementId:     line.movement.id,
          itemId:         line.selectedItem.id,
          quantity:       qty,
          fromLocationId: _fromLoc?.id ?? line.movement.fromLocationId,
          toLocationId:   _toLoc!.id,
          baleNo:         line.baleCtrl.text.trim().isEmpty
              ? null : line.baleCtrl.text.trim(),
          remark:         _remarkCtrl.text.trim().isEmpty
              ? null : _remarkCtrl.text.trim(),
        );
        if (!ok) allOk = false;
      }
      // Soft-delete removed lines
      for (final line in _editLines.where((l) => l.removed)) {
        await widget.data.deleteMovement(line.movement.id);
      }
      if (!mounted) return;
      setState(() => _isSaving = false);
      if (allOk) { showSuccess(context, 'Movement updated'); Navigator.of(context).pop(); }
      else       { showError(context, 'Some lines could not be updated.'); }
    }
    return ;
  }

  @override
  Widget build(BuildContext context) {
    final t   = context.appTheme;
    final bot = MediaQuery.of(context).viewInsets.bottom;
    final locs = widget.data.locations;

    // Re-resolve from live list — prevents stale reference crash on realtime sync
    final fromId = _fromLoc?.id;
    final toId   = _toLoc?.id;
    if (fromId != null) {
      final f = locs.firstWhere((l) => l.id == fromId, orElse: () => _fromLoc!);
      if (!identical(f, _fromLoc)) _fromLoc = f;
    }
    if (toId != null) {
      final f = locs.firstWhere((l) => l.id == toId, orElse: () => _toLoc!);
      if (!identical(f, _toLoc)) _toLoc = f;
    }
    if (!widget.isMulti && _selectedItem != null) {
      final f = widget.data.items.firstWhere(
          (i) => i.id == _selectedItem!.id, orElse: () => _selectedItem!);
      if (!identical(f, _selectedItem)) _selectedItem = f;
    }

    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bot),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          controller: widget.scrollController,
          child: Column(
            mainAxisSize:       MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // Handle
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color:        t.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              )),
              const SizedBox(height: AppSpacing.md),

              // Title
              Row(children: [
                Expanded(child: Text('Edit Movement',
                    style: AppFonts.heading(color: t.text))),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(Icons.close_rounded, size: 20, color: t.text3),
                ),
              ]),
              const SizedBox(height: AppSpacing.lg),

              // ── SINGLE MOVEMENT ────────────────────────────────────────────
              if (!widget.isMulti) ...[
                // Item
                DropdownButtonFormField<ItemModel>(
                  initialValue: widget.data.items
                      .where((i) => i.id == _selectedItem?.id).firstOrNull,
                      isExpanded:    true,
                  dropdownColor: t.surface,
                  style:         AppFonts.body(color: t.text),
                  decoration: InputDecoration(
                    labelText:  'Item',
                    prefixIcon: Icon(Icons.inventory_2_outlined,
                        size: 18, color: t.text3),
                  ),
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
                  items: widget.data.items.map((i) => DropdownMenuItem(
                    value: i,
                    child: Text(i.name, style: AppFonts.body(color: t.text)),
                  )).toList(),
                  onChanged: (v) => setState(() => _selectedItem = v),
                  validator: (_) =>
                      _selectedItem == null ? 'Select an item' : null,
                ),
                const SizedBox(height: AppSpacing.md),

                // Quantity
                TextFormField(
                  controller:   _qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  style: AppFonts.monoStyle(
                      size: 16, color: t.text, weight: FontWeight.w600),
                  decoration: InputDecoration(
                    labelText:  'Quantity',
                    prefixIcon: Icon(Icons.scale_outlined,
                        size: 18, color: t.text3),
                    suffix: _selectedItem != null
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(_selectedItem!.unit,
                                style: AppFonts.monoStyle(
                                    size: 11, color: t.primary)),
                          )
                        : null,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final q = double.tryParse(v.trim());
                    if (q == null || q <= 0) return 'Must be greater than 0';
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),

                // Bale No — all single movements
                TextFormField(
                  controller: _baleNoCtrl,
                  style:      AppFonts.body(color: t.text),
                  decoration: InputDecoration(
                    labelText:  'Bale No (optional)',
                    hintText:   widget.supplierOnly
                        ? 'e.g. 1274*2'
                        : 'Must match existing bale at From location',
                    prefixIcon: Icon(Icons.tag_rounded,
                        size: 18, color: t.text3),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ]

              // ── MULTI-ITEM TRANSACTION ─────────────────────────────────────
              else ...[
                ..._editLines.asMap().entries.map((entry) {
                  final idx  = entry.key;
                  final line = entry.value;
                  if (line.removed) return const SizedBox.shrink();
                  final activeCount =
                      _editLines.where((l) => !l.removed).length;
                  return Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color:        t.bg,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border:       Border.all(color: t.border, width: 0.8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Line header
                        Row(children: [
                          Text('Item ${idx + 1}',
                              style: AppFonts.label(color: t.text3)),
                          const Spacer(),
                          if (activeCount > 1)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => line.removed = true),
                              child: Icon(Icons.close_rounded,
                                  size: 18, color: t.error),
                            ),
                        ]),
                        const SizedBox(height: AppSpacing.sm),
                        // Item dropdown per line
                        DropdownButtonFormField<ItemModel>(
                          initialValue: widget.data.items.firstWhere(
                            (i) => i.id == line.selectedItem.id,
                            orElse: () => line.selectedItem,
                          ),
                          isExpanded:    true,
                          dropdownColor: t.surface,
                          style:         AppFonts.body(color: t.text),
                          decoration: InputDecoration(
                            labelText:  'Item',
                            prefixIcon: Icon(Icons.inventory_2_outlined,
                                size: 18, color: t.text3),
                          ),
                          icon: Icon(Icons.keyboard_arrow_down_rounded,
                              color: t.text3),
                          items: widget.data.items.map((i) =>
                            DropdownMenuItem(
                              value: i,
                              child: Text(i.name,
                                  style: AppFonts.body(color: t.text)),
                            )).toList(),
                          onChanged: (v) => setState(
                              () => line.selectedItem = v ?? line.selectedItem),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // Qty
                        TextFormField(
                          controller:   line.qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: AppFonts.monoStyle(
                              size: 15, color: t.text,
                              weight: FontWeight.w600),
                          decoration: InputDecoration(
                            labelText:  'Quantity',
                            prefixIcon: Icon(Icons.scale_outlined,
                                size: 18, color: t.text3),
                            suffix: Text(line.selectedItem.unit,
                                style: AppFonts.monoStyle(
                                    size: 11, color: t.primary)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        // Bale No — all lines
                        TextFormField(
                          controller: line.baleCtrl,
                          style:      AppFonts.body(color: t.text),
                          decoration: InputDecoration(
                            labelText:  'Bale No (optional)',
                            hintText:   'Must match existing bale',
                            prefixIcon: Icon(Icons.tag_rounded,
                                size: 18, color: t.text3),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: AppSpacing.sm),
              ],

              // ── SHARED: From / To / Remark ─────────────────────────────────
              // From location
              if (widget.supplierOnly)
                _LockedField(
                  label: 'From',
                  value: 'Supplier',
                  icon:  Icons.local_shipping_outlined,
                  t:     t,
                )
              else
                DropdownButtonFormField<LocationModel>(
                  initialValue: locs.any((l) => l.id == _fromLoc?.id)
                      ? _fromLoc : null,
                      isExpanded:    true,
                  dropdownColor: t.surface,
                  style:         AppFonts.body(color: t.text),
                  decoration: InputDecoration(
                    labelText:  'From',
                    prefixIcon: Icon(Icons.output_rounded,
                        size: 18, color: t.text3),
                  ),
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
                  items: locs
                      .where((l) => _toLoc == null || l.id != _toLoc!.id)
                      .where((l) =>
                          !l.name.toLowerCase().contains('customer'))
                      .map((l) => DropdownMenuItem(
                        value: l,
                        child: Row(children: [
                          Icon(l.type == 'shop'
                              ? Icons.storefront_outlined
                              : Icons.warehouse_outlined,
                              size: 14, color: t.text3),
                          const SizedBox(width: 8),
                          Text(l.name, style: AppFonts.body(color: t.text)),
                        ]),
                      )).toList(),
                  onChanged: (v) => setState(() => _fromLoc = v),
                  validator: (_) => (!widget.supplierOnly && _fromLoc == null)
                      ? 'Required' : null,
                ),
              const SizedBox(height: AppSpacing.sm),

              // To location
              DropdownButtonFormField<LocationModel>(
                initialValue: locs.any((l) => l.id == _toLoc?.id)
                    ? _toLoc : null,
                    isExpanded:    true,
                dropdownColor: t.surface,
                style:         AppFonts.body(color: t.text),
                decoration: InputDecoration(
                  labelText:  'To',
                  prefixIcon: Icon(Icons.input_rounded,
                      size: 18, color: t.text3),
                ),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
                items: locs
                    .where((l) => widget.supplierOnly ||
                        _fromLoc == null || l.id != _fromLoc!.id)
                    .map((l) => DropdownMenuItem(
                      value: l,
                      child: Row(children: [
                        Icon(l.type == 'shop'
                            ? Icons.storefront_outlined
                            : Icons.warehouse_outlined,
                            size: 14, color: t.text3),
                        const SizedBox(width: 8),
                        Text(l.name, style: AppFonts.body(color: t.text)),
                      ]),
                    )).toList(),
                onChanged: (v) => setState(() => _toLoc = v),
                validator: (_) => _toLoc == null ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.sm),

              // Remark
              TextFormField(
                controller: _remarkCtrl,
                maxLines:   2,
                maxLength:  150,
                style:      AppFonts.body(color: t.text),
                decoration: InputDecoration(
                  labelText:          'Remark (optional)',
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(bottom: 26),
                    child: Icon(Icons.notes_rounded,
                        size: 18, color: t.text3),
                  ),
                  counterStyle:       AppFonts.label(color: t.text3),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Save
              PrimaryButton(
                label:   'Save Changes',
                icon:    Icons.check_rounded,
                onTap:   _submit,
                loading: _isSaving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedField extends StatelessWidget {
  final String             label;
  final String             value;
  final IconData           icon;
  final AppThemeExtension  t;

  const _LockedField({
    required this.label,
    required this.value,
    required this.icon,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: 14),
      decoration: BoxDecoration(
        color:        t.border.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: t.text3),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: AppFonts.label(color: t.text3, size: 11)),
            const SizedBox(height: 2),
            Text(value,
                style: AppFonts.body(color: t.text2)),
          ],
        )),
        Icon(Icons.lock_outline_rounded, size: 14, color: t.text3),
      ]),
    );
  }
}

// ─── Filter chip ──────────────────────────────────────────────────────────────
class _Chip extends StatelessWidget {
  final String       label;
  final bool         selected;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? t.primary : t.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
          border: Border.all(
              color: selected ? t.primary : t.border, width: 0.8),
        ),
        child: Text(
          label,
          style: AppFonts.label(
              color: selected ? t.primaryFg : t.text2, size: 11),
        ),
      ),
    );
  }
}
