import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/features/overwrite/overwrite.dart';
import 'package:fl_clash/models/models.dart' hide FileInfo;
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NameAddEntry {
  final String title;
  final String? subtitle;

  const NameAddEntry({required this.title, this.subtitle});
}

/// One labelled block of addable names. [scene] namespaces the staging set, so
/// blocks that stage independently each get their own; a picker with a single
/// block leaves it null and shares the state's own key.
class NameAddSection {
  final String label;
  final String? scene;
  final List<NameAddEntry> entries;

  const NameAddSection({
    required this.label,
    required this.entries,
    this.scene,
  });
}

typedef NameAddSectionsBuilder =
    List<NameAddSection> Function(BuildContext context, WidgetRef ref);

/// The shared body of the custom-overwrite "add" sheets: sectioned lists of
/// names, each row staging itself into a `ProxyGroup` field through
/// [OverwriteStageFlowMixin].
class NameAddPicker extends ConsumerStatefulWidget {
  final String title;

  /// Base for the debounce tag. A section's scene is appended to it, matching
  /// how [OverwriteStageFlowMixin] derives its staging keys.
  final String stageTagPrefix;

  /// Scenes to register listeners for in `initState`. Must cover every scene
  /// [sectionsBuilder] can produce, since sections are only known at build.
  final List<String?> scenes;
  final ProxyGroup Function(ProxyGroup state, Set<dynamic> staged) apply;
  final NameAddSectionsBuilder sectionsBuilder;
  final double heightFactor;

  const NameAddPicker({
    super.key,
    required this.title,
    required this.stageTagPrefix,
    required this.apply,
    required this.sectionsBuilder,
    this.scenes = const [null],
    this.heightFactor = 0.8,
  });

  @override
  ConsumerState<NameAddPicker> createState() => _NameAddPickerState();
}

class _NameAddPickerState extends ConsumerState<NameAddPicker>
    with UniqueKeyStateMixin, OverwriteStageFlowMixin<NameAddPicker> {
  String _tagOf(String? scene) =>
      scene == null ? widget.stageTagPrefix : '${widget.stageTagPrefix}_$scene';

  @override
  void initState() {
    super.initState();
    for (final scene in widget.scenes) {
      listenForStageChanges(
        tag: _tagOf(scene),
        scene: scene,
        duration: const Duration(milliseconds: 350),
        apply: widget.apply,
      );
    }
  }

  Widget _buildItem({
    required NameAddEntry entry,
    required ItemPosition position,
    required bool dismiss,
    required VoidCallback onAdd,
  }) {
    final subtitle = entry.subtitle;
    return ExternalDismissible(
      effect: ExternalDismissibleEffect.resize,
      key: ValueKey(entry.title),
      dismiss: dismiss,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: ItemPositionProvider(
          position: position,
          child: DecorationListItem(
            minVerticalPadding: 8,
            title: TooltipText(
              text: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            subtitle: subtitle == null ? null : Text(subtitle),
            trailing: CommonMinIconButtonTheme(
              child: IconButton.filledTonal(
                tooltip: context.appLocalizations.add,
                onPressed: onAdd,
                icon: const Icon(Icons.add, size: 18),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSection(NameAddSection section, bool isLast) {
    final titles = section.entries.map((entry) => entry.title).toList();
    final dismissed = ref.watch(
      itemsProvider(section.scene == null ? key : '${key}_${section.scene}'),
    );
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: InfoHeader(info: Info(label: section.label)),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate((_, index) {
          final entry = section.entries[index];
          return _buildItem(
            entry: entry,
            position: ItemPosition.calculateVisualPosition(
              index,
              titles,
              dismissed,
            ),
            dismiss: dismissed.contains(entry.title),
            onAdd: () {
              handleStage(entry.title, section.scene);
            },
          );
        }, childCount: section.entries.length),
      ),
      if (!isLast) const SliverToBoxAdapter(child: SizedBox(height: 8)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final height = ref.sheetHeight(context, widget.heightFactor);
    final sections = widget
        .sectionsBuilder(context, ref)
        .where((section) => section.entries.isNotEmpty)
        .toList();
    return SizedBox(
      height: height,
      child: AdaptiveSheetScaffold(
        sheetTransparentToolBar: true,
        title: widget.title,
        body: sections.isEmpty
            ? NullStatus(label: appLocalizations.noData)
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(height: context.sheetTopPadding),
                  ),
                  for (var i = 0; i < sections.length; i++)
                    ..._buildSection(sections[i], i == sections.length - 1),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
      ),
    );
  }
}
