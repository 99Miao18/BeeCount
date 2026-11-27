import 'dart:async';

import 'package:beecount_ui/beecount_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cloud_sync/flutter_cloud_sync.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cloud/sync/sync_engine.dart';
import '../../cloud/sync_service.dart';
import '../../data/repositories/local/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/budget_providers.dart';
import '../../services/attachment_service.dart';
import '../../services/system/logger_service.dart';
import '../../utils/format_utils.dart';
import '../shared/selectors/ledger_selector_dialog.dart';

final transactionMoveAvailableProvider = FutureProvider<bool>((ref) async {
  ref.watch(syncStatusRefreshProvider);
  final config = await ref.watch(activeCloudConfigProvider.future);
  if (config.type == CloudBackendType.local) return true;
  if (config.type != CloudBackendType.beecountCloud) return false;
  final cloud = await ref.watch(beecountCloudProviderInstance.future);
  if (cloud == null) return false;
  try {
    final server = await cloud.fetchServerVersion().timeout(
          const Duration(seconds: 5),
        );
    return server.capabilities.contains('transaction_move_v1');
  } catch (_) {
    return false;
  }
});

/// 跨账本移动后的分类重映射结果。
typedef MoveRemapResult = ({int mapped, int cleared});

/// 把刚移动过来的账单分类，按**名称**映射到目标账本自己的分类树。
///
/// 服务端移动只换账本归属，分类 id 原样保留 —— 于是「家庭账本 → 投资账本」
/// 搬过来的「餐饮」在投资账本里是个**不存在的分类**（分类严格归属账本后），
/// 统计页按分类树汇总时这笔会漏掉。这里按名称重挂：
/// - 目标账本有同名分类 → 改挂到它（mapped）
/// - 没有 → 置为「未分类」，让用户一眼看见需要手选（cleared）
Future<MoveRemapResult> _remapMovedCategories(
  LocalRepository repo, {
  required int targetLedgerId,
  required Set<int> transactionIds,
}) async {
  final pools = {
    'expense': await repo.getUsableCategories('expense', ledgerId: targetLedgerId),
    'income': await repo.getUsableCategories('income', ledgerId: targetLedgerId),
  };
  var mapped = 0;
  var cleared = 0;
  for (final id in transactionIds) {
    final tx = await repo.getTransactionById(id);
    if (tx == null || tx.categoryId == null) continue;
    // 转账的分类是虚拟转账分类，不参与账本分类树，别动它
    if (tx.type == 'transfer') continue;
    final current = await repo.getCategoryById(tx.categoryId!);
    if (current == null) continue;
    final pool = pools[tx.type] ?? const [];
    int? targetId;
    for (final c in pool) {
      if (c.name.trim() == current.name.trim()) {
        targetId = c.id;
        break;
      }
    }
    if (targetId == current.id) continue;
    if (targetId == null && current.ledgerId == targetLedgerId) continue;
    await repo.updateTransactionFields(
      id: id,
      writeCategory: true,
      categoryId: targetId,
    );
    if (targetId != null) {
      mapped++;
    } else {
      cleared++;
    }
  }
  return (mapped: mapped, cleared: cleared);
}

