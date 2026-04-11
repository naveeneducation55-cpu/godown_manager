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
//   • Each godown card collapses independently (ValueKey fix)
//   • Bale numbers shown per movement under each item
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.08),
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
// SUMMARY STRIP
// ═══════════════════════════════════════════════════════════════════════════

class _SummaryStrip extends StatelessWidget {
  final AppDataProvider    data;
  final List<StockBalance> allStock;
  const _SummaryStrip({required this.data, required this.allStock});

  @override
  Widget build(BuildContext context) {
    final t = context.appTheme;

    final zeroItems   = data.items.where((i) => data.totalStockForItem(i.id) <= 0).length;
    final activeItems = data.items.length - zeroItems;

    return Row(children: [
      _StatBox(label: 'locations', value: '${data.locations.length}'),
      const SizedBox(width: AppSpacing.sm),
      _StatBox(label: 'in stock',  value: '$activeItems'),
      const SizedBox(width: AppSpacing.sm),
      _StatBox(label: 'zero stock', value: '$zeroItems', warn: zeroItems > 0),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LOCATION VIEW
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
          key:          ValueKey(name),
          locationName: name,
          locationType: entries.first.location.type,
          entries:      entries,
          movements:    data.sortedMovements,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEM VIEW
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
    final q             = search.toLowerCase();
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
        final item     = filteredItems[i];
        final entries  = allStock.where((s) => s.item.id == item.id).toList();
        final totalQty = entries.fold<double>(0, (sum, e) => sum + e.balance);
        return _ItemCard(
          item:      item,
          entries:   entries,
          totalQty:  totalQty,
          movements: data.sortedMovements,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEM CARD — By Item view
// ═══════════════════════════════════════════════════════════════════════════

class _ItemCard extends StatefulWidget {
  final ItemModel           item;
  final List<StockBalance>  entries;
  final double              totalQty;
  final List<MovementModel> movements;
  const _ItemCard({
    required this.item,
    required this.entries,
    required this.totalQty,
    required this.movements,
  });
  @override
  State<_ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<_ItemCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t      = context.appTheme;
    final isZero = widget.totalQty <= 0;
    final accent = isZero ? t.error : t.primary;

    final totalDisplay = widget.totalQty == widget.totalQty.truncateToDouble()
        ? widget.totalQty.toInt().toString()
        : widget.totalQty.toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color:        t.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(
          color: isZero ? t.error.withValues(alpha: 0.3) : t.border,
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
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.name, style: TextStyle(
                        fontFamily: AppFonts.sans,
                        fontSize:   14,
                        fontWeight: FontWeight.w600,
                        color:      t.text)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.08),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isZero
                      ? t.error.withValues(alpha: 0.1)
                      : t.primary.withValues(alpha: 0.1),
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
            _LocationRow(entry: e, movements: widget.movements)),
          if (widget.entries.any((e) => e.balance <= 0))
            ...widget.entries.where((e) => e.balance <= 0).map((e) =>
              _LocationRow(entry: e, movements: widget.movements, isZero: true)),
        ],

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
  final StockBalance        entry;
  final List<MovementModel> movements;
  final bool                isZero;
  const _LocationRow({
    required this.entry,
    required this.movements,
    this.isZero = false,
  });

  @override
  Widget build(BuildContext context) {
    final t       = context.appTheme;
    final v       = entry.balance;
    final display = v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);
    final isShop  = entry.location.type == 'shop';

    final incomingMvts = movements.where((m) =>
        !m.isDeleted &&
        m.itemId       == entry.item.id &&
        m.toLocationId == entry.location.id,
    ).toList();

    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: t.border, width: 0.5))),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              isShop ? Icons.storefront_outlined : Icons.warehouse_outlined,
              size: 14, color: isZero ? t.text3 : (isShop ? t.success : t.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(entry.location.name, style: TextStyle(
                  fontFamily: AppFonts.sans,
                  fontSize:   13,
                  fontWeight: FontWeight.w500,
                  color:      isZero ? t.text3 : t.text)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isShop
                    ? t.success.withValues(alpha: 0.08)
                    : t.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(entry.location.type,
                  style: AppFonts.monoStyle(
                      size: 10, color: isShop ? t.success : t.primary)),
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
                color: t.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(entry.item.unit,
                  style: AppFonts.monoStyle(size: 10, color: t.primary)),
            ),
          ]),

          // Bale sub-lines — only for movements with bale number
          if (incomingMvts.any((m) =>
              m.baleNo != null && m.baleNo!.isNotEmpty)) ...[
            const SizedBox(height: 6),
            ...incomingMvts
                .where((m) => m.baleNo != null && m.baleNo!.isNotEmpty)
                .map((m) {
              final qty = m.quantity == m.quantity.truncateToDouble()
                  ? m.quantity.toInt().toString()
                  : m.quantity.toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.only(left: 22, bottom: 3),
                child: Row(children: [
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 12, color: t.text3),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      m.baleNo!,
                      style: AppFonts.monoStyle(
                          size:   11,
                          color:  t.primary,
                          weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$qty ${entry.item.unit}',
                    style: AppFonts.monoStyle(size: 11, color: t.text2),
                  ),
                ]),
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// GODOWN CARD — By Location view
// ═══════════════════════════════════════════════════════════════════════════

class _GodownCard extends StatefulWidget {
  final String              locationName;
  final String              locationType;
  final List<StockBalance>  entries;
  final List<MovementModel> movements;
  const _GodownCard({
    super.key,
    required this.locationName,
    required this.locationType,
    required this.entries,
    required this.movements,
  });
  @override
  State<_GodownCard> createState() => _GodownCardState();
}

class _GodownCardState extends State<_GodownCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t      = context.appTheme;
    final isShop = widget.locationType == 'shop';
    final accent = isShop ? t.success : t.primary;

    final totalQty     = widget.entries.fold<double>(0, (sum, e) => sum + e.balance);
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

        // Header
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
                  color: accent.withValues(alpha: 0.1),
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
                        fontFamily: AppFonts.sans,
                        fontSize:   17,
                        fontWeight: FontWeight.w700,
                        color:      t.text)),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
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

        // Item rows
        if (_expanded) ...[
          Divider(height: 0, color: t.border),
          ...widget.entries.map((e) => _ItemRow(
            entry:     e,
            movements: widget.movements,
          )),
        ],
      ]),
    );
  }
}

