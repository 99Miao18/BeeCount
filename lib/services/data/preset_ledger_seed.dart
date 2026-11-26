import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';

/// 定制：新建账本时可套用的内置账本模板。
/// 模板本身不是账本，首次启动不会自动创建任何账本；只有用户新建账本并选择模板时，
/// 才把模板里的分类复制成该账本的独立副本。
class PresetCategory {
  const PresetCategory(this.kind, this.name, [this.children = const <String>[]]);

  final String kind; // expense / income
  final String name;
  final List<String> children;
}

class LedgerTemplate {
  const LedgerTemplate(this.key, this.name, this.categories);

  final String key;
  final String name;
  final List<PresetCategory> categories;
}

const presetLedgerTemplates = <LedgerTemplate>[
  // 蜜蜂账本 = App 原版自带的那套通用分类，留给「想按原版习惯记账」或
  // 从旧版本升级上来、需要有个地方放通用分类的场景。名字特意叫「蜜蜂账本」，
  // 一眼能认出它就是原版默认分类，不是自己新建的账本。
  LedgerTemplate('default', '蜜蜂账本', [
    PresetCategory('expense', '餐饮', ['买菜做饭', '外出就餐']),
    PresetCategory('expense', '交通', ['公共交通', '打车', '自驾']),
    PresetCategory('expense', '购物', ['日用品', '服饰鞋包']),
    PresetCategory('expense', '居家', ['房贷/房租', '物业水电', '家居日用']),
    PresetCategory('expense', '娱乐', ['休闲娱乐', '学习提升']),
    PresetCategory('expense', '医疗', ['看病买药', '健康保险']),
    PresetCategory('expense', '其他', ['杂项支出']),
    PresetCategory('income', '工资', ['月薪', '奖金']),
    PresetCategory('income', '理财', ['利息', '基金收益']),
    PresetCategory('income', '其他收入'),
  ]),
  LedgerTemplate('family', '家庭账本', [
    PresetCategory('expense', '食', ['买菜做饭', '外出就餐']),
    PresetCategory('expense', '衣', ['服装鞋帽', '洗护美妆']),
    PresetCategory('expense', '住', ['房贷/房租', '物业水电', '家居日用', '大件采购']),
    PresetCategory('expense', '行', ['公共交通', '打车', '自驾']),
    PresetCategory('expense', '娱', ['休闲娱乐', '旅游度假', '学习提升']),
    PresetCategory('expense', '人情', ['红包礼金', '送礼请客', '孝敬长辈']),
    PresetCategory('expense', '宠物', ['宠物食品', '宠物用品', '宠物医疗']),
    PresetCategory('expense', '医疗', ['看病买药', '健康保险']),
    PresetCategory('expense', '其他', ['杂项支出']),
    PresetCategory('income', '工资'),
    PresetCategory('income', '奖金'),
    PresetCategory('income', '房租收入'),
    PresetCategory('income', '福利'),
    PresetCategory('income', '分成'),
    PresetCategory('income', '其他'),
  ]),
  // 旅游以支出为主，收入只留「意外之喜」（退款、返现、中奖等零星进账）。
  LedgerTemplate('travel', '旅游账本', [
    PresetCategory('expense', '大交通'),
    PresetCategory('expense', '住宿'),
    PresetCategory('expense', '当地交通'),
    PresetCategory('expense', '餐饮'),
    PresetCategory('expense', '游玩购物'),
    PresetCategory('income', '意外之喜'),
  ]),
  LedgerTemplate('investment', '投资账本', [
    // 你的表头写明「支出与收入相同」：收支两侧镜像同一套平台树，
    // 这样「某平台一年盈亏」才等于 收入侧金额 - 支出侧金额，
    // 且洞察页会把二级（资产类型）上卷到一级（平台）显示合计。
    // 记账约定：赚了记收入、亏了记支出，每个平台每年只记一笔净额。
    PresetCategory('expense', '支付宝', ['余额宝', '支付宝基金']),
    PresetCategory('expense', '微信', ['货币基金', '微信基金']),
    PresetCategory('expense', '雪球', ['雪球基金']),
    PresetCategory('expense', '华宝', ['华宝股票', '华宝理财']),
    PresetCategory('income', '支付宝', ['余额宝', '支付宝基金']),
    PresetCategory('income', '微信', ['货币基金', '微信基金']),
    PresetCategory('income', '雪球', ['雪球基金']),
    PresetCategory('income', '华宝', ['华宝股票', '华宝理财']),
  ]),
];

/// 把模板内全部一/二级分类复制到指定账本。
/// 每个分类都用新建的 syncId，副本独立，删除互不影响。
Future<void> applyPresetLedgerTemplate(
  BaseRepository repo,
  int ledgerId,
  LedgerTemplate template,
) async {
  var order = 0;
  for (final category in template.categories) {
    final parentId = await repo.createCategory(
      name: category.name,
      kind: category.kind,
      ledgerId: ledgerId,
      sortOrder: order++,
    );
    var childOrder = 0;
    for (final childName in category.children) {
      await repo.createSubCategory(
        parentId: parentId,
        name: childName,
        kind: category.kind,
        ledgerId: ledgerId,
        sortOrder: childOrder++,
      );
    }
  }
}
