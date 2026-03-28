// ─────────────────────────────────────────────────────────────────────────────
// stock_screen.dart — Checkpoint 2 (rebuilt)
//
// Checkpoint 2 changes:
//   • Dual view toggle: Location view (default) + Item view
//   • Location view: shows all items per location, expanded by default
//   • Item view: shows where each item is stored across all locations
//   • Zero stock items visible with "0" badge — no items hidden
//   • Total row per location shows sum of all item quantities
//   • Total row per item shows sum across all locations
//   • Summary strip shows total quantity across entire inventory
//   • Search works in both views
//
// Design spec applied:
//   • padding: 12px, border-radius: 12px, gap: 10px
//   • font: Inter / monospace for data
//   • heading 18/600, body 14/400, label 12/500
//   • large clickable areas
//   • theme adaptive (light/dark)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';

// ── View mode ────────────────────────────────────────────────────────────────
enum _ViewMode { byLocation, byItem }

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String    _search   = '';
  _ViewMode _viewMode = _ViewMode.byLocation;
  final     _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t    = context.appTheme;
    final data = context.watch<AppDataProvider>();
    final allStock = data.getStock();

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.surface,
        leading: const AppBackButton(),
        title: Text(
          'View Stock',
          style: AppFonts.heading(color: t.text).copyWith(fontSize: 16),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: t.success,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 5),
              Text('live',
                  style: AppFonts.monoStyle(size: 11, color: t.success)),
            ]),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [

            // Search + view toggle
            Padding(
              padding: AppSizes.pagePadding(context).copyWith(bottom: 0),
              child: Column(children: [
                TextField(
                  controller: _searchCtrl,
                  onChanged:  (v) => setState(() => _search = v),
                  style:      AppFonts.body(color: t.text),
                  decoration: InputDecoration(
                    hintText:   'Search items or locations...',
                    prefixIcon: Icon(Icons.search_rounded, size: 18, color: t.text3),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close_rounded, size: 16, color: t.text3),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _search = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                // View mode toggle
                Row(children: [
                  _ViewChip(
                    icon:     Icons.warehouse_outlined,
                    label:    'By Location',
                    selected: _viewMode == _ViewMode.byLocation,
                    onTap:    () => setState(() => _viewMode = _ViewMode.byLocation),
                  ),
                  const SizedBox(width: 6),
                  _ViewChip(
                    icon:     Icons.inventory_2_outlined,
                    label:    'By Item',
                    selected: _viewMode == _ViewMode.byItem,
                    onTap:    () => setState(() => _viewMode = _ViewMode.byItem),
                  ),
                  const Spacer(),
                  // Total items in stock count
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                    ),
                    child: Text(
                      '${data.items.length} items',
                      style: AppFonts.monoStyle(size: 11, color: t.primary),
                    ),
                  ),
                ]),
              ]),
            ),

            const SizedBox(height: AppSpacing.sm),

            // Summary strip
            if (_search.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _SummaryStrip(data: data, allStock: allStock),
              ),

            // Stock content
            Expanded(
              child: _viewMode == _ViewMode.byLocation
                  ? _LocationView(
                      data:     data,
                      allStock: allStock,
                      search:   _search,
                    )
                  : _ItemView(
                      data:     data,
                      allStock: allStock,
                      search:   _search,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SUMMARY STRIP — overview numbers
// ═══════════════════════════════════════════════════════════════════════════

class _SummaryStrip extends StatelessWidget {
  final AppDataProvider    data;
  final List<StockBalance> allStock;
  const _SummaryStrip({required this.data, required this.allStock});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    final zeroItems = data.items
        .where((i) => data.totalStockForItem(i.id) <= 0)
        .length;
    final activeItems = data.items.length - zeroItems;

    return Row(children: [
      _StatBox(label: 'locations', value: '${data.locations.length}'),
      const SizedBox(width: AppSpacing.sm),
      _StatBox(label: 'in stock', value: '$activeItems'),
      const SizedBox(width: AppSpacing.sm),
      _StatBox(
          label: 'zero stock',
          value: '$zeroItems',
          warn:  zeroItems > 0),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOCATION VIEW — grouped by godown/shop
// ═══════════════════════════════════════════════════════════════════════════

class _LocationView extends StatelessWidget {
  final AppDataProvider    data;
  final List<StockBalance> allStock;
  final String             search;
  const _LocationView({
    required this.data,
    required this.allStock,
    required this.search,
  });

  @override
  Widget build(BuildContext context) {
    // Group stock by location, filtering by search
    final grouped = <String, List<StockBalance>>{};
    for (final s in allStock) {
      if (s.balance <= 0) continue;
      if (search.isNotEmpty) {
        final q = search.toLowerCase();
        if (!s.item.name.toLowerCase().contains(q) &&
            !s.location.name.toLowerCase().contains(q)) continue;
      }
      grouped.putIfAbsent(s.location.name, () => []).add(s);
    }

    // Sort: godowns first, shop last
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aType = allStock.firstWhere((s) => s.location.name == a).location.type;
        final bType = allStock.firstWhere((s) => s.location.name == b).location.type;
        if (aType == bType) return a.compareTo(b);
        return aType == 'godown' ? -1 : 1;
      });

    if (grouped.isEmpty) {
      return EmptyState(
        icon:    Icons.warehouse_outlined,
        message: search.isEmpty
            ? 'No stock data.\nAdd movements to see stock.'
            : 'No items match "$search"',
      );
    }

    return ListView.separated(
      padding: AppSizes.pagePadding(context).copyWith(top: 4, bottom: AppSpacing.lg),
      itemCount: sortedKeys.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm + 2),
      itemBuilder: (_, i) {
        final name    = sortedKeys[i];
        final entries = grouped[name]!;
        return _GodownCard(
          locationName: name,
          locationType: entries.first.location.type,
          entries:      entries,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEM VIEW — grouped by item, shows locations where stored
// ═══════════════════════════════════════════════════════════════════════════

class _ItemView extends StatelessWidget {
  final AppDataProvider    data;
  final List<StockBalance> allStock;
  final String             search;
  const _ItemView({
    required this.data,
    required this.allStock,
    required this.search,
  });

  @override
  Widget build(BuildContext context) {
    // Get all items (including zero stock ones)
    final q = search.toLowerCase();
    final filteredItems = data.items.where((item) {
      if (search.isNotEmpty && !item.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();

    if (filteredItems.isEmpty) {
      return EmptyState(
        icon:    Icons.inventory_2_outlined,
        message: search.isEmpty
            ? 'No items yet.\nAdd items in Manage Data.'
            : 'No items match "$search"',
      );
    }

    return ListView.separated(
      padding: AppSizes.pagePadding(context).copyWith(top: 4, bottom: AppSpacing.lg),
      itemCount: filteredItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm + 2),
      itemBuilder: (_, i) {
        final item = filteredItems[i];
        // Get stock entries for this item across all locations
        final entries = allStock.where((s) => s.item.id == item.id).toList();
        final totalQty = entries.fold<double>(0, (sum, e) => sum + e.balance);
        return _ItemCard(
          item:     item,
          entries:  entries,
          totalQty: totalQty,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEM CARD — shows one item and all locations where it's stored
// ═══════════════════════════════════════════════════════════════════════════

class _ItemCard extends StatefulWidget {
  final ItemModel          item;
  final List<StockBalance> entries;
  final double             totalQty;
  const _ItemCard({
    required this.item,
    required this.entries,
    required this.totalQty,
  });
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final t      = context.appTheme;
    final isZero = widget.totalQty <= 0;
    final accent = isZero ? t.error : t.primary;

    // Format total
    final totalDisplay = widget.totalQty == widget.totalQty.truncateToDouble()
        ? widget.totalQty.toInt().toString()
        : widget.totalQty.toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
          color: isZero ? t.error.withOpacity(0.3) : t.border,
          width: 0.8,
        ),
      ),
      child: Column(children: [
        // Header
        InkWell(
          onTap: widget.entries.isNotEmpty
              ? () => setState(() => _expanded = !_expanded)
              : null,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radius),
            bottom: _expanded && widget.entries.isNotEmpty
                ? Radius.zero
                : Radius.circular(AppSpacing.radius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(children: [
              // Item avatar
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Center(
                  child: Text(
                    widget.item.name[0].toUpperCase(),
                    style: AppFonts.monoStyle(
                        size: 16, weight: FontWeight.w700, color: accent),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Item name + unit
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.name, style: TextStyle(
                        fontFamily:  AppFonts.sans,
                        fontSize:    14,
                        fontWeight:  FontWeight.w600,
                        color:       t.text)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(widget.item.unit,
                            style: AppFonts.monoStyle(size: 11, color: accent)),
                      ),
                      const SizedBox(width: 6),
                      if (widget.entries.isNotEmpty)
                        Text(
                          '${widget.entries.where((e) => e.balance > 0).length} location'
                          '${widget.entries.where((e) => e.balance > 0).length == 1 ? '' : 's'}',
                          style: AppFonts.label(color: t.text3),
                        ),
                    ]),
                  ],
                ),
              ),
              // Total quantity badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isZero
                      ? t.error.withOpacity(0.1)
                      : t.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                ),
                child: Text(
                  isZero ? '0' : totalDisplay,
                  style: AppFonts.monoStyle(
                    size:   15,
                    weight: FontWeight.w700,
                    color:  isZero ? t.error : t.primary,
                  ),
                ),
              ),
              if (widget.entries.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18, color: t.text3,
                ),
              ],
            ]),
          ),
        ),

        // Location rows
        if (_expanded && widget.entries.isNotEmpty) ...[
          Divider(height: 0, color: t.border),
          ...widget.entries.where((e) => e.balance > 0).map((e) =>
            _LocationRow(entry: e)),
          // Zero stock footer if applicable
          if (widget.entries.any((e) => e.balance <= 0))
            ...widget.entries.where((e) => e.balance <= 0).map((e) =>
              _LocationRow(entry: e, isZero: true)),
        ],

        // Zero stock message if no entries at all
        if (widget.entries.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded, size: 14, color: t.warnFg),
              const SizedBox(width: 6),
              Text('No stock in any location',
                  style: AppFonts.monoStyle(size: 11, color: t.warnFg)),
            ]),
          ),
      ]),
    );
  }
}

