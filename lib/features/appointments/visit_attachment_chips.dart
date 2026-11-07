import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/utils/imgs.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show listEquals;

const int kGalleryChipPreviews = 2;

/// The pictures a visit's gallery chip carries. Photos come before X-rays, as in
/// the agenda badge; `getImage` resolves a `.dcm` to the PNG preview beside it.
class VisitGalleryChipPreviews extends StatefulWidget {
  const VisitGalleryChipPreviews(this.appointment, {super.key});

  final Appointment appointment;

  /// The chip, or null when the visit has no pictures: a gap would promise
  /// pictures that are not there.
  static Widget? of(Appointment appointment) =>
      _namesOf(_live(appointment)).isEmpty
          ? null
          : VisitGalleryChipPreviews(appointment);

  /// The store's copy of the visit when it exists: uploads land there, while the
  /// record handed in may be the stale copy its surface was built from.
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
  /// The names [_images] belong to. The appointment is edited in place, so old and
  /// new widgets read the same mutated record and their lists cannot be compared.
  List<String> _names = const [];
  Future<List<ImageProvider?>> _images = Future.value(const <ImageProvider?>[]);

  @override
  void initState() {
    super.initState();
    _load();
    // Only the store hears every upload, so follow it to keep the band's chip and
    // the post-op card's chip saying the same thing.
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
    // A draft with no id has nothing to fetch, so nothing is drawn for it.
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

/// One preview in a fixed frame, so the chip does not resize as the image lands.
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
