import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';

class AddMovementScreen extends StatefulWidget {
  const AddMovementScreen({super.key});
  @override
  State<AddMovementScreen> createState() => _AddMovementScreenState();
}

class _AddMovementScreenState extends State<AddMovementScreen> {

  ItemModel?     _selectedItem;
  LocationModel? _selectedFrom;
  LocationModel? _selectedTo;
  bool           _isSaving = false;

  final _qtyCtrl    = TextEditingController();
  final _itemCtrl   = TextEditingController();
  final _remarkCtrl = TextEditingController();
  final _formKey    = GlobalKey<FormState>();

  List<ItemModel> _visibleItems = [];
  bool            _showItemList = false;
  final _itemFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _qtyCtrl.addListener(() => setState(() {}));
    _itemFocus.addListener(() {
      if (!_itemFocus.hasFocus && mounted) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) setState(() => _showItemList = false);
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Load items from provider
    final allItems = context.read<AppDataProvider>().items;
    _visibleItems = allItems.take(5).toList();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _itemCtrl.dispose();
    _remarkCtrl.dispose();
    _itemFocus.dispose();
    super.dispose();
  }

  void _onItemType(String query) {
    final allItems = context.read<AppDataProvider>().items;
    final q = query.toLowerCase().trim();
    setState(() {
      _selectedItem = null;
      _visibleItems = q.isEmpty
          ? allItems.take(5).toList()
          : allItems.where((i) => i.name.toLowerCase().contains(q)).toList();
      _showItemList = true;
    });
  }

  void _selectItem(ItemModel item) {
    setState(() {
      _selectedItem = item;
      _itemCtrl.text = item.name;
      _showItemList  = false;
    });
    _itemFocus.unfocus();
  }

