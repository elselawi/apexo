import 'dart:math' as math;

import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// One kind of information a visit can carry, as the icon that stands for it
/// and the key that names it.
///
/// The icons are the ones the appointment card already uses for the same
/// sections (`common_widgets/appointment_card.dart`), so a visit's labwork is a
/// factory everywhere, its prescriptions a pill, and its photos a camera.
enum AppointmentIndicator {
  dentalNotes(FluentIcons.teeth, "dentalNotes"),
  prescriptions(FluentIcons.pill, "prescription"),
  labwork(FluentIcons.manufacturing, "labworks"),
  gallery(FluentIcons.camera, "gallery");

  const AppointmentIndicator(this.icon, this.labelKey);

  final IconData icon;

  /// The tooltip's heading — the same key the card's section is titled with.
  final String labelKey;
}

/// What a visit carries, as a small pile of circular badges: the dental
/// chart's notes, its prescriptions, its labwork order and its gallery.
///
/// Each badge is a Fluent circle — the app's solid surface, a crisp definition
/// stroke and compound elevation shadows — with the icon large enough (18px floor)
/// to be instantly recognized without reading; the pile overlaps by [overlap]
/// so badges read as a cohesive stack. The badge under the pointer lifts 2px
/// to the front of the pile, displays an accent halo and tint, revealing its
/// full silhouette.
///
/// Hovering any badge opens **one card** listing every kind, each with its
/// icon, its name and the whole of its information. One hover answers the
/// whole question; a tooltip per badge would make the visitor hunt.
class AppointmentIndicators extends StatefulWidget {
  const AppointmentIndicators({
    super.key,
    required this.item,
    this.iconSize = 18,
    this.overlap = 8,
    this.showDentalNotes = true,
    this.showGalleryThumbnail = true,
  });

  final Appointment item;

  /// The glyph inside each badge; the circle around it is larger by [overlap]
  /// plus the ring it wears.
  final double iconSize;

  /// How far each badge sits on the one before it.
  final double overlap;

  /// The agenda row draws the chart's treatments as `TreatmentLabels` chips;
  /// the teeth badge there would be the same fact twice.
  final bool showDentalNotes;

  /// A picture says more than a camera icon: the gallery badge is the visit's
  /// first picture when there is one.
  final bool showGalleryThumbnail;

  /// The circle a badge of [iconSize] glyphs is drawn in.
  static double sizeFor(double iconSize) => iconSize + 10;

  /// Whether [item] draws anything at all — for callers that would otherwise
  /// leave a gap where the empty line is.
  static bool hasAny(Appointment item, {bool showDentalNotes = true}) =>
      (showDentalNotes && _hasDentalNotes(item)) ||
      _prescriptions(item).isNotEmpty ||
      item.hasLabwork ||
      _hasGallery(item);

  @override
  State<AppointmentIndicators> createState() => _AppointmentIndicatorsState();
}

class _AppointmentIndicatorsState extends State<AppointmentIndicators> {
  /// The badge the pointer is over: brought to the front of the pile and
  /// tinted, so the part its neighbour covers is read in full.
  int? _hovered;

