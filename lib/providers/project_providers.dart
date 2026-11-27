import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db.dart';
import 'database_providers.dart';
import 'tag_providers.dart';

/// 项目列表的一行用量（当前账本口径）。
typedef ProjectUsage = ({
  Tag tag,
  int transactionCount,
  double expense,
  double income,
  int foreignCount,
  DateTime? firstAt,
  DateTime? lastAt,
});

/// 当前账本内的项目及用量。
///
/// 项目不是独立实体，而是带 `ProjectTags.prefix` 前缀的标签（详见
/// `services/project/project_tags.dart`）。这样项目天然走标签的同步 / 备份 /
/// 多设备展示通道，不需要改服务端，也不会出现「本机有、另一台没有」。
///
/// 标签本身是账号级的，归属过滤统一在 [tagsForCurrentLedgerProvider] 里做
/// （带账本钥匙的只看本账本，旧版项目看实际用过的账本），这里只保留那份名单
/// 里的项目 —— 否则一个「云南」会在所有账本里都出现，两个「云南」还会被算成
/// 同一行。
final projectUsageProvider =
    StreamProvider.autoDispose<List<ProjectUsage>>((ref) {
  ref.watch(tagListRefreshProvider);
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);
  final visible = ref.watch(tagsForCurrentLedgerProvider).valueOrNull;
  // 名单还没算出来（首帧 / 账本切换中）先不发射，避免闪一下「没有项目」。
  if (visible == null) return const Stream<List<ProjectUsage>>.empty();
  final ids = {for (final tag in visible) tag.id};
  return repo.watchProjectUsage(ledgerId).map((items) => [
        for (final item in items)
          if (ids.contains(item.tag.id)) item,
      ]);
});
