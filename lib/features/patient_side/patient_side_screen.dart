import 'dart:io' show File, Platform;
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/language_picker.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/patient_side.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:apexo/utils/save_file/save_file_platform.dart';

class PatientSideScreen extends StatefulWidget {
  const PatientSideScreen({super.key});

  @override
  State<PatientSideScreen> createState() => _PatientSideScreenState();
}

class _PatientSideScreenState extends State<PatientSideScreen> {
  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
      streams: [patientSide.stream],
      builder: (context, _) {
        return _buildBody(context);
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    final theme = FluentTheme.of(context);
    final appointments = patientSide.appointments;

    final totalPrice = appointments.fold(0.0, (s, a) => s + a.price);
    final totalPaid = appointments.fold(0.0, (s, a) => s + a.paid);
    final balance = totalPrice - totalPaid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Hero Header ──────────────────────────────────────────────────────
        _HeroHeader(
          name: patientSide.name,
          totalPrice: totalPrice,
          totalPaid: totalPaid,
          balance: balance,
          currency: patientSide.currency,
          clinicNameAndAddress: patientSide.clinicNameAndAddress,
          phone: patientSide.phone,
          countryCode: patientSide.countryCode,
          theme: theme,
        ),

        // ── Tab bar ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _TabChip(
                label: txt("appointments"),
                icon: FluentIcons.calendar,
                selected: _selectedTab == 0,
                onTap: () => setState(() => _selectedTab = 0),
              ),
              const SizedBox(width: 8),
              _TabChip(
                label: txt("gallery"),
                icon: FluentIcons.camera,
                selected: _selectedTab == 1,
                onTap: () => setState(() => _selectedTab = 1),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ── Tab content ──────────────────────────────────────────────────────
        Expanded(
          child: _selectedTab == 0
              ? _AppointmentTimeline(
                  appointments: appointments,
                  currency: patientSide.currency,
                  theme: theme,
                )
              : _PhotoGallery(
                  imgLinks: patientSide.imgLinks,
                  getThumb: patientSide.getThumbFromImgLink,
                  theme: theme,
                ),
        ),
      ],
    );
  }
}

// ── Hero Header ─────────────────────────────────────────────────────────────

class _HeroHeader extends StatefulWidget {
  const _HeroHeader({
    required this.name,
    required this.totalPrice,
    required this.totalPaid,
    required this.balance,
    required this.currency,
    required this.clinicNameAndAddress,
    required this.phone,
    required this.countryCode,
    required this.theme,
  });

  final String name;
  final double totalPrice;
  final double totalPaid;
  final double balance;
  final String currency;
  final String clinicNameAndAddress;
  final String phone;
  final String countryCode;
  final FluentThemeData theme;

  @override
  State<_HeroHeader> createState() => _HeroHeaderState();
}

