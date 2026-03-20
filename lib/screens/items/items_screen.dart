import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';

// Supported units
const _units = [
  'pcs','kg','gram','ton','litre','ml','dozen','box','bag','bundle',
];
String _unitDesc(String u) => const {
  'pcs':'pieces','kg':'kilogram','gram':'gram','ton':'metric ton',
  'litre':'litre','ml':'millilitre','dozen':'12 pieces',
  'box':'box','bag':'bag','bundle':'bundle',
}[u] ?? '';

// ─── Main tabbed screen ───────────────────────────────────────────────────────
class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key});
  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        leading: const AppBackButton(),
        title: Text('Manage Data',
            style: AppFonts.heading(color: t.text).copyWith(fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Container(
            color: t.surface,
            child: TabBar(
              controller:          _tabs,
              labelColor:          t.primary,
              unselectedLabelColor: t.text3,
              indicatorColor:      t.primary,
              indicatorWeight:     2,
              labelStyle: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize:   13,
                  fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  TextStyle(fontFamily: AppFonts.sans, fontSize: 13),
              tabs: const [
                Tab(text: 'Items'),
                Tab(text: 'Godowns'),
                Tab(text: 'Staff'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_ItemsTab(), _GodownsTab(), _StaffTab()],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEMS TAB
// ═══════════════════════════════════════════════════════════════════════════
class _ItemsTab extends StatefulWidget {
  const _ItemsTab();
  @override
  State<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<_ItemsTab> {
  String _search = '';
  final  _ctrl   = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _openAdd(BuildContext ctx) {
    _showItemSheet(
      context:  ctx,
      existing: null,
      onSave: (name, unit, locId, qty) =>
          ctx.read<AppDataProvider>()
              .addItem(name: name, unit: unit,
                  openingLocationId: locId, openingQty: qty),
    );
  }

  void _openEdit(BuildContext ctx, ItemModel item) {
    _showItemSheet(
      context:  ctx,
      existing: item,
      onSave: (name, unit, _, __) =>
          ctx.read<AppDataProvider>()
              .editItem(id: item.id, name: name, unit: unit),
    );
  }

  Future<void> _delete(BuildContext ctx, ItemModel item) async {
    final ok = await showDeleteConfirm(ctx, item.name);
    if (ok && ctx.mounted) {
      ctx.read<AppDataProvider>().deleteItem(item.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data     = context.watch<AppDataProvider>();
    final isAdmin = data.currentStaff?.role == 'admin';
    final filtered = data.items.where((i) => _search.isEmpty ||
        i.name.toLowerCase().contains(_search.toLowerCase())).toList();

    return Column(children: [
      _SearchBar(
        ctrl:      _ctrl,
        onChanged: (v) => setState(() => _search = v),
        onAdd:     () => _openAdd(context),
      ),
      // Role info banner
      _RoleBanner(
        isAdmin:    isAdmin,
        staffNote:  'You can add items. Only admin can edit or delete.',
      ),
      Expanded(
        child: filtered.isEmpty
            ? EmptyState(
                icon:        Icons.inventory_2_outlined,
                message:     _search.isEmpty
                    ? 'No items yet.\nTap + to add your first item.'
                    : 'No items match "$_search"',
                actionLabel: _search.isEmpty ? 'Add Item' : null,
                onAction:    _search.isEmpty ? () => _openAdd(context) : null,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _DataRow(
                  avatar:    filtered[i].name[0].toUpperCase(),
                  title:     filtered[i].name,
                  meta:      filtered[i].unit,
                  date:      filtered[i].createdAt,
                  // Edit + delete only for admin
                  showActions: isAdmin,
                  onEdit:   () => _openEdit(context, filtered[i]),
                  onDelete: () => _delete(context, filtered[i]),
                ),
              ),
      ),
    ]);
  }
}

// Item sheet — add mode has 4 fields, edit mode has 2
void _showItemSheet({
  required BuildContext context,
  required ItemModel?   existing,
  required void Function(String name, String unit, int? locId, double? qty)
      onSave,
}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _ItemSheet(existing: existing, onSave: onSave),
  );
}

class _ItemSheet extends StatefulWidget {
  final ItemModel? existing;
  final void Function(String, String, int?, double?) onSave;
  const _ItemSheet({required this.existing, required this.onSave});
  @override
  State<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends State<_ItemSheet> {
  final _nameCtrl = TextEditingController();
  final _qtyCtrl  = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  String?        _unit;
  LocationModel? _openingLoc;
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.existing!.name;
      _unit          = widget.existing!.unit;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_unit == null) {
      showError(context, 'Please select a unit');
      return;
    }

    final qty = double.tryParse(_qtyCtrl.text.trim()) ?? 0;

    // Validate opening stock consistency
    if (_qtyCtrl.text.trim().isNotEmpty && qty > 0 && _openingLoc == null) {
      showError(context, 'Please select a location for the opening stock');
      return;
    }
    if (_openingLoc != null && qty <= 0) {
      showError(context, 'Please enter a quantity greater than 0');
      return;
    }

    widget.onSave(
      _nameCtrl.text.trim(),
      _unit!,
      _openingLoc?.id,
      qty > 0 ? qty : null,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t         = context.appTheme;
    final bot       = MediaQuery.of(context).viewInsets.bottom;
    final locations = context.read<AppDataProvider>().locations;

    return _Sheet(
      title:     _isEdit ? 'Edit Item' : 'Add Item',
      bottomPad: bot,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize:        MainAxisSize.min,
          crossAxisAlignment:  CrossAxisAlignment.stretch,
          children: [

            // Name
            TextFormField(
              controller:          _nameCtrl,
              textCapitalization:  TextCapitalization.words,
              style:               AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:  'Item name',
                hintText:   'e.g. 60*90 Dabangg',
                prefixIcon: Icon(Icons.inventory_2_outlined,
                    size: 18, color: t.text3),
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Minimum 2 characters' : null,
            ),
            const SizedBox(height: AppSpacing.md),

            // Unit
            DropdownButtonFormField<String>(
              value:         _unit,
              dropdownColor: t.surface,
              style:         AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:  'Unit',
                prefixIcon: Icon(Icons.scale_outlined,
                    size: 18, color: t.text3),
              ),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
              items: _units.map((u) => DropdownMenuItem(
                value: u,
                child: Row(children: [
                  Text(u, style: AppFonts.monoStyle(size: 13, color: t.text)),
                  const SizedBox(width: 8),
                  Text(_unitDesc(u), style: AppFonts.label(color: t.text3)),
                ]),
              )).toList(),
              onChanged: (v) => setState(() => _unit = v),
              validator: (_) =>
                  _unit == null ? 'Please select a unit' : null,
            ),

            // Opening stock — only for add mode
            if (!_isEdit) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(children: [
                Expanded(child: Container(height: 0.6, color: t.border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('OPENING STOCK (optional)',
                      style: AppFonts.labelStyle(color: t.text3)),
                ),
                Expanded(child: Container(height: 0.6, color: t.border)),
              ]),
              const SizedBox(height: AppSpacing.md),

              // Location
              DropdownButtonFormField<LocationModel>(
                value:         _openingLoc,
                dropdownColor: t.surface,
                style:         AppFonts.body(color: t.text),
                decoration: InputDecoration(
                  labelText:  'Location',
                  hintText:   'Where is this stock stored?',
                  prefixIcon: Icon(Icons.warehouse_outlined,
                      size: 18, color: t.text3),
                ),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: t.text3),
                items: locations.map((loc) => DropdownMenuItem(
                  value: loc,
                  child: Row(children: [
                    Icon(
                      loc.type == 'shop'
                          ? Icons.storefront_outlined
                          : Icons.warehouse_outlined,
                      size: 14, color: t.text3,
                    ),
                    const SizedBox(width: 8),
                    Text(loc.name, style: AppFonts.body(color: t.text)),
                    const SizedBox(width: 6),
                    Text(loc.type, style: AppFonts.label(color: t.text3)),
                  ]),
                )).toList(),
                onChanged: (v) => setState(() => _openingLoc = v),
              ),
              const SizedBox(height: AppSpacing.md),

              // Quantity
              TextFormField(
                controller:   _qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                ],
                style: AppFonts.monoStyle(
                    size: 15, color: t.text, weight: FontWeight.w600),
                decoration: InputDecoration(
                  labelText:  'Quantity',
                  hintText:   '0',
                  prefixIcon: Icon(Icons.numbers_rounded,
                      size: 18, color: t.text3),
                  suffix: _unit != null
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: t.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(_unit!,
                              style: AppFonts.monoStyle(
                                  size: 11, color: t.primary)),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Leave empty to add stock later via Add Movement',
                style: AppFonts.label(color: t.text3),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: _isEdit ? 'Update Item' : 'Add Item',
              icon:  _isEdit ? Icons.check_rounded : Icons.add_rounded,
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GODOWNS TAB
// ═══════════════════════════════════════════════════════════════════════════
class _GodownsTab extends StatefulWidget {
  const _GodownsTab();
  @override
  State<_GodownsTab> createState() => _GodownsTabState();
}

class _GodownsTabState extends State<_GodownsTab> {
  String _search = '';
  final  _ctrl   = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _openAdd(BuildContext ctx) => _showLocSheet(
    context:  ctx,
    existing: null,
    onSave: (n, tp) =>
        ctx.read<AppDataProvider>().addLocation(name: n, type: tp),
  );

  void _openEdit(BuildContext ctx, LocationModel loc) => _showLocSheet(
    context:  ctx,
    existing: loc,
    onSave: (n, tp) =>
        ctx.read<AppDataProvider>()
            .editLocation(id: loc.id, name: n, type: tp),
  );

  Future<void> _delete(BuildContext ctx, LocationModel loc) async {
    final ok = await showDeleteConfirm(ctx, loc.name);
    if (ok && ctx.mounted) {
      ctx.read<AppDataProvider>().deleteLocation(loc.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data     = context.watch<AppDataProvider>();
    final isAdmin  = data.isAdmin;
    final filtered = data.locations.where((l) => _search.isEmpty ||
        l.name.toLowerCase().contains(_search.toLowerCase())).toList();

    return Column(children: [
      // Only admin sees the add button
      isAdmin
          ? _SearchBar(
              ctrl:      _ctrl,
              onChanged: (v) => setState(() => _search = v),
              onAdd:     () => _openAdd(context),
            )
          : _SearchBarNoAdd(
              ctrl:      _ctrl,
              onChanged: (v) => setState(() => _search = v),
            ),
      _RoleBanner(
        isAdmin:   isAdmin,
        staffNote: 'Only admin can add, edit or delete locations.',
      ),
      Expanded(
        child: filtered.isEmpty
            ? EmptyState(
                icon:    Icons.warehouse_outlined,
                message: _search.isEmpty
                    ? 'No locations yet.'
                    : 'No locations match "$_search"',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _DataRow(
                  avatar:      filtered[i].type == 'shop' ? 'S' : 'G',
                  avatarAlt:   filtered[i].type == 'shop',
                  title:       filtered[i].name,
                  meta:        filtered[i].type,
                  date:        filtered[i].createdAt,
                  showActions: isAdmin,
                  onEdit:      () => _openEdit(context, filtered[i]),
                  onDelete:    () => _delete(context, filtered[i]),
                ),
              ),
      ),
    ]);
  }
}

void _showLocSheet({
  required BuildContext   context,
  required LocationModel? existing,
  required void Function(String, String) onSave,
}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _LocSheet(existing: existing, onSave: onSave),
  );
}

class _LocSheet extends StatefulWidget {
  final LocationModel? existing;
  final void Function(String, String) onSave;
  const _LocSheet({required this.existing, required this.onSave});
  @override
  State<_LocSheet> createState() => _LocSheetState();
}

class _LocSheetState extends State<_LocSheet> {
  final _nameCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  String _type    = 'godown';
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.existing!.name;
      _type          = widget.existing!.type;
    }
  }

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSave(_nameCtrl.text.trim(), _type);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t   = context.appTheme;
    final bot = MediaQuery.of(context).viewInsets.bottom;
    return _Sheet(
      title:     _isEdit ? 'Edit Location' : 'Add Location',
      bottomPad: bot,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller:         _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style:              AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:  'Location name',
                hintText:   'e.g. Godown A, Main Shop',
                prefixIcon: Icon(Icons.warehouse_outlined,
                    size: 18, color: t.text3),
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Minimum 2 characters' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Type', style: AppFonts.label(color: t.text3)),
            const SizedBox(height: 6),
            Row(children: [
              _TypeChip(
                label:    'Godown',
                icon:     Icons.warehouse_outlined,
                selected: _type == 'godown',
                onTap:    () => setState(() => _type = 'godown'),
              ),
              const SizedBox(width: AppSpacing.sm),
              _TypeChip(
                label:    'Shop',
                icon:     Icons.storefront_outlined,
                selected: _type == 'shop',
                onTap:    () => setState(() => _type = 'shop'),
              ),
            ]),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: _isEdit ? 'Update Location' : 'Add Location',
              icon:  _isEdit ? Icons.check_rounded : Icons.add_rounded,
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String       label;
  final IconData     icon;
  final bool         selected;
  final VoidCallback onTap;
  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color:        selected ? t.primary : t.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: selected ? t.primary : t.border,
              width: selected ? 1.5 : 0.8,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16,
                  color: selected ? t.primaryFg : t.text2),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                fontFamily:  AppFonts.sans,
                fontSize:    13,
                fontWeight:  FontWeight.w500,
                color:       selected ? t.primaryFg : t.text2,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STAFF TAB
// ═══════════════════════════════════════════════════════════════════════════
class _StaffTab extends StatefulWidget {
  const _StaffTab();
  @override
  State<_StaffTab> createState() => _StaffTabState();
}

class _StaffTabState extends State<_StaffTab> {
  String _search = '';
  final  _ctrl   = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _openAdd(BuildContext ctx) => _showStaffSheet(
    context:  ctx,
    existing: null,
    onSave: (n, p, r) =>
        ctx.read<AppDataProvider>().addStaff(name: n, pin: p, role: r),
  );

  void _openEdit(BuildContext ctx, StaffModel s) => _showStaffSheet(
    context:  ctx,
    existing: s,
    onSave: (n, p, r) =>
        ctx.read<AppDataProvider>().editStaff(id: s.id, name: n, pin: p, role: r),
  );

  Future<void> _delete(BuildContext ctx, StaffModel s) async {
    final ok = await showDeleteConfirm(ctx, s.name);
    if (ok && ctx.mounted) {
      ctx.read<AppDataProvider>().deleteStaff(s.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data     = context.watch<AppDataProvider>();
    final isAdmin  = data.isAdmin;
    final filtered = data.staff.where((s) => _search.isEmpty ||
        s.name.toLowerCase().contains(_search.toLowerCase())).toList();

    return Column(children: [
      isAdmin
          ? _SearchBar(
              ctrl:      _ctrl,
              onChanged: (v) => setState(() => _search = v),
              onAdd:     () => _openAdd(context),
            )
          : _SearchBarNoAdd(
              ctrl:      _ctrl,
              onChanged: (v) => setState(() => _search = v),
            ),
      _RoleBanner(
        isAdmin:   isAdmin,
        staffNote: 'Only admin can add or edit staff members.',
      ),
      Expanded(
        child: filtered.isEmpty
            ? EmptyState(
                icon:    Icons.people_outline_rounded,
                message: _search.isEmpty
                    ? 'No staff yet.'
                    : 'No staff match "$_search"',
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (_, i) => _DataRow(
                  avatar:      filtered[i].name[0].toUpperCase(),
                  title:       filtered[i].name,
                  // Show role badge instead of PIN for clarity
                  meta:        filtered[i].role,
                  date:        filtered[i].createdAt,
                  showActions: isAdmin,
                  onEdit:      () => _openEdit(context, filtered[i]),
                  onDelete:    () => _delete(context, filtered[i]),
                ),
              ),
      ),
    ]);
  }
}

void _showStaffSheet({
  required BuildContext context,
  required StaffModel?  existing,
  required void Function(String, String, String) onSave,
}) {
  showModalBottomSheet(
    context:            context,
    isScrollControlled: true,
    backgroundColor:    Colors.transparent,
    builder: (_) => _StaffSheet(existing: existing, onSave: onSave),
  );
}

class _StaffSheet extends StatefulWidget {
  final StaffModel? existing;
  final void Function(String name, String pin, String role) onSave;
  const _StaffSheet({required this.existing, required this.onSave});
  @override
  State<_StaffSheet> createState() => _StaffSheetState();
}

class _StaffSheetState extends State<_StaffSheet> {
  final _nameCtrl = TextEditingController();
  final _pinCtrl  = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  bool  _showPin  = false;
  String _role    = 'staff';
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.existing!.name;
      _pinCtrl.text  = widget.existing!.pin;
      _role          = widget.existing!.role;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSave(_nameCtrl.text.trim(), _pinCtrl.text.trim(), _role);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t   = context.appTheme;
    final bot = MediaQuery.of(context).viewInsets.bottom;
    return _Sheet(
      title:     _isEdit ? 'Edit Staff' : 'Add Staff',
      bottomPad: bot,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller:         _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style:              AppFonts.body(color: t.text),
              decoration: InputDecoration(
                labelText:  'Staff name',
                prefixIcon: Icon(Icons.person_outline_rounded,
                    size: 18, color: t.text3),
              ),
              validator: (v) => (v == null || v.trim().length < 2)
                  ? 'Minimum 2 characters' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller:      _pinCtrl,
              obscureText:     !_showPin,
              keyboardType:    TextInputType.number,
              maxLength:       4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppFonts.monoStyle(
                  size: 16, color: t.text, weight: FontWeight.w600),
              decoration: InputDecoration(
                labelText:   'PIN (4 digits)',
                hintText:    '●●●●',
                counterText: '',
                prefixIcon:  Icon(Icons.lock_outline_rounded,
                    size: 18, color: t.text3),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPin
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18, color: t.text3,
                  ),
                  onPressed: () => setState(() => _showPin = !_showPin),
                ),
              ),
              validator: (v) => (v == null || v.trim().length != 4)
                  ? 'PIN must be exactly 4 digits' : null,
            ),
            const SizedBox(height: AppSpacing.md),

            // Role selector
            Text('Role', style: AppFonts.label(color: t.text3)),
            const SizedBox(height: 6),
            Row(children: [
              _TypeChip(
                label:    'Staff',
                icon:     Icons.person_outline_rounded,
                selected: _role == 'staff',
                onTap:    () => setState(() => _role = 'staff'),
              ),
              const SizedBox(width: AppSpacing.sm),
              _TypeChip(
                label:    'Admin',
                icon:     Icons.admin_panel_settings_outlined,
                selected: _role == 'admin',
                onTap:    () => setState(() => _role = 'admin'),
              ),
            ]),

            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: _isEdit ? 'Update Staff' : 'Add Staff',
              icon:  _isEdit ? Icons.check_rounded : Icons.add_rounded,
              onTap: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _DataRow extends StatelessWidget {
  final String       avatar;
  final String       title;
  final String       meta;
  final DateTime     date;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool         avatarAlt;
  final bool         showActions; // false = staff view, hides edit/delete

  const _DataRow({
    required this.avatar,
    required this.title,
    required this.meta,
    required this.date,
    required this.onEdit,
    required this.onDelete,
    this.avatarAlt   = false,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final t      = context.appTheme;
    final accent = avatarAlt ? t.success : t.primary;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Center(
            child: Text(avatar,
                style: AppFonts.monoStyle(
                    size: 16, weight: FontWeight.w700, color: accent)),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(
                  fontFamily:  AppFonts.sans,
                  fontSize:    14,
                  fontWeight:  FontWeight.w600,
                  color:       t.text)),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(meta,
                      style: AppFonts.monoStyle(size: 11, color: accent)),
                ),
                const SizedBox(width: 8),
                Text(_fmtDate(date),
                    style: AppFonts.monoStyle(size: 10, color: t.text3)),
              ]),
            ],
          ),
        ),
        if (showActions)
          Row(mainAxisSize: MainAxisSize.min, children: [
            ActionButton(
                label: 'edit',
                icon:  Icons.edit_outlined,
                onTap: onEdit),
            const SizedBox(width: AppSpacing.xs + 2),
            ActionButton(
                label:  'delete',
                icon:   Icons.delete_outline_rounded,
                onTap:  onDelete,
                danger: true),
          ]),
      ]),
    );
  }

  static String _fmtDate(DateTime d) {
    const mo = ['Jan','Feb','Mar','Apr','May','Jun',
                 'Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${mo[d.month - 1]} ${d.year}';
  }
}

// Role info banner shown at top of each tab
class _RoleBanner extends StatelessWidget {
  final bool   isAdmin;
  final String staffNote;
  const _RoleBanner({
    required this.isAdmin,
    required this.staffNote,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    if (isAdmin) {
      // Admin sees a small green "Admin access" badge
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
        decoration: BoxDecoration(
          color:        t.successBg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
          border:       Border.all(color: t.success.withOpacity(0.3), width: 0.8),
        ),
        child: Row(children: [
          Icon(Icons.admin_panel_settings_outlined,
              size: 13, color: t.success),
          const SizedBox(width: 6),
          Text(
            'Admin access — full control',
            style: AppFonts.monoStyle(size: 11, color: t.success),
          ),
        ]),
      );
    }
    // Staff sees a muted info note
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color:        t.infoBg,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border:       Border.all(color: t.infoFg.withOpacity(0.2), width: 0.8),
      ),
      child: Row(children: [
        Icon(Icons.info_outline_rounded, size: 13, color: t.infoFg),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            staffNote,
            style: AppFonts.monoStyle(size: 11, color: t.infoFg),
          ),
        ),
      ]),
    );
  }
}