  @override
  Widget build(BuildContext context) {
    final badges = _collect();
    if (badges.isEmpty) return const SizedBox.shrink();

    final double size = AppointmentIndicators.sizeFor(widget.iconSize);
    final double step = size - widget.overlap;

    // The one under the pointer is painted last, so all of its circle is on
    // top of the pile while the card is open.
    final order = [for (var i = 0; i < badges.length; i++) i];
    final hovered = _hovered;
    if (hovered != null && hovered < badges.length) {
      order
        ..remove(hovered)
        ..add(hovered);
    }

    return Tooltip(
      // One card for the whole pile: the question is "what does this visit
      // carry?", not four separate ones. Hover only, so it never competes with
      // the row's long press.
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
                // Keyed by kind, so lifting one to the front moves the
                // element instead of rebuilding it — a rebuilt tooltip would
                // close the one the hover just opened.
                key: ValueKey(badges[i].kind.name),
                start: i * step,
                top: 0,
                width: size,
                height: size,
                child: MouseRegion(
                  onEnter: (_) => _setHovered(i),
                  onExit: (_) => _clearHovered(i),
                  child: _badge(context, badges[i], hovered: hovered == i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One circle of the pile: the glyph on the app's own surface, ringed and
  /// lifted a little, so overlapping circles still read as separate tokens.
  Widget _badge(BuildContext context, _Badge badge, {required bool hovered}) {
    final theme = FluentTheme.of(context);
    final accent = theme.accentColor;
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
              : theme.resources.controlStrokeColorDefault.withValues(alpha: 0.75),
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
            color: hovered ? accent : theme.resources.textFillColorPrimary,
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
      final double size = AppointmentIndicators.sizeFor(widget.iconSize);
      add(
        AppointmentIndicator.gallery,
        _galleryLines(widget.item),
        media: widget.showGalleryThumbnail
            ? _GalleryThumb(
                item: widget.item,
                circleSize: size,
                iconSize: widget.iconSize,
                fallbackIcon: AppointmentIndicator.gallery.icon,
              )
            : null,
      );
    }
    return badges;
  }
}

/// One entry of the pile: what the badge stands for, what the card says about
/// it, and — for the gallery — the picture drawn in the badge.
class _Badge {
  const _Badge(this.kind, this.lines, {this.media});

  final AppointmentIndicator kind;
  final List<String> lines;
  final Widget? media;
}

/// The note line under a visit's title (and the badge pile, when the caller
/// keeps it here rather than floating it over the card).
///
/// The note gives the pile room before itself: text is what ellipsizes, and a
/// pile that still does not fit is scaled down rather than allowed to break
/// the row.
class AppointmentInfoLine extends StatelessWidget {
  const AppointmentInfoLine({
    super.key,
    required this.item,
    required this.note,
    this.iconSize = 18,
    this.showDentalNotes = true,
    this.showIndicators = true,
    this.noteStyle,
  });

  final Appointment item;
  final String note;
  final double iconSize;
  final bool showDentalNotes;

  /// False where the pile is drawn somewhere else — the timeline floats it
  /// over the card, and the line keeps the note alone.
  final bool showIndicators;
  final TextStyle? noteStyle;

  /// What the note keeps even when the pile would rather have it all — and no
  /// more than this share of a line too narrow to spare it.
  static const double _noteRoom = 46;
  static const double _noteShare = 0.45;

  @override
  Widget build(BuildContext context) {
    final badges = showIndicators &&
        AppointmentIndicators.hasAny(item, showDentalNotes: showDentalNotes);
    if (!badges && note.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final noteRoom = note.isEmpty
            ? 0.0
            : math.min(_noteRoom, constraints.maxWidth * _noteShare);
        final room = math.max(0.0, constraints.maxWidth - noteRoom);
        final pile = !badges
            ? null
            : ConstrainedBox(
                constraints: BoxConstraints(maxWidth: room),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AppointmentIndicators(
                    item: item,
                    iconSize: iconSize,
                    showDentalNotes: showDentalNotes,
                  ),
                ),
              );

        if (note.isEmpty) return pile ?? const SizedBox.shrink();
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (pile != null) ...[pile, const SizedBox(width: 6)],
            Expanded(
              child: Tooltip(
                message: note,
                triggerMode: TooltipTriggerMode.manual,
                child: Txt(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: noteStyle,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The card a badge opens: every kind the visit carries, each with its icon,
/// its name and the whole of its information.
///
/// The icons are drawn as glyphs of the icon font rather than as widgets, so
/// they take the tooltip's own text colour and sit on its baseline.
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

/// Wide enough for a prescription name and a tooth note, narrow enough to stay
/// beside the row it belongs to.
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

/// Each treated tooth on its own line: its ISO number, the treatment and, when
/// one was written, the note. This is what the agenda's treatment chips keep
/// behind their flyout, spelled out in one card.
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

/// Counts rather than a list of names: a gallery can hold dozens, and "Photos:
/// 12" is the fact the badge is asked for. The labels read the same in every
/// locale whether there is one photo or many.
List<String> _galleryLines(Appointment item) => [
      if (item.viewableImgs.isNotEmpty)
        "${txt("photos")}: ${item.viewableImgs.length}",
      if (item.viewableDcmImgs.isNotEmpty)
        "${txt("dcm")}: ${item.viewableDcmImgs.length}",
    ];

/// The picture a visit's gallery previews: its first photo, or its first X-ray
/// when it has no photos. `getImage` resolves a `.dcm` to the PNG preview beside it.
String? _previewName(Appointment item) {
  if (item.viewableImgs.isNotEmpty) return item.viewableImgs.first;
  if (item.viewableDcmImgs.isNotEmpty) return item.viewableDcmImgs.first;
  return null;
}

/// The gallery's first picture, filling its badge.
///
/// The future is resolved once per visit (and again only when the visit's
/// pictures change), because the timeline rebuilds every chip on the minute —
/// a `FutureBuilder` fed a fresh future each build would restart the download
/// each time. Until the picture lands (or if it never does) the camera icon
/// stands in for it.
class _GalleryThumb extends StatefulWidget {
  const _GalleryThumb({
    required this.item,
    required this.circleSize,
    required this.iconSize,
    required this.fallbackIcon,
  });

  final Appointment item;
  final double circleSize;
  final double iconSize;

  /// What the badge shows until the picture lands — the icon the gallery
  /// badge would have drawn on its own.
  final IconData fallbackIcon;

  @override
  State<_GalleryThumb> createState() => _GalleryThumbState();
}

class _GalleryThumbState extends State<_GalleryThumb> {
  late Future<ImageProvider?> _image;

  /// The picture the badge previews: the first photo, or the first X-ray —
  /// whose PNG preview `getImage` resolves in its place.
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
      color: FluentTheme.of(context).resources.textFillColorPrimary,
    );
    return FutureBuilder<ImageProvider?>(
      future: _image,
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) return fallback;
        return ClipOval(
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
