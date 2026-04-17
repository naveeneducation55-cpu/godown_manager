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

class _HistoryScreenState extends State<HistoryScreen> {
  String      _search     = '';
  _DateFilter _dateFilter = _DateFilter.all;
  final _searchCtrl = TextEditingController();
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
        final stf  = data.staff.firstWhere(
          (s) => s.id == m.staffId,
          orElse: () => StaffModel(
              id: '', name: '', pin: '', createdAt: DateTime.now()),
        );
        return (item?.name.toLowerCase().contains(q) ?? false) ||
               stf.name.toLowerCase().contains(q) ||
               (from?.name.toLowerCase().contains(q) ?? false) ||
               (to?.name.toLowerCase().contains(q) ?? false);
      }
      return true;
    }).toList();
  }

  // Group movements by date label
  List<MapEntry<String, List<MovementModel>>> _group(
      List<MovementModel> list) {
    final now       = DateTime.now();
    final today     = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final map       = <String, List<MovementModel>>{};

    for (final m in list) {
      final local = m.createdAt.toLocal();
      final d = DateTime(local.year, local.month, local.day);
      final label = d == today
          ? 'Today'
          : d == yesterday
              ? 'Yesterday'
              : _fmtDate(m.createdAt);
      map.putIfAbsent(label, () => []).add(m);
    }
    return map.entries.toList();
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
    final data     = context.watch<AppDataProvider>();
    final filtered = _filter(data);
    final grouped  = _group(filtered);

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
                      BorderRadius.circular(AppSpacing.radiusXs),
                ),
                child: Text(
                  '${filtered.length} records',
                  style: AppFonts.monoStyle(size: 11, color: t.primary),
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
              child: grouped.isEmpty
                  ? EmptyState(
                      icon:    Icons.history_rounded,
                      message: _search.isNotEmpty
                          ? 'No records match "$_search"'
                          : 'No movements recorded yet.',
                    )
                  : ListView.builder(
                      padding: AppSizes.pagePadding(context)
                          .copyWith(top: 4, bottom: AppSpacing.lg),
                      itemCount: grouped.length,
                      itemBuilder: (_, i) {
                        final label = grouped[i].key;
                        final list  = grouped[i].value;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Date group header
                            Padding(
                              padding: const EdgeInsets.only(
                                  top: 16, bottom: 8),
                              child: Row(children: [
                                Text(label.toUpperCase(),
                                    style: AppFonts.labelStyle(
                                        color: t.text3)),
                                const SizedBox(width: 8),
                                Expanded(child: Container(
                                    height: 0.5, color: t.border)),
                                const SizedBox(width: 8),
                                Text('${list.length}',
                                    style: AppFonts.monoStyle(
                                        size: 10, color: t.text3)),
                              ]),
                            ),
                            // Log rows
                            ...list.asMap().entries.map((e) =>
                              _LogRow(
                                movement: e.value,
                                data:     data,
                                isLast:   e.key == list.length - 1,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
                context, m, widget.data,
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
                  style: AppFonts.monoStyle(size: 15, color: t.border),
                ),
                TextSpan(
                  text:  '$fromName → ${to?.name ?? '—'}',
                  style: AppFonts.monoStyle(size: 15, color: t.text2),
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
                  style: AppFonts.monoStyle(size: 15, color: t.border, weight: FontWeight.w600),
                ),
                TextSpan(
                  text: m.remark!,
                  style: AppFonts.monoStyle(size: 15, color: t.border, weight: FontWeight.w600),
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
  BuildContext      context,
  MovementModel     movement,
  AppDataProvider   data, {
  bool supplierOnly = false,
}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _EditSheet(
        movement:     movement,
        data:         data,
        supplierOnly: supplierOnly,
    ),
  );
}

class _EditSheet extends StatefulWidget {
  final MovementModel   movement;
  final AppDataProvider data;
  final bool            supplierOnly;
  const _EditSheet({
    required this.movement,
    required this.data,
    this.supplierOnly = false,
  });

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _baleNoCtrl;
  late final TextEditingController _remarkCtrl;
  final _formKey = GlobalKey<FormState>();
  LocationModel? _fromLoc;
  LocationModel? _toLoc;
  ItemModel?     _selectedItem;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.movement;
    _qtyCtrl    = TextEditingController(
        text: m.quantity == m.quantity.truncateToDouble()
            ? m.quantity.toInt().toString()
            : m.quantity.toStringAsFixed(1));
            
    _baleNoCtrl = TextEditingController(text: m.baleNo ?? '');
    _remarkCtrl = TextEditingController(text: m.remark ?? '');
    _fromLoc      = widget.data.getLocationById(m.fromLocationId);
    _toLoc        = widget.data.getLocationById(m.toLocationId);
    _selectedItem = widget.data.getItemById(m.itemId);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedItem == null) { showError(context, 'Select an item');         return; }
    if (_fromLoc == null)      { showError(context, 'Select From location');   return; }
    if (_toLoc   == null)      { showError(context, 'Select To location');     return; }
    if (_fromLoc!.id == _toLoc!.id) {
      showError(context, 'From and To cannot be the same');
      return;
    }

    setState(() => _isSaving = true);

    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;

    // Stock validation
    if (_fromLoc!.id != 'SUPPLIER') {
      final stockList  = widget.data.getStock();
      final stockEntry = stockList.where((s) =>
          s.item.id     == _selectedItem!.id &&
          s.location.id == _fromLoc!.id,
      ).toList();
      final currentBalance = stockEntry.isEmpty ? 0.0 : stockEntry.first.balance;
      // If item or from-location changed, no original qty to add back
      final sameItem = _selectedItem!.id == widget.movement.itemId;
      final sameFrom = _fromLoc!.id == widget.movement.fromLocationId;
      final originalQty = (sameItem && sameFrom) ? widget.movement.quantity : 0.0;
      final available = currentBalance + originalQty;

      if (qty > available) {
        showError(
          context,
          'Not enough stock. Available: '
          '${available % 1 == 0 ? available.toInt() : available.toStringAsFixed(1)} '
          '${_selectedItem!.unit} in ${_fromLoc!.name}',
        );
        setState(() => _isSaving = false);
        return;
      }
    }

    final ok = await widget.data.editMovement(
      movementId:     widget.movement.id,
      itemId:         _selectedItem!.id,
      quantity:       qty,
      fromLocationId: _fromLoc!.id,
      toLocationId:   _toLoc!.id,
      baleNo:         _baleNoCtrl.text.trim().isEmpty
          ? null
          : _baleNoCtrl.text.trim(),
      remark:         _remarkCtrl.text.trim().isEmpty
          ? null
          : _remarkCtrl.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      showSuccess(context, 'Movement updated');
      Navigator.of(context).pop();
    } else {
      showError(context, 'Failed to update. Try again.');
    }
  }

  @override
 Widget build(BuildContext context) {
    final t         = context.appTheme;
    final bot       = MediaQuery.of(context).viewInsets.bottom;
    final locations = widget.data.locations;
    final items     = widget.data.items;

    // Re-resolve from live list by ID on every build.
    // After realtime sync, list rebuilds with new object instances.
    // Dropdown compares by == (object identity) — stale reference = crash.
    final itemId = _selectedItem?.id;
    final fromId = _fromLoc?.id;
    final toId   = _toLoc?.id;
    if (itemId != null) {
      final fresh = items.firstWhere(
        (i) => i.id == itemId, orElse: () => _selectedItem!);
      if (!identical(fresh, _selectedItem)) _selectedItem = fresh;
    }
    if (fromId != null) {
      final fresh = locations.firstWhere(
        (l) => l.id == fromId, orElse: () => _fromLoc!);
      if (!identical(fresh, _fromLoc)) _fromLoc = fresh;
    }
    if (toId != null) {
      final fresh = locations.firstWhere(
        (l) => l.id == toId, orElse: () => _toLoc!);
      if (!identical(fresh, _toLoc)) _toLoc = fresh;
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
          child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // Handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: t.border,
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
            const SizedBox(height: AppSpacing.md),

            // Item selector
            DropdownButtonFormField<ItemModel>(
              initialValue:         _selectedItem,
              dropdownColor: t.surface,
              style:         AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:  'Item',
                prefixIcon: Icon(Icons.inventory_2_outlined, size: 18, color: t.text3),
              ),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
              items: items.map((i) => DropdownMenuItem(
                value: i,
                child: Text(i.name, style: AppFonts.body(color: t.text)),
              )).toList(),
              onChanged: (v) => setState(() => _selectedItem = v),
              validator: (_) => _selectedItem == null ? 'Select an item' : null,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Quantity
            TextFormField(
              controller:   _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppFonts.monoStyle(size: 16, color: t.text, weight: FontWeight.w600),
              decoration: InputDecoration(
                labelText:  'Quantity',
                prefixIcon: Icon(Icons.scale_outlined, size: 18, color: t.text3),
                suffix: _selectedItem != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(_selectedItem!.unit,
                            style: AppFonts.monoStyle(size: 11, color: t.primary)),
                      )
                    : null,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                final qty = double.tryParse(v.trim());
                if (qty == null || qty <= 0) return 'Must be greater than 0';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // From location
           // From location — locked for supplier movements
            if (widget.supplierOnly)
              _LockedField(
                label: 'From',
                value: 'Supplier',
                icon:  Icons.local_shipping_outlined,
                t:     t,
              )
            else
              DropdownButtonFormField<LocationModel>(
                initialValue: locations.any((l) => l.id == _fromLoc?.id) ? _fromLoc : null,
                dropdownColor: t.surface,
                style:         AppFonts.body(color: t.text),
                decoration: InputDecoration(
                  labelText:  'From',
                  prefixIcon: Icon(Icons.output_rounded, size: 18, color: t.text3),
                ),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
                items: locations
                    .where((l) => _toLoc == null || l.id != _toLoc!.id)
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
                validator: (_) => _fromLoc == null ? 'Required' : null,
              ),
            const SizedBox(height: AppSpacing.sm),

            // To location — locked for supplier movements
            if (widget.supplierOnly)
              _LockedField(
                label: 'To',
                value: _toLoc?.name ?? '—',
                icon:  Icons.warehouse_outlined,
                t:     t,
              )
            else
              DropdownButtonFormField<LocationModel>(
                initialValue: locations.any((l) => l.id == _toLoc?.id) ? _toLoc : null,
                dropdownColor: t.surface,
                style:         AppFonts.body(color: t.text),
                decoration: InputDecoration(
                  labelText:  'To',
                  prefixIcon: Icon(Icons.input_rounded, size: 18, color: t.text3),
                ),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
                items: locations
                    .where((l) => _fromLoc == null || l.id != _fromLoc!.id)
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
           // Bale No — SUPPLIER arrivals only for editing
            if (widget.movement.fromLocationId == 'SUPPLIER') ...[
              TextFormField(
                controller:  _baleNoCtrl,
                maxLines:    1,
                style:       AppFonts.body(color: t.text),
                decoration:  InputDecoration(
                  labelText:  'Bale No / LR No (optional)',
                  prefixIcon: Icon(Icons.tag_rounded,
                      size: 18, color: t.text3),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            // Remark
            TextFormField(
              controller: _remarkCtrl,
              maxLines:   2,
              maxLength:  150,
              style:      AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:    'Remark (optional)',
                prefixIcon:   Padding(
                  padding: const EdgeInsets.only(bottom: 26),
                  child: Icon(Icons.notes_rounded, size: 18, color: t.text3),
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