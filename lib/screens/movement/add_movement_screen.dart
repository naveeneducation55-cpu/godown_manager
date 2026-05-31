import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';


// State for each item line in a multi-itemj movement
class _ItemLineState {
  ItemModel?   selectedItem;
  final qtyCtrl    = TextEditingController();
  final itemCtrl   = TextEditingController();
  final baleNoCtrl = TextEditingController();
  final itemFocus  = FocusNode();
  List<ItemModel> visibleItems = [];
  bool showItemList = false;

  // Error state — set by _handleSave on validation failure
  bool   hasStockError = false;
  bool   hasBaleError  = false;
  String errorMessage  = '';

  void dispose() {
    qtyCtrl.dispose();
    itemCtrl.dispose();
    baleNoCtrl.dispose();
    itemFocus.dispose();
  }

  bool get isValid =>
      selectedItem != null &&
      (double.tryParse(qtyCtrl.text.trim()) ?? 0) > 0;
}

class AddMovementScreen extends StatefulWidget {
  const AddMovementScreen({super.key});
  @override
  State<AddMovementScreen> createState() => _AddMovementScreenState();
}

class _AddMovementScreenState extends State<AddMovementScreen> {

  // Multi-item line state
  final List<_ItemLineState> _lines = [_ItemLineState()];
  
