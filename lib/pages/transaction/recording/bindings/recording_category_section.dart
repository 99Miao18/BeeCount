import 'dart:async';
import 'dart:math' as math;

import 'package:beecount_business_ui/beecount_business_ui.dart';
import 'package:beecount_ui/beecount_ui.dart';
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
    for (final parent in parents) {
      rowHeight = math.max(
        rowHeight,
        RecordingCategoryTile.heightFor(context, label(parent),
            width: cellWidth,
            compact: narrow,
            selected: parent.id == activeParent),
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

    final visible = parents.take(capacity).toList();
    if (activeParent != null && !visible.any((c) => c.id == activeParent)) {
      final target =
          parents.where((c) => c.id == activeParent).firstOrNull;
      final index = visible.lastIndexWhere((c) => c.id != activeParent);
      if (target != null && index >= 0) visible[index] = target;
    }

    Widget tile(Category category) {
      final isSelected = activeParent == category.id;
      final children = childrenByParent[category.id] ?? const <Category>[];
      return RecordingCategoryTile(
        compact: narrow,
        key: ValueKey('recording-category-${category.id}'),
        label: label(category),
        selected: isSelected,
        hasChildren: children.isNotEmpty,
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
        return LayoutBuilder(
          builder: (context, box) =>
              _categoryGrid(context, box, all, parents, narrow),
        );
      },
    );
  }
}
