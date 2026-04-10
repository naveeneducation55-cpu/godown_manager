// ─────────────────────────────────────────────────────────────────────────────
// items_screen.dart
//
// From inventory_app_spec.md — Phase 7: Manage Items
//
// What this screen does:
//   • Shows a list of all items with their name and unit
//   • Add button opens a bottom sheet to create a new item
//   • Edit button on each row opens the same sheet pre-filled
//   • Delete does a soft delete (is_deleted = true) — item stays in DB
//     but disappears from the list
//   • Search bar at top filters the list as user types
//
// Fields per item (from spec section 5 Items Table):
//   item_name  — text, required
//   unit       — chosen from a fixed list (kg/pcs/litre/ton/dozen/gram/box)
//   is_deleted — soft delete flag
//   created_at / updated_at — set automatically
//
// Design from ui-design-spec.md:
//   • Card style rows with 1px border, 12px radius
//   • Primary blue add button
//   • Danger red delete button
//   • Label 12/500, Body 14/400
//   • Error messages in red 12px
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';

// ── Temp model (replaced by DB in Phase 2) ────────────────────────────────────
class _Item {
  final int    id;
  String       name;
  String       unit;
  bool         isDeleted;
  final DateTime createdAt;
  DateTime     updatedAt;

  _Item({
    required this.id,
    required this.name,
    required this.unit,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
  });
}

// ── Supported units (from spec + real warehouse usage) ────────────────────────
const _units = [
  'kg',
  'gram',
  'ton',
  'litre',
  'ml',
  'pcs',
  'dozen',
  'box',
  'bag',
  'bundle',
];