  LocationModel? _selectedFrom;
  LocationModel? _selectedTo;
  bool           _isRestock = false;
  bool           _isSaving  = false;
  final _remarkCtrl = TextEditingController();
  final _formKey    = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _initLine(_lines.first);
  }

  
   void _initLine(_ItemLineState line) {
    line.qtyCtrl.addListener(() => setState(() {}));
    line.itemFocus.addListener(() {
      if (!line.itemFocus.hasFocus && mounted) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => line.showItemList = false);
        });
      }
    });
    final items = context.read<AppDataProvider>().items;
    line.visibleItems = items.take(5).toList();
  }

  @override
  void dispose() {
    for (final line in _lines) line.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }


  // ── Save ─────────────────────────────────────────────────────────────────────
  Future<void> _handleSave() async {
    // Clear all previous error states before re-validating
    for (final line in _lines) {
      line.hasStockError = false;
      line.hasBaleError  = false;
      line.errorMessage  = '';
    }
    setState(() {});

    // Validate form
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Guard: item must be selected
    // Validate all lines
    for (int i = 0; i < _lines.length; i++) {
      final line = _lines[i];
      if (line.selectedItem == null) {
        showError(context, 'Please select an item for line ${i + 1}');
        return;
      }
      final qty = double.tryParse(line.qtyCtrl.text.trim());
      if (qty == null || qty <= 0) {
        showError(context, 'Enter valid quantity for line ${i + 1}');
        return;
      }
    }
    // EC3 — duplicate item check
    final selectedIds = _lines.map((l) => l.selectedItem!.id).toList();
    if (selectedIds.toSet().length != selectedIds.length) {
      showError(context, 'Same item appears more than once. Combine quantities instead.');
      return;
    }
    if (_selectedFrom == null && !_isRestock) {
      showError(context, 'Please select a From location');
      return;
    }
    if (_selectedTo == null) {
      showError(context, 'Please select a To location');
      return;
    }
    if (!_isRestock && _selectedFrom!.id == _selectedTo!.id) {
      showError(context, 'From and To cannot be the same location');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final data    = context.read<AppDataProvider>();
      final String staffId = data.currentStaff?.id ??
    (data.staff.isNotEmpty ? data.staff.first.id : '');

      bool ok;
    if (_lines.length == 1) {
      // Single item — use existing addMovement
      final line = _lines.first;
      final qty = double.tryParse(line.qtyCtrl.text.trim()) ?? 0;
      ok = await data.addMovement(
        itemId:         line.selectedItem!.id,
        fromLocationId: _isRestock ? 'SUPPLIER' : _selectedFrom!.id,
        toLocationId:   _selectedTo!.id,
        quantity:       qty,
        staffId:        staffId,
        baleNo: line.baleNoCtrl.text.trim().isEmpty
            ? null : line.baleNoCtrl.text.trim(),
        remark: _remarkCtrl.text.trim().isEmpty
            ? null : _remarkCtrl.text.trim(),
      );
    } else {
      // Multi-item — use addMultiMovement
      ok = await data.addMultiMovement(
        fromLocationId: _isRestock ? 'SUPPLIER' : _selectedFrom!.id,
        toLocationId:   _selectedTo!.id,
        staffId:        staffId,
        itemIds:   _lines.map((l) => l.selectedItem!.id).toList(),
        quantities: _lines.map((l) =>
            double.tryParse(l.qtyCtrl.text.trim()) ?? 0).toList(),
        baleNos:   _lines.map((l) =>
            l.baleNoCtrl.text.trim().isEmpty
                ? null : l.baleNoCtrl.text.trim()).toList(),
        remark: _remarkCtrl.text.trim().isEmpty
            ? null : _remarkCtrl.text.trim(),
      );
    }

      if (!mounted) return;

       if (!ok) {
        _highlightFailingLines(data);
        setState(() => _isSaving = false);
        return;
      }

      showSuccess(context,
          '${_lines.length} item${_lines.length > 1 ? 's' : ''} '
          'added to ${_selectedTo!.name}');
      _clearForm();

    } catch (e) {
      debugPrint('addMovement error: $e');
      if (!mounted) return;
      showError(context, 'Failed to save. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _clearForm() {
    for (final line in _lines) line.dispose();
    _lines.clear();
    final newLine = _ItemLineState();
    _initLine(newLine);
    _lines.add(newLine);
    _remarkCtrl.clear();
    if (mounted) {
      setState(() {
        _selectedFrom = null;
        _selectedTo   = null;
        _isRestock    = false;
      });
    }
  }

  bool get _canSave =>
      _lines.every((l) => l.isValid) &&
      (_isRestock || _selectedFrom != null) &&
      _selectedTo != null;

  String _timeNow() {
    final n    = DateTime.now().toUtc();
    final h    = n.hour % 12 == 0 ? 12 : n.hour % 12;
    final min  = n.minute.toString().padLeft(2, '0');
    final ampm = n.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  void _highlightFailingLines(AppDataProvider data) {
  for (int i = 0; i < _lines.length; i++) {
    final line = _lines[i];
    if (line.selectedItem == null) continue;
    final fromId = _isRestock ? 'SUPPLIER' : _selectedFrom?.id ?? '';
    if (fromId == 'SUPPLIER') continue;

    final qty       = double.tryParse(line.qtyCtrl.text.trim()) ?? 0;
    final available = data.getStock()
        .where((s) =>
            s.item.id     == line.selectedItem!.id &&
            s.location.id == fromId)
        .fold(0.0, (sum, s) => sum + s.balance);

    if (qty > available) {
      line.hasStockError = true;
      line.errorMessage  =
          'Only ${available.toStringAsFixed(available.truncateToDouble() == available ? 0 : 1)}'
          ' ${line.selectedItem!.unit} available.';
    }

    final baleNo = line.baleNoCtrl.text.trim();
    if (!line.hasStockError && baleNo.isNotEmpty) {
       final baleExists = data.sortedMovements.any((m) =>
          !m.isDeleted &&
          m.itemId       == line.selectedItem!.id &&
          m.toLocationId == fromId &&
          m.baleNo       == baleNo);
      if (!baleExists) {
        line.hasBaleError = true;
        line.errorMessage = 'Bale "$baleNo" not found at this location.';
      }
    }
  }
}

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
 Widget build(BuildContext context) {
    final t    = context.appTheme;
    final data = context.watch<AppDataProvider>();

    // Re-resolve selected locations from live list on every build.
    // Realtime sync replaces LocationModel instances with new objects.
    // DropdownButton uses == (object identity) — stale ref causes assertion crash.
    final locs  = data.locations;
    
    if (_selectedFrom != null) {
      final fresh = locs.where((l) => l.id == _selectedFrom!.id).firstOrNull;
      if (fresh != null && !identical(fresh, _selectedFrom)) {
        _selectedFrom = fresh;
      } else if (fresh == null) {
        _selectedFrom = null; // location was deleted remotely
      }
    }
    if (_selectedTo != null) {
      final fresh = locs.where((l) => l.id == _selectedTo!.id).firstOrNull;
      if (fresh != null && !identical(fresh, _selectedTo)) {
        _selectedTo = fresh;
      } else if (fresh == null) {
        _selectedTo = null;
      }
    }

    return GestureDetector(
      onTap: () {
        for (final line in _lines) {
          line.itemFocus.unfocus();
          line.showItemList = false;
        }
        setState(() {});
      },
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          backgroundColor: t.surface,
          leading: const AppBackButton(),
          title: Text(
            'Add Movement',
            style: AppFonts.heading(color: t.text).copyWith(fontSize: 16),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: Text(
                  _timeNow(),
                  style: AppFonts.monoStyle(size: 11, color: t.text3),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: AppSizes.pagePadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  const SectionLabel('What moved?'),
                  ..._lines.asMap().entries.map((entry) {
                    final idx  = entry.key;
                    final line = entry.value;
                    return _buildItemLine(t, data.items, line, idx);
                  }),
                  const SizedBox(height: AppSpacing.sm),
                  // Add line button — hidden for restock (single item only)
                  if (!_isRestock)
                    TextButton.icon(
                      onPressed: () {
                        final newLine = _ItemLineState();
                        _initLine(newLine);
                        setState(() => _lines.add(newLine));
                      },
                      icon: Icon(Icons.add_rounded, size: 16, color: t.primary),
                      label: Text('Add another item',
                          style: AppFonts.body(color: t.primary)),
                    ),
                  const SizedBox(height: AppSpacing.md),

                  const SectionLabel('Movement route'),

                  // Restock toggle
                  GestureDetector(
                    onTap: () => setState(() {
                      _isRestock    = !_isRestock;
                      _selectedFrom = null;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: _isRestock
                            ? t.primary.withValues(alpha:0.08)
                            : t.surface,
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                        border: Border.all(
                          color: _isRestock
                              ? t.primary.withValues(alpha:0.4)
                              : t.border,
                          width: 0.8,
                        ),
                      ),
                      child: Row(children: [
                        Icon(
                          _isRestock
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 18,
                          color: _isRestock ? t.primary : t.text3,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('New stock arriving — add to existing item',
                                style: AppFonts.body(
                                    color: _isRestock ? t.primary : t.text)),
                            Text('Use this instead of creating a new item',
                                style: AppFonts.label(color: t.text3)),
                          ],
                        )),
                      ]),
                    ),
                  ),

                  if (!_isRestock)
                  _buildLocationField(
                    t:         t,
                    label:     'From',
                    hint:      'Select From location',
                    icon:      Icons.output_rounded,
                    value:     _selectedFrom,
                    locations: data.locations,
                    exclude:   _selectedTo,
                    excludeCustomer: true,
                    onChanged: (v) => setState(() => _selectedFrom = v),
                    validator: (_) => (!_isRestock && _selectedFrom == null)
                        ? 'From location is required' : null,
                  ),

                  const SizedBox(height: AppSpacing.sm + 2),
                  Center(
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: t.primary.withValues(alpha:0.08),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Icon(
                        Icons.arrow_downward_rounded,
                        size: 16, color: t.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _buildLocationField(
                    t:         t,
                    label:     'To',
                    hint:      'Select To location',
                    icon:      Icons.input_rounded,
                    value:     _selectedTo,
                    locations: data.locations,
                    exclude:   _selectedFrom,
                    onChanged: (v) => setState(() => _selectedTo = v),
                    validator: (_) => _selectedTo == null
                        ? 'To location is required' : null,
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  const SizedBox(height: AppSpacing.md),

                  // Remark — optional
                  const SectionLabel('Remark (optional)'),
                  TextFormField(
                    controller: _remarkCtrl,
                    maxLines:   2,
                    maxLength:  150,
                    style:      AppFonts.body(color: t.text),
                    decoration: InputDecoration(
                      hintText: 'e.g. damaged goods, urgent transfer...',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(bottom: 26),
                        child: Icon(
                          Icons.notes_rounded, size: 18, color: t.text3,
                        ),
                      ),
                      counterStyle: AppFonts.label(color: t.text3),
                      alignLabelWithHint: true,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),

                  // Save button
                  _SaveButton(
                    canSave:  _canSave,
                    isSaving: _isSaving,
                    onTap:    _handleSave,
                  ),

                  TextButton(
                    onPressed: _clearForm,
                    child: Text(
                      'Clear form',
                      style: AppFonts.label(color: t.text3),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
Widget _buildItemLine(
  AppThemeExtension t,
  List<ItemModel>   allItems,
  _ItemLineState    line,
  int               index,
) {
  final isFirst  = index == 0;
  final hasError = line.hasStockError || line.hasBaleError;
  return AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    curve:    Curves.easeOut,
    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color:        hasError
          ? t.error.withValues(alpha: 0.04)
          : t.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      border: Border.all(
        color: hasError ? t.error : t.border,
        width: hasError ? 1.5   : 0.8,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Line header
        Row(children: [
          Text('Item ${index + 1}',
              style: AppFonts.label(
                color: hasError ? t.error : t.text3,
              )),
          if (hasError) ...[
            const SizedBox(width: 6),
            Icon(Icons.warning_amber_rounded,
                size: 13, color: t.error),
          ],
          const Spacer(),
          // Remove button — only for non-first lines
          if (!isFirst)
            GestureDetector(
              onTap: () => setState(() {
                line.dispose();
                _lines.removeAt(index);
              }),
              child: Icon(Icons.close_rounded, size: 18, color: t.error),
            ),
        ]),
        const SizedBox(height: AppSpacing.sm),
        // Item search field
        _buildItemFieldForLine(t, allItems, line),
        const SizedBox(height: AppSpacing.sm),
        // Qty + Bale row
        Row(children: [
          Expanded(
            child: TextFormField(
              controller:   line.qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              style: AppFonts.monoStyle(
                  size: 15, color: t.text, weight: FontWeight.w600),
              decoration: InputDecoration(
                labelText:  'Quantity',
                hintText:   '0',
                prefixIcon: Icon(Icons.scale_outlined, size: 18, color: t.text3),
                suffix: line.selectedItem != null
                    ? Text(line.selectedItem!.unit,
                        style: AppFonts.monoStyle(size: 11, color: t.primary))
                    : null,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextFormField(
              controller: line.baleNoCtrl,
              style:      AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:  _isRestock ? 'Bale No' : 'Bale (optional)',
                hintText:   _isRestock ? '1274*2' : 'match existing',
                prefixIcon: Icon(Icons.tag_rounded, size: 18, color: t.text3),
              ),
            ),
          ),
        ]),
        // Error label — shown only when this line has an error
        if (hasError) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(children: [
            Icon(Icons.info_outline_rounded,
                size: 13, color: t.error),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                line.errorMessage.isNotEmpty
                    ? line.errorMessage
                    : line.hasBaleError
                        ? 'Bale number not found at this location.'
                        : 'Not enough stock at selected location.',
                style: AppFonts.label(color: t.error),
      ),
            ),
          ]),
        ],
      ],
    ),
  );
}

Widget _buildItemFieldForLine(
  AppThemeExtension t,
  List<ItemModel>   allItems,
  _ItemLineState    line,
) {
  return Column(
    children: [
      TextFormField(
        controller: line.itemCtrl,
        focusNode:  line.itemFocus,
        onChanged: (q) {
          final query = q.toLowerCase().trim();
          setState(() {
            line.selectedItem  = null;
            line.visibleItems  = query.isEmpty
                ? allItems.take(5).toList()
                : allItems.where((i) =>
                    i.name.toLowerCase().contains(query)).toList();
            line.showItemList  = true;
          });
        },
        onTap: () => setState(() => line.showItemList = true),
        style: AppFonts.body(color: t.text),
        decoration: InputDecoration(
          labelText:  'Item',
          hintText:   'Search...',
          prefixIcon: Icon(Icons.inventory_2_outlined,
              size: 18,
              color: line.selectedItem != null ? t.primary : t.text3),
          suffix: line.selectedItem != null
              ? GestureDetector(
                  onTap: () => setState(() {
                    line.selectedItem = null;
                    line.itemCtrl.clear();
                    line.visibleItems = allItems.take(5).toList();
                  }),
                  child: Icon(Icons.close_rounded, size: 18, color: t.text3),
                )
              : null,
        ),
      ),
      if (line.showItemList)
        Container(
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color:        t.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border:       Border.all(color: t.border, width: 0.8),
          ),
          child: Column(
            children: line.visibleItems.isEmpty
                ? [Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text('No items found',
                        style: AppFonts.label(color: t.text3)),
                  )]
                : line.visibleItems.map((item) => InkWell(
                    onTap: () => setState(() {
                      line.selectedItem = item;
                      line.itemCtrl.text = item.name;
                      line.showItemList = false;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical:   AppSpacing.sm + 2),
                      child: Row(children: [
                        Expanded(child: Text(item.name,
                            style: AppFonts.body(color: t.text))),
                        Text(item.unit,
                            style: AppFonts.monoStyle(
                                size: 11, color: t.primary)),
                      ]),
                    ),
                  )).toList(),
          ),
        ),
    ],
  );
}
  

  

  // ── Location dropdown ─────────────────────────────────────────────────────────
  Widget _buildLocationField({
    required AppThemeExtension       t,
    required String                  label,
    required String                  hint,
    required IconData                icon,
    required LocationModel?          value,
    required List<LocationModel>     locations,
    required LocationModel?          exclude,
    required ValueChanged<LocationModel?> onChanged,
    required String? Function(LocationModel?) validator,
    bool excludeCustomer = false,
  }) {
    final available = locations
        .where((l) => exclude == null || l.id != exclude.id)
        .where((l) => !excludeCustomer ||
            !l.name.toLowerCase().contains('customer'))
        .toList();
    final safeValue =
        available.any((l) => l.id == value?.id) ? value : null;

    return DropdownButtonFormField<LocationModel>(
      initialValue:     safeValue,
      validator: validator,
      decoration: InputDecoration(
        labelText:  label,
        hintText:   hint,
        prefixIcon: Icon(icon, size: 18, color: t.text3),
      ),
      dropdownColor: t.surface,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
      style: AppFonts.body(color: t.text),
      items: available.map((loc) => DropdownMenuItem(
        value: loc,
        child: Row(children: [
          Icon(
            loc.type == 'shop'
                ? Icons.storefront_outlined
                : Icons.warehouse_outlined,
            size: 15, color: t.text3,
          ),
          const SizedBox(width: 8),
          Text(loc.name, style: AppFonts.body(color: t.text)),
          const SizedBox(width: 6),
          Text(loc.type, style: AppFonts.label(color: t.text3)),
        ]),
      )).toList(),
      onChanged: onChanged,
    );
  }

}

// ─── Save button ──────────────────────────────────────────────────────────────
class _SaveButton extends StatelessWidget {
  final bool         canSave;
  final bool         isSaving;
  final VoidCallback onTap;
  const _SaveButton({
    required this.canSave,
    required this.isSaving,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t  = context.appTheme;
    final fg = canSave ? t.primaryFg : t.text3;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: (!canSave || isSaving) ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:         canSave ? t.primary : t.border,
          foregroundColor:         fg,
          disabledBackgroundColor: t.border,
          disabledForegroundColor: t.text3,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
        ),
        child: isSaving
            ? SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: fg),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    canSave
                        ? Icons.check_rounded
                        : Icons.lock_outline_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Save Movement',
                    style: TextStyle(
                      fontFamily:  AppFonts.sans,
                      fontSize:    14,
                      fontWeight:  FontWeight.w600,
                      color:       fg,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}