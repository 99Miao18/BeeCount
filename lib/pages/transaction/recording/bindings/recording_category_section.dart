import 'dart:async';
import 'dart:math' as math;

import 'package:beecount_business_ui/beecount_business_ui.dart';
import 'package:beecount_ui/beecount_ui.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/db.dart';
import '../../../../data/repositories/local/local_repository.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../category/category_edit_page.dart';
import '../../../category/category_manage_page.dart';
import '../../../../providers.dart';
import '../../../../providers/shared_ledger_providers.dart';
import '../../../../utils/category_utils.dart';
import '../../../../utils/shared_ledger_picker_filter.dart';
import '../../../shared/resources/bindings/recording_category_icon.dart';

final recordingCategoriesProvider = FutureProvider.autoDispose
    .family<List<Category>, ({int ledgerId, String kind})>((ref, query) async {
  ref.watch(sharedResourceRefreshProvider);
  ref.watch(syncGenerationProvider);
  final repo = ref.watch(repositoryProvider);
  final all = (await repo.getAllCategories())
      .where((category) => category.kind == query.kind)
      .toList();
  if (repo is! LocalRepository) return all;
  final scope = await repo.db.loadLedgerPickerContext(query.ledgerId);
  return repo.db.filterCategoriesForLedger(all, scope,
      kind: query.kind, topLevelOnly: false);
});

/// 记账页分类区的「上次选择 + 常用」统计（定制）。
///
/// 直接聚合 [Transactions]：不改表结构、不需要迁移，历史账目自动生效。
/// 共享账本 Editor 记的账 `category_id` 为 null（走 syncId override），
/// 所以同时按 `category_sync_id_override` 归组；UI 侧再用 syncId 映射回
/// synthetic 分类。
class RecordingCategoryUsageRow {
  const RecordingCategoryUsageRow({
    this.categoryId,
    this.categorySyncId,
    required this.total,
    required this.recent,
    required this.lastTxId,
  });

  /// 本地分类 id（单人账本 / Owner）。
  final int? categoryId;

  /// 共享账本 Editor 记账时用的分类 syncId。
  final String? categorySyncId;

  /// 累计使用次数。
  final int total;

  /// 近期（[recentWindow] 内）使用次数，用于让新习惯慢慢盖过老账。
  final int recent;

  /// 最近一次使用的交易 id：用它而不是 `happened_at` 判断「上次」，
  /// 因为补记往日账单时 `happened_at` 会早于实际记录顺序。
  final int lastTxId;

  static const recentWindow = Duration(days: 180);
}

final recordingCategoryUsageProvider = FutureProvider.autoDispose
    .family<List<RecordingCategoryUsageRow>, ({int ledgerId, String kind})>(
        (ref, query) async {
  ref.watch(syncGenerationProvider);
  ref.watch(sharedResourceRefreshProvider);
  final repo = ref.watch(repositoryProvider);
  if (repo is! LocalRepository) return const [];
  final since = DateTime.now().subtract(RecordingCategoryUsageRow.recentWindow);
  final rows = await repo.db.customSelect(
    '''
    SELECT
      t.category_id AS category_id,
      t.category_sync_id_override AS category_sync_id,
      COUNT(*) AS total_uses,
      SUM(CASE WHEN t.happened_at >= ? THEN 1 ELSE 0 END) AS recent_uses,
      MAX(t.id) AS last_tx_id
    FROM transactions t
    WHERE t.ledger_id = ? AND t.type = ?
      AND (
        t.category_id IS NOT NULL
        OR (t.category_sync_id_override IS NOT NULL
            AND t.category_sync_id_override <> '')
      )
    GROUP BY t.category_id, t.category_sync_id_override
    ''',
    variables: [
      Variable.withDateTime(since),
      Variable.withInt(query.ledgerId),
      Variable.withString(query.kind),
    ],
    readsFrom: {repo.db.transactions},
  ).get();
  return [
    for (final row in rows)
      RecordingCategoryUsageRow(
        categoryId: (row.data['category_id'] as num?)?.toInt(),
        categorySyncId: row.data['category_sync_id'] as String?,
        total: (row.data['total_uses'] as num?)?.toInt() ?? 0,
        recent: (row.data['recent_uses'] as num?)?.toInt() ?? 0,
        lastTxId: (row.data['last_tx_id'] as num?)?.toInt() ?? 0,
      ),
  ];
});

/// Compact presentation when the viewport cannot accommodate a full grid tile.
class RecordingMoreCategoriesButton extends StatelessWidget {
  const RecordingMoreCategoriesButton({super.key, required this.onPressed});