// Search bar without add button — shown to staff on restricted tabs
class _SearchBarNoAdd extends StatelessWidget {
  final TextEditingController ctrl;
  final ValueChanged<String>  onChanged;
  const _SearchBarNoAdd({required this.ctrl, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: TextField(
        controller: ctrl,
        onChanged:  onChanged,
        style:      AppFonts.body(color: t.text),
        decoration: InputDecoration(
          hintText:   'Search...',
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: t.text3),
          suffixIcon: ctrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close_rounded, size: 16, color: t.text3),
                  onPressed: () { ctrl.clear(); onChanged(''); },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController ctrl;
  final ValueChanged<String>  onChanged;
  final VoidCallback          onAdd;
  const _SearchBar({
    required this.ctrl,
    required this.onChanged,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            onChanged:  onChanged,
            style:      AppFonts.body(color: t.text),
            decoration: InputDecoration(
              hintText:   'Search...',
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: t.text3),
              suffixIcon: ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: 16, color: t.text3),
                      onPressed: () { ctrl.clear(); onChanged(''); },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        GestureDetector(
          onTap: onAdd,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: t.primary,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(Icons.add_rounded, size: 20, color: t.primaryFg),
          ),
        ),
      ]),
    );
  }
}

class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;
  final double bottomPad;
  const _Sheet({
    required this.title,
    required this.child,
    required this.bottomPad,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      padding: EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md,
          AppSpacing.lg, AppSpacing.lg + bottomPad),
      child: Column(
        mainAxisSize:       MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: t.border,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(children: [
            Text(title, style: AppFonts.heading(color: t.text)),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(Icons.close_rounded, size: 20, color: t.text3),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}