import 'package:apexo/services/launch.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/utils/que.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../core/model.dart';

class ItemTitleLabel {
  Color color;
  String string;
  IconData icon;
  ItemTitleLabel({required this.string, required this.color, required this.icon});
}

class ItemTitle extends StatefulWidget {
  final Model item;
  final double radius;
  final double maxWidth;
  final IconData? icon;
  final Color? predefinedColor;
  final double? fontSize;
  final List<ItemTitleLabel> labels;
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
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
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
              SizedBox(
                width: 130,
                height: 24,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: List.generate(
                      widget.labels.length,
                      (i) => Container(
                          margin: const EdgeInsetsDirectional.only(end: 2),
                          padding: const EdgeInsets.symmetric(
                              vertical: 3, horizontal: 5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: widget.labels[i].color.withAlpha(120),
                          ),
                          child: Row(
                            children: [
                              Icon(widget.labels[i].icon),
                              const SizedBox(width: 3),
                              Txt(
                                txt(widget.labels[i].string),
                                style: FluentTheme.of(context)
                                    .typography
                                    .caption
                                    ,
                              ),
                            ],
                          ))),
                ),
              )
          ],
        )
      ]),
    );
  }
}
