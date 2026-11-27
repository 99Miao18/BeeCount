import 'dart:async';

import 'package:beecount_business_ui/beecount_business_ui.dart';
import 'package:beecount_ui/beecount_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db.dart';
import '../../l10n/app_localizations.dart';
import '../../providers.dart';
import '../../services/billing/post_processor.dart';
import '../../services/data/tag_seed_service.dart';
import '../../services/project/project_tags.dart';
import '../tag/detail/bindings/tag_detail.dart' show tagDetailColor;
import '../tag/editor/bindings/tag_editor.dart';

/// 新建 / 编辑项目。
///
/// 项目不是独立实体，落库时用 [ProjectTags.storageName] 写入带前缀的标签名，
/// 因此校重名、写库、同步都复用标签那套逻辑，不需要额外通道。
class ProjectEditSheet extends ConsumerStatefulWidget {
  const ProjectEditSheet({super.key, this.project});
  final Tag? project;

  static Future<Tag?> show(BuildContext context, {Tag? project}) =>
      showModalBottomSheet<Tag>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          // 键盘弹起时 BeeSheet 会垫上 viewInsets；限高后剩余内容改为滚动，
          // 否则色板 + 保存键会顶出屏幕（Bottom overflowed）。
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .86),
          backgroundColor: BeeCardTheme.of(context).overlay,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
          builder: (_) => ProjectEditSheet(project: project));

  @override
  ConsumerState<ProjectEditSheet> createState() => _ProjectEditSheetState();
}

class _ProjectEditSheetState extends ConsumerState<ProjectEditSheet> {
  late final _name = TextEditingController(
      text: ProjectTags.displayName(widget.project?.name ?? ''));
  late String _color =
      widget.project?.color ?? TagSeedService.getRandomColor();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l = AppLocalizations.of(context);
    // 「|」是账本钥匙的分隔符，名字里出现会把解析弄乱，直接剔除。
    final name = _name.text.trim().replaceAll(ProjectTags.scopeSeparator, '');
    if (name.isEmpty) {
      showBeeToast(context, l.projectNameRequired, tone: BeeTone.error);
      return;
    }
    setState(() => _saving = true);
    try {
      // 新建时把当前账本的钥匙编进名字（不同账本允许同名项目）；改名沿用
      // 原标签的钥匙，避免把项目「搬」到别的账本。
      final scope = widget.project == null
          ? await ref.read(currentProjectScopeProvider.future)
          : ProjectTags.parse(widget.project!.name).scope;
      final saved = await saveTagDraft(ref.read(repositoryProvider),
          name: ProjectTags.storageName(name, scope: scope),
          color: _color,
          existing: widget.project);
      if (!mounted) return;
      ref.read(tagListRefreshProvider.notifier).state++;
      final ledger = ref.read(currentLedgerIdProvider);
      if (ledger > 0) unawaited(PostProcessor.sync(ref, ledgerId: ledger));
      showBeeToast(context,
          widget.project == null ? l.projectCreateSuccess : l.projectUpdateSuccess,
          tone: BeeTone.success);
      Navigator.pop(context, saved);
    } on DuplicateTagName {
      if (mounted) {
        showBeeToast(context, l.tagNameDuplicate, tone: BeeTone.error);
      }
    } catch (e) {
      if (mounted) {
        showBeeToast(context, '${l.commonError}: $e', tone: BeeTone.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = TagSeedService.getColorPalette();
    return BeeSheet(
        title: widget.project == null ? l.projectCreateTitle : l.projectEditTitle,
        footer: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: BeeButton(
                label: l.commonSave, onPressed: _saving ? null : _save)),
        child: SingleChildScrollView(
            // 色板三行，小屏 + 键盘时必须能滚，不能溢出到红黑条。
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
              BeeSurface(
                  child: Row(children: [
                Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: tagDetailColor(_color, Colors.grey),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                        _name.text.trim().isEmpty
                            ? ProjectTags.prefix
                            : _name.text.trim().substring(0, 1),
                        style: const TextStyle(
                            fontSize: 15,
                            color: Colors.white,
                            fontWeight: FontWeight.w600))),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        _name.text.trim().isEmpty
                            ? l.projectNameLabel
                            : _name.text.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)))
              ])),
              const SizedBox(height: 12),
              BeeSurface(
                  child: BeeField(
                      label: l.projectNameLabel,
                      hint: l.projectNameHint,
                      controller: _name,
                      maxLength: ProjectTags.maxNameLength,
                      onChanged: (_) => setState(() {}))),
              const SizedBox(height: 12),
              BeeSurface(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Text(l.tagColorLabel,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    BeeColorPalette<String>(
                        value: _color,
                        items: [
                          for (final hex in colors)
                            BeeColorOption(
                                value: hex,
                                color: tagDetailColor(hex, Colors.grey),
                                label: '${l.tagColorLabel} $hex')
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _color = value))
                  ])),
            ])));
  }
}
