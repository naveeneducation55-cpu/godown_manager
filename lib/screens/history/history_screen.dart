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
        final d = DateTime(
            m.createdAt.year, m.createdAt.month, m.createdAt.day);
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
              id: 0, name: '', pin: '', createdAt: DateTime.now()),
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
      final d = DateTime(
          m.createdAt.year, m.createdAt.month, m.createdAt.day);
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
    const mo = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
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
                  color: t.primary.withOpacity(0.1),
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
class _LogRow extends StatelessWidget {
  final MovementModel   movement;
  final AppDataProvider data;
  final bool            isLast;

  const _LogRow({
    required this.movement,
    required this.data,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final m = movement;

    // Resolve names safely
    final item  = data.getItemById(m.itemId);
    final from  = data.getLocationById(m.fromLocationId);
    final to    = data.getLocationById(m.toLocationId);
    final staff = data.staff.firstWhere(
      (s) => s.id == m.staffId,
      orElse: () => StaffModel(
          id: 0, name: 'Unknown', pin: '', createdAt: DateTime.now()),
    );
    final editedByStaff = m.editedBy != null
        ? data.staff.firstWhere(
            (s) => s.id == m.editedBy,
            orElse: () => StaffModel(
                id: 0, name: 'Unknown', pin: '',
                createdAt: DateTime.now()),
          )
        : null;

    // Quantity display
    final qty = m.quantity == m.quantity.truncateToDouble()
        ? m.quantity.toInt().toString()
        : m.quantity.toStringAsFixed(1);

    // From label — -1 means external supplier
    final fromName = m.fromLocationId == -1
        ? 'Supplier'
        : (from?.name ?? '—');

    // Supplier movements (-1) cannot be edited — no route to change
    final canEdit = m.fromLocationId != -1;

    return GestureDetector(
      onTap: canEdit
          ? () => _showEditSheet(context, m, data)
          : null,
      child: Container(
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: t.border, width: 0.5))),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main log line
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text:  _fmtTime(m.createdAt),
                style: AppFonts.monoStyle(size: 12, color: t.text3),
              ),
              TextSpan(
                text:  '  ·  ',
                style: AppFonts.monoStyle(size: 12, color: t.border),
              ),
              TextSpan(
                text:  staff.name,
                style: AppFonts.monoStyle(
                    size:   12,
                    color:  t.text2,
                    weight: FontWeight.w600),
              ),
              TextSpan(
                text:  '  ·  ',
                style: AppFonts.monoStyle(size: 12, color: t.border),
              ),
              TextSpan(
                text:  '$qty ${item?.unit ?? ''}',
                style: AppFonts.monoStyle(
                    size:   13,
                    color:  t.primary,
                    weight: FontWeight.w700),
              ),
              TextSpan(
                text:  ' ${item?.name ?? '—'}',
                style: AppFonts.monoStyle(
                    size:   13,
                    color:  t.text,
                    weight: FontWeight.w700),
              ),
              TextSpan(
                text:  '  ·  ',
                style: AppFonts.monoStyle(size: 12, color: t.border),
              ),
              TextSpan(
                text:  '$fromName → ${to?.name ?? '—'}',
                style: AppFonts.monoStyle(size: 12, color: t.text2),
              ),
            ]),
            softWrap: true,
          ),

          // Edited line
          if (m.edited) ...[
            const SizedBox(height: 4),
            Text.rich(TextSpan(children: [
              TextSpan(
                text:  '✎ ',
                style: AppFonts.monoStyle(size: 11, color: t.warnFg),
              ),
              TextSpan(
                text: editedByStaff != null
                    ? 'edited by ${editedByStaff.name}'
                    : 'edited',
                style: AppFonts.monoStyle(size: 11, color: t.warnFg),
              ),
            ])),
          ],
        ],
      ),
    ), // Container
    ); // GestureDetector
  }

  static String _fmtTime(DateTime d) {
    final h    = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min  = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }
}

// ─── Edit movement sheet ─────────────────────────────────────────────────────
void _showEditSheet(
  BuildContext      context,
  MovementModel     movement,
  AppDataProvider   data,
) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _EditSheet(movement: movement, data: data),
  );
}

class _EditSheet extends StatefulWidget {
  final MovementModel   movement;
  final AppDataProvider data;
  const _EditSheet({required this.movement, required this.data});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _remarkCtrl;
  final _formKey = GlobalKey<FormState>();
  LocationModel? _fromLoc;
  LocationModel? _toLoc;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.movement;
    _qtyCtrl    = TextEditingController(
        text: m.quantity == m.quantity.truncateToDouble()
            ? m.quantity.toInt().toString()
            : m.quantity.toStringAsFixed(1));
    _remarkCtrl = TextEditingController(text: m.remark ?? '');
    // Pre-select current from/to
    _fromLoc = widget.data.getLocationById(m.fromLocationId);
    _toLoc   = widget.data.getLocationById(m.toLocationId);
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_fromLoc == null) { showError(context, 'Select From location'); return; }
    if (_toLoc   == null) { showError(context, 'Select To location');   return; }
    if (_fromLoc!.id == _toLoc!.id) {
      showError(context, 'From and To cannot be the same');
      return;
    }

    setState(() => _isSaving = true);

    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final ok  = await widget.data.editMovement(
      movementId:     widget.movement.id,
      quantity:       qty,
      fromLocationId: _fromLoc!.id,
      toLocationId:   _toLoc!.id,
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
    final item      = widget.data.getItemById(widget.movement.itemId);

    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bot),
      child: Form(
        key: _formKey,
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

            // Title + item name (fixed — cannot change)
            Row(children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Edit Movement',
                      style: AppFonts.heading(color: t.text)),
                  const SizedBox(height: 2),
                  // Item is fixed — shown as read-only label
                  Row(children: [
                    Icon(Icons.inventory_2_outlined, size: 12, color: t.text3),
                    const SizedBox(width: 4),
                    Text(item?.name ?? '—',
                        style: AppFonts.monoStyle(size: 11, color: t.text3)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: t.warnBg,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text('item cannot change',
                          style: AppFonts.monoStyle(size: 9, color: t.warnFg)),
                    ),
                  ]),
                ],
              )),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(Icons.close_rounded, size: 20, color: t.text3),
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),

            // Quantity
            TextFormField(
              controller:   _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppFonts.monoStyle(size: 16, color: t.text, weight: FontWeight.w600),
              decoration: InputDecoration(
                labelText:  'Quantity',
                prefixIcon: Icon(Icons.scale_outlined, size: 18, color: t.text3),
                suffix: item != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: t.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(item.unit,
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
            DropdownButtonFormField<LocationModel>(
              value:         _fromLoc,
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

            // To location
            DropdownButtonFormField<LocationModel>(
              value:         _toLoc,
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
            const SizedBox(height: AppSpacing.md),

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