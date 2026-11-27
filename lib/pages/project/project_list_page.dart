import 'package:beecount_business_ui/beecount_business_ui.dart';
import 'package:beecount_ui/beecount_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../providers/project_providers.dart';
import '../../services/project/project_tags.dart';
import '../../utils/currencies.dart';
import '../../utils/format_money.dart';
import '../shared/scaffold/widgets/page_scaffold.dart';
import '../tag/detail/bindings/tag_detail.dart' show tagDetailColor;
import '../tag/tag_detail_page.dart';
import 'project_edit_sheet.dart';

/// 项目列表：当前账本里的项目及各自花销。
///
/// 项目复用标签通道（见 [ProjectTags]），所以这里的「编辑 / 删除 / 分类分布 /
/// 账单列表」全部落在既有的 [TagDetailPage] 上，不重复实现统计口径。
class ProjectListPage extends ConsumerWidget {
  const ProjectListPage({super.key});

  String _range(DateTime? first, DateTime? last) {
    if (first == null || last == null) return '';
    String fmt(DateTime d) => d.year == DateTime.now().year
        ? '${d.month}/${d.day}'
        : '${d.year}/${d.month}/${d.day}';
    final a = fmt(first), b = fmt(last);
    return a == b ? a : '$a – $b';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final usage = ref.watch(projectUsageProvider);
    final book = ref.watch(currentLedgerProvider).valueOrNull;
    final hide = ref.watch(hideAmountsProvider);
    final symbol = getDistinctCurrencySymbol(book?.currency ?? 'CNY');
    final items = usage.valueOrNull ?? const <ProjectUsage>[];
    final hasForeign = items.any((item) => item.foreignCount > 0);

    Widget empty = BeeEmptyState(
        icon: const BeeLineIcon('FolderOpen', size: 36),
        title: l.projectEmptyTitle,
        message: l.projectEmptySubtitle,
        action: BeeButton(
            label: l.projectCreateTitle,
            onPressed: () => ProjectEditSheet.show(context)));

    return V4PageScaffold(
        body: Column(children: [
      BeePageHeader(
          title: l.projectTitle,
          leading: const BackButton(),
          actions: [
            BeeIconButton(
                label: l.projectCreateTitle,
                icon: const BeeLineIcon('Plus'),
                onPressed: () => ProjectEditSheet.show(context))
          ]),
      Expanded(
          child: usage.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                  child: BeeStatus(
                      label: l.commonError,
                      tone: BeeTone.error,
                      action: BeeButton(
                          label: l.v4RecordingRetry,
                          onPressed: () =>
                              ref.invalidate(projectUsageProvider)))),
              data: (rows) => rows.isEmpty
                  ? empty
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(17, 4, 17, 28),
                      children: [
                          for (final item in rows)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _tile(
                                    context, l, item, symbol, hide)),
                          if (hasForeign)
                            Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(l.projectForeignNotice,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color:
                                            Theme.of(context).hintColor))),
                        ]))),
    ]));
  }

  Widget _tile(BuildContext context, AppLocalizations l, ProjectUsage item,
      String symbol, bool hide) {
    final theme = Theme.of(context);
    final color = tagDetailColor(item.tag.color, theme.colorScheme.primary);
    final name = ProjectTags.displayName(item.tag.name);
    final foreign = item.foreignCount > 0;
    final subtitle = [
      l.tagTransactionCount(item.transactionCount),
      _range(item.firstAt, item.lastAt),
    ].where((part) => part.isNotEmpty).join(' · ');
    final amount = foreign
        ? '—'
        : hide
            ? '••••'
            : '$symbol${formatMoneyCompact(item.expense, trimZeros: false)}';
    return BeeSurface(
        child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                    builder: (_) => TagDetailPage(
                        tagId: item.tag.id, tagName: item.tag.name))),
            child: Row(children: [
              Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: color, borderRadius: BorderRadius.circular(11)),
                  child: Text(name.isEmpty ? ProjectTags.prefix : name.substring(0, 1),
                      style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w600))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: theme.hintColor))
                    ]
                  ])),
              const SizedBox(width: 8),
              Text(amount,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: foreign ? theme.hintColor : theme.colorScheme.onSurface)),
              const SizedBox(width: 4),
              BeeLineIcon('ChevronRight', size: 15, color: theme.hintColor),
            ])));
  }
}
