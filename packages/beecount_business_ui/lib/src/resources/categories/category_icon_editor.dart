import 'package:beecount_ui/beecount_ui.dart';
import 'package:flutter/material.dart';

enum BeeCategoryIconSource { preset, custom }

/// 分组内部的分段：同一个 tab 里按场景再切块，[label] 非空时在图标前显示一行
/// 小标题。图标很多的分组（例如彩色图标）靠它保持可定位，避免一大片平铺。
class BeeCategoryIconSection {
  const BeeCategoryIconSection({this.label = '', required this.items});
  final String label;
  final List<BeeIconChoice<String>> items;
}

class BeeCategoryIconGroup {
  const BeeCategoryIconGroup(
      {required this.id,
      required this.label,
      required this.items,
      this.sections = const []});
  final String id, label;
  final List<BeeIconChoice<String>> items;

  /// 为空表示整组平铺（沿用 [items]）；非空时按分段渲染。
  final List<BeeCategoryIconSection> sections;

  /// 实际参与渲染的段：没有分段数据时退化成单段。
  List<BeeCategoryIconSection> get effectiveSections => sections.isEmpty
      ? [BeeCategoryIconSection(items: items)]
      : sections;
}

/// Controlled icon/source selection. Image picking, cropping, files and saving
/// remain in the App; opening a group never changes the selected icon.
class BeeCategoryIconEditor extends StatefulWidget {
  const BeeCategoryIconEditor({
    super.key,
    required this.source,
    required this.value,
    required this.groups,
    required this.commonItems,
    required this.presetLabel,
    required this.customLabel,
    required this.commonLabel,
    required this.imageHint,
    required this.chooseImageLabel,
    required this.onSourceChanged,
    required this.onChanged,
    required this.onChooseImage,
    this.preview,
    this.locateByValue = true,
    this.loading = false,
    this.enabled = true,
    this.iconExtent = 24,
  });
  final BeeCategoryIconSource source;
  final String value;
  final List<BeeCategoryIconGroup> groups;
  final List<BeeIconChoice<String>> commonItems;
  final String presetLabel,
      customLabel,
      commonLabel,
      imageHint,
      chooseImageLabel;
  final ValueChanged<BeeCategoryIconSource> onSourceChanged;
  final ValueChanged<String> onChanged;
  final VoidCallback onChooseImage;
  final Widget? preview;

  /// 是否按 [value] 自动定位到所在分组；新建分类时图标还是占位值，可以关掉
  /// 直接停在第一组，避免被占位值带到别的分组。
  final bool locateByValue;
  final bool loading, enabled;

  /// 单格图标边长；彩色图标带底色块，会显得比线框小，宿主可以调大一点。
  final double iconExtent;

  @override
  State<BeeCategoryIconEditor> createState() => _BeeCategoryIconEditorState();
}

class _BeeCategoryIconEditorState extends State<BeeCategoryIconEditor> {
  String group = '';
  @override
  void initState() {
    super.initState();
    if (widget.locateByValue &&
        !widget.commonItems.any((item) => item.value == widget.value)) {
      for (final candidate in widget.groups) {
        final hit = candidate.effectiveSections
            .any((s) => s.items.any((item) => item.value == widget.value));
        if (hit) {
          group = candidate.id;
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = [
      // 常用栏可以不配；为空时整栏不出现，避免留下一个空 tab。
      if (widget.commonItems.isNotEmpty)
        BeeCategoryIconGroup(
            id: '', label: widget.commonLabel, items: widget.commonItems),
      ...widget.groups
    ];
    final active =
        all.firstWhere((g) => g.id == group, orElse: () => all.first);
    final enabled = widget.enabled && !widget.loading;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final source in BeeCategoryIconSource.values) ...[
          if (source == BeeCategoryIconSource.custom) const SizedBox(width: 8),
          Expanded(
              child: BeeChoiceChip(
                  label: source == BeeCategoryIconSource.preset
                      ? widget.presetLabel
                      : widget.customLabel,
                  selected: source == widget.source,
                  onSelected:
                      enabled ? (_) => widget.onSourceChanged(source) : null))
        ]
      ]),
      const SizedBox(height: 12),
      if (widget.source == BeeCategoryIconSource.preset) ...[
        SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final candidate in all)
                Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: BeeChoiceChip(
                        compact: true,
                        label: candidate.label,
                        selected: active.id == candidate.id,
                        onSelected: enabled
                            ? (_) => setState(() => group = candidate.id)
                            : null))
            ])),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, size) {
          final columns = ((size.maxWidth + 6) / 50).floor().clamp(1, 6);
          Widget grid(BeeCategoryIconSection section) =>
              BeeIconChoiceGrid<String>(
                  items: section.items
                      .map((item) => BeeIconChoice<String>(
                          value: item.value,
                          label: item.label,
                          icon: item.icon,
                          enabled: enabled && item.enabled))
                      .toList(),
                  value: widget.value,
                  columns: columns,
                  showLabels: false,
                  iconSize: widget.iconExtent,
                  onChanged: widget.onChanged);
          final sections = active.effectiveSections;
          if (sections.length == 1 && sections.first.label.isEmpty) {
            return grid(sections.first);
          }
          final captionStyle = TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant);
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < sections.length; i++) ...[
                  if (sections[i].label.isNotEmpty) ...[
                    if (i > 0) const SizedBox(height: 14),
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(sections[i].label, style: captionStyle)),
                  ] else if (i > 0)
                    const SizedBox(height: 16),
                  grid(sections[i]),
                ]
              ]);
        })
      ] else ...[
        Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: BeeCardTheme.of(context).soft,
                borderRadius: BorderRadius.circular(13)),
            child: Row(children: [
              SizedBox(
                  width: 72,
                  height: 72,
                  child: widget.loading
                      ? const Center(
                          child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : widget.preview ??
                          const Center(
                              child: BeeLineIcon('ImagePlus', size: 28))),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(widget.imageHint,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: Theme.of(context).hintColor)))
            ])),
        const SizedBox(height: 12),
        BeeButton(
            label: widget.chooseImageLabel,
            icon: const BeeLineIcon('ImagePlus', size: 18),
            kind: BeeButtonKind.secondary,
            onPressed: enabled ? widget.onChooseImage : null)
      ]
    ]);
  }
}
