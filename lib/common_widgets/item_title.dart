import 'dart:async';
import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:apexo/utils/que.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' show CircleAvatar;
import '../core/model.dart';

/// The title's first whole character: taking a substring would split an emoji's
/// surrogate pair, which Flutter rejects as malformed UTF-16.
String initialOf(Model item) {
  final title = item.title.isEmpty ? " " : item.title;
  return String.fromCharCode(title.runes.first);
}

class TreatmentLabel {
  TreatmentLabel(
      {required this.string,
      required this.color,
      required this.icon,
      this.iso,
      this.extraNote});
  Color color;
  String string;
  IconData icon;
  String? iso;
  String? extraNote;
}

class ItemTitle extends StatefulWidget {
  const ItemTitle({
    super.key,
    required this.item,
    this.radius = 15,
    this.maxWidth = 130.0,
    this.labels = const [],
    this.icon,
    this.archivedStyling = true,
    this.predefinedColor,
    this.fontSize,
  });
  final Model item;
  final double radius;
  final double maxWidth;
  final IconData? icon;
  final bool archivedStyling;
  final Color? predefinedColor;
  final double? fontSize;
  final List<TreatmentLabel> labels;

  @override
  State<ItemTitle> createState() => _ItemTitleState();
}

class _ItemTitleState extends State<ItemTitle> {
  @override
  Widget build(BuildContext context) {
    final Color color = widget.predefinedColor ??
        (widget.item.archived == true && widget.archivedStyling
            ? FluentTheme.of(context).shadowColor.withValues(alpha: 0.2)
            : widget.item.color);
    return SizedBox(
      width: 200,
      child: Row(children: [
        if (widget.radius > 0)
          ItemAvatar(
            item: widget.item,
            radius: widget.radius,
            icon: widget.icon,
            archivedStyling: widget.archivedStyling,
            predefinedColor: widget.predefinedColor,
          ),
        const SizedBox(width: 5),
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Flexible, with no minimum: the row may be narrower than
              // `maxWidth`, and the chip ellipsizes rather than overflowing.
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  constraints: BoxConstraints(maxWidth: widget.maxWidth),
                  child: Txt(
                    widget.item.title,
                    overflow: TextOverflow.ellipsis,
                    style: FluentTheme.of(context)
                        .typography
                        .bodyStrong
                        ?.copyWith(backgroundColor: color.withAlpha(25)),
                  ),
                ),
              ),
              if (widget.labels.isNotEmpty)
                TreatmentLabels(labels: widget.labels)
            ],
          ),
        )
      ]),
    );
  }
}

/// An item's avatar, shown where the name is not. The image request is kept
/// across rebuilds and refreshed only when the row or filename changes.
class ItemAvatar extends StatefulWidget {
  const ItemAvatar({
    super.key,
    required this.item,
    this.radius = 15,
    this.icon,
    this.archivedStyling = true,
    this.predefinedColor,
  });

  final Model item;
  final double radius;
  final IconData? icon;
  final bool archivedStyling;
  final Color? predefinedColor;

  @override
  State<ItemAvatar> createState() => _ItemAvatarState();
}

class _ItemAvatarState extends State<ItemAvatar> {
  ImageProvider? _avatarToEvict;
  Future<ImageProvider?>? _image;
  (String, String?)? _imageKey;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant ItemAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadImage();
  }

  void _loadImage() {
    final item = widget.item;
    final rowID = launch.isDemo ? item.id : item.imageRowId ?? item.id;
    final avatar = item.avatar;
    final key = (rowID, avatar);
    if (_imageKey == key) return;
    _imageKey = key;
    if (_avatarToEvict != null) unawaited(_avatarToEvict!.evict());
    _avatarToEvict = null;
    _image = avatar == null
        ? null
        : launch.isDemo
            ? demoAvatarRequestQue.add(() => getImage(rowID, avatar))
            : getImage(rowID, avatar);
  }

  @override
  void dispose() {
    super.dispose();
    if (_avatarToEvict != null) unawaited(_avatarToEvict!.evict());
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final Color color = widget.predefinedColor ??
        (item.archived == true && widget.archivedStyling
            ? FluentTheme.of(context).shadowColor.withValues(alpha: 0.2)
            : item.color);
    return FutureBuilder<ImageProvider?>(
        key: ValueKey(_imageKey),
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.data != null) {
            _avatarToEvict = snapshot.data;
          }
          return CircleAvatar(
            key: Key(item.id),
            radius: widget.radius,
            backgroundColor: color,
            backgroundImage: (snapshot.data != null) ? snapshot.data : null,
            child: (item.archived == true && widget.archivedStyling)
                ? Icon(WindowsIcons.delete, size: widget.radius)
                : snapshot.data == null
                    ? widget.icon == null
                        // The avatar's colour is the record's, not the theme's,
                        // so the initial stays white in both themes.
                        ? Txt(initialOf(item),
                            style: const TextStyle(color: Colors.white))
                        : Icon(widget.icon, size: widget.radius)
                    : null,
          );
        });
  }
}

