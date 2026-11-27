import 'ledger_repository.dart';
import 'transaction_repository.dart';
import '../db.dart' show Transaction;
import 'category_repository.dart';
import 'account_repository.dart'
    show AccountBalanceUpdateResult, AccountRepository;
import 'statistics_repository.dart';
import 'recurring_transaction_repository.dart';
import 'ai_repository.dart';
import 'tag_repository.dart';
import 'budget_repository.dart';
import 'attachment_repository.dart';
import 'exchange_rate_repository.dart';
import '../../models/home_transaction_preview.dart';
import '../../models/trash_item.dart';

/// 基础 Repository 抽象类
/// 组合所有 Repository 接口，用于类型约束
/// LocalRepository、CloudRepository、ApiRepository 等都应该实现这个抽象类
///
/// 设计原则：
/// - 不包含任何具体实现细节（如数据库访问）
/// - 仅定义数据访问的抽象接口
/// - 支持无缝切换不同的数据源实现
abstract class BaseRepository
    implements
        LedgerRepository,
        TransactionRepository,
        CategoryRepository,
        AccountRepository,
        StatisticsRepository,
        RecurringTransactionRepository,
        AIRepository,
        TagRepository,
        BudgetRepository,
        AttachmentRepository,
        ExchangeRateRepository {
  /// Read a small, complete first screen and its full-day totals in one snapshot.
  /// The ordering must be the exact prefix of transactionsWithCategoryAll.
  Future<HomeTransactionPreview> getHomeTransactionPreview({
    required int ledgerId,
    int limit = 20,
  });

  /// 将账户当前余额校准到目标值。该操作需要同时更新账户基线、交易和同步
  /// 变更，属于聚合 Repository 的用例，不由账户子 Repository 单独实现。
  Future<AccountBalanceUpdateResult> setAccountBalance({
    required int ledgerId,
    required int accountId,
    required double targetBalance,
    required bool createBalanceAdjustment,
    DateTime? happenedAt,
    String? note,
  });

  // -------------------------------------------------------------------
  // v30 交易级多币种(.docs/multi-currency-ledger):重算 / 检测。
  // 声明在聚合层而非 TransactionRepository:这些方法要同时访问交易表与
  // 有效汇率(ExchangeRateRepository),交易子仓拿不到汇率。
  // -------------------------------------------------------------------

  /// 本位币变更后全量重算该账本交易的 nativeAmount(用当前有效汇率,历史
  /// 汇率不可得)。逐笔记 change(L13:不记则云端投影永远旧值、full_pull 会
  /// 把重算成果冲回)。返回实际改动条数。
  Future<int> recalcNativeAmountsForLedger(int ledgerId, String newBase);

  /// 存量补折算(L11):只重算「currencyCode≠本位币 且 nativeAmount==amount」
  /// 的外币交易(迁移回填后从没折算过的)。缺汇率的跳过留待用户。逐笔记 change。
  /// 返回实际改动条数。
  Future<int> recomputeForeignTxForLedger(int ledgerId);

  /// 检测:该账本「未折算外币交易」条数(currencyCode≠本位币 且
  /// nativeAmount==amount;currency_code IS NULL 的行 join 账户币种兜底判定)。
  /// 统计页横幅按 >0 显示。
  Future<int> countUnconvertedForeignTx(int ledgerId);

  /// 该账本外币交易条数(currencyCode≠本位币,含已折算)。统计页折算脚注
  /// 按 >0 显示(01 §五:「含外币,已按各笔记账时汇率折算为 {本位币}」)。
  Future<int> countForeignCurrencyTx(int ledgerId);

  /// 该账本交易涉及的全部外币币种集合(重算前并入汇率拉取 extraQuotes)。
  Future<Set<String>> getLedgerForeignCurrencies(int ledgerId);

  /// 按 picker 账户 id 解析币种:正数=主表账户;负数=共享账本 synthetic id。
  Future<String?> getAccountCurrencyByAnyId(int accountId);

  /// 原子生成单期周期账单：在同一数据库事务中重读规则校验未过期消费、
  /// 创建携带 `recurringId` 的交易（并登记 ChangeTracker 变更）以及更新
  /// `lastGeneratedDate`。若规则已禁用、已推进、关联账户隐藏或缺失则返回 null。
  Future<Transaction?> generateRecurringOccurrence({
    required int recurringId,
    required DateTime scheduledDate,
  });

  // -------------------------------------------------------------------
  // 最近删除（本地回收站，30 天）
  //
  // 声明在聚合层：快照要同时读交易、分类、账户、标签、账本，
  // 恢复要重新走 addTransaction + 标签写入 + 变更登记。
  // -------------------------------------------------------------------

  /// 删除交易并先留一份快照（回收站）。UI 的删除入口都应该走这条。
  Future<void> deleteTransactionToTrash(int id);

  /// 该账本的回收站列表（删除时间倒序，已自动剔除过期的）。
  Future<List<TrashItem>> getTrashItems({required int ledgerId});

  /// 恢复一条：按快照重新记一笔（新 syncId，不复活云端那条），
  /// 分类/账户/标签在当前账本已不存在时自动丢弃。成功返回 true。
  Future<bool> restoreTrashItem(int trashId);

  /// 彻底删除一条回收站记录（不动已经删掉的交易）。
  Future<void> deleteTrashItem(int trashId);

  /// 清空某账本的回收站，返回清理条数。
  Future<int> clearTrash({required int ledgerId});

  /// 清理超过保留期的记录，返回清理条数。
  Future<int> purgeExpiredTrash();
}