Future<int?> showTransactionMove(
  BuildContext context,
  WidgetRef ref, {
  required int sourceLedgerId,
  required Set<int> transactionIds,
}) async {
  if (transactionIds.isEmpty) return null;
  final l = AppLocalizations.of(context);
  final repo = ref.read(repositoryProvider);
  if (repo is! LocalRepository) return null;
  try {
    final source = await repo.getLedgerById(sourceLedgerId);
    final ledgers = await repo.getAllLedgers();
    if (!context.mounted) return null;
    final targets = source == null
        ? <int>{}
        : ledgers
            .where((ledger) => canMoveTransactionsBetween(source, ledger))
            .map((ledger) => ledger.id)
            .toSet();
    if (source == null || targets.isEmpty) {
      showBeeToast(context, l.transactionMoveNoTarget, tone: BeeTone.warning);
      return null;
    }
    final targetId = await showLedgerSelector(
      context,
      candidates:
          ledgers.where((ledger) => targets.contains(ledger.id)).toList(),
      title: l.transactionMoveChooseLedger,
    );
    if (!context.mounted || targetId == null) return null;
    final target = ledgers.firstWhere((ledger) => ledger.id == targetId);
    final confirmed = await showBeeConfirm(
      context,
      title: l.transactionMoveConfirmTitle,
      message: l.transactionMoveConfirmMessage(
        transactionIds.length,
        translateLedgerName(context, source.name),
        translateLedgerName(context, target.name),
      ),
      confirmLabel: l.transactionMoveCommit,
      cancelLabel: l.commonCancel,
    );
    if (!context.mounted || !confirmed) return null;

    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: BeeDialog(
          title: Text(l.transactionMoveWorking),
          content: const LinearProgressIndicator(),
        ),
      ),
    );
    unawaited(navigator.push(progress));
    late final int count;
    try {
      final config = await ref.read(activeCloudConfigProvider.future);
      final sync = ref.read(syncServiceProvider);
      if (config.type == CloudBackendType.local &&
          sync is LocalOnlySyncService) {
        count = await repo.moveTransactionsLocally(
          sourceLedgerId: source.id,
          targetLedgerId: targetId,
          transactionIds: transactionIds,
        );
      } else if (config.type == CloudBackendType.beecountCloud &&
          sync is SyncEngine &&
          await ref.read(transactionMoveAvailableProvider.future)) {
        count = await sync.moveTransactionsInCloud(
          sourceLedgerId: source.id,
          targetLedgerId: targetId,
          transactionIds: transactionIds,
        );
      } else {
        throw TransactionMoveFailure.unsynced;
      }
    } finally {
      if (progress.isActive) navigator.removeRoute(progress);
    }
    // 迁移后的分类重映射。**必须在刷新统计之前**跑完，否则列表会先按旧分类
    // 闪一下，再跳成未分类。
    MoveRemapResult remap = (mapped: 0, cleared: 0);
    try {
      remap = await _remapMovedCategories(
        repo,
        targetLedgerId: targetId,
        transactionIds: transactionIds,
      );
    } catch (error, stack) {
      // 重映射失败不影响「已经搬过去了」这个事实，只记日志，让用户手动改分类
      logger.warning('TransactionMove', '分类重映射失败: $error', stack);
    }
    if (!context.mounted) return targetId;
    ref.invalidate(countsForLedgerProvider(source.id));
    ref.invalidate(countsForLedgerProvider(targetId));
    ref.read(ledgerListRefreshProvider.notifier).state++;
    ref.read(statsRefreshProvider.notifier).state++;
    ref.read(budgetRefreshProvider.notifier).state++;
    ref.read(attachmentListRefreshProvider.notifier).state++;
    ref.read(tagListRefreshProvider.notifier).state++;
    updateAppWidget(ref, context);
    final done = l.transactionMoveDone(count);
    showBeeToast(
      context,
      remap.cleared > 0
          ? '$done · ${l.transactionMoveRemapCleared(remap.cleared)}'
          : done,
      tone: remap.cleared > 0 ? BeeTone.warning : BeeTone.success,
    );
    return targetId;
  } catch (error) {
    if (!context.mounted) return null;
    final message = switch (error) {
      TransactionMoveFailure.awaitingConfirmation => l.transactionMovePending,
      TransactionMoveFailure.unsynced => l.transactionMoveUnsynced,
      TransactionMoveFailure.changed ||
      StateError() =>
        l.transactionMoveChanged,
      BeeCountCloudTransactionMoveException(statusCode: 404) =>
        l.transactionMoveUnsynced,
      BeeCountCloudTransactionMoveException(statusCode: 409) =>
        l.transactionMoveChanged,
      _ => l.transactionMoveFailed,
    };
    showBeeToast(context, message, tone: BeeTone.warning);
    return null;
  }
}
