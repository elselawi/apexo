import 'dart:math' as math;

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A visit section and its icon; the icons match the appointment card's sections.
enum AppointmentIndicator {
  dentalNotes(FluentIcons.teeth, "dentalNotes"),
  prescriptions(FluentIcons.pill, "prescription"),
  labwork(FluentIcons.manufacturing, "labworks"),
  gallery(FluentIcons.camera, "gallery");

  const AppointmentIndicator(this.icon, this.labelKey);

  final IconData icon;

  /// The tooltip's heading — the same key the card's section is titled with.
  final String labelKey;

  AppointmentWindow get window => switch (this) {
        dentalNotes => AppointmentWindow.dentalChart,
        prescriptions => AppointmentWindow.operative,
        labwork => AppointmentWindow.labwork,
        gallery => AppointmentWindow.gallery,
      };
}

class AppointmentIndicators extends StatefulWidget {
  const AppointmentIndicators({
    super.key,
    required this.item,
    this.iconSize = 18,
    this.overlap = 8,
    this.showDentalNotes = true,
    this.showGalleryThumbnail = true,
    this.embedded = true,
    this.color,
    this.onOpenWindow,
  });

  final Appointment item;

  final double iconSize;

  /// How far each badge sits on the one before it.
  final double overlap;

  /// The agenda shows treatments as chips already, so it turns this badge off.
  final bool showDentalNotes;

  final bool showGalleryThumbnail;

  final bool embedded;

  /// The operator's chip color, used for a stronger fill.
  final Color? color;

  /// Uses the existing standalone-window opener when no callback is supplied.
  final ValueChanged<AppointmentWindow>? onOpenWindow;

  /// The circle a badge of [iconSize] glyphs is drawn in.
  static double sizeFor(double iconSize) => iconSize + 10;

  static bool hasAny(Appointment item, {bool showDentalNotes = true}) =>
      (showDentalNotes && _hasDentalNotes(item)) ||
      _prescriptions(item).isNotEmpty ||
      item.hasLabwork ||
      _hasGallery(item);

  @override
  State<AppointmentIndicators> createState() => _AppointmentIndicatorsState();
}

class _AppointmentIndicatorsState extends State<AppointmentIndicators> {
  int? _hovered;
  bool _canOpen(AppointmentIndicator kind) =>
      appointmentWindows(widget.item).contains(kind.window);

  void _open(AppointmentIndicator kind) {
    if (!_canOpen(kind)) return;
    if (widget.onOpenWindow case final open?) {
      open(kind.window);
    } else {
      openAppointmentWindow(widget.item, kind.window);
    }
  }

  Color get _baseColor => widget.color ?? FluentTheme.of(context).accentColor;

  Color get _inkColor => Color.lerp(
        _baseColor,
        FluentTheme.of(context).brightness.isDark ? Colors.white : Colors.black,
        FluentTheme.of(context).brightness.isDark ? 0.55 : 0.28,
      )!;