  void _clearItem() {
    final allItems = context.read<AppDataProvider>().items;
    setState(() {
      _selectedItem = null;
      _visibleItems = allItems.take(5).toList();
    });
    _itemCtrl.clear();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFrom == null) { showError(context, 'Please select a From location'); return; }
    if (_selectedTo   == null) { showError(context, 'Please select a To location');   return; }
    if (_selectedFrom!.id == _selectedTo!.id) {
      showError(context, 'From and To cannot be the same location');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final data    = context.read<AppDataProvider>();
      final staffId = data.currentStaff?.id ?? 1; // fallback to first staff if not logged in

      data.addMovement(
        itemId:         _selectedItem!.id,
        fromLocationId: _selectedFrom!.id,
        toLocationId:   _selectedTo!.id,
        quantity:       double.parse(_qtyCtrl.text.trim()),
        staffId:        staffId,
        remark:         _remarkCtrl.text.trim().isEmpty ? null : _remarkCtrl.text.trim(),
      );

      if (!mounted) return;
      showSuccess(
        context,
        '${_selectedItem!.name}  ${_qtyCtrl.text.trim()} ${_selectedItem!.unit}'
        '  ·  ${_selectedFrom!.name} → ${_selectedTo!.name}',
      );
      _clearForm();
    } catch (e) {
      if (!mounted) return;
      showError(context, 'Failed to save. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _clearForm() {
    _clearItem();
    _qtyCtrl.clear();
    _remarkCtrl.clear();
    setState(() { _selectedFrom = null; _selectedTo = null; });
  }

  bool get _canSave =>
      _selectedItem != null &&
      _qtyCtrl.text.trim().isNotEmpty &&
      _selectedFrom != null &&
      _selectedTo   != null;

  String _timeNow() {
    final n = DateTime.now();
    final h = n.hour % 12 == 0 ? 12 : n.hour % 12;
    final m = n.minute.toString().padLeft(2, '0');
    return '$h:$m ${n.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final t    = context.appTheme;
    // Watch provider so dropdowns update if items/locations change
    final data = context.watch<AppDataProvider>();

    return GestureDetector(
      onTap: () { _itemFocus.unfocus(); setState(() => _showItemList = false); },
      child: Scaffold(
        backgroundColor: t.bg,
        appBar: AppBar(
          backgroundColor: t.surface,
          leading: const AppBackButton(),
          title: Text('Add Movement', style: AppFonts.heading(color: t.text).copyWith(fontSize: 16)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(child: Text(_timeNow(), style: AppFonts.monoStyle(size: 11, color: t.text3))),
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
                  _buildItemField(t, data.items),
                  const SizedBox(height: AppSpacing.sm + 2),
                  _buildQtyField(t),
                  const SizedBox(height: AppSpacing.xl),

                  const SectionLabel('Movement route'),
                  _buildLocationDropdown(
                    t: t, label: 'From', hint: 'Select From location',
                    icon: Icons.output_rounded, value: _selectedFrom,
                    locations: data.locations, exclude: _selectedTo,
                    onChanged: (v) => setState(() => _selectedFrom = v),
                    validator: (_) => _selectedFrom == null ? 'From location is required' : null,
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  Center(
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: t.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Icon(Icons.arrow_downward_rounded, size: 16, color: t.primary),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  _buildLocationDropdown(
                    t: t, label: 'To', hint: 'Select To location',
                    icon: Icons.input_rounded, value: _selectedTo,
                    locations: data.locations, exclude: _selectedFrom,
                    onChanged: (v) => setState(() => _selectedTo = v),
                    validator: (_) => _selectedTo == null ? 'To location is required' : null,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Preview
                  if (_canSave)
                    _buildPreview(t),

                  // Remark
                  const SectionLabel('Remark'),
                  TextFormField(
                    controller: _remarkCtrl,
                    maxLines: 3, maxLength: 200,
                    style: AppFonts.body(color: t.text),
                    decoration: InputDecoration(
                      hintText: 'Optional — e.g. damaged goods, urgent transfer...',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(bottom: 40),
                        child: Icon(Icons.notes_rounded, size: 18, color: t.text3),
                      ),
                      counterStyle: AppFonts.label(color: t.text3),
                      alignLabelWithHint: true,
                    ),
                  ),

                  const SizedBox(height: AppSpacing.md),
                  _SaveButton(canSave: _canSave, isSaving: _isSaving, onTap: _handleSave),
                  TextButton(
                    onPressed: _clearForm,
                    child: Text('Clear form', style: AppFonts.label(color: t.text3)),
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

  Widget _buildItemField(AppThemeExtension t, List<ItemModel> allItems) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _itemCtrl, focusNode: _itemFocus,
          onChanged: _onItemType,
          onTap: () { setState(() => _showItemList = true); },
          style: AppFonts.body(color: t.text),
          decoration: InputDecoration(
            labelText: 'Item', hintText: 'Tap to see items or type to search...',
            prefixIcon: Icon(Icons.inventory_2_outlined, size: 18,
                color: _selectedItem != null ? t.primary : t.text3),
            suffix: _selectedItem != null
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: t.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(_selectedItem!.unit,
                          style: AppFonts.monoStyle(size: 11, color: t.primary)),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: _clearItem,
                      child: Icon(Icons.close_rounded, size: 18, color: t.text3),
                    ),
                    const SizedBox(width: 2),
                  ])
                : null,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              borderSide: BorderSide(
                color: _selectedItem != null ? t.primary : t.border,
                width: _selectedItem != null ? 1.5 : 0.8,
              ),
            ),
          ),
          validator: (_) => _selectedItem == null ? 'Please select an item' : null,
        ),
        if (_showItemList)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(color: t.border, width: 0.8),
              boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(t.isDark ? 0.35 : 0.07),
                blurRadius: 10, offset: const Offset(0, 4),
              )],
            ),
            child: _visibleItems.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text('No items match "${_itemCtrl.text}"',
                        style: AppFonts.label(color: t.text3), textAlign: TextAlign.center),
                  )
                : Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
                      child: Row(children: [
                        Text(
                          _itemCtrl.text.isEmpty
                              ? 'Showing first 5 items'
                              : '${_visibleItems.length} result${_visibleItems.length == 1 ? '' : 's'}',
                          style: AppFonts.labelStyle(color: t.text3),
                        ),
                      ]),
                    ),
                    Divider(height: 0, color: t.border),
                    ..._visibleItems.map((item) => InkWell(
                      onTap: () => _selectItem(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(
                            color: item == _visibleItems.last
                                ? Colors.transparent : t.border,
                            width: 0.6,
                          )),
                        ),
                        child: Row(children: [
                          Expanded(child: Text(item.name, style: AppFonts.body(color: t.text))),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(item.unit,
                                style: AppFonts.monoStyle(size: 11, color: t.primary)),
                          ),
                        ]),
                      ),
                    )),
                  ]),
          ),
      ],
    );
  }

  Widget _buildQtyField(AppThemeExtension t) {
    return TextFormField(
      controller: _qtyCtrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
      style: AppFonts.monoStyle(size: 17, color: t.text, weight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: 'Quantity', hintText: '0',
        prefixIcon: Icon(Icons.scale_outlined, size: 18, color: t.text3),
        suffix: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _selectedItem != null
                ? t.primary.withOpacity(0.1) : t.border.withOpacity(0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            _selectedItem?.unit ?? '—',
            style: AppFonts.monoStyle(
              size: 12, color: _selectedItem != null ? t.primary : t.text3,
            ),
          ),
        ),
      ),
      validator: (val) {
        if (val == null || val.trim().isEmpty) return 'Quantity is required';
        final qty = double.tryParse(val.trim());
        if (qty == null || qty <= 0) return 'Must be greater than 0';
        return null;
      },
    );
  }

  Widget _buildLocationDropdown({
    required AppThemeExtension t,
    required String label, required String hint, required IconData icon,
    required LocationModel? value, required List<LocationModel> locations,
    required LocationModel? exclude,
    required ValueChanged<LocationModel?> onChanged,
    required String? Function(LocationModel?) validator,
  }) {
    final available = locations.where((l) => exclude == null || l.id != exclude.id).toList();
    final safeValue = available.any((l) => l.id == value?.id) ? value : null;

    return DropdownButtonFormField<LocationModel>(
      value: safeValue, validator: validator,
      decoration: InputDecoration(labelText: label, hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: t.text3)),
      dropdownColor: t.surface,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
      style: AppFonts.body(color: t.text),
      items: available.map((loc) => DropdownMenuItem(
        value: loc,
        child: Row(children: [
          Icon(loc.type == 'shop'
              ? Icons.storefront_outlined : Icons.warehouse_outlined,
              size: 15, color: t.text3),
          const SizedBox(width: 8),
          Text(loc.name, style: AppFonts.body(color: t.text)),
          const SizedBox(width: 6),
          Text(loc.type, style: AppFonts.label(color: t.text3)),
        ]),
      )).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildPreview(AppThemeExtension t) {
    final qty = _qtyCtrl.text.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: t.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: t.primary.withOpacity(0.18), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PREVIEW', style: AppFonts.labelStyle(color: t.primary.withOpacity(0.6))),
          const SizedBox(height: 6),
          Row(children: [
            Text(_selectedItem!.name,
                style: AppFonts.monoStyle(size: 14, color: t.text, weight: FontWeight.w700)),
            const SizedBox(width: 10),
            Text('$qty ${_selectedItem!.unit}',
                style: AppFonts.monoStyle(size: 14, color: t.primary)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.circle, size: 5, color: t.text3),
            const SizedBox(width: 6),
            Text(_selectedFrom!.name, style: AppFonts.monoStyle(size: 12, color: t.text2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded, size: 13, color: t.text3),
            ),
            Text(_selectedTo!.name, style: AppFonts.monoStyle(size: 12, color: t.text2)),
          ]),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool canSave, isSaving;
  final VoidCallback onTap;
  const _SaveButton({required this.canSave, required this.isSaving, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t  = context.appTheme;
    final bg = canSave ? t.primary : t.border;
    final fg = canSave ? t.primaryFg : t.text3;
    return SizedBox(
      width: double.infinity, height: 50,
      child: ElevatedButton(
        onPressed: (!canSave || isSaving) ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg, foregroundColor: fg,
          disabledBackgroundColor: t.border, disabledForegroundColor: t.text3,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radius)),
        ),
        child: isSaving
            ? SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: fg))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(canSave ? Icons.check_rounded : Icons.lock_outline_rounded, size: 16),
                const SizedBox(width: 8),
                Text('Save Movement', style: TextStyle(
                  fontFamily: AppFonts.sans, fontSize: 14,
                  fontWeight: FontWeight.w600, color: fg,
                )),
              ]),
      ),
    );
  }
}