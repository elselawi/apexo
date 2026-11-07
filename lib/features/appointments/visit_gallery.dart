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

  /// How the card opens its visit.
  final void Function(Appointment appointment, AppointmentWindow window)?
      onOpen;

  /// Photos permission plus visit edit rights, like every other visit write.
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

/// One visit's photos and X-rays. Files are always written through the visit,
/// whichever window is showing them.
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

  /// Whose photos these are, so several photo windows can be told apart.
  final String Function()? owner;

  /// Leads a photo's window back to the visit that holds it.
  final Future<void> Function()? onOpenRecord;

  /// Reports a bulk upload or delete so a panel can show it as progress.
  final ValueChanged<bool>? onProgress;

  /// Acknowledges only the file fields the gallery wrote, so unsaved notes typed
  /// into the visit draft survive an upload.
  final void Function(Iterable<String> fields)? onFieldsSaved;

  /// Whether photos can be added here; off in the patient's gallery, which has no
  /// visit window to write through.
  final bool uploads;

  @override
  State<VisitGallery> createState() => _VisitGalleryState();
}

class _VisitGalleryState extends State<VisitGallery> {
  Appointment get visit => widget.visit;

  /// Photos permission plus visit edit rights, like every other visit write.
  bool get canEdit =>
      login.perm(Perm.photos).exact(1) &&
      canEditAppointments(visit.operatorsIDs);

  void _wrote() {
    // Only the image fields reach the store; notes in the draft stay dirty.
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