  ButtonStyle get _buttonStyle => ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed)
                ? (widget.color ?? FluentTheme.of(context).accentColor)
                    .withValues(alpha: 0.12)
                : Colors.transparent),
        shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
      );

  Widget _indicatorButton(_Badge badge, Widget child) => Semantics(
        label: txt(badge.kind.labelKey),
        child: Button(
          onPressed: _canOpen(badge.kind) ? () => _open(badge.kind) : null,
          style: _buttonStyle,
          child: SizedBox.expand(child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final badges = _collect();
    if (badges.isEmpty) return const SizedBox.shrink();
    if (widget.embedded) return _embeddedStrip(context, badges);

    final double size = AppointmentIndicators.sizeFor(widget.iconSize);
    final double step = size - widget.overlap;

    // Paint the hovered badge last so its full circle sits above the pile.
    final order = [for (var i = 0; i < badges.length; i++) i];
    final hovered = _hovered;
    if (hovered != null && hovered < badges.length) {
      order
        ..remove(hovered)
        ..add(hovered);
    }

    return Tooltip(
      // Hover only, so the card never competes with the row's long press.
      triggerMode: TooltipTriggerMode.manual,
      style: _tooltipStyle,
      richMessage: _card(context, badges),
      child: SizedBox(
        key: WK.appointmentInfoBadges,
        width: size + (badges.length - 1) * step,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final i in order)
              PositionedDirectional(
                // Keyed by kind so reordering moves the element rather than
                // rebuilding it; a rebuild would close the open tooltip.
                key: ValueKey(badges[i].kind.name),
                start: i * step,
                top: 0,
                width: size,
                height: size,
                child: MouseRegion(
                  onEnter: (_) => _setHovered(i),
                  onExit: (_) => _clearHovered(i),
                  child: _indicatorButton(
                    badges[i],
                    _badge(context, badges[i], hovered: hovered == i),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _embeddedStrip(BuildContext context, List<_Badge> badges) {
    final theme = FluentTheme.of(context);
    final color = _baseColor;
    final dark = theme.brightness.isDark;
    return Tooltip(
      triggerMode: TooltipTriggerMode.manual,
      style: _tooltipStyle,
      richMessage: _card(context, badges),
      child: LayoutBuilder(builder: (context, room) {
        final showLabels =
            room.maxWidth.isFinite && room.maxWidth >= badges.length * 88;
        final cellWidth = showLabels ? 88.0 : 28.0;
        final displayed = badges;
        return Semantics(
          label: badges.map((badge) => txt(badge.kind.labelKey)).join(', '),
          child: MouseRegion(
            onEnter: (_) => _setHovered(0),
            onExit: (_) => _setHovered(null),
            child: AnimatedContainer(
              key: WK.appointmentInfoBadges,
              duration: const Duration(milliseconds: 120),
              constraints: BoxConstraints(maxWidth: badges.length * cellWidth),
              height: 24,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: color.withValues(
                    alpha: _hovered != null
                        ? (dark ? 0.32 : 0.25)
                        : (dark ? 0.24 : 0.18)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < badges.length; i++)
                    Expanded(
                      child: Container(
                        key: WK.appointmentIndicator(displayed[i].kind.name),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: i == 0
                              ? null
                              : BorderDirectional(
                                  start: BorderSide(
                                    color: color.withValues(alpha: 0.22),
                                  ),
                                ),
                        ),
                        child: _indicatorButton(
                            displayed[i],
                            Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: showLabels ? 6 : 0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: displayed[i].media ??
                                          Icon(
                                            displayed[i].kind.icon,
                                            size: 14,
                                            color: _inkColor,
                                          ),
                                    ),
                                  ),
                                  if (showLabels) ...[
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Txt(
                                        txt(displayed[i].kind.labelKey),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.typography.caption
                                            ?.copyWith(color: _inkColor),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            )),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _badge(BuildContext context, _Badge badge, {required bool hovered}) {
    final theme = FluentTheme.of(context);
    final accent = widget.color ?? theme.accentColor;
    final double size = AppointmentIndicators.sizeFor(widget.iconSize);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      transform: Matrix4.translationValues(0, hovered ? -2 : 0, 0),
      key: WK.appointmentIndicator(badge.kind.name),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hovered
            ? accent.withValues(alpha: 0.16)
            : theme.resources.solidBackgroundFillColorBase,
        border: Border.all(
          color: hovered
              ? accent.withValues(alpha: 0.90)
              : theme.resources.controlStrokeColorDefault
                  .withValues(alpha: 0.75),
          width: hovered ? 1.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: hovered ? 0.18 : 0.08),
            blurRadius: hovered ? 6 : 3.5,
            offset: Offset(0, hovered ? 2.5 : 1),
          ),
          if (hovered)
            BoxShadow(
              color: accent.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 1),
            )
          else
            const BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.03),
              blurRadius: 1,
              offset: Offset(0, 0.5),
            ),
        ],
      ),
      child: badge.media ??
          Icon(
            badge.kind.icon,
            size: widget.iconSize,
            color: accent,
          ),
    );
  }

  void _setHovered(int? index) {
    if (_hovered != index) setState(() => _hovered = index);
  }

  void _clearHovered(int index) {
    if (_hovered == index) setState(() => _hovered = null);
  }

  List<_Badge> _collect() {
    final badges = <_Badge>[];
    void add(AppointmentIndicator kind, List<String> lines, {Widget? media}) {
      if (lines.isEmpty) return;
      badges.add(_Badge(kind, lines, media: media));
    }

    if (widget.showDentalNotes) {
      add(AppointmentIndicator.dentalNotes, _dentalNoteLines(widget.item));
    }
    add(AppointmentIndicator.prescriptions, _prescriptions(widget.item));
    if (widget.item.hasLabwork) {
      add(AppointmentIndicator.labwork, _labworkLines(widget.item));
    }
    if (_hasGallery(widget.item)) {
      final double size =
          widget.embedded ? 20 : AppointmentIndicators.sizeFor(widget.iconSize);
      add(
        AppointmentIndicator.gallery,
        _galleryLines(widget.item),
        media: widget.showGalleryThumbnail
            ? _GalleryThumb(
                item: widget.item,
                circleSize: size,
                iconSize: widget.iconSize,
                fallbackIcon: AppointmentIndicator.gallery.icon,
                color: _inkColor,
              )
            : null,
      );
    }
    return badges;
  }
}

class _Badge {
  const _Badge(this.kind, this.lines, {this.media});

  final AppointmentIndicator kind;
  final List<String> lines;
  final Widget? media;
}

class AppointmentInfoLine extends StatelessWidget {
  const AppointmentInfoLine({
    super.key,
    required this.item,
    required this.note,
    this.iconSize = 18,
    this.showDentalNotes = true,
    this.showIndicators = true,
    this.noteStyle,
    this.color,
    this.onOpenWindow,
  });

  final Appointment item;
  final String note;
  final double iconSize;
  final bool showDentalNotes;

  final bool showIndicators;
  final TextStyle? noteStyle;
  final Color? color;
  final ValueChanged<AppointmentWindow>? onOpenWindow;

  @override
  Widget build(BuildContext context) {
    final badges = showIndicators &&
        AppointmentIndicators.hasAny(item, showDentalNotes: showDentalNotes);
    if (!badges && note.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final stripWidth = note.isEmpty
            ? constraints.maxWidth
            : math.min(112.0, math.max(0.0,
                constraints.maxWidth - math.min(64.0, constraints.maxWidth * 0.4) - 6));
        final strip = AppointmentIndicators(
          item: item,
          iconSize: iconSize,
          showDentalNotes: showDentalNotes,
          color: color,
          onOpenWindow: onOpenWindow,
        );
        if (note.isEmpty) return strip;
        return SizedBox(
          height: 24,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Tooltip(
                  message: note,
                  triggerMode: TooltipTriggerMode.manual,
                  child: LayoutBuilder(
                      builder: (context, room) => FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(maxWidth: room.maxWidth),
                              child: Txt(
                                note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: noteStyle,
                              ),
                            ),
                          )),
                ),
              ),
              if (badges) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: stripWidth),
                  child: strip,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// The hover card. Icons are drawn as font glyphs rather than widgets so they
/// take the tooltip's text colour and sit on its baseline.
InlineSpan _card(BuildContext context, List<_Badge> badges) {
  final typography = FluentTheme.of(context).typography;
  return TextSpan(
    children: [
      for (var i = 0; i < badges.length; i++) ...[
        if (i > 0) const TextSpan(text: "\n\n"),
        TextSpan(
          text: String.fromCharCode(badges[i].kind.icon.codePoint),
          style: TextStyle(
            // Text styles name a package font by its prefixed family.
            fontFamily: _familyOf(badges[i].kind.icon),
            fontSize: 13,
          ),
        ),
        TextSpan(
          text: "  ${txt(badges[i].kind.labelKey)}",
          style: typography.bodyStrong,
        ),
        for (final line in badges[i].lines)
          TextSpan(text: "\n$line", style: typography.caption),
      ],
    ],
  );
}

// Wide enough for a prescription name and a tooth note, narrow enough to stay
// beside the row it belongs to.
const _tooltipStyle = TooltipThemeData(maxWidth: 280);

String _familyOf(IconData icon) {
  final package = icon.fontPackage;
  return package == null
      ? icon.fontFamily ?? ''
      : 'packages/$package/${icon.fontFamily}';
}

bool _hasDentalNotes(Appointment item) =>
    item.teeth.isNotEmpty || item.teethExtraNotes.isNotEmpty;

bool _hasGallery(Appointment item) =>
    item.viewableImgs.isNotEmpty || item.viewableDcmImgs.isNotEmpty;

List<String> _prescriptions(Appointment item) =>
    item.prescriptions.where((p) => p.trim().isNotEmpty).toList();

List<String> _dentalNoteLines(Appointment item) {
  final isos = {...item.teeth.keys, ...item.teethExtraNotes.keys}.toList()
    ..sort();
  return [
    for (final iso in isos)
      [
        iso,
        if (item.teeth[iso]?.isNotEmpty ?? false) txt(item.teeth[iso]!),
        if (item.teethExtraNotes[iso]?.isNotEmpty ?? false)
          item.teethExtraNotes[iso]!,
      ].join(" · "),
  ];
}

List<String> _labworkLines(Appointment item) => [
      if (item.labName.isNotEmpty) "${txt("laboratory")}: ${item.labName}",
      item.labworkStatus,
      if (item.labworkNotes.isNotEmpty)
        "${txt("orderNotes")}: ${item.labworkNotes}",
    ];

List<String> _galleryLines(Appointment item) => [
      if (item.viewableImgs.isNotEmpty)
        "${txt("photos")}: ${item.viewableImgs.length}",
      if (item.viewableDcmImgs.isNotEmpty)
        "${txt("dcm")}: ${item.viewableDcmImgs.length}",
    ];

// First photo, else first X-ray; `getImage` maps a `.dcm` to its PNG preview.
String? _previewName(Appointment item) {
  if (item.viewableImgs.isNotEmpty) return item.viewableImgs.first;
  if (item.viewableDcmImgs.isNotEmpty) return item.viewableDcmImgs.first;
  return null;
}

/// Caches the picture future across rebuilds: the timeline rebuilds chips every
/// minute, and a fresh future each build would restart the download.
class _GalleryThumb extends StatefulWidget {
  const _GalleryThumb({
    required this.item,
    required this.circleSize,
    required this.iconSize,
    required this.fallbackIcon,
    required this.color,
  });

  final Appointment item;
  final double circleSize;
  final double iconSize;

  final IconData fallbackIcon;
  final Color color;

  @override
  State<_GalleryThumb> createState() => _GalleryThumbState();
}

class _GalleryThumbState extends State<_GalleryThumb> {
  late Future<ImageProvider?> _image;

  String? get _name => _previewName(widget.item);

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(covariant _GalleryThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        _previewName(oldWidget.item) != _name) {
      _image = _load();
    }
  }

  Future<ImageProvider?> _load() {
    final name = _name;
    if (name == null || widget.item.id.isEmpty) return Future.value();
    return getImage(widget.item.id, name);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      widget.fallbackIcon,
      size: widget.iconSize,
      color: widget.color,
    );
    return FutureBuilder<ImageProvider?>(
      future: _image,
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) return fallback;
        return ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            width: widget.circleSize,
            height: widget.circleSize,
            child: Image(
              image: image,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => fallback,
            ),
          ),
        );
      },
    );
  }
}
