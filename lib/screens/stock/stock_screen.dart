import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app_theme.dart';
import '../../common_widgets.dart';
import '../../providers/app_data_provider.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String _search = '';
  final  _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t    = context.appTheme;
    final data = context.watch<AppDataProvider>();

    // Compute stock grouped by location
    final allStock = data.getStock();
    final grouped  = <String, List<StockBalance>>{};

    for (final s in allStock) {
      if (s.balance <= 0) continue;
      if (_search.isNotEmpty &&
          !s.item.name.toLowerCase().contains(_search.toLowerCase())) continue;
      grouped.putIfAbsent(s.location.name, () => []).add(s);
    }

    // Sort: godowns first, shop last
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        final aType = allStock
            .firstWhere((s) => s.location.name == a)
            .location.type;
        final bType = allStock
            .firstWhere((s) => s.location.name == b)
            .location.type;
        if (aType == bType) return a.compareTo(b);
        return aType == 'godown' ? -1 : 1;
      });

    final zeroItems = data.items
        .where((i) => data.totalStockForItem(i.id) <= 0)
        .length;

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

            // Search
            Padding(
              padding: AppSizes.pagePadding(context).copyWith(bottom: 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged:  (v) => setState(() => _search = v),
                style:      AppFonts.body(color: t.text),
                decoration: InputDecoration(
                  hintText:   'Search items...',
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
            ),

            // Summary strip
            if (_search.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(children: [
                  _StatBox(
                      label: 'locations',
                      value: '${data.locations.length}'),
                  const SizedBox(width: AppSpacing.sm),
                  _StatBox(
                      label: 'items',
                      value: '${data.items.length}'),
                  const SizedBox(width: AppSpacing.sm),
                  _StatBox(
                      label: 'zero stock',
                      value: '$zeroItems',
                      warn:  zeroItems > 0),
                ]),
              ),

            // Godown cards
            Expanded(
              child: grouped.isEmpty
                  ? EmptyState(
                      icon:    Icons.warehouse_outlined,
                      message: _search.isEmpty
                          ? 'No stock data.\nAdd movements to see stock.'
                          : 'No items match "$_search"',
                    )
                  : ListView.separated(
                      padding: AppSizes.pagePadding(context)
                          .copyWith(top: 4, bottom: AppSpacing.lg),
                      itemCount: sortedKeys.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm + 2),
                      itemBuilder: (_, i) {
                        final name    = sortedKeys[i];
                        final entries = grouped[name]!;
                        return _GodownCard(
                          locationName: name,
                          locationType: entries.first.location.type,
                          entries:      entries,
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
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t      = context.appTheme;
    final isShop = widget.locationType == 'shop';
    final accent = isShop ? t.success : t.primary;

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
                      '${widget.entries.length == 1 ? '' : 's'} in stock',
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
          // Total footer
          Container(
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(AppSpacing.radius)),
              border: Border(
                  top: BorderSide(color: t.border, width: 0.8)),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical:   AppSpacing.sm + 2),
            child: Row(children: [
              Text('TOTAL ITEMS IN STOCK',
                  style: AppFonts.labelStyle(color: t.text3)),
              const Spacer(),
              Text(
                '${widget.entries.length}',
                style: AppFonts.monoStyle(
                    size: 13, weight: FontWeight.w700, color: t.text2),
              ),
            ]),
          ),
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