import 'package:drift/drift.dart' show Variable;

import '../data/db.dart';
import '../services/project/project_tags.dart';

/// 项目（`◆` 前缀标签）的账本归属查询。
///
/// 新项目把账本钥匙编进标签名（见 [ProjectTags]），直接比字符串即可；旧版
/// 项目没有钥匙，只能按「它实际记过账的账本」反推归属 —— 这里就是那份统计。
extension ProjectScopeQueries on BeeDatabase {
  /// 返回（本账本用过的项目 id, 任意账本用过的项目 id）。
  ///
  /// 只扫项目标签，普通标签不进集合；共享账本 Editor 记账走
  /// `transaction_tag_overrides`，与项目用量聚合保持同一口径（不覆盖）。
  Future<({Set<int> usedHere, Set<int> usedAnywhere})> projectTagUsage(
      int ledgerId) async {
    final rows = await customSelect(
      '''
      SELECT tt.tag_id AS tag_id,
             MAX(CASE WHEN x.ledger_id = ?1 THEN 1 ELSE 0 END) AS used_here
      FROM transaction_tags tt
      INNER JOIN transactions x ON x.id = tt.transaction_id
      INNER JOIN tags t ON t.id = tt.tag_id
      WHERE t.name LIKE ?2
      GROUP BY tt.tag_id
      ''',
      variables: [
        Variable.withInt(ledgerId),
        Variable.withString('${ProjectTags.prefix}%'),
      ],
      readsFrom: {tags, transactionTags, transactions},
    ).get();
    final usedHere = <int>{};
    final usedAnywhere = <int>{};
    for (final row in rows) {
      final id = row.read<int>('tag_id');
      usedAnywhere.add(id);
      if (row.read<int>('used_here') == 1) usedHere.add(id);
    }
    return (usedHere: usedHere, usedAnywhere: usedAnywhere);
  }
}
