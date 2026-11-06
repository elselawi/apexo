import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/features/booking/booking_api.dart';
import 'package:apexo/features/booking/booking_labels.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_schedule.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// The request detail: everything the patient wrote, the resolved candidate
/// dates, and the two transitions staff may take.
Future<void> openBookingRequestPanel(
  BuildContext context,
  BookingRequest request,
) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    dismissWithEsc: true,
    builder: (_) => BookingRequestPanel(request: request),
  );
}

class BookingRequestPanel extends StatefulWidget {
  const BookingRequestPanel({super.key, required this.request});

  final BookingRequest request;

  @override
  State<BookingRequestPanel> createState() => _BookingRequestPanelState();
}

class _BookingRequestPanelState extends State<BookingRequestPanel> {
  late BookingRequest _request = widget.request;
  bool _busy = false;
  String? _notice;

  bool get _actionable => _request.isPending && !_request.isExpired;

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() => _notice = "${txt("bookingCopied")} $label");
  }

  Future<void> _schedule() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final handled = await scheduleBookingRequest(context, _request);
      if (!mounted) return;
      if (handled) {
        Navigator.of(context).pop();
        return;
      }
      final refreshed = booking.requests.cache.byId(_request.requestId);
      if (refreshed != null) setState(() => _request = refreshed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ContentDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        style: dialogStyling(dialogContext, false, true),
        title: Text(txt("bookingDeclineConfirm")),
        content: Text(txt("bookingDeclineBody")),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: ButtonContent(FluentIcons.delete, txt("bookingDecline")),
          ),
          const CloseButtonInDialog(),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final version = await booking.requests.decline(_request);
      if (!mounted) return;
      setState(() {
        _request = _request.copyWith(
          status: "declined",
          version: version,
          handledAt: DateTime.now().millisecondsSinceEpoch,
        );
        _notice = txt("bookingDeclined");
      });
    } on BookingApiException catch (error) {
      if (!mounted) return;
      setState(() => _notice = error.conflict
          ? txt("bookingStateConflictBody")
          : txt("bookingActionFailed"));
    } catch (_) {
      if (mounted) setState(() => _notice = txt("bookingActionFailed"));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return KeyboardAwareView(
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 480),
        style: dialogStyling(context, false, true),
        title: Row(
          children: [
            const Icon(WindowsIcons.contact_info),
            const SizedBox(width: 5),
            Expanded(child: Text(_request.name)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(bookingStatusLabel(_request.status),
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 10,
              children: [
                _row(txt("bookingReference"), _request.reference, copy: true),
                _row(txt("phone"), _request.phone, copy: true),
                if (_request.email != null)
                  _row(txt("email"), _request.email!),
                _row(txt("bookingPreference"), bookingPreferenceLabel(_request)),
                if (_request.candidateDates.isNotEmpty)
                  _row(txt("bookingCandidateDates"),
                      _request.candidateDates.join(", ")),
                _row(txt("bookingClinicZone"), _request.timeZone),
                if (_request.note != null && _request.note!.isNotEmpty)
                  _row(txt("note"), _request.note!, copy: true),
                _row(txt("bookingSubmitted"), bookingSubmittedLabel(_request.createdAt)),
                if (_request.isExpired)
                  Text(txt("bookingExpiredBody"),
                      style: const TextStyle(color: Colors.warningPrimaryColor)),
                if (_notice != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_notice!),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          Button(
            onPressed: _busy || !_actionable || !canScheduleBooking
                ? null : () => unawaited(_schedule()),
            child: ButtonContent(
              WindowsIcons.calendar,
              txt("bookingSchedule"),
              inProgress: _busy,
            ),
          ),
          Button(
            onPressed: _busy || !_actionable ? null : () => unawaited(_decline()),
            child: ButtonContent(FluentIcons.delete, txt("bookingDecline")),
          ),
          const CloseButtonInDialog(),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool copy = false}) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: FluentTheme.of(context).typography.bodyStrong),
          ),
          Expanded(child: Text(value)),
          if (copy)
            IconButton(
              icon: const Icon(FluentIcons.copy, size: 12),
              onPressed: () => unawaited(_copy(value, label)),
            ),
        ],
      );
}