class _HeroHeaderState extends State<_HeroHeader> {
  bool _showClinicInfo = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.theme.accentColor;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.dark,
            accent,
            accent.lighter,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Clinic quick info line
          if (widget.clinicNameAndAddress.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() => _showClinicInfo = !_showClinicInfo),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withAlpha(100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(FluentIcons.hospital,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.clinicNameAndAddress.split('\n').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _showClinicInfo
                          ? FluentIcons.chevron_up
                          : FluentIcons.chevron_down,
                      color: Colors.white.withAlpha(180),
                      size: 10,
                    ),
                  ],
                ),
              ),
            ),

          if (_showClinicInfo) ...[
            const SizedBox(height: 12),
            // Expanded Clinic Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withAlpha(40)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.clinicNameAndAddress.contains('\n'))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(FluentIcons.map_pin,
                              color: Colors.white.withAlpha(200), size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.clinicNameAndAddress
                                  .substring(widget.clinicNameAndAddress
                                          .indexOf('\n') +
                                      1)
                                  .trim(),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.phone.isNotEmpty)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _HeaderCommunicationAction(
                          icon: FluentIcons.phone,
                          label: txt("call"),
                          onTap: () =>
                              launchUrl(Uri.parse("tel:${widget.phone}")),
                        ),
                        _HeaderCommunicationAction(
                          icon: FluentIcons.message,
                          label: txt("text"),
                          onTap: () =>
                              launchUrl(Uri.parse("sms:${widget.phone}")),
                        ),
                        _HeaderCommunicationAction(
                          icon: FluentIcons.chat,
                          label: txt("whatsapp"),
                          onTap: () {
                            final cleanCode =
                                widget.countryCode.replaceAll('+', '').trim();
                            final cleanPhone =
                                widget.phone.replaceAll(RegExp(r'\D'), '');
                            launchUrl(Uri.parse(
                                "https://wa.me/$cleanCode$cleanPhone"));
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Greeting & Top Actions
          StreamBuilder(
              stream: localSettings.stream,
              builder: (context, asyncSnapshot) {
                return Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(FluentIcons.contact,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            txt("hello"),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Text(
                            widget.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    LanguagePicker(key: ValueKey(localSettings.selectedLocale)),
                    const SizedBox(width: 4),
                    Tooltip(
                      message: txt("logout"),
                      child: IconButton(
                        icon: const Icon(FluentIcons.power_button,
                            color: Colors.white, size: 18),
                        onPressed: patientSide.logout,
                      ),
                    ),
                  ],
                );
              }),

          const SizedBox(height: 6),

          // Financial summary cards
          Row(
            children: [
              Expanded(
                child: _FinancialChip(
                  label: txt("totalPayments"),
                  value: widget.totalPaid,
                  currency: widget.currency,
                  icon: FluentIcons.money,
                  positive: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FinancialChip(
                  label: widget.balance > 0
                      ? txt("underpaid")
                      : widget.balance < 0
                          ? txt("overpaid")
                          : txt("fullyPaid"),
                  value: widget.balance.abs(),
                  currency: widget.currency,
                  icon: widget.balance > 0
                      ? FluentIcons.warning
                      : widget.balance < 0
                          ? FluentIcons.chevron_up_small
                          : FluentIcons.accept,
                  positive: widget.balance <= 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderCommunicationAction extends StatelessWidget {
  const _HeaderCommunicationAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        final isHovering = states.contains(WidgetState.hovered);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isHovering ? Colors.white.withAlpha(40) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FinancialChip extends StatelessWidget {
  const _FinancialChip({
    required this.label,
    required this.value,
    required this.currency,
    required this.icon,
    required this.positive,
  });

  final String label;
  final double value;
  final String currency;
  final IconData icon;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(positive ? 30 : 45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: 11,
                  ),
                ),
                Text(
                  "${value.toStringAsFixed(0)} $currency",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Clinic Info Card ──────────────────────────────────────────────────────────

// The _ClinicCard class and _CommunicationAction are removed as per instructions.

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? theme.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? theme.accentColor
                : theme.resources.controlStrokeColorDefault,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected
                  ? Colors.white
                  : theme.resources.textFillColorPrimary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected
                    ? Colors.white
                    : theme.resources.textFillColorPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentTimeline extends StatelessWidget {
  const _AppointmentTimeline({
    required this.appointments,
    required this.currency,
    required this.theme,
  });

  final List<PatientAppointment> appointments;
  final String currency;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (appointments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.calendar_agenda,
              size: 48,
              color: theme.resources.textFillColorTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              txt("noAppointmentsFound"),
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.resources.textFillColorSecondary),
            ),
          ],
        ),
      );
    }

    // Sort newest first
    final sorted = [...appointments]..sort((a, b) => b.date.compareTo(a.date));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        return _AppointmentCard(
          appointment: sorted[index],
          currency: currency,
          theme: theme,
          isFirst: index == 0,
          isLast: index == sorted.length - 1,
          order: sorted.length - index,
        );
      },
    );
  }
}

class _AppointmentCard extends StatefulWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.currency,
    required this.theme,
    required this.isFirst,
    required this.isLast,
    required this.order,
  });

  final PatientAppointment appointment;
  final String currency;
  final FluentThemeData theme;
  final bool isFirst;
  final bool isLast;
  final int order;

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand the most recent appointment
    if (widget.isFirst) _expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    final apt = widget.appointment;
    final theme = widget.theme;
    final isPaid = apt.price == 0 || apt.paid >= apt.price;
    final payColor =
        isPaid ? Colors.successPrimaryColor : Colors.warningPrimaryColor;
    final dateStr = DateFormat("d MMM yyyy", locale.s.$code).format(apt.date);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline column
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: widget.isFirst
                          ? theme.accentColor
                          : theme.resources.subtleFillColorTertiary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isFirst
                            ? theme.accentColor
                            : theme.resources.controlStrokeColorDefault,
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        "${widget.order}",
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: widget.isFirst
                              ? Colors.white
                              : theme.resources.textFillColorSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (!widget.isLast)
                    Container(
                      width: 2,
                      height: _expanded
                          ? (apt.prescriptions.isEmpty
                              ? 80
                              : 80 + apt.prescriptions.length * 28.0)
                          : 60,
                      color: theme.resources.controlStrokeColorDefault,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                    ),
                ],
              ),
            ),
            // Card
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.isFirst
                          ? theme.accentColor.withAlpha(120)
                          : theme.resources.controlStrokeColorDefault,
                    ),
                    boxShadow: widget.isFirst
                        ? [
                            BoxShadow(
                              color: theme.accentColor.withAlpha(30),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row (always visible)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                        child: Row(
                          children: [
                            Icon(
                              FluentIcons.calendar,
                              size: 14,
                              color: theme.resources.textFillColorSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: theme.resources.textFillColorPrimary,
                              ),
                            ),
                            if (widget.isFirst) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.accentColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  apt.isDone
                                      ? txt("lastVisit")
                                      : txt("nextVisit"),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 10),
                                ),
                              ),
                            ],
                            if (apt.isDone) ...[
                              const SizedBox(width: 8),
                              const Icon(FluentIcons.completed,
                                  size: 14, color: Colors.successPrimaryColor),
                            ],
                            if (apt.archived) ...[
                              const SizedBox(width: 8),
                              Icon(FluentIcons.archive,
                                  size: 14,
                                  color:
                                      theme.resources.textFillColorSecondary),
                            ],
                            const Spacer(),
                            // Pay badge
                            if (apt.isDone)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: payColor.withAlpha(25),
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: payColor.withAlpha(80)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isPaid
                                          ? FluentIcons.accept
                                          : FluentIcons.warning,
                                      size: 10,
                                      color: payColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      apt.price == 0
                                          ? "—"
                                          : "${apt.paid.toStringAsFixed(0)} / ${apt.price.toStringAsFixed(0)} ${widget.currency}",
                                      style: TextStyle(
                                        color: payColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(width: 6),
                            Icon(
                              _expanded
                                  ? FluentIcons.chevron_up
                                  : FluentIcons.chevron_down,
                              size: 12,
                              color: theme.resources.textFillColorTertiary,
                            ),
                          ],
                        ),
                      ),

                      // Expanded section
                      if (_expanded) ...[
                        Divider(
                          style: DividerThemeData(
                            horizontalMargin:
                                const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: theme.resources.controlStrokeColorDefault,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Precise timing
                              Row(
                                children: [
                                  Icon(
                                    FluentIcons.clock,
                                    size: 12,
                                    color:
                                        theme.resources.textFillColorSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat.yMMMMEEEEd(locale.s.$code)
                                        .add_jm()
                                        .format(apt.date),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: theme
                                          .resources.textFillColorSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (apt.prescriptions.isNotEmpty) ...[
                                Row(
                                  children: [
                                    Icon(
                                      FluentIcons.medication_admin,
                                      size: 13,
                                      color: theme
                                          .resources.textFillColorSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      txt("prescription"),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: theme
                                            .resources.textFillColorSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: apt.prescriptions
                                      .map((p) => _PrescriptionPill(
                                            label: p,
                                            theme: theme,
                                          ))
                                      .toList(),
                                ),
                              ],
                              if (apt.imgs.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(
                                      FluentIcons.camera,
                                      size: 13,
                                      color: theme.accentColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "${apt.imgs.length} ${txt("photos")}",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.accentColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  height: 60,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: apt.imgs.length,
                                    itemBuilder: (context, index) {
                                      final url = patientSide.getImgLink(
                                          apt.id, apt.imgs[index]);
                                      final thumb =
                                          patientSide.getThumbFromImgLink(url);
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: _PhotoTile(
                                          thumbUrl: thumb,
                                          fullUrl: url,
                                          theme: theme,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrescriptionPill extends StatelessWidget {
  const _PrescriptionPill({required this.label, required this.theme});
  final String label;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.accentColor.withAlpha(18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.accentColor.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.pill, size: 11, color: theme.accentColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: theme.accentColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Photo Gallery ────────────────────────────────────────────────────────────

class _PhotoGallery extends StatelessWidget {
  const _PhotoGallery({
    required this.imgLinks,
    required this.getThumb,
    required this.theme,
  });

  final List<String> imgLinks;
  final String Function(String) getThumb;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (imgLinks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.camera,
              size: 48,
              color: theme.resources.textFillColorTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              txt("noPhotos"),
              style: TextStyle(color: theme.resources.textFillColorSecondary),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: imgLinks.length,
      itemBuilder: (context, index) {
        final url = imgLinks[index];
        final thumb = getThumb(url);
        return _PhotoTile(
          thumbUrl: thumb,
          fullUrl: url,
          theme: theme,
        );
      },
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.thumbUrl,
    required this.fullUrl,
    required this.theme,
  });

  final String thumbUrl;
  final String fullUrl;
  final FluentThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          thumbUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: ProgressRing(),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            color: theme.cardColor,
            child: Icon(
              FluentIcons.photo_error,
              color: theme.resources.textFillColorTertiary,
            ),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    showDialog(
      dismissWithEsc: true,
      barrierDismissible: true,
      context: context,
      builder: (ctx) => ContentDialog(
        style: dialogStyling(context, false).merge(
          const ContentDialogThemeData(
            decoration: BoxDecoration(color: Colors.transparent),
          ),
        ),
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 700),
        content: SizedBox(
          width: double.infinity,
          height: 600,
          child: InteractiveViewer(
            clipBehavior: Clip.none,
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.network(
              fullUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(child: ProgressRing());
              },
            ),
          ),
        ),
        actions: [
          FilledButton(
            style: filledButtonStyle(Colors.grey),
            child: ButtonContent(FluentIcons.cancel, txt("close")),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          FilledButton(
            style: filledButtonStyle(Colors.blue),
            child: ButtonContent(FluentIcons.save, txt("save")),
            onPressed: () => _saveImage(fullUrl, context),
          ),
        ],
      ),
    );
  }

  Future<void> _saveImage(String url, BuildContext context) async {
    try {
      final fileName = "ap_img_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final response = await http.get(Uri.parse(url));
      final bytes = response.bodyBytes;

      if (kIsWeb) {
        SaveFilePlatform.saveFileWeb(bytes, fileName);
      } else if (!kIsWeb && Platform.isWindows) {
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Photo',
          fileName: fileName,
        );
        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsBytes(bytes);
        }
      } else if (!kIsWeb) {
        // Android / iOS
        final directory = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        final file = File("${directory.path}/$fileName");
        await file.writeAsBytes(bytes);

        if (context.mounted) {
          displayInfoBar(
            context,
            builder: (context, close) => InfoBar(
              title: const Text('Saved!'),
              content: Text('Photo saved to ${file.path}'),
              severity: InfoBarSeverity.success,
              onClose: close,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        displayInfoBar(
          context,
          builder: (context, close) => InfoBar(
            title: const Text('Error saving photo'),
            content: Text(e.toString()),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    }
  }
}
