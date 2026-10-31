import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;

/// How many pictures a gallery chip previews: enough to say what the visit
/// holds, few enough that the chip stays a chip rather than a strip.
const int kGalleryChipPreviews = 2;

/// The pictures a visit's gallery chip carries beside its name.
///
/// Photos come first and X-rays after — the order the agenda's gallery badge
/// uses — and `getImage` resolves a `.dcm` to the PNG preview beside it, so an
/// X-ray reads without the raw file. A visit with no pictures shows nothing:
/// the camera icon already says what the chip opens, and an empty frame would
/// promise pictures there are none of.
class VisitGalleryChipPreviews extends StatefulWidget {
  const VisitGalleryChipPreviews(this.appointment, {super.key});

  final Appointment appointment;

  /// The previews [appointment] would show, or null when it has no pictures —
  /// a chip that says nothing must not leave a gap where a picture would sit.
  static Widget? of(Appointment appointment) =>
      _namesOf(_live(appointment)).isEmpty
          ? null
          : VisitGalleryChipPreviews(appointment);

  /// The visit as the chip should read it: the store's copy once it exists,
  /// because that is where an upload lands. The record handed in may be the copy
  /// its surface was laid out from, which an upload does not touch.
  static Appointment _live(Appointment appointment) =>
      appointments.get(appointment.id) ?? appointment;

  /// The pictures the chip previews, in the order it shows them.
  static List<String> _namesOf(Appointment appointment) => [
        ...appointment.viewableImgs,
        ...appointment.viewableDcmImgs,
      ].take(kGalleryChipPreviews).toList(growable: false);

  @override
  State<VisitGalleryChipPreviews> createState() =>
      _VisitGalleryChipPreviewsState();
}

class _VisitGalleryChipPreviewsState extends State<VisitGalleryChipPreviews> {
  /// The names [_images] belongs to. The record is edited in place, so the old
  /// widget's own list cannot be compared with the new one: both read the same,
  /// already-mutated appointment.
  List<String> _names = const [];
  Future<List<ImageProvider?>> _images = Future.value(const <ImageProvider?>[]);

  @override
  void initState() {
    super.initState();
    _load();
    // The band and the post-op card each draw this chip from what they were
    // given, and only the store hears every upload: following it is what keeps
    // the two trays of one visit saying the same thing.
    appointments.observableMap.observe(_onStoreChanged);
  }

  @override
  void dispose() {
    appointments.observableMap.unObserve(_onStoreChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VisitGalleryChipPreviews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(_namesNow, _names)) _load();
  }

  List<String> get _namesNow => VisitGalleryChipPreviews._namesOf(
      VisitGalleryChipPreviews._live(widget.appointment));

  void _onStoreChanged(_) {
    if (!mounted) return;
    if (!listEquals(_namesNow, _names)) setState(_load);
  }

  void _load() {
    _names = _namesNow;
    final id = widget.appointment.id;
    // A draft the server has not seen has nothing to fetch; nothing is drawn
    // for it, exactly as for a visit with no pictures.
    _images = id.isEmpty || _names.isEmpty
        ? Future.value(const <ImageProvider?>[])
        : Future.wait(_names.map((name) => getImage(id, name)));
  }

  @override
  Widget build(BuildContext context) {
    if (_names.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<List<ImageProvider?>>(
      future: _images,
      builder: (context, snapshot) {
        final images = snapshot.data;
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 2,
          children: [
            for (var i = 0; i < _names.length; i++)
              _ChipThumb(
                image: images != null && i < images.length ? images[i] : null,
              ),
          ],
        );
      },
    );
  }
}

/// One preview inside a chip: the same frame whether the picture has landed or
/// not, so the chip does not resize as the image arrives.
class _ChipThumb extends StatelessWidget {
  const _ChipThumb({required this.image});

  final ImageProvider? image;

  static const double _size = 14;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(
        color: FluentTheme.of(context).resources.subtleFillColorSecondary);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2.5),
      child: SizedBox(
        width: _size,
        height: _size,
        child: image == null
            ? placeholder
            : Image(
                image: image!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

/// What a labwork chip says once an order has been written: a check when the
/// work is back, an amber dot while the lab still has it — the two states the
/// post-op card already spells out as "received" and "due".
class VisitLabworkChipBadge extends StatelessWidget {
  const VisitLabworkChipBadge(this.appointment, {super.key});

  final Appointment appointment;

  /// The badge [appointment] carries, or null while no order exists.
  static Widget? of(Appointment appointment) =>
      appointment.hasLabwork ? VisitLabworkChipBadge(appointment) : null;

  @override
  Widget build(BuildContext context) {
    if (!appointment.hasLabwork) return const SizedBox.shrink();
    final received = appointment.labworkReceived;
    return Icon(
      received ? FluentIcons.check_mark : FluentIcons.clock,
      size: 10,
      color: received ? Colors.green : Colors.orange,
    );
  }
}