  final VoidCallback onPressed;
  static const height = 44.0;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).v4RecordingMoreCategories;
    return SizedBox(
      width: 80,
      height: height,
      child: Tooltip(
        message: label,
        child: InkWell(
          key: const ValueKey('recording-more-categories'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: BeeCardTheme.of(context).soft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: BeeLineIcon('Grid2x2', size: 16)),
              ),
              const SizedBox(width: 4),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }
}

/// App binding: shared-ledger filtering and image resolution stay outside the UI package.
class RecordingCategorySection extends ConsumerStatefulWidget {
  const RecordingCategorySection(
      {super.key,
      required this.ledgerId,
      required this.kind,
      required this.selectedId,
      required this.onSelected,
      this.preferredColumns = 4,
      this.moreInDetails,
      this.showAll = false});
  final int ledgerId;
  final String kind;
  final int? selectedId;
  final ValueChanged<Category> onSelected;
  final int preferredColumns;
  final ValueNotifier<VoidCallback?>? moreInDetails;
  final bool showAll;

  @override
  ConsumerState<RecordingCategorySection> createState() =>
      _RecordingCategorySectionState();
}

class _RecordingCategorySectionState
    extends ConsumerState<RecordingCategorySection> {
  bool _fallbackPending = false;
  VoidCallback? _detailsAction;

  void _placeMoreInDetails(bool show) {
    final target = widget.moreInDetails;
    if (target == null) return;
    _detailsAction = show ? _more : null;
    if (_fallbackPending || target.value == _detailsAction) return;
    // LayoutBuilder runs during layout. Update the sibling after this frame.
    _fallbackPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fallbackPending = false;
      if (mounted && widget.moreInDetails == target) {
        target.value = _detailsAction;
      }
    });
  }

  Future<void> _manage({bool create = false}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => create
            ? CategoryEditPage(kind: widget.kind)
            : CategoryManagePage(
                initialTabIndex: widget.kind == 'expense' ? 0 : 1)));
    if (mounted) {
      ref.invalidate(recordingCategoriesProvider(
          (ledgerId: widget.ledgerId, kind: widget.kind)));
    }
  }

  Future<void> _more() async {
    final l10n = AppLocalizations.of(context);
    final query = (ledgerId: widget.ledgerId, kind: widget.kind);
    final result = await showBeeSheet<Category>(
      context,
      title: l10n.v4RecordingMoreCategories,
      child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: Consumer(
              builder: (sheetContext, ref, _) => ref
                  .watch(recordingCategoriesProvider(query))
                  .when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (_, __) => BeeStatus(
                          label: l10n.v4RecordingCategoriesFailed,
                          tone: BeeTone.error,
                          action: BeeButton(
                              label: l10n.v4RecordingRetry,
                              onPressed: () => ref.invalidate(
                                  recordingCategoriesProvider(query)))),
                      data: (all) {
                        BeeCategoryChoice choice(Category category,
                                {bool withChildren = false}) =>
                            BeeCategoryChoice(
                                id: '${category.id}',
                                label: CategoryUtils.getDisplayName(
                                    category.name, context),
                                icon: RecordingCategoryIcon(
                                    category: category, size: 18),
                                enabled:
                                    !all.any((c) => c.parentId == category.id),
                                children: withChildren
                                    ? all
                                        .where((c) => c.parentId == category.id)
                                        .map((c) => choice(c))
                                        .toList()
                                    : const []);
                        return Column(children: [
                          Expanded(
                              child: BeeCategoryPicker(
                                  items: all
                                      .where((c) => c.level == 1)
                                      .map((c) => choice(c, withChildren: true))
                                      .toList(),
                                  selected: widget.selectedId?.toString(),
                                  immediate: true,
                                  searchLabel: l10n.searchCategoryHint,
                                  emptyLabel: l10n.categoryEmpty,
                                  confirmLabel: l10n.commonConfirm,
                                  cancelLabel: l10n.commonCancel,
                                  onConfirm: (id) => Navigator.pop(sheetContext,
                                      all.firstWhere((c) => '${c.id}' == id)),
                                  onCancel: () => Navigator.pop(sheetContext))),
                          TextButton.icon(
                              onPressed: _manage,
                              icon: const BeeLineIcon('SlidersHorizontal',
                                  size: 18),
                              label: Text(l10n.mineCategoryManagement)),
                        ]);
                      }))),
    );
    if (result != null && mounted) {
      widget.onSelected(result);
    }
  }

  /// 需求 2：点有二级的父分类 → 弹出该父分类下的二级列表；
  /// 点中任一二级立即回传并关闭，不需要再点「确认」。
  ///
  /// 弹层里不列「父分类本身」：有二级的分类必须落到二级，否则同一笔支出
  /// 会在一级、二级两种口径下混记，年度统计对不上。
  Future<void> _openChildren(Category parent, List<Category> children) async {
    // 与「更多分类」弹层保持同一高度：二级只有两三项时不再缩成一条矮抽屉。
    final height = MediaQuery.sizeOf(context).height * .65;
    final picked = await showBeeSheet<Category>(
      context,
      title: CategoryUtils.getDisplayName(parent.name, context),
      child: Builder(builder: (sheetContext) {
        return SizedBox(
          height: height,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: RecordingSubcategoryGrid(
              items: children
                  .map((category) => BeeCategoryChoice(
                        id: category.id.toString(),
                        label: CategoryUtils.getDisplayName(
                            category.name, context),
                        enabled: true,
                        icon: RecordingCategoryIcon(
                          category: category,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ))
                  .toList(),
              selected: widget.selectedId?.toString(),
              onSelected: (id) {
                Navigator.of(sheetContext)
                    .pop(children.firstWhere((c) => c.id.toString() == id));
              },
            ),
          ),
        );
      }),
    );
    if (picked != null && mounted) {
      widget.onSelected(picked);
    }
  }

  /// 第一格（上次用过的分类）的小圆点：让「这一格不是普通一级分类」看得出来。
  Widget _lastUsedMarker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 1.5),
      ),
    );
  }

  /// 定制：把「上次用过的分类」提到第一格，其余按使用频次排序。
  ///
  /// 返回 `(last: 上次分类, ranked: 排好序的父分类)`。
  /// - 没有历史时 `last` 为 null、`ranked` 就是原顺序，即用户熟悉的默认分类；
  /// - 上次用过的若是二级分类，第一格直接显示该二级（点一下即选中），
  ///   它的父分类仍保留在后面的格子/「更多」里，方便换同族子类；
  /// - 频次取「近 [RecordingCategoryUsageRow.recentWindow] 次数 → 累计次数」，
  ///   父分类按自身 + 子分类合计，这样常记「餐饮/午餐」也会把「餐饮」顶上来。
  ({Category? last, List<Category> ranked}) _rankCategories(
    List<Category> parents,
    List<Category> all,
    List<RecordingCategoryUsageRow> usage,
  ) {
    if (usage.isEmpty) return (last: null, ranked: parents);

    final byId = {for (final c in all) c.id: c};
    final bySyncId = <String, Category>{};
    for (final category in all) {
      final syncId = category.syncId;
      if (syncId != null && syncId.isNotEmpty) bySyncId[syncId] = category;
    }
    final stats = <int, _CategoryUsage>{};
    for (final row in usage) {
      final id = row.categoryId;
      final syncId = row.categorySyncId;
      final category = id != null
          ? byId[id]
          : (syncId == null || syncId.isEmpty ? null : bySyncId[syncId]);
      if (category == null) continue; // 分类已被删除，忽略这条历史
      final stat = stats.putIfAbsent(category.id, () => _CategoryUsage());
      stat.total += row.total;
      stat.recent += row.recent;
      if (row.lastTxId > stat.lastTxId) stat.lastTxId = row.lastTxId;
    }

    final parentIds = {for (final p in parents) p.id};
    Category? last;
    var lastTxId = -1;
    for (final entry in stats.entries) {
      final category = byId[entry.key];
      // 二级分类的父级已不存在时不进第一格：点开也回不到它。
      if (category == null || (category.level != 1 &&
          !parentIds.contains(category.parentId))) {
        continue;
      }
      if (entry.value.lastTxId > lastTxId) {
        lastTxId = entry.value.lastTxId;
        last = category;
      }
    }

    final childrenOf = <int, List<Category>>{};
    for (final category in all) {
      final parentId = category.parentId;
      if (parentId != null) {
        childrenOf.putIfAbsent(parentId, () => []).add(category);
      }
    }
    int aggregate(Category parent, int Function(_CategoryUsage) pick) {
      var value = pick(stats[parent.id] ?? _emptyUsage);
      for (final child in childrenOf[parent.id] ?? const <Category>[]) {
        value += pick(stats[child.id] ?? _emptyUsage);
      }
      return value;
    }

    final baseIndex = <int, int>{
      for (var i = 0; i < parents.length; i++) parents[i].id: i,
    };
    final sorted = [...parents]..sort((a, b) {
        final recent = aggregate(b, (s) => s.recent) -
            aggregate(a, (s) => s.recent);
        if (recent != 0) return recent;
        final total =
            aggregate(b, (s) => s.total) - aggregate(a, (s) => s.total);
        if (total != 0) return total;
        return (baseIndex[a.id] ?? 0) - (baseIndex[b.id] ?? 0);
      });

    final lastCategory = last;
    final ranked = <Category>[
      if (lastCategory != null) lastCategory,
      for (final parent in sorted)
        if (lastCategory == null || parent.id != lastCategory.id) parent,
    ];
    return (last: lastCategory, ranked: ranked);
  }

  /// 记账页分类区：固定「4 列 × 2 排」，第 8 格恒为「更多」。
  ///
  /// 定制（需求 1 + 2）：
  /// - 目标两排，方块尺寸沿用 [RecordingCategoryTile] 的原有高度，不缩放；
  /// - 高度连一排都放不下时（小屏 / 超大系统字号）退化成「一排 + 更多」；
  /// - 上游把二级分类内嵌成可滚动面板，展开时会把第二排挤掉，本定制改为
  ///   点父分类弹出二级弹层（[_openChildren]），分类区高度因此只归父分类用。
  Widget _categoryGrid(
    BuildContext context,
    BoxConstraints box,
    List<Category> all,
    List<Category> parents,
    bool narrow,
    List<RecordingCategoryUsageRow> usage,
  ) {
    const denseColumns = 5;
    const horizontalPadding = 13.0;
    final l10n = AppLocalizations.of(context);
    final selected = all.where((c) => c.id == widget.selectedId).firstOrNull;
    final activeParent = selected?.parentId ?? selected?.id;
    final childrenByParent = <int, List<Category>>{};
    for (final category in all) {
      final parentId = category.parentId;
      if (parentId != null) {
        childrenByParent.putIfAbsent(parentId, () => []).add(category);
      }
    }
    // 一级格子代表整族（有子类被选中时高亮）；二级格子只认自己。
    bool tileSelected(Category category) => category.level == 1
        ? activeParent == category.id
        : widget.selectedId == category.id;
    // 定制：第一格 = 上次用过的分类，其余按使用频次排序（无历史即默认顺序）。
    final ranking = _rankCategories(parents, all, usage);
    final lastCategory = ranking.last;
    final rankSource = widget.showAll ? parents : ranking.ranked;
    String label(Category category) =>
        CategoryUtils.getDisplayName(category.name, context);
    final verticalPadding = narrow ? 2.0 : 6.0;
    final width = math.max(0.0, box.maxWidth - 2 * horizontalPadding);
    final useFiveColumns = widget.preferredColumns == denseColumns &&
        width >= denseColumns * kMinInteractiveDimension;
    final columns = useFiveColumns ? denseColumns : 4;
    final cellWidth = width / columns;
    final moreLabel =
        useFiveColumns ? l10n.commonMore : l10n.v4RecordingMoreCategories;
    final bound = !widget.showAll && box.hasBoundedHeight;
    final height = box.maxHeight - 2 * verticalPadding;
    var rowHeight = RecordingCategoryTile.heightFor(context, moreLabel,
        width: cellWidth, compact: narrow);
    for (final category in rankSource) {
      rowHeight = math.max(
        rowHeight,
        RecordingCategoryTile.heightFor(context, label(category),
            width: cellWidth,
            compact: narrow,
            selected: tileSelected(category)),
      );
    }
    rowHeight = rowHeight.ceilToDouble();

    // 连一排都放不下：把入口缩到明细行右侧。
    if (bound && height < rowHeight) {
      final inDetails = box.maxHeight < RecordingMoreCategoriesButton.height;
      _placeMoreInDetails(inDetails);
      return inDetails
          ? const SizedBox.shrink()
          : Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Align(
                alignment: Alignment.bottomRight,
                child: RecordingMoreCategoriesButton(onPressed: _more),
              ),
            );
    }
    _placeMoreInDetails(false);

    // 目标两排；只够一排时退一排（不压缩键盘行高，避免影响点按）。
    const targetRows = 2;
    final rows = bound && height < rowHeight * targetRows ? 1 : targetRows;
    final slots = columns * rows;
    final capacity = widget.showAll ? parents.length : math.max(1, slots - 1);

    final visible = rankSource.take(capacity).toList();
    if (activeParent != null && !visible.any((c) => c.id == activeParent)) {
      final target =
          rankSource.where((c) => c.id == activeParent).firstOrNull;
      final index = visible.lastIndexWhere((c) => c.id != activeParent);
      if (target != null && index >= 0) visible[index] = target;
    }

    Widget tile(Category category) {
      final isSelected = tileSelected(category);
      final isLastUsed = lastCategory?.id == category.id;
      final children = childrenByParent[category.id] ?? const <Category>[];
      return RecordingCategoryTile(
        compact: narrow,
        key: ValueKey('recording-category-${category.id}'),
        label: label(category),
        selected: isSelected,
        hasChildren: children.isNotEmpty,
        marker: isLastUsed ? _lastUsedMarker(context) : null,
        icon: RecordingCategoryIcon(
          category: category,
          size: 18,
          color: isSelected
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
        ),
        onTap: () {
          if (children.isEmpty) {
            widget.onSelected(category);
          } else {
            unawaited(_openChildren(category, children));
          }
        },
      );
    }

    final entries = <Widget>[...visible.map(tile)];
    if (!widget.showAll) {
      final moreTile = RecordingCategoryTile(
        compact: narrow,
        key: const ValueKey('recording-more-categories'),
        label: moreLabel,
        icon: const BeeLineIcon('Grid2x2', size: 18),
        onTap: _more,
      );
      entries.add(useFiveColumns
          ? Semantics(
              excludeSemantics: true,
              button: true,
              enabled: true,
              label: l10n.v4RecordingMoreCategories,
              onTap: _more,
              child: moreTile)
          : moreTile);
    }

    final gridRows = <Widget>[];
    for (var i = 0; i < entries.length; i += columns) {
      final row = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(
          columns,
          (offset) => Expanded(
              child: i + offset < entries.length
                  ? entries[i + offset]
                  : const SizedBox.shrink()),
        ),
      );
      gridRows.add(SizedBox(height: rowHeight, child: row));
    }

    return BeeSurface(
      padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding, vertical: verticalPadding),
      child: Column(
        // 定制：卡片按两排格子收口，由外层决定留白，避免整段大白块。
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...gridRows,
          if (widget.showAll)
            TextButton.icon(
              onPressed: _manage,
              icon: const Icon(Icons.tune, size: 18),
              label: Text(l10n.mineCategoryManagement),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final narrow = MediaQuery.sizeOf(context).width <= 340 &&
        MediaQuery.sizeOf(context).height -
                MediaQuery.viewPaddingOf(context).vertical <
            720;
    final query = (ledgerId: widget.ledgerId, kind: widget.kind);
    return ref.watch(recordingCategoriesProvider(query)).when(
      loading: () {
        _placeMoreInDetails(false);
        return const BeeSurface(
            child: Center(child: CircularProgressIndicator()));
      },
      error: (_, __) {
        _placeMoreInDetails(false);
        return BeeSurface(
          child: SingleChildScrollView(
            child: Column(children: [
              Text(l10n.v4RecordingCategoriesFailed),
              TextButton(
                onPressed: () =>
                    ref.invalidate(recordingCategoriesProvider(query)),
                child: Text(l10n.v4RecordingRetry),
              ),
            ]),
          ),
        );
      },
      data: (all) {
        final parents = all.where((category) => category.level == 1).toList();
        if (parents.isEmpty) {
          _placeMoreInDetails(false);
          return BeeSurface(
            child: SingleChildScrollView(
              child: Column(children: [
                Text(l10n.categoryEmpty),
                TextButton.icon(
                  onPressed: () => _manage(create: true),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.categoryNew),
                ),
              ]),
            ),
          );
        }
        // 用量统计只影响排序，取不到（首帧 / 云端仓库）就按默认顺序渲染，
        // 不阻塞分类区显示。
        final usage = widget.showAll
            ? const <RecordingCategoryUsageRow>[]
            : ref.watch(recordingCategoryUsageProvider(query)).valueOrNull ??
                const <RecordingCategoryUsageRow>[];
        return LayoutBuilder(
          builder: (context, box) =>
              _categoryGrid(context, box, all, parents, narrow, usage),
        );
      },
    );
  }
}

// 单个分类的累计用量（_rankCategories 内部用）。
class _CategoryUsage {
  int total = 0;
  int recent = 0;
  int lastTxId = -1;
}

/// 只读占位，避免在排序时往 map 里写空记录。
final _emptyUsage = _CategoryUsage();
