import '../../data/db.dart';
import '../../providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 定制：首次启动时内置三套账本分类模板。
/// 只补齐缺失的账本/分类，不动已有数据，重复启动安全。
class _Preset {
  const _Preset(this.ledgerName, this.tree);
  final String ledgerName;
  final Map<String, List<String>> tree; // 一级 -> 二级列表（空列表表示只建一级）
}

const _presets = <_Preset>[
  _Preset('家庭记账 · 主账本', {
    '食': ['买菜做饭', '外出就餐'],
    '衣': ['服装鞋帽', '洗护美妆'],
    '住': ['房贷/房租', '物业水电', '家居日用', '大件采购'],
    '行': ['公共交通', '打车', '自驾'],
    '娱': ['休闲娱乐', '旅游度假', '学习提升'],
    '人情': ['红包礼金', '送礼请客', '孝敬长辈'],
    '宠物': ['宠物食品', '宠物用品', '宠物医疗'],
    '医疗': ['看病买药', '健康保险'],
    '其他': ['杂项支出'],
  }),
  _Preset('投资账本', {
    '支付宝': ['货币基金', '基金'],
    '微信': ['货币基金', '基金'],
    '雪球': ['基金'],
    '华宝': ['股票', '理财'],
  }),
  _Preset('旅游专项账本', {
    '大交通': [],
    '住宿': [],
    '当地交通': [],
    '餐饮': [],
    '游玩购物': [],
  }),
];

// 冷启动与分类页可能同时触发 seed；并发时复用同一次执行，避免重复建账本。
Future<void>? _runningSeed;

Future<void> seedPresetLedgers(WidgetRef ref) {
  final running = _runningSeed;
  if (running != null) return running;
  final task = _seedPresetLedgers(ref).whenComplete(() => _runningSeed = null);
  _runningSeed = task;
  return task;
}

Future<void> _seedPresetLedgers(WidgetRef ref) async {
  final repo = ref.read(repositoryProvider);
  final ledgers = await repo.getAllLedgers();
  final categories = await repo.getAllCategories();

  Ledger? findLedger(String name) {
    for (final l in ledgers) {
      if (l.name == name) return l;
    }
    return null;
  }

  Category? findCategory(String name, int ledgerId, int? parentId) {
    for (final c in categories) {
      if (c.name == name &&
          c.kind == 'expense' &&
          c.ledgerId == ledgerId &&
          c.parentId == parentId) {
        return c;
      }
    }
    return null;
  }

  for (final preset in _presets) {
    var ledger = findLedger(preset.ledgerName);
    if (ledger == null) {
      final id = await repo.createLedger(name: preset.ledgerName);
      ledger = await repo.getLedgerById(id);
      if (ledger != null) ledgers.add(ledger);
    }
    if (ledger == null) continue;

    var order = 0;
    for (final entry in preset.tree.entries) {
      var parent = findCategory(entry.key, ledger.id, null);
      if (parent == null) {
        final id = await repo.createCategory(
          name: entry.key,
          kind: 'expense',
          ledgerId: ledger.id,
          sortOrder: order,
        );
        parent = await repo.getCategoryById(id);
        if (parent != null) categories.add(parent);
      }
      order++;
      if (parent == null) continue;

      var childOrder = 0;
      for (final childName in entry.value) {
        if (findCategory(childName, ledger.id, parent.id) != null) {
          childOrder++;
          continue;
        }
        final id = await repo.createSubCategory(
          parentId: parent.id,
          name: childName,
          kind: 'expense',
          ledgerId: ledger.id,
          sortOrder: childOrder,
        );
        final child = await repo.getCategoryById(id);
        if (child != null) categories.add(child);
        childOrder++;
      }
    }
  }
}
