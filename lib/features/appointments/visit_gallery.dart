import 'package:apexo/common_widgets/appointment_card.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/grid_gallery.dart';
import 'package:apexo/features/appointments/appointment_commands.dart';
import 'package:apexo/features/appointments/appointment_model.dart';
import 'package:apexo/features/appointments/appointment_windows.dart';
import 'package:apexo/features/appointments/appointments_store.dart';
import 'package:apexo/features/dicom/open_dicom_viewer_window.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/utils/logger.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// A visit's photos and X-rays as a compact card: its pictures, and the way
/// into the visit that holds them.
///
/// One design for both places a visit's files are seen from outside the visit's
/// own gallery: below a visit's gallery, where the patient's other visits with
/// pictures are listed, and the patient's gallery, where every one of them is.
class VisitPhotosCard extends StatelessWidget {
  const VisitPhotosCard(
    this.visit, {
    super.key,
    this.number,
    this.onOpen,
  });

  final Appointment visit;

  /// The card's place in the list it is drawn in, if the list numbers its cards.
  final int? number;

  /// How the card opens its visit. Defaults to [openAppointment], which opens
  /// the visit beside the patient.
  final void Function(Appointment appointment, AppointmentWindow window)?
      onOpen;

  /// Whether this user may delete this visit's pictures: the photos permission,
  /// and the visit itself — the gate every other write to a visit uses.
  bool get _canDelete =>
      login.perm(Perm.photos).exact(1) &&
      canEditAppointments(visit.operatorsIDs);

  @override
  Widget build(BuildContext context) {
    return AppointmentCard(
      appointment: visit,
      number: number ?? 0,
      onOpen: onOpen,
      onTapDcm: (context, rowId, name) => openDicomViewerWindow(rowId, name),
      canDeletePhotos: _canDelete,
      readOnly: true,
      showLeftBorder: false,
      showSectionTitle: false,
      photosClipCount: 999,
      openButtonColor: Colors.grey,
      hide: const [
        AppointmentSections.dentalNotes,
        AppointmentSections.doctors,
        AppointmentSections.labworks,
        AppointmentSections.patient,
        AppointmentSections.pay,
        AppointmentSections.postNotes,
        AppointmentSections.preNotes,
        AppointmentSections.prescriptions,
        AppointmentSections.appointmentNumber,
      ],
    );
  }
}

/// One visit's photos and X-rays, as a gallery.
///
/// This is what the visit's own gallery window shows. The patient's gallery
/// shows the same visit's files as a [VisitPhotosCard] — one per visit — and
/// both routes change the files through the visit that holds them: a photo is
/// uploaded to, deleted from and drawn on through that visit, whichever window
/// the user happens to be looking at it in.
class VisitGallery extends StatefulWidget {
  const VisitGallery(
    this.visit, {
    super.key,
    this.owner,
    this.onOpenRecord,
    this.onProgress,
    this.onFieldsSaved,
    this.uploads = false,
  });

  final Appointment visit;

  /// Whose photos these are — the visit's patient and day. A photo's own window
  /// says it, so several open at once can be told apart.
  final String Function()? owner;

  /// The visit these photos belong to, for a photo's own window: it leads back
  /// to the record that holds them.
  final Future<void> Function()? onOpenRecord;

  /// Reports a bulk upload or delete so a panel can show it as progress.
  final ValueChanged<bool>? onProgress;

  /// The visit's owner acknowledges *which* fields the gallery wrote — the files
  /// and drawings, never the notes typed beside them. A visit's draft is only
  /// clean on those fields, so unsaved clinical text survives an upload.
  final void Function(Iterable<String> fields)? onFieldsSaved;

  /// Whether photos can be added here. Off where there is no visit window to
  /// keep the write (the patient's gallery): a new file would still belong to
  /// this visit, so adding one belongs to the visit's own gallery.
  final bool uploads;

  @override
  State<VisitGallery> createState() => _VisitGalleryState();
}

class _VisitGalleryState extends State<VisitGallery> {
  Appointment get visit => widget.visit;

  /// Whether the user may change this visit's photos: the photos permission,
  /// and the visit itself — the gate every other write to a visit uses.
  bool get canEdit =>
      login.perm(Perm.photos).exact(1) &&
      canEditAppointments(visit.operatorsIDs);

  void _wrote() {
    // Only the fields this gallery owns reach the store: a photo upload must
    // never commit the notes that happen to be typed into the visit's draft.
    writeVisitImages(visit);
    widget.onFieldsSaved?.call(kVisitImageFields);
    if (mounted) setState(() {});
  }

  Future<void> _deleteImage(String img) async {
    try {
      await appointments.deleteImg(visit.id, img);
      visit.imgs.remove(img);
      visit.drawings.remove(img);
      _wrote();
    } catch (e, s) {
      showErrorMessage(e, "deletingPatientImageFromServer");
      login.askForLoginAgain(e);
      logger("Error during deleting image: $e", s);
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteDcmImage(String dcmName) async {
    try {
      await appointments.deleteDcmImg(visit.id, dcmName);
      visit.dcmImgs.remove(dcmName);
      _wrote();
    } catch (e, s) {
      showErrorMessage(e, "deletingPatientImageFromServer");
      login.askForLoginAgain(e);
      logger("Error during deleting DCM image: $e", s);
    }
    if (mounted) setState(() {});
  }

  void _saveDrawing(String img, String drawing) {
    visit.drawings[img] = drawing;
    _wrote();
  }

  GalleryUploadConfig? get _uploadConfig {
    if (!widget.uploads || !canEdit) return null;
    return GalleryUploadConfig(
      store: appointments,
      canUpload: true,
      modelPersistence: (names) async {
        visit.imgs = {...visit.imgs, ...names}.toList();
        _wrote();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return GridGallery(
      onProgress: widget.onProgress,
      rowId: visit.id,
      imgs: visit.imgs,
      dcmImgs: visit.dcmImgs,
      canDelete: canEdit,
      owner: widget.owner,
      onOpenRecord: widget.onOpenRecord,
      slideshowEnabled: true,
      drawings: visit.drawings,
      onSaveDrawing: canEdit ? _saveDrawing : null,
      onTapDcm: (context, rowId, name) => openDicomViewerWindow(rowId, name),
      onPressDelete: _deleteImage,
      onPressDeleteDcm: _deleteDcmImage,
      uploadConfig: _uploadConfig,
    );
  }
}
