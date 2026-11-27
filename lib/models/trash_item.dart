import 'dart:convert';

/// 「最近删除」里的一笔账单快照。
///
/// 分类/账户/标签的名称一起存快照 —— 删除之后分类可能被改名或删掉，
/// 回收站仍要显示删除当时的样子；恢复时名称只用于展示，落库按 id 重新校验。
class TrashItem {
  const TrashItem({
    required this.id,
    required this.ledgerId,
    required this.type,
    required this.amount,
    required this.happenedAt,
    required this.deletedAt,
    this.ledgerName = '',
    this.syncId,
    this.note,
    this.categoryId,
    this.categoryName,
    this.accountId,
    this.accountName,
    this.toAccountId,
    this.toAccountName,
    this.currencyCode,
    this.nativeAmount,
    this.excludeFromStats = false,
    this.excludeFromBudget = false,
    this.tagIds = const [],
    this.tagNames = const [],
  });

  final int id;
  final int ledgerId;
  final String ledgerName;
  final String? syncId;
  final String type; // expense / income / transfer
  final double amount;
  final DateTime happenedAt;
  final DateTime deletedAt;
  final String? note;
  final int? categoryId;
  final String? categoryName;
  final int? accountId;
  final String? accountName;
  final int? toAccountId;
  final String? toAccountName;
  final String? currencyCode;
  final double? nativeAmount;
  final bool excludeFromStats;
  final bool excludeFromBudget;
  final List<int> tagIds;
  final List<String> tagNames;

  /// 展示用：备注优先，没有就显示分类名/转账。
  String label(String Function(String?) categoryLabel) {
    final n = note?.trim();
    if (n != null && n.isNotEmpty) return n;
    if (type == 'transfer') return accountName ?? '';
    return categoryLabel(categoryName);
  }

  Map<String, dynamic> toPayload() => {
        'type': type,
        'amount': amount,
        'happenedAt': happenedAt.toIso8601String(),
        'note': note,
        'categoryId': categoryId,
        'categoryName': categoryName,
        'accountId': accountId,
        'accountName': accountName,
        'toAccountId': toAccountId,
        'toAccountName': toAccountName,
        'currencyCode': currencyCode,
        'nativeAmount': nativeAmount,
        'excludeFromStats': excludeFromStats,
        'excludeFromBudget': excludeFromBudget,
        'tagIds': tagIds,
        'tagNames': tagNames,
      };

  /// 从数据库行还原。payload 解析失败时退化成一条最小记录，绝不抛异常
  /// （列表里出现一条「坏数据」不该让整个回收站打不开）。
  factory TrashItem.fromRow({
    required int id,
    required int ledgerId,
    required String ledgerName,
    required String? syncId,
    required String payload,
    required DateTime deletedAt,
  }) {
    Map<String, dynamic> map = const {};
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) map = decoded;
    } catch (_) {
      // 忽略，走下面的默认值
    }
    double asDouble(Object? v) => v is num ? v.toDouble() : 0;
    int? asInt(Object? v) => v is num ? v.toInt() : null;
    return TrashItem(
      id: id,
      ledgerId: ledgerId,
      ledgerName: ledgerName,
      syncId: syncId,
      type: (map['type'] as String?) ?? 'expense',
      amount: asDouble(map['amount']),
      happenedAt: DateTime.tryParse('${map['happenedAt']}') ??
          deletedAt.subtract(const Duration(days: 1)),
      deletedAt: deletedAt,
      note: map['note'] as String?,
      categoryId: asInt(map['categoryId']),
      categoryName: map['categoryName'] as String?,
      accountId: asInt(map['accountId']),
      accountName: map['accountName'] as String?,
      toAccountId: asInt(map['toAccountId']),
      toAccountName: map['toAccountName'] as String?,
      currencyCode: map['currencyCode'] as String?,
      nativeAmount: map['nativeAmount'] is num
          ? (map['nativeAmount'] as num).toDouble()
          : null,
      excludeFromStats: map['excludeFromStats'] == true,
      excludeFromBudget: map['excludeFromBudget'] == true,
      tagIds: (map['tagIds'] as List?)?.whereType<num>().map((e) => e.toInt()).toList() ??
          const [],
      tagNames: (map['tagNames'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

/// 恢复结果：成功恢复的笔数与跳过的笔数（分类/账户已不存在时置空但照样恢复，
/// 跳过只发生在交易本身已被彻底删除或账本不匹配时）。
class TrashRestoreResult {
  const TrashRestoreResult({required this.restored, required this.skipped});
  final int restored;
  final int skipped;
  int get total => restored + skipped;
}
