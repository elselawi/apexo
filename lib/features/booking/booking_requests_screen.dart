import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/context_menu_region.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/booking/booking_labels.dart';
import 'package:apexo/features/booking/booking_models.dart';
import 'package:apexo/features/booking/booking_request_details.dart';
import 'package:apexo/features/booking/booking_schedule.dart';
import 'package:apexo/features/booking/booking_session.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/open_external.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// The staff inbox. The pending badge is only as fresh as the last successful
/// refresh.
class BookingRequestsScreen extends StatefulWidget {
  const BookingRequestsScreen({super.key});

  @override
  State<BookingRequestsScreen> createState() => _BookingRequestsScreenState();
}

class _BookingRequestsScreenState extends State<BookingRequestsScreen> {
  final TextEditingController _search = TextEditingController();
  String _sort = "newest";

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<BookingRequest> _visible(List<BookingRequest> source) {
    final needle = _search.text.trim().toLowerCase();
    // Patients quote the reference, so `110603` must match `1106-03`.
    final digits = needle.replaceAll(RegExp(r"[^0-9]"), "");
    final items = source
        .where((request) =>
            needle.isEmpty ||
            request.name.toLowerCase().contains(needle) ||
            request.phone.toLowerCase().contains(needle) ||
            request.reference.toLowerCase().contains(needle) ||
            (digits.length >= 3 &&
                request.reference.replaceAll("-", "").contains(digits)))
        .toList();
    items.sort((a, b) => _sort == "oldest"
        ? a.createdAt.compareTo(b.createdAt)
        : b.createdAt.compareTo(a.createdAt));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [
        booking.ready.stream,
        booking.requests.filter.stream,
        booking.requests.items.stream,
        booking.requests.refreshing.stream,
        booking.requests.connected.stream,
        booking.requests.revoked.stream,
        booking.requests.stale.stream,
        booking.requests.pending.stream,
        booking.requests.lastSuccessfulAt.stream,
      ],
      builder: (context, _) {
        final theme = FluentTheme.of(context);
        if (!booking.available) {
          return _notice(theme, FluentIcons.globe, txt("bookingUnavailable"));
        }
        if (!booking.ready()) {
          return _notice(theme, FluentIcons.globe, txt("bookingNotConfigured"));
        }
        final requests = _visible(booking.requests.items());
        return Column(
          key: WK.bookingScreen,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCommandBar(context),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TopSearch(controller: _search, setState: setState),
                  ),
                ],
              ),
            ),
            _buildFilterBar(theme),
            ..._buildBanners(theme),
            Expanded(
              child: requests.isEmpty
                  ? _empty(theme)
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemExtent: 95,
                      itemCount: requests.length,
                      itemBuilder: (context, index) =>
                          _buildRow(theme, requests[index]),
                    ),
            ),
          ],
        );
      },
    );
  }

  ScreenCommandBar _buildCommandBar(BuildContext context) {
    final clinic = booking.clinic();
    final pending = booking.requests.pending();
    final theme = FluentTheme.of(context);
    // Labels do not fit beside the badge on a phone-width window.
    final compact = MediaQuery.sizeOf(context).width < 520;
    void refresh() => unawaited(booking.requests.refresh());
    final onPressed = booking.requests.refreshing() ? null : refresh;
    return ScreenCommandBar(
      mainButton: compact
          ? IconButton(
              icon: const Icon(WindowsIcons.sync),
              onPressed: onPressed,
            )
          : IconButton(
              icon: ButtonContent(WindowsIcons.sync, txt("refresh")),
              onPressed: onPressed,
            ),
      otherButtons: [
        if (clinic != null)
          compact
              ? IconButton(
                  icon: const Icon(FluentIcons.open_in_new_window),
                  onPressed: () =>
                      unawaited(openExternal(Uri.parse(clinic.publicUrl))),
                )
              : IconButton(
                  icon: ButtonContent(
                      FluentIcons.open_in_new_window, txt("open")),
                  onPressed: () =>
                      unawaited(openExternal(Uri.parse(clinic.publicUrl))),
                ),
      ],
      farItems: [
        Tooltip(
          message: txt("bookingInbox"),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (pending == 0 ? theme.inactiveColor : theme.accentColor)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Txt(
              pending == 0
                  ? (compact ? "0" : txt("bookingEmptyPending"))
                  : (compact
                      ? "$pending"
                      : "$pending ${txt("bookingPendingCount")}"),
              style: theme.typography.caption,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(FluentThemeData theme) {
    final lastPull = booking.requests.lastSuccessfulAt();
    return Container(
      width: double.infinity,
      decoration: topBarDecoration(context, Colors.grey),
      padding: const EdgeInsetsDirectional.only(
        start: 8,
        end: 8,
        top: 8,
        bottom: 8,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Row(
          spacing: 5,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ComboBox<String>(
              value: booking.requests.filter(),
              placeholder: Txt(txt("filter")),
              items: [
                ComboBoxItem(value: "pending", child: Txt(txt("pending"))),
                ComboBoxItem(
                    value: "handled", child: Txt(txt("bookingStatusHandled"))),
                ComboBoxItem(
                    value: "declined",
                    child: Txt(txt("bookingStatusDeclined"))),
              ],
              onChanged: (value) {
                if (value != null) booking.requests.switchFilter(value);
              },
            ),
            ToggleButton(
              checked: _sort == "newest",
              onChanged: (checked) {
                if (checked) setState(() => _sort = "newest");
              },
              child: Row(
                spacing: 3,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sort == "newest") const Icon(FluentIcons.sort_down),
                  Txt(txt("bookingSortNewest")),
                ],
              ),
            ),
            ToggleButton(
              checked: _sort == "oldest",
              onChanged: (checked) {
                if (checked) setState(() => _sort = "oldest");
              },
              child: Row(
                spacing: 3,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sort == "oldest") const Icon(FluentIcons.sort_up),
                  Txt(txt("bookingSortOldest")),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Txt(
              "${txt("bookingLastPull")}: "
              "${lastPull == null ? txt("bookingNever") : bookingSubmittedLabel(lastPull)}",
              style: theme.typography.caption,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildBanners(FluentThemeData theme) {
    if (booking.requests.revoked()) {
      return [_banner(txt("bookingKeyRevoked"))];
    }
    if (!booking.requests.connected()) {
      return [_banner(txt("bookingDisconnected"))];
    }
    if (booking.requests.stale()) {
      return [_banner(txt("bookingStale"))];
    }
    return const [];
  }

  Widget _buildRow(FluentThemeData theme, BookingRequest request) {
    final canSchedule = canScheduleBooking && request.isPending && !request.isExpired;
    final compact = MediaQuery.sizeOf(context).width < 700;
    return ContextMenuRegion(
      items: (context, controller) => [
        MenuFlyoutItem(
          onPressed: () => unawaited(openBookingRequestPanel(context, request)),
          text: Text(txt("open")),
        ),
        if (canSchedule)
          MenuFlyoutItem(
            onPressed: () =>
                unawaited(scheduleBookingRequest(context, request)),
            text: Text(txt("bookingSchedule")),
          ),
      ],
      child: ListTile(
        key: ValueKey(request.requestId),
        margin: EdgeInsets.zero,
        shape: listDividerBorder(context),
        contentPadding: const EdgeInsetsDirectional.only(
          top: 0,
          bottom: 5,
          start: 5,
          end: 10,
        ),
        tileColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return theme.resources.controlAltFillColorTertiary;
          }
          return theme.resources.solidBackgroundFillColorBase;
        }),
        onPressed: () => unawaited(openBookingRequestPanel(context, request)),
        title: Row(
          spacing: 5,
          children: [
            const Divider(size: 65, direction: Axis.vertical),
            _avatar(theme, request),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                spacing: 5,
                children: [
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: Text(
                        request.name,
                        style: theme.typography.bodyStrong,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (!compact)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _cell(
                              theme,
                              FluentIcons.phone,
                              txt("phone"),
                              request.phone,
                              150,
                              ltr: true,
                            ),
                            _cell(
                              theme,
                              FluentIcons.calendar,
                              txt("bookingPreference"),
                              bookingPreferenceLabel(request),
                              220,
                            ),
                            _cell(
                              theme,
                              FluentIcons.date_time,
                              txt("bookingSubmitted"),
                              bookingSubmittedLabel(request.createdAt),
                              175,
                            ),
                            _cell(
                              theme,
                              FluentIcons.tag,
                              txt("bookingReference"),
                              request.reference,
                              120,
                              ltr: true,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (canSchedule && !compact)
                    Tooltip(
                      message: txt("bookingSchedule"),
                      child: IconButton(
                        icon: const Icon(FluentIcons.calendar, size: 14),
                        onPressed: () =>
                            unawaited(scheduleBookingRequest(context, request)),
                      ),
                    ),
                  _statusChip(theme, request),
                  const SizedBox(width: 6),
                  Icon(
                    Directionality.of(context) == TextDirection.rtl
                        ? FluentIcons.chevron_left
                        : FluentIcons.chevron_right,
                    size: 12,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(FluentThemeData theme, BookingRequest request) {
    final color = switch (request.status) {
      "handled" => Colors.successPrimaryColor,
      "declined" => theme.inactiveColor,
      _ => theme.accentColor,
    };
    final name = request.name.trim();
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Text(
        name.isEmpty ? "?" : name.characters.first,
        style: theme.typography.bodyStrong!.copyWith(color: color),
      ),
    );
  }

  Widget _cell(
    FluentThemeData theme,
    IconData icon,
    String title,
    String content,
    double width, {
    bool ltr = false,
  }) {
    return Tooltip(
      message: "$title: $content",
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          border: BorderDirectional(
            end: BorderSide(color: theme.resources.dividerStrokeColorDefault),
          ),
        ),
        child: Row(
          spacing: 6,
          children: [
            Icon(icon, size: 16, color: theme.inactiveColor),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.typography.caption!.copyWith(
                        color: theme.resources.textFillColorSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    content,
                    textDirection: ltr ? TextDirection.ltr : null,
                    style: theme.typography.body,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(FluentThemeData theme, BookingRequest request) {
    final color = switch (request.status) {
      "handled" => Colors.successPrimaryColor,
      "declined" => theme.resources.textFillColorSecondary,
      _ => theme.accentColor,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        bookingStatusLabel(request.status),
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }

  Widget _empty(FluentThemeData theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Icon(FluentIcons.inbox, size: 32, color: theme.inactiveColor),
            Txt(
              txt("noResultsFound"),
              style: theme.typography.bodyStrong!
                  .copyWith(color: theme.resources.textFillColorDisabled),
            ),
          ],
        ),
      );

  Widget _notice(FluentThemeData theme, IconData icon, String message) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Icon(icon, size: 32, color: theme.inactiveColor),
              Txt(message),
            ],
          ),
        ),
      );

  Widget _banner(String message) => Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.warningPrimaryColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Txt(
          message,
          style: const TextStyle(color: Colors.warningPrimaryColor),
        ),
      );
}