// ── Screen ────────────────────────────────────────────────────────────────────
class ItemsScreen extends StatefulWidget {
  const ItemsScreen({super.key});
  @override
  State<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends State<ItemsScreen> {

  // Sample items — replaced by DB in Phase 2
  final List<_Item> _items = [
    _Item(id: 1, name: 'Rice',         unit: 'kg',    createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 2, name: 'Sugar',        unit: 'kg',    createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 3, name: 'Wheat flour',  unit: 'kg',    createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 4, name: 'Mustard oil',  unit: 'litre', createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 5, name: 'Dal',          unit: 'kg',    createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 6, name: 'Salt',         unit: 'kg',    createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 7, name: 'Ghee',         unit: 'kg',    createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 8, name: 'Biscuits',     unit: 'pcs',   createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 9, name: 'Water bottle', unit: 'pcs',   createdAt: DateTime.now(), updatedAt: DateTime.now()),
    _Item(id: 10,name: 'Diesel',       unit: 'litre', createdAt: DateTime.now(), updatedAt: DateTime.now()),
  ];

  // Search query
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // Next ID counter (DB handles this in Phase 2)
  int _nextId = 11;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Filtered list ─────────────────────────────────────────────────────────
  // Only shows non-deleted items that match the search query
  List<_Item> get _filtered {
    final q = _searchQuery.toLowerCase().trim();
    return _items
        .where((i) =>
            !i.isDeleted &&
            (q.isEmpty || i.name.toLowerCase().contains(q)))
        .toList();
  }

  // ── Add ───────────────────────────────────────────────────────────────────
  void _openAddSheet() {
    _showItemSheet(
      context:  context,
      existing: null, // null = add mode
      onSave: (name, unit) {
        setState(() {
          _items.add(_Item(
            id:        _nextId++,
            name:      name,
            unit:      unit,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
        });
        showSuccess(context, '$name added successfully');
      },
    );
  }

  // ── Edit ──────────────────────────────────────────────────────────────────
  void _openEditSheet(_Item item) {
    _showItemSheet(
      context:  context,
      existing: item, // non-null = edit mode
      onSave: (name, unit) {
        setState(() {
          item.name      = name;
          item.unit      = unit;
          item.updatedAt = DateTime.now().toUtc();
        });
        showSuccess(context, '$name updated');
      },
    );
  }

  // ── Delete (soft) ─────────────────────────────────────────────────────────
  Future<void> _deleteItem(_Item item) async {
    final confirmed = await showDeleteConfirm(context, item.name);
    if (!confirmed) return;
    setState(() {
      item.isDeleted = true;
      item.updatedAt = DateTime.now().toUtc();
    });
    if (!mounted) return;
    showSuccess(context, '${item.name} deleted');
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t        = context.appTheme;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        leading: const AppBackButton(),
        title: Text(
          'Manage Items',
          style: AppFonts.heading(color: t.text).copyWith(fontSize: 16),
        ),
        // Item count badge in top right
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:        t.primary.withValues(alpha:0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                ),
                child: Text(
                  '${filtered.length} items',
                  style: AppFonts.monoStyle(size: 11, color: t.primary),
                ),
              ),
            ),
          ),
        ],
      ),

      // ── Floating Add button ───────────────────────────────────────────────
      // Spec: "Large clickable areas", primary blue button
      floatingActionButton: FloatingActionButton.extended(
        onPressed:       _openAddSheet,
        backgroundColor: t.primary,
        foregroundColor: t.primaryFg,
        elevation:       0,
        icon:            const Icon(Icons.add_rounded, size: 20),
        label: Text(
          'Add Item',
          style: TextStyle(
            fontFamily:  AppFonts.sans,
            fontSize:    14,
            fontWeight:  FontWeight.w600,
            color:       t.primaryFg,
          ),
        ),
      ),

      body: SafeArea(
        child: Column(
          children: [

            // ── Search bar ─────────────────────────────────────────────────
            Padding(
              padding: AppSizes.pagePadding(context).copyWith(bottom: 8),
              child: TextField(
                controller:  _searchCtrl,
                onChanged:   (v) => setState(() => _searchQuery = v),
                style:       AppFonts.body(color: t.text),
                decoration: InputDecoration(
                  hintText:    'Search items...',
                  prefixIcon:  Icon(Icons.search_rounded, size: 18, color: t.text3),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon:    Icon(Icons.close_rounded, size: 16, color: t.text3),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical:   AppSpacing.sm,
                  ),
                ),
              ),
            ),

            // ── List ───────────────────────────────────────────────────────
            Expanded(
              child: filtered.isEmpty
                  ? EmptyState(
                      icon:        Icons.inventory_2_outlined,
                      message:     _searchQuery.isEmpty
                          ? 'No items yet.\nTap + Add Item to create one.'
                          : 'No items match "$_searchQuery"',
                      actionLabel: _searchQuery.isEmpty ? 'Add Item' : null,
                      onAction:    _searchQuery.isEmpty ? _openAddSheet : null,
                    )
                  : ListView.separated(
                      padding: AppSizes.pagePadding(context).copyWith(
                        bottom: 100, // space above FAB
                      ),
                      itemCount:      filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (_, i) =>
                          _ItemRow(
                            item:     filtered[i],
                            onEdit:   () => _openEditSheet(filtered[i]),
                            onDelete: () => _deleteItem(filtered[i]),
                          ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ItemRow
//
// Single item card in the list.
// Shows: item name, unit pill, created date, edit + delete buttons
// Spec: Card — surface bg, 1px border, 12px radius, 12px padding
// ─────────────────────────────────────────────────────────────────────────────
class _ItemRow extends StatelessWidget {
  final _Item        item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ItemRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Row(
        children: [

          // Item icon circle
          Container(
            width:  40,
            height: 40,
            decoration: BoxDecoration(
              color:        t.primary.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Center(
              child: Text(
                // First letter of item name as avatar
                item.name[0].toUpperCase(),
                style: AppFonts.monoStyle(
                  size:   16,
                  color:  t.primary,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),

          const SizedBox(width: AppSpacing.md),

          // Name + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Item name
                Text(
                  item.name,
                  style: TextStyle(
                    fontFamily:  AppFonts.sans,
                    fontSize:    14,
                    fontWeight:  FontWeight.w600,
                    color:       t.text,
                  ),
                ),
                const SizedBox(height: 3),
                // Unit pill + created date
                Row(
                  children: [
                    // Unit pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color:        t.primary.withValues(alpha:0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.unit,
                        style: AppFonts.monoStyle(
                          size: 11, color: t.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Created date
                    Text(
                      _formatDate(item.createdAt),
                      style: AppFonts.monoStyle(size: 10, color: t.text3),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Action buttons ───────────────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Edit — secondary outlined
              ActionButton(
                label: 'edit',
                icon:  Icons.edit_outlined,
                onTap: onEdit,
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              // Delete — danger red
              ActionButton(
                label:  'delete',
                icon:   Icons.delete_outline_rounded,
                onTap:  onDelete,
                danger: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Formats "18 Mar 2026"
  String _formatDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _showItemSheet
//
// Bottom sheet used for BOTH add and edit.
// Add mode  — existing is null, sheet title = "Add Item"
// Edit mode — existing is non-null, fields pre-filled, title = "Edit Item"
//
// Fields:
//   item_name — text input, required
//   unit      — dropdown from fixed list, required
// ─────────────────────────────────────────────────────────────────────────────
void _showItemSheet({
  required BuildContext              context,
  required _Item?                    existing,
  required void Function(String name, String unit) onSave,
}) {
  showModalBottomSheet(
    context:       context,
    isScrollControlled: true, // lets sheet resize when keyboard opens
    backgroundColor: Colors.transparent,
    builder: (_) => _ItemSheet(existing: existing, onSave: onSave),
  );
}

class _ItemSheet extends StatefulWidget {
  final _Item?   existing;
  final void Function(String name, String unit) onSave;

  const _ItemSheet({required this.existing, required this.onSave});

  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {

  final _nameCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  String? _selectedUnit;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    // Pre-fill fields when editing
    if (_isEdit) {
      _nameCtrl.text  = widget.existing!.name;
      _selectedUnit   = widget.existing!.unit;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedUnit == null) {
      showError(context, 'Please select a unit');
      return;
    }
    widget.onSave(
      _nameCtrl.text.trim(),
      _selectedUnit!,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    // viewInsets.bottom pushes sheet up when keyboard opens
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
        ),
        border: Border.all(color: t.border, width: 0.8),
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg + bottomPad,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Sheet handle ──────────────────────────────────────────────
            Center(
              child: Container(
                width:  40,
                height: 4,
                decoration: BoxDecoration(
                  color:        t.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Title row ─────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  _isEdit ? 'Edit Item' : 'Add Item',
                  style: AppFonts.heading(color: t.text),
                ),
                const Spacer(),
                // Close button
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Icon(
                    Icons.close_rounded, size: 20, color: t.text3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Item name ─────────────────────────────────────────────────
            TextFormField(
              controller:      _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style:           AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:  'Item name',
                hintText:   'e.g. Rice, Sugar, Diesel...',
                prefixIcon: Icon(
                  Icons.inventory_2_outlined, size: 18, color: t.text3,
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Item name is required';
                }
                if (v.trim().length < 2) {
                  return 'Name must be at least 2 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),

            // ── Unit ──────────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              initialValue:         _selectedUnit,
              dropdownColor: t.surface,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded, color: t.text3,
              ),
              style: AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:  'Unit',
                hintText:   'Select unit',
                prefixIcon: Icon(
                  Icons.scale_outlined, size: 18, color: t.text3,
                ),
              ),
              items: _units.map((u) {
                return DropdownMenuItem(
                  value: u,
                  child: Row(
                    children: [
                      Text(u, style: AppFonts.monoStyle(
                        size: 13, color: t.text,
                      )),
                      const SizedBox(width: 8),
                      Text(
                        _unitDescription(u),
                        style: AppFonts.label(color: t.text3),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _selectedUnit = v),
              validator: (_) =>
                  _selectedUnit == null ? 'Please select a unit' : null,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Save button ───────────────────────────────────────────────
            PrimaryButton(
              label: _isEdit ? 'Update Item' : 'Add Item',
              icon:  _isEdit ? Icons.check_rounded : Icons.add_rounded,
              onTap: _submit,
            ),

            // Delete option shown only in edit mode
            if (_isEdit) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop(); // close sheet first
                  // Let the parent handle the delete confirm dialog
                },
                child: Text(
                  'Delete this item',
                  style: AppFonts.label(color: t.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Human-readable description for each unit
  String _unitDescription(String unit) {
    switch (unit) {
      case 'kg':     return 'kilogram';
      case 'gram':   return 'gram';
      case 'ton':    return 'metric ton';
      case 'litre':  return 'litre';
      case 'ml':     return 'millilitre';
      case 'pcs':    return 'pieces';
      case 'dozen':  return '12 pieces';
      case 'box':    return 'box';
      case 'bag':    return 'bag';
      case 'bundle': return 'bundle';
      default:       return '';
    }
  }
}