/// 项目 = 带固定前缀的标签。
///
/// 服务端（BeeCount-Cloud）同步白名单只有
/// `{transaction, account, category, tag, budget, ledger, exchange_rate_override}`，
/// 没有 project 实体，附件种类也只有 transaction / category_icon。新增实体要
/// 改服务端模型 + alembic + 分发 + 投影，官方镜像一升级就被覆盖。
///
/// 为了满足「换设备后项目一致：统一同步 / 统一备份 / 统一展示」，这里不建表、
/// 不加列，直接复用标签通道：
/// - 名称以 [prefix] 开头 → 是项目；
/// - 颜色沿用 `tags.color`，排序沿用 `tags.sort_order`；
/// - 账单归属沿用 `transaction_tags`（等价于服务端的 tagIds payload）。
///
/// 代价只有一个：标签名是全局唯一的，所以项目名不能与普通标签重名。前缀本身
/// 就能规避撞名，但所有展示点必须调用 [displayName] 把前缀剥掉。
class ProjectTags {
  const ProjectTags._();

  /// 项目标签的存储前缀。选 ◆ 是因为它不会出现在正常的账目标签命名里。
  static const prefix = '◆';

  /// 该标签名是否代表一个项目。
  static bool isProject(String? name) =>
      name != null && name.startsWith(prefix);

  /// 展示用名称（剥掉前缀）。
  static String displayName(String name) =>
      isProject(name) ? name.substring(prefix.length) : name;

  /// 存储用名称（补上前缀，已带则不重复加）。
  static String storageName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return trimmed;
    return isProject(trimmed) ? trimmed : '$prefix$trimmed';
  }

  /// 项目名的最大长度（前缀不计入，与标签 20 字上限对齐）。
  static const maxNameLength = 20;
}
