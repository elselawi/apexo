import 'dart:async';
import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:apexo/utils/que.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../core/model.dart';

/// The avatar's letter: the first *whole* character of an item's title.
///
/// `("${title} ").substring(0, 1)` splits a surrogate pair. Titles do start
/// with an emoji — a labwork's is `"📌 undelivered"` — and half of one is not a
/// string Flutter will draw: the paragraph builder rejects it with
/// `Invalid argument(s): string is not well-formed UTF-16`, which fails the
/// frame the item appears in.
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
  ImageProvider? _avatarToEvict;

  @override
  void dispose() {
    super.dispose();
    if (_avatarToEvict != null) unawaited(_avatarToEvict!.evict());
  }

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
          FutureBuilder(
              future: widget.item.avatar != null
                  ? (launch.isDemo
                      ? demoAvatarRequestQue.add(
                          () => getImage(widget.item.id, widget.item.avatar!))
                      : getImage(widget.item.imageRowId ?? widget.item.id,
                          widget.item.avatar!))
                  : null,
              builder: (context, snapshot) {
                if (snapshot.data != null) {
                  _avatarToEvict = snapshot.data;
                }
                if (widget.item.title.isEmpty) {
                  widget.item.title = " ";
                }
                return CircleAvatar(
                  key: Key(widget.item.id),
                  radius: widget.radius,
                  backgroundColor: color,
                  backgroundImage:
                      (snapshot.data != null) ? snapshot.data : null,
                  child:
                      (widget.item.archived == true && widget.archivedStyling)
                          ? Icon(WindowsIcons.delete, size: widget.radius)
                          : snapshot.data == null
                              ? widget.icon == null
                                  ? Txt(initialOf(widget.item))
                                  : Icon(widget.icon, size: widget.radius)
                              : null,
                );
              }),
        const SizedBox(width: 5),
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // `Flexible`, and no *minimum*: the floor used to be the caller's
              // `maxWidth`, and a dashboard square hands this row 117.3px of
              // space while asking for `maxWidth: 123` — which is exactly the
              // `A RenderFlex overflowed by 5.7 pixels on the right` that redded
              // `dashboard 02`. The chip ellipsizes its own text, so it is the
              // side that gives.
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
      // A chip is its 18px icon, 3px of padding above and below, and a 1px
      // border: 26. At 25 the chip's own column was a pixel taller than the
      // row it was given, and the row it sat in reported an overflow.
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
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 5),
            decoration: BoxDecoration(
                border: Border.all(
                    color: color.withAlpha(120),
                    style: BorderStyle.solid,
                    width: 1),
                borderRadius: BorderRadius.circular(8),
                color: color.withAlpha(120),
                boxShadow: [
                  BoxShadow(
                    offset: const Offset(0.0, 0),
                    blurRadius: 15.0,
                    spreadRadius: 3.0,
                    color: color.withAlpha(70),
                  )
                ]),
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
