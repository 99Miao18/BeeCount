import 'package:beecount_business_ui/beecount_business_ui.dart';
import 'package:beecount_ui/beecount_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/trash_item.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../services/billing/post_processor.dart';
import '../../utils/category_utils.dart';
import '../../utils/format_money.dart';
import '../shared/scaffold/widgets/page_scaffold.dart';

/// 最近删除（本地回收站）。
///
/// 只展示**当前账本**删掉的账单：删除快照是本地表，不参与云同步；恢复等于
/// 按快照重新记一笔（新 syncId），因此不会把别的设备上已经删掉的记录复活。
class TrashPage extends ConsumerStatefulWidget {
  const TrashPage({super.key});
  @override
  ConsumerState<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends ConsumerState<TrashPage> {
  List<TrashItem> _items = const [];
  bool _loading = true, _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final ledgerId = ref.read(currentLedgerIdProvider);
    try {
      final items = await repo.getTrashItems(ledgerId: ledgerId);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _afterWrite(int ledgerId) {
    ref.invalidate(countsForLedgerProvider(ledgerId));
    ref.read(statsRefreshProvider.notifier).state++;
    ref.read(budgetRefreshProvider.notifier).state++;
    PostProcessor.sync(ref, ledgerId: ledgerId);
  }

  Future<void> _restore(TrashItem item) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final ok = await ref.read(repositoryProvider).restoreTrashItem(item.id);
      if (!mounted) return;
      _afterWrite(item.ledgerId);
      await _load();
      if (!mounted) return;
      showBeeToast(context, ok ? l.trashRestored : l.trashRestoreFailed,
          tone: ok ? BeeTone.success : BeeTone.error);
    } catch (e) {
      if (mounted) {
        showBeeToast(context, '${l.trashRestoreFailed}: $e',
            tone: BeeTone.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteForever(TrashItem item) async {
    final l = AppLocalizations.of(context);
    final ok = await showBeeConfirm(context,
        title: l.trashDeleteForever,
        message: l.trashDeleteConfirm,
        confirmLabel: l.trashDeleteForever,
        cancelLabel: l.commonCancel,
        danger: true);
    if (!ok || !mounted) return;
    await ref.read(repositoryProvider).deleteTrashItem(item.id);
    await _load();
  }

  Future<void> _clear(int ledgerId) async {
    if (_items.isEmpty) return;
    final l = AppLocalizations.of(context);
    final ok = await showBeeConfirm(context,
        title: l.trashClearAll,
        message: l.trashClearConfirm,
        confirmLabel: l.trashClearAll,
        cancelLabel: l.commonCancel,
        danger: true);
    if (!ok || !mounted) return;
    await ref.read(repositoryProvider).clearTrash(ledgerId: ledgerId);
    await _load();
  }

  String _when(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ledgerId = ref.watch(currentLedgerIdProvider);
    final theme = Theme.of(context);
    // 回收站按账本隔离，切账本要重新读（页面可能停在后台时被切过）。
    ref.listen(currentLedgerIdProvider, (previous, next) {
      if (previous == next || !mounted) return;
      setState(() {
        _loading = true;
        _items = const [];
      });
      _load();
    });
    return V4PageScaffold(
        body: Column(children: [
      BeePageHeader(
          title: l.trashTitle,
          leading: const BackButton(),
          actions: [
            if (_items.isNotEmpty)
              BeeIconButton(
                  label: l.trashClearAll,
                  icon: const BeeLineIcon('Trash2'),
                  onPressed: _busy ? null : () => _clear(ledgerId))
          ]),
      Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(
                      child: BeeEmptyState(
                          title: l.trashEmpty,
                          message: l.trashEmptyHint,
                          icon: const BeeLineIcon('Trash2', size: 36)))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(17, 8, 17, 24),
                      itemCount: _items.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(l.trashHint,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme.hintColor)));
                        }
                        final item = _items[index - 1];
                        return _row(context, l, item, theme);
                      })),
    ]));
  }

  Widget _row(BuildContext context, AppLocalizations l, TrashItem item,
      ThemeData theme) {
    final category = CategoryUtils.displayName(item.categoryName, l);
    final subtitle = item.type == 'transfer'
        ? '${item.accountName ?? ''} → ${item.toAccountName ?? ''}'
        : '$category · ${_when(item.deletedAt)}';
    final sign = item.type == 'income' ? '+' : item.type == 'expense' ? '-' : '';
    return BeeSurface(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          SizedBox(
              width: 34,
              height: 34,
              child: Center(
                  child: BeeLineIcon(
                      item.type == 'transfer'
                          ? 'ArrowLeftRight'
                          : item.type == 'income'
                              ? 'ArrowDownLeft'
                              : 'ArrowUpRight',
                      size: 18,
                      color: theme.colorScheme.onSurface))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(item.label((name) => CategoryUtils.displayName(name, l)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: theme.hintColor))
              ])),
          const SizedBox(width: 8),
          Text('$sign${formatMoneyCompact(item.amount.abs(), trimZeros: false)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          BeeIconButton(
              label: l.trashRestore,
              icon: const BeeLineIcon('RotateCcw', size: 18),
              onPressed: _busy ? null : () => _restore(item)),
          BeeIconButton(
              label: l.trashDeleteForever,
              icon: const BeeLineIcon('Trash2', size: 18),
              onPressed: _busy ? null : () => _deleteForever(item)),
        ]));
  }
}
