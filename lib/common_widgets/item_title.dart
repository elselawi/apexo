import 'package:apexo/common_widgets/notation.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/iso_to_textual.dart';
import 'package:apexo/utils/que.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../core/model.dart';

class TreatmentLabel {
  Color color;
  String string;
  IconData icon;
  String? iso;
  TreatmentLabel(
      {required this.string,
      required this.color,
      required this.icon,
      this.iso});
}

class ItemTitle extends StatefulWidget {
  final Model item;
  final double radius;
  final double maxWidth;
  final IconData? icon;
  final Color? predefinedColor;
  final double? fontSize;
  final List<TreatmentLabel> labels;
  const ItemTitle({
    super.key,
    required this.item,
    this.radius = 15,
    this.maxWidth = 130.0,
    this.labels = const [],
    this.icon,
    this.predefinedColor,
    this.fontSize,
  });

  @override
  State<ItemTitle> createState() => _ItemTitleState();
}

class _ItemTitleState extends State<ItemTitle> {
  ImageProvider? _avatarToEvict;

  @override
  void dispose() {
    super.dispose();
    if (_avatarToEvict != null) _avatarToEvict!.evict();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.predefinedColor ??
        (widget.item.archived == true
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
                  child: widget.item.archived == true
                      ? Icon(FluentIcons.archive, size: widget.radius)
                      : snapshot.data == null
                          ? widget.icon == null
                              ? Txt(("${widget.item.title} ").substring(0, 1))
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
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                constraints: BoxConstraints(
                  minWidth: widget.maxWidth < 100 ? widget.maxWidth : 100,
                  maxWidth: widget.maxWidth,
                ),
                child: Txt(
                  widget.item.title,
                  overflow: TextOverflow.ellipsis,
                  style: FluentTheme.of(context)
                      .typography
                      .bodyStrong
                      ?.copyWith(backgroundColor: color.withAlpha(25)),
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
      height: showPalmer ? labels.length * 35 : 25,
      child: ListView(
        scrollDirection: showPalmer ? Axis.vertical : Axis.horizontal,
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

class SingleTreatmentLabel extends StatelessWidget {
  SingleTreatmentLabel({
    super.key,
    required this.label,
    required this.showPalmer,
    required this.showToolTip,
    this.endMargin = 2,
  });

  final ctrl = FlyoutController();
  final TreatmentLabel label;
  final bool showPalmer;
  final bool showToolTip;
  final double endMargin;

  @override
  Widget build(BuildContext context) {
    final color = label.color;
    return FlyoutTarget(
      controller: ctrl,
      child: GestureDetector(
        onTap: showToolTip
            ? () {
                _showTreatmentLabelDetails();
              }
            : null,
        child: Container(
            margin: EdgeInsetsDirectional.only(end: endMargin),
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
            child: Row(
              children: [
                Icon(label.icon, size: 18),
                if (showPalmer) ...[
                  const SizedBox(width: 5),
                  Txt(txt(label.string)),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        DentalNotation(iso: label.iso ?? "11"),
                      ],
                    ),
                  )
                ]
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
        return TeachingTip(
          leading: Row(
            children: [
              Icon(labelToIcon(label.string)),
              const SizedBox(width: 5),
              const Divider(
                direction: Axis.vertical,
                style: DividerThemeData(
                    decoration: BoxDecoration(color: Colors.grey)),
              ),
              const SizedBox(width: 5),
              Column(children: [
                Txt(
                  txt(label.string),
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                if (label.iso != null)
                  Row(
                    children: [
                      DentalNotation(iso: label.iso!),
                      const SizedBox(width: 5),
                      Txt(
                        txt(isoToTextualNotation(label.iso!)),
                        style: FluentTheme.of(context).typography.caption,
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