class TreatmentLabels extends StatelessWidget {
  const TreatmentLabels({
    super.key,
    required this.labels,
    this.showPalmer = false,
    this.showToolTip = true,
  });

  final bool showToolTip;
  final List<TreatmentLabel> labels;
  final bool showPalmer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      // 26 = 18px icon + 3px vertical padding each side + 1px border; 25 left
      // the chip taller than its row, which overflowed.
      height: showPalmer ? null : 26,
      child: ListView(
        shrinkWrap: showPalmer,
        scrollDirection: showPalmer ? Axis.vertical : Axis.horizontal,
        physics: showPalmer ? const NeverScrollableScrollPhysics() : null,
        children: List.generate(
            labels.length,
            (i) => Padding(
                  padding: showPalmer
                      ? const EdgeInsets.only(bottom: 4)
                      : const EdgeInsetsGeometry.all(0),
                  child: SingleTreatmentLabel(
                    label: labels[i],
                    showPalmer: showPalmer,
                    showToolTip: showToolTip,
                  ),
                )),
      ),
    );
  }
}

class SingleTreatmentLabel extends StatefulWidget {
  const SingleTreatmentLabel({
    super.key,
    required this.label,
    required this.showPalmer,
    required this.showToolTip,
    this.endMargin = 2,
  });

  final TreatmentLabel label;
  final bool showPalmer;
  final bool showToolTip;
  final double endMargin;

  @override
  State<SingleTreatmentLabel> createState() => _SingleTreatmentLabelState();
}

class _SingleTreatmentLabelState extends State<SingleTreatmentLabel> {
  final ctrl = FlyoutController();

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.label.color;
    return FlyoutTarget(
      controller: ctrl,
      child: GestureDetector(
        onTap: widget.showToolTip
            ? () {
                unawaited(_showTreatmentLabelDetails());
              }
            : null,
        child: Container(
            margin: EdgeInsetsDirectional.only(end: widget.endMargin),
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
            decoration: BoxDecoration(
                border: Border.all(
                    color: color.withValues(alpha: 0.35),
                    style: BorderStyle.solid,
                    width: FluentMaterials.hairlineWidth),
                borderRadius: FluentMaterials.controlRadius,
                color: color.withValues(alpha: 0.16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Icon(widget.label.icon, size: 18),
                  if (widget.showPalmer) ...[
                    const SizedBox(width: 5),
                    Txt(txt(widget.label.string)),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          DentalNotation(iso: widget.label.iso ?? "11"),
                        ],
                      ),
                    )
                  ]
                ]),
                if (widget.showPalmer &&
                    widget.label.extraNote?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(widget.label.extraNote!,
                        style: FluentTheme.of(context).typography.caption),
                  ),
              ],
            )),
      ),
    );
  }

  Future<Object?> _showTreatmentLabelDetails() {
    return showTeachingTip(
      flyoutController: ctrl,
      placementMode: FlyoutPlacementMode.topCenter,
      builder: (context) {
        final extraNote = widget.label.extraNote;
        return TeachingTip(
          leading: Row(
            children: [
              Icon(labelToIcon(widget.label.string)),
              const SizedBox(width: 5),
              const Divider(
                direction: Axis.vertical,
                style: DividerThemeData(
                    decoration: BoxDecoration(color: Colors.grey)),
              ),
              const SizedBox(width: 5),
              Column(children: [
                Txt(
                  txt(widget.label.string),
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                if (widget.label.iso != null)
                  Row(
                    children: [
                      DentalNotation(iso: widget.label.iso!),
                      const SizedBox(width: 5),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Txt(
                          extraNote != null && extraNote.isNotEmpty
                              ? extraNote
                              : txt(isoToTextualNotation(widget.label.iso!)),
                          style: FluentTheme.of(context).typography.caption,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 3,
                        ),
                      )
                    ],
                  ),
              ])
            ],
          ),
          title: const SizedBox(),
          subtitle: const SizedBox(),
        );
      },
    );
  }
}
