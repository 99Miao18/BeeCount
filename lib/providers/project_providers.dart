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
final projectUsageProvider =
    StreamProvider.autoDispose<List<ProjectUsage>>((ref) {
  ref.watch(tagListRefreshProvider);
  final ledgerId = ref.watch(currentLedgerIdProvider);
  final repo = ref.watch(repositoryProvider);
  return repo.watchProjectUsage(ledgerId);
});
