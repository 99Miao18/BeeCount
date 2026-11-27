import 'dart:math' as math;

import 'package:beecount_business_ui/beecount_business_ui.dart';
import 'package:beecount_ui/beecount_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/project_providers.dart';
import '../../services/project/project_tags.dart';
import '../tag/detail/bindings/tag_detail.dart' show tagDetailColor;
import 'project_edit_sheet.dart';

/// 项目选择结果。用一个包装类区分「选了/清了」（[tagId] 为 null）
/// 和「用户取消」（整个返回值为 null）。
class ProjectPickResult {
  const ProjectPickResult(this.tagId);
  final int? tagId;
}

/// 记账页「项目」chip 点开的弹层：单选项目，可新建，可清空。
///
/// 只做选择，不写库；选中结果交回调用方，由调用方并入账单的 tagIds。
class ProjectPickerSheet extends ConsumerWidget {
  const ProjectPickerSheet(
      {super.key, required this.ledgerId, this.selectedTagId});

  final int ledgerId;
  final int? selectedTagId;

  static Future<ProjectPickResult?> show(BuildContext context,
          {required int ledgerId, int? selectedTagId}) =>
      showModalBottomSheet<ProjectPickResult>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: BeeCardTheme.of(context).overlay,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          builder: (_) =>
              ProjectPickerSheet(ledgerId: ledgerId, selectedTagId: selectedTagId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final usage = ref.watch(projectUsageProvider);
    final rows = usage.valueOrNull ?? const <ProjectUsage>[];
    final theme = Theme.of(context);

    return BeeSheet(
        title: l.projectPickTitle,
        footer: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: BeeButton(
                label: l.projectCreateTitle,
                onPressed: () async {
                  final tag = await ProjectEditSheet.show(context);
                  if (tag != null && context.mounted) {
                    Navigator.pop(context, ProjectPickResult(tag.id));
                  }
                })),
        child: SizedBox(
            height: math.min(MediaQuery.sizeOf(context).height * .52, 380),
            child: usage.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(
                    child: BeeStatus(
                        label: l.commonError,
                        tone: BeeTone.error,
                        action: BeeButton(
                            label: l.v4RecordingRetry,
                            onPressed: () =>
                                ref.invalidate(projectUsageProvider)))),
                data: (_) => ListView(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        children: [
                          _Tile(
                              title: l.projectClearSelection,
                              selected: selectedTagId == null,
                              leading: Icon(Icons.block,
                                  size: 20, color: theme.hintColor),
                              onTap: () =>
                                  Navigator.pop(context, const ProjectPickResult(null))),
                          const Divider(height: 16),
                          if (rows.isEmpty)
                            Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    10, 18, 10, 18),
                                child: Text(l.projectEmptySubtitle,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: theme.hintColor))),
                          for (final item in rows)
                            _Tile(
                                title: ProjectTags.displayName(item.tag.name),
                                subtitle: l.tagTransactionCount(
                                    item.transactionCount),
                                color: tagDetailColor(item.tag.color,
                                    theme.colorScheme.primary),
                                selected: item.tag.id == selectedTagId,
                                onTap: () => Navigator.pop(
                                    context, ProjectPickResult(item.tag.id))),
                        ]))));
  }
}

class _Tile extends StatelessWidget {
  const _Tile(
      {required this.title,
      required this.selected,
      required this.onTap,
      this.subtitle,
      this.color,
      this.leading});

  final String title;
  final String? subtitle;
  final Color? color;
  final Widget? leading;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(children: [
              if (leading != null)
                SizedBox(width: 34, child: Center(child: leading))
              else
                Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: color ?? primary,
                        borderRadius: BorderRadius.circular(9)),
                    child: Text(
                        ProjectTags.displayName(title).isEmpty
                            ? ProjectTags.prefix
                            : ProjectTags.displayName(title).substring(0, 1),
                        style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w600))),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: theme.hintColor))
                    ]
                  ])),
              if (selected)
                Icon(Icons.check, size: 20, color: primary)
              else
                const SizedBox(width: 20),
            ])));
  }
}