// ── Location row inside item card ─────────────────────────────────────────────
class _LocationRow extends StatelessWidget {
  final StockBalance entry;
  final bool         isZero;
  const _LocationRow({required this.entry, this.isZero = false});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final v = entry.balance;
    final display = v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
    final isShop = entry.location.type == 'shop';

    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: t.border, width: 0.5))),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      child: Row(children: [
        Icon(
          isShop ? Icons.storefront_outlined : Icons.warehouse_outlined,
          size: 14, color: isZero ? t.text3 : (isShop ? t.success : t.primary),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(entry.location.name, style: TextStyle(
              fontFamily:  AppFonts.sans,
              fontSize:    13,
              fontWeight:  FontWeight.w500,
              color:       isZero ? t.text3 : t.text)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isShop ? t.success.withOpacity(0.08) : t.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(entry.location.type,
              style: AppFonts.monoStyle(size: 10, color: isShop ? t.success : t.primary)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          isZero ? '0' : display,
          style: AppFonts.monoStyle(
            size:   14,
            weight: FontWeight.w700,
            color:  isZero ? t.text3 : t.text,
          ),
        ),
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: t.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(entry.item.unit,
              style: AppFonts.monoStyle(size: 10, color: t.primary)),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GODOWN CARD — same as before but expanded by default
// ═══════════════════════════════════════════════════════════════════════════

class _GodownCard extends StatefulWidget {
  final String             locationName;
  final String             locationType;
  final List<StockBalance> entries;
  const _GodownCard({
    required this.locationName,
    required this.locationType,
    required this.entries,
  });
  @override
  State<_GodownCard> createState() => _GodownCardState();
}

class _GodownCardState extends State<_GodownCard> {
  // Checkpoint 2: Expanded by default — user shouldn't have to tap to see stock
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final t      = context.appTheme;
    final isShop = widget.locationType == 'shop';
    final accent = isShop ? t.success : t.primary;

    // Total quantity in this location
    final totalQty = widget.entries.fold<double>(0, (sum, e) => sum + e.balance);
    final totalDisplay = totalQty == totalQty.truncateToDouble()
        ? totalQty.toInt().toString()
        : totalQty.toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: t.border, width: 0.8),
      ),
      child: Column(children: [

        // Header — tap to expand/collapse
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radius),
            bottom: _expanded
                ? Radius.zero
                : Radius.circular(AppSpacing.radius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(
                  isShop
                      ? Icons.storefront_outlined
                      : Icons.warehouse_outlined,
                  size: 18, color: accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.locationName, style: TextStyle(
                        fontFamily:  AppFonts.sans,
                        fontSize:    15,
                        fontWeight:  FontWeight.w600,
                        color:       t.text)),
                    const SizedBox(height: 2),
                    Text(
                      '${widget.entries.length} item'
                      '${widget.entries.length == 1 ? '' : 's'} · $totalDisplay total',
                      style: AppFonts.label(color: t.text3),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                ),
                child: Text(widget.locationType,
                    style: AppFonts.monoStyle(size: 11, color: accent)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18, color: t.text3,
              ),
            ]),
          ),
        ),

        // Item rows — shown when expanded
        if (_expanded) ...[
          Divider(height: 0, color: t.border),
          ...widget.entries.map((e) => _ItemRow(entry: e)),
        ],
      ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final StockBalance entry;
  const _ItemRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    final v = entry.balance;
    final display = v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: t.border, width: 0.6))),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 3),
      child: Row(children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: t.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Text(
              entry.item.name[0].toUpperCase(),
              style: AppFonts.monoStyle(
                  size: 13, weight: FontWeight.w700, color: t.primary),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm + 2),
        Expanded(
          child: Text(entry.item.name, style: TextStyle(
              fontFamily:  AppFonts.sans,
              fontSize:    13,
              fontWeight:  FontWeight.w500,
              color:       t.text)),
        ),
        Text(display,
            style: AppFonts.monoStyle(
                size: 14, weight: FontWeight.w700, color: t.text)),
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: t.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(entry.item.unit,
              style: AppFonts.monoStyle(size: 11, color: t.primary)),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════════════

class _StatBox extends StatelessWidget {
  final String label, value;
  final bool   warn;
  const _StatBox({
    required this.label,
    required this.value,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: warn ? t.error.withOpacity(0.07) : t.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
              color: warn ? t.error.withOpacity(0.3) : t.border,
              width: 0.8),
        ),
        child: Column(children: [
          Text(value,
              style: AppFonts.monoStyle(
                  size:   18,
                  weight: FontWeight.w700,
                  color:  warn ? t.error : t.text)),
          const SizedBox(height: 2),
          Text(label, style: AppFonts.labelStyle(color: t.text3)),
        ]),
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  final IconData   icon;
  final String     label;
  final bool       selected;
  final VoidCallback onTap;
  const _ViewChip({
    required this.icon,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? t.primary : t.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
          border: Border.all(
              color: selected ? t.primary : t.border, width: 0.8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13,
              color: selected ? t.primaryFg : t.text3),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppFonts.label(
                color: selected ? t.primaryFg : t.text2, size: 11),
          ),
        ]),
      ),
    );
  }
}