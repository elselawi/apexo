import 'dart:math' as math;

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/follow_up_scheduling.dart';
import 'package:apexo/features/appointments/open_appointment.dart';
import 'package:apexo/features/settings/settings_stores.dart' show DF;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A visit section and its icon; the icons match the appointment card's sections.
enum AppointmentIndicator {
  dentalNotes(FluentIcons.teeth, "dentalNotes", Color(0xFF0D9488)),
  prescriptions(FluentIcons.pill, "prescription", Color(0xFF2563EB)),
  labwork(FluentIcons.manufacturing, "labworks", Color(0xFFD97706)),
  gallery(WindowsIcons.camera, "gallery", Color(0xFF7C3AED)),
  followUp(WindowsIcons.walk_solid, "followUp", kFollowUpAccent);

  const AppointmentIndicator(this.icon, this.labelKey, this.tint);

  final IconData icon;

  /// The tooltip's heading — the same key the card's section is titled with.
  final String labelKey;

  /// Category accent used by the indicator pill.
  final Color tint;

  AppointmentWindow get window => switch (this) {
        dentalNotes => AppointmentWindow.dentalChart,
        prescriptions => AppointmentWindow.operative,
        labwork => AppointmentWindow.labwork,
        gallery => AppointmentWindow.gallery,
        followUp => AppointmentWindow.operative,
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
      _hasGallery(item) ||
      _hasFollowUpAfter(item);

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

  Color _inkColorFor(Color tint) {
    final isDark = FluentTheme.of(context).brightness == Brightness.dark;
    return Color.lerp(
      tint,
      isDark ? Colors.white : Colors.black,
      isDark ? 0.45 : 0.22,
    )!;
  }

  ButtonStyle _buttonStyleFor(Color tint) => ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.pressed)
                ? tint.withValues(alpha: 0.16)
                : Colors.transparent),
        shape: const WidgetStatePropertyAll(CircleBorder()),
      );

  Widget _indicatorButton(_Badge badge, Widget child, {Color? tint}) =>
      Semantics(
        label: txt(badge.kind.labelKey),
        child: Button(
          onPressed: _canOpen(badge.kind) ? () => _open(badge.kind) : null,
          style: _buttonStyleFor(
              tint ?? widget.color ?? FluentTheme.of(context).accentColor),
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
    final dark = theme.brightness == Brightness.dark;
    const dockHeight = 24.0;
    const tokenSize = 20.0;
    const tokenGap = 3.0;
    const dockPad = 2.0;

    return Tooltip(
      triggerMode: TooltipTriggerMode.manual,
      style: _tooltipStyle,
      richMessage: _card(context, badges),
      child: Semantics(
        label: badges.map((badge) => txt(badge.kind.labelKey)).join(', '),
        child: SizedBox(
          key: WK.appointmentInfoBadges,
          height: dockHeight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Container(
              height: dockHeight,
              padding: const EdgeInsets.all(dockPad),
              decoration: BoxDecoration(
                color: FluentMaterials.of(context).acrylic,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.24 : 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < badges.length; i++) ...[
                    if (i > 0) const SizedBox(width: tokenGap),
                    _embeddedToken(
                      badges[i],
                      index: i,
                      size: tokenSize,
                      dark: dark,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _embeddedToken(
    _Badge badge, {
    required int index,
    required double size,
    required bool dark,
  }) {
    final tint = badge.kind.tint;
    final ink = _inkColorFor(tint);
    final hovered = _hovered == index;

    return MouseRegion(
      onEnter: (_) => _setHovered(index),
      onExit: (_) => _clearHovered(index),
      child: AnimatedContainer(
        key: WK.appointmentIndicator(badge.kind.name),
        duration: const Duration(milliseconds: 120),
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              tint.withValues(
                alpha: hovered ? (dark ? 0.48 : 0.28) : (dark ? 0.34 : 0.18),
              ),
              tint.withValues(
                alpha: hovered ? (dark ? 0.28 : 0.16) : (dark ? 0.18 : 0.09),
              ),
            ],
          ),
          border: Border.all(
            color: tint.withValues(
              alpha: hovered ? (dark ? 0.88 : 0.80) : (dark ? 0.55 : 0.36),
            ),
            width: hovered ? 1.2 : 0.9,
          ),
          boxShadow: hovered
              ? [
                  BoxShadow(
                    color: tint.withValues(alpha: dark ? 0.38 : 0.26),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: _indicatorButton(
          badge,
          tint: tint,
          badge.media ??
              Center(
                child: Icon(
                  badge.kind.icon,
                  size: 11.5,
                  color: ink,
                ),
              ),
        ),
      ),
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
                iconSize: widget.embedded ? 11.5 : widget.iconSize,
                fallbackIcon: AppointmentIndicator.gallery.icon,
                color: _inkColorFor(AppointmentIndicator.gallery.tint),
              )
            : null,
      );
    }
    if (_hasFollowUpAfter(widget.item)) {
      add(AppointmentIndicator.followUp, _followUpLines(widget.item));
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
            : math.min(
                124.0,
                math.max(
                    0.0,
                    constraints.maxWidth -
                        math.min(64.0, constraints.maxWidth * 0.4) -
                        6));
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
            spacing: 5,
            children: [
              if (badges) ...[
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: stripWidth),
                  child: strip,
                ),
              ],
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

bool _hasFollowUpAfter(Appointment item) {
  if (!followUpsEnabled) return false;
  final followUpDay = item.patient?.followUpDay;
  if (followUpDay == null) return false;
  return followUpDay.isAfter(dayOnly(item.date));
}

List<String> _followUpLines(Appointment item) {
  final patient = item.patient;
  final followUpDay = patient?.followUpDay;
  if (patient == null || followUpDay == null) return const [];
  return [
    '${DF.commonDate(followUpDay).replaceAll('📅 ', '')} · ${followUpRelativeLabel(followUpDay)}',
    if (patient.followUpNote.isNotEmpty) patient.followUpNote,
  ];
}

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
          borderRadius: BorderRadius.circular(999),
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