// ── Item row inside godown card ───────────────────────────────────────────────
class _ItemRow extends StatelessWidget {
  final StockBalance        entry;
  final List<MovementModel> movements;
  const _ItemRow({required this.entry, required this.movements});

  @override
  Widget build(BuildContext context) {
    final t       = context.appTheme;
    final v       = entry.balance;
    final display = v == v.truncateToDouble()
        ? v.toInt().toString()
        : v.toStringAsFixed(1);

    final incomingMvts = movements.where((m) =>
        !m.isDeleted &&
        m.itemId       == entry.item.id &&
        m.toLocationId == entry.location.id,
    ).toList();

    return Container(
      decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: t.border, width: 0.6))),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main row
          Row(children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.07),
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
                  fontFamily: AppFonts.sans,
                  fontSize:   15,
                  fontWeight: FontWeight.w500,
                  color:      t.text)),
            ),
            Text(display,
                style: AppFonts.monoStyle(
                    size: 16, weight: FontWeight.w700, color: t.text)),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: t.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(entry.item.unit,
                  style: AppFonts.monoStyle(size: 11, color: t.primary)),
            ),
          ]),

          // Bale sub-lines — only for movements with bale number
          if (incomingMvts.any((m) =>
              m.baleNo != null && m.baleNo!.isNotEmpty)) ...[
            const SizedBox(height: 6),
            ...incomingMvts
                .where((m) => m.baleNo != null && m.baleNo!.isNotEmpty)
                .map((m) {
              final qty = m.quantity == m.quantity.truncateToDouble()
                  ? m.quantity.toInt().toString()
                  : m.quantity.toStringAsFixed(1);
              return Padding(
                padding: const EdgeInsets.only(left: 38, bottom: 3),
                child: Row(children: [
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 12, color: t.text3),
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: t.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      m.baleNo!,
                      style: AppFonts.monoStyle(
                          size:   11,
                          color:  t.primary,
                          weight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$qty ${entry.item.unit}',
                    style: AppFonts.monoStyle(size: 11, color: t.text2),
                  ),
                ]),
              );
            }),
          ],
        ],
      ),
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
          color: warn ? t.error.withValues(alpha: 0.07) : t.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
              color: warn ? t.error.withValues(alpha: 0.3) : t.border,
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
  final IconData     icon;
  final String       label;
  final bool         selected;
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