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
/// 但标签是 **账号级全局** 的（`tags` 表没有 ledger_id，同步也按 user-global
/// 推送），天然会在所有账本里串门。项目必须按账本隔离，而账本身份又不能存进
/// 本地表（换手机就丢），所以这里把账本钥匙编进标签名：
///
/// ```
/// ◆<账本钥匙>|<项目名>      例：◆a1b2c3d4|云南
/// ```
///
/// 钥匙 = 账本 `sync_id` 的前 8 位（同一账本在两台手机上完全一致），账本还没
/// 同步过时退化为 `L<本地 id>`。这样两个账本可以各有一个「云南」，它们是两个
/// 独立标签（名字不同、计数各自独立），服务端也只是两个普通标签，不需要任何
/// 服务端改动。
///
/// 旧版数据（只有 `◆云南`、没有钥匙）保留兼容：按「它实际记过账的账本」判定
/// 归属，见 [belongsToLedger]。
class ProjectTags {
  const ProjectTags._();

  /// 项目标签的存储前缀。选 ◆ 是因为它不会出现在正常的账目标签命名里。
  static const prefix = '◆';

  /// 钥匙与项目名之间的分隔符。项目名里的同名字符会在 [storageName] 里剔除。
  static const scopeSeparator = '|';

  /// 钥匙最大长度（取 syncId 前 8 位）。
  static const scopeLength = 8;

  static final RegExp _scopePattern = RegExp(r'^[0-9a-zA-Z]{1,12}$');

  /// 该标签名是否代表一个项目。
  static bool isProject(String? name) =>
      name != null && name.startsWith(prefix);

  /// 账本钥匙：优先用账本 sync_id（跨设备一致），没有则退化为本地 id。
  static String scopeKey({String? ledgerSyncId, required int ledgerId}) {
    final cleaned =
        (ledgerSyncId ?? '').replaceAll(RegExp(r'[^0-9a-zA-Z]'), '');
    if (cleaned.isEmpty) return localScopeKey(ledgerId);
    return cleaned.length <= scopeLength
        ? cleaned
        : cleaned.substring(0, scopeLength);
  }

  /// 账本还没同步过时的临时钥匙。只在本机有效，用于「同一个账本」的兜底匹配。
  static String localScopeKey(int ledgerId) => 'L$ledgerId';

  /// 拆出（账本钥匙, 展示名）。旧版无钥匙时 scope 为 null。
  static ({String? scope, String name}) parse(String rawName) {
    if (!isProject(rawName)) return (scope: null, name: rawName);
    final body = rawName.substring(prefix.length);
    final index = body.indexOf(scopeSeparator);
    if (index <= 0 || index >= body.length - 1) {
      return (scope: null, name: body);
    }
    final scope = body.substring(0, index);
    if (!_scopePattern.hasMatch(scope)) return (scope: null, name: body);
    return (scope: scope, name: body.substring(index + 1));
  }

  /// 展示用名称（剥掉前缀与账本钥匙）。
  static String displayName(String name) {
    if (!isProject(name)) return name;
    return parse(name).name;
  }

  /// 存储用名称（补上前缀与账本钥匙，已带则不重复加）。
  static String storageName(String name, {String? scope}) {
    var trimmed = name.trim().replaceAll(scopeSeparator, '');
    if (isProject(trimmed)) trimmed = parse(trimmed).name;
    if (trimmed.isEmpty) return trimmed;
    if (scope == null || scope.isEmpty) return '$prefix$trimmed';
    return '$prefix$scope$scopeSeparator$trimmed';
  }

  /// 项目是否属于某个账本。
  ///
  /// - 带钥匙：只认当前账本的钥匙（含本机临时钥匙）；
  /// - 旧版无钥匙：按实际使用账本判定，避免历史项目在别的账本里冒出来；
  ///   一笔都没用过的孤儿项目放行，否则升级后再也找不到它。
  static bool belongsToLedger(
    String rawName, {
    required String scope,
    String? localScope,
    required bool usedInLedger,
    required bool usedAnywhere,
  }) {
    if (!isProject(rawName)) return true;
    final key = parse(rawName).scope;
    if (key != null) return key == scope || key == localScope;
    return usedInLedger || !usedAnywhere;
  }

  /// 项目名的最大长度（前缀与钥匙不计入，与标签 20 字上限对齐）。
  static const maxNameLength = 20;
}
