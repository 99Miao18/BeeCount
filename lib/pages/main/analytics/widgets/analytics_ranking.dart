import 'package:beecount_business_ui/beecount_business_ui.dart';
import 'package:beecount_ui/beecount_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../transaction/category_detail_page.dart';
import '../../../transaction/search_page.dart';
import '../../../transaction/search/bindings/transaction_search.dart';
import '../../../../providers.dart';
import '../../../../utils/category_utils.dart';
import '../../../../utils/format_money.dart';
import '../bindings/analytics_data.dart';
import '../../../shared/resources/bindings/recording_category_icon.dart';

class AnalyticsRanking extends ConsumerStatefulWidget {
  const AnalyticsRanking(
      {super.key,
      required this.data,
      required this.scope,
      required this.month,
      required this.type});
  final AnalyticsResult data;
  final String scope;
  final DateTime month;

  /// expense / income / balance:未分类下钻时用来限定交易类型
  /// (转账没有分类,不加类型会串进未分类列表)。
  final String type;
  @override
  ConsumerState<AnalyticsRanking> createState() => _AnalyticsRankingState();
}

class _AnalyticsRankingState extends ConsumerState<AnalyticsRanking> {
  final expanded = <String>{};
  bool showAll = false;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        hide = ref.watch(hideAmountsProvider);
    String amount(double n) =>
        hide ? '****' : formatMoneyCompact(n, signed: false);
    BeeRankItem item(int? id, String name, dynamic category, double total,
            [List<BeeRankItem> children = const []]) =>
        BeeRankItem(
            id: '$id',
            label: CategoryUtils.getDisplayName(name, context),
            amount: amount(total),
            fraction: widget.data.total == 0 ? 0 : total / widget.data.total,
            description: hide
                ? '****'
                : '${(widget.data.total == 0 ? 0 : total / widget.data.total * 100).toStringAsFixed(1)}%',
            icon: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: BeeCardTheme.of(context).soft,
                    borderRadius: BorderRadius.circular(11)),
                child: Center(
                    child: category == null
                        ? BeeLineIcon('Shapes',
                            size: 18,
                            color: Theme.of(context).colorScheme.onSurface)
                        : RecordingCategoryIcon(
                            category: category,
                            color: Theme.of(context).colorScheme.onSurface))),
            children: children);
    final list = widget.data.categories
        .map((e) => item(
            e.id,
            e.name,
            e.category,
            e.total,
            e.subCategories
                .where((s) => s.total > 0)
                .map((s) => item(s.id, s.name, s.category, s.total))
                .toList()))
        .toList();
    void detail(String id) {
      final categoryId = int.tryParse(id);
      if (categoryId == null) {
        // 「未分类」行:id 为 null,没有分类详情可看,改为列出这段时间内
        // 没有分类的交易,让用户可以批量补分类。
        Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) => SearchPage(
                    title: l.commonUncategorized,
                    initialFilter: TransactionSearchFilter(
                        uncategorized: true,
                        kind: widget.type == 'income' ? 'income' : 'expense',
                        start: widget.scope == 'all' ? null : widget.data.start,
                        end: widget.scope == 'all'
                            ? null
                            : widget.data.end
                                .subtract(const Duration(days: 1))))));
        return;
      }
      final names = <int?, String>{
        for (final e in widget.data.categories) e.id: e.name,
        for (final e in widget.data.categories)
          for (final s in e.subCategories) s.id: s.name
      };
      final name = names[categoryId]!;
      Navigator.push(
          context,
          MaterialPageRoute<void>(
              builder: (_) => CategoryDetailPage(
                  categoryId: categoryId,
                  categoryName: name,
                  startDate: widget.scope == 'all' ? null : widget.data.start,
                  endDate: widget.scope == 'all' ? null : widget.data.end,
                  periodLabel: widget.scope == 'all'
                      ? null
                      : widget.scope == 'year'
                          ? '${widget.month.year}'
                          : '${widget.month.year}.${widget.month.month.toString().padLeft(2, '0')}')));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BeeAnalyticsRankingList(
          items: showAll ? list : list.take(4).toList(),
          expanded: expanded,
          onExpand: (id) => setState(() {
                expanded.contains(id) ? expanded.remove(id) : expanded.add(id);
              }),
          onDetail: detail),
      if (list.length > 4)
        TextButton(
            onPressed: () => setState(() => showAll = !showAll),
            child: Text(
                showAll
                    ? l.v4InsightsCollapseCategories
                    : l.v4InsightsAllCategories(list.length),
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).hintColor)))
    ]);
  }
}

class AnalyticsPie extends ConsumerStatefulWidget {
  const AnalyticsPie({super.key, required this.data});
  final AnalyticsResult data;
  @override
  ConsumerState<AnalyticsPie> createState() => _AnalyticsPieState();
}

class _AnalyticsPieState extends ConsumerState<AnalyticsPie> {
  int selected = 0;
  @override
  void didUpdateWidget(AnalyticsPie old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) selected = 0;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        hide = ref.watch(hideAmountsProvider);
    final sorted = List<AnalyticsCategory>.of(widget.data.categories)
      ..sort((a, b) => b.total.compareTo(a.total));
    final positive = sorted.where((c) => c.total > 0).toList();
    if (positive.isEmpty || widget.data.total <= 0) {
      return const SizedBox.shrink();
    }
    final entries = <({String name, double total})>[
      for (final category in positive.take(3))
        (
          name: CategoryUtils.getDisplayName(category.name, context),
          total: category.total
        ),
      if (positive.length > 3)
        (
          name: l.v4InsightsOtherCategories,
          total: positive.skip(3).fold<double>(0, (sum, c) => sum + c.total)
        )
    ];
    return BeeAnalyticsProportion(
        items: entries
            .map((e) => BeeAnalyticsShare(
                label: e.name,
                fraction: e.total / widget.data.total,
                valueLabel: hide
                    ? '****'
                    : '${(e.total / widget.data.total * 100).toStringAsFixed(1)}%'))
            .toList(),
        selected: selected,
        onSelected: (i) => setState(() => selected = i),
        hint: l.v4InsightsShareHint);
  }
}
