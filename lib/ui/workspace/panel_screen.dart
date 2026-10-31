import 'dart:async';

import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panel_window.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:apexo/ui/workspace/window_group.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/unsaved_dot.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
import 'package:apexo/ui/workspace/window_attachments.dart';
import 'package:apexo/ui/workspace/window_dock.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

part 'panel_visit_band.dart';

/// The panel host: the chrome drawn around whatever [Panel] is on screen — its
/// header, its record's editor, the switches for the record's other windows,
/// and the archive/save/close bar.
///
/// A panel holds its **first** window inline, as its own body: what used to be
/// the first tab is still the panel, so a panel is never an empty frame with a
/// row of buttons. The windows after it are what the panel floats beside
/// itself, drawn by `WindowsLayer` at the size their content needs and switched
/// from the dock under the panel's header.
///
/// It reaches the panel only through [Panel] and never touches the records
/// behind it. That is what lets one host draw a row panel, a delegated panel and
/// a hand-written panel alike, and why this file must not learn about drafts,
/// stores or account models.
final class PanelScreen extends StatefulWidget {
  const PanelScreen({
    required this.panel,
    this.layoutWidth = 500,
    super.key,
  });
  final double layoutWidth;
  final Panel panel;

  @override
  State<PanelScreen> createState() => _PanelScreenState();
}

class _PanelScreenState extends State<PanelScreen> {
  late bool isNew;
  final FocusNode focusNode = FocusNode();
  final panelSwitchController = FlyoutController();
  final confirmCancelController = FlyoutController();
  Timer? saveButtonCheckTimer;
  StreamSubscription<int>? pendingEditsSub;
  StreamSubscription<bool>? savingSub;

  @override
  void dispose() {
    saveButtonCheckTimer?.cancel();
    unawaited(pendingEditsSub?.cancel());
    unawaited(savingSub?.cancel());
    focusNode.dispose();
    panelSwitchController.dispose();
    confirmCancelController.dispose();
    super.dispose();
  }

  /// Copies the panel's verdict on [Panel.hasPendingEdits] — and its owned
  /// visits' — into the observable the bottom controls watch, so Save is enabled
  /// exactly while a save would write something.
  void _syncPendingEdits() {
    widget.panel.refreshDirty();
  }

  @override
  void initState() {
    super.initState();
    isNew = widget.panel.isNew;
    // A safety net: the opener reads the title before showing the panel, so this
    // costs nothing there, and covers a panel added without one.
    unawaited(widget.panel.readTitle());
    final signal = widget.panel.pendingEditsSignal;
    if (signal == null) {
      // Nothing to push: the kind's answer is its caller's callback, which can
      // only be asked, so it is sampled. Every other kind says so at once.
      saveButtonCheckTimer = Timer.periodic(
        const Duration(milliseconds: 750),
        (_) => _syncPendingEdits(),
      );
    } else {
      pendingEditsSub = signal.stream.listen((_) => _syncPendingEdits());
    }
    // A window of this panel saves with the panel's own write, so the panel is
    // the only place that hears about it. A new record becomes an existing one
    // there, and the dock and the archive button have to say so.
    savingSub = widget.panel.inProgress.stream.listen((saving) {
      if (saving || !mounted) return;
      _syncPendingEdits();
      if (widget.panel.isNew != isNew) {
        setState(() => isNew = widget.panel.isNew);
      }
    });
    _syncPendingEdits();
  }

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    return KeyboardListener(
      autofocus: true,
      focusNode: focusNode,
      onKeyEvent: (value) {
        if (value is KeyDownEvent &&
            value.logicalKey == LogicalKeyboardKey.escape &&
            PanelsManager.active().isNotEmpty &&
            widget.panel.inProgress() == false) {
          closeOrConfirmCancel();
        }
      },
      child: Container(
        margin: widget.layoutWidth < 490
            ? EdgeInsets.zero
            : const EdgeInsetsDirectional.only(
                top: 5, bottom: 5, start: 0, end: 5),
        decoration: BoxDecoration(
          // Keep the large editing surface subdued beneath floating windows.
          color: resources.solidBackgroundFillColorSecondary,
          boxShadow: [
            BoxShadow(
              color: resources.smokeFillColorDefault,
              offset: const Offset(0, 4),
              blurRadius: 16,
            ),
          ],
          border: Border.all(color: resources.surfaceStrokeColorDefault),
          borderRadius: BorderRadius.circular(5),
        ),
        child: MStreamBuilder(
            streams: [
              locale.selected.stream,
              PanelsManager.minimize.stream,
              // A visit attached to (or detached from) this panel mutates it
              // without replacing it: this is how the dock and the band hear it
              // (plan §6.2-2).
              widget.panel.attachments.stream,
            ],
            builder: (context, snapshot) {
              return Column(
                key: Key(locale.selected().toString()),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPanelHeader(),
                  if (PanelsManager.minimize() == false ||
                      widget.layoutWidth >= kWindowsBreakpoint) ...[
                    // The record's workspaces are part of the record, not of its
                    // chrome: a prominent row inside the panel, where they are
                    // seen with the content they open, instead of two icons lost
                    // among the window controls.
                    if (widget.panel.workspaceWindows.isNotEmpty)
                      _buildWorkspaceBar(),
                    // The visit bubble sits under the patient's workspaces: what
                    // it carries is about the patient, but it is not the patient
                    // record's own navigation.
                    if (widget.panel.attached case final session?)
                      _buildVisitBand(session),
                    // A panel that presents its windows as attachments and header
                    // actions has no dock: the same controls are already on the
                    // name and on the frames themselves (plan §4.4).
                    if (!widget.panel.attachmentLayout &&
                        widget.panel.floatingWindows.isNotEmpty) ...[
                      // Two docks can be on screen at once, so each says what it
                      // answers: this one is the panel's own record. The visit's
                      // band says its own line — the date and the state.
                      if (widget.panel.attached != null)
                        _buildDockLabel(txt('thisPatient')),
                      _buildWindowDock(),
                    ],
                    Expanded(child: _buildPrimaryWindow()),
                    if (widget.panel.attachmentLayout &&
                        widget.panel.panelAttachments.isNotEmpty)
                      _buildPanelAttachments(),
                    _buildBottomControls(),
                  ],
                ],
              );
            }),
      ),
    );
  }

  /// The tray of windows hanging off the panel itself — a patient's photos and
  /// page — drawn under the record and above the bottom bar, never as a dock.
  Widget _buildPanelAttachments() {
    return StreamBuilder<int>(
      stream: widget.panel.workspace.revision.stream,
      builder: (context, _) => WindowAttachments(
        windows: widget.panel.panelAttachments,
        accent: _accent,
        keyForWindow: (window) => WK.attachmentToggle(window.id),
        isOpen: (window) => widget.panel.workspace.isOpen(window.id),
        enabled: (window) => !(window.onlyIfSaved && isNew),
        onToggle: (window) => widget.panel.workspace.toggle(window.id),
      ),
    );
  }

  /// The panel's first window: the record's own editor, drawn in the panel
  /// itself just as the first tab used to be.
  ///
  /// While a record is carried beside this one — a visit on a patient — the
  /// host's fields stay visible but stop taking edits: the visit is the thing
  /// being worked on, and an accidental patient edit underneath it would be
  /// written by a different Save. Their existing unsaved work is still savable.
  Widget _buildPrimaryWindow() {
    final window = widget.panel.primaryWindow;
    if (window == null) return const SizedBox.shrink();
    final body = window.body;
    final readOnly = widget.panel.attached != null;
    final editor = window.scrollable
        ? SingleChildScrollView(
            padding: EdgeInsets.all(window.padding),
            child: body,
          )
        : Padding(
            padding: EdgeInsets.all(window.padding),
            child: body,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (readOnly) _buildReadOnlyNotice(),
        Expanded(
          child: ColoredBox(
            color: FluentTheme.of(context)
                .resources
                .solidBackgroundFillColorSecondary,
            child: readOnly
                ? Opacity(
                    opacity: 0.55,
                    child: AbsorbPointer(
                      child: Focus(
                        canRequestFocus: false,
                        descendantsAreFocusable: false,
                        child: editor,
                      ),
                    ),
                  )
                : editor,
          ),
        ),
        if (window.footer != null) window.footer!,
      ],
    );
  }

  /// Why the fields below the visit are not editable: the visit is the open
  /// record, and its Save writes the visit — never the patient underneath.
  Widget _buildReadOnlyNotice() {
    final theme = FluentTheme.of(context);
    return Container(
      key: WK.patientReadOnly,
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          _accent.withValues(alpha: 0.04),
          theme.resources.solidBackgroundFillColorSecondary,
        ),
        border: Border(
          bottom: BorderSide(color: theme.resources.dividerStrokeColorDefault),
        ),
      ),
      child: Row(
        children: [
          Icon(FluentIcons.lock, size: 11, color: theme.inactiveColor),
          const SizedBox(width: 6),
          Expanded(
            child: Txt(
              txt('patientReadOnlyWhileVisit'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.caption?.copyWith(
                fontSize: 10,
                color: theme.inactiveColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The line above a dock that says whose windows it switches, so two docks on
  /// one screen are never read as one list (plan §4.4).
  Widget _buildDockLabel(String label) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(10, 4, 10, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Txt(
          label,
          style: FluentTheme.of(context).typography.caption?.copyWith(
                fontSize: 10,
                color: FluentTheme.of(context).inactiveColor,
              ),
        ),
      ),
    );
  }

  /// The record's own workspaces — the chart, the visits list — as a row of
  /// labelled buttons at the top of its body, so they are seen with the record
  /// they open instead of hiding among the window controls.
  ///
  /// The row is the panel's dock, drawn the same way and by the same widget
  /// ([WindowDock]): equal segments filling the panel's width, joined with no
  /// gap and only the outer corners rounded, so the two read as one control
  /// naming the record's two workspaces rather than as two unrelated actions.
  ///
  /// Both are always drawn. Which one is *open* is the active state; the record
  /// still has the other one, so hiding it would make the pair look like a single
  /// control that changes identity. While a visit is attached, its chart is the
  /// chart on screen, so the Dental Chart button switches that window instead of
  /// looking in the patient's own slot.
  Widget _buildWorkspaceBar() {
    return MStreamBuilder(
      streams: [
        widget.panel.workspace.revision.stream,
        // A retained visit's draft marks the visits button while its windows are
        // not on screen, so the dot has to hear about an edit too.
        widget.panel.hasUnsavedChanges.stream,
      ],
      builder: (context, _) {
        final windows = <PanelWindow>[
          for (final id in widget.panel.workspaceWindows)
            if (_windowById(id) case final window?) window,
        ];
        if (windows.isEmpty) return const SizedBox.shrink();
        return WindowDock(
          windows: windows,
          padding: const EdgeInsetsDirectional.fromSTEB(8, 8, 8, 6),
          accent: _accent,
          keyForWindow: (window) => WK.workspaceWindowToggle(window.id),
          isOpen: (window) {
            final carried = _carriedWindowOf(window);
            return carried != null
                ? widget.panel.workspace.isOpen(carried.id, slot: kAttachedSlot)
                : widget.panel.workspace.isOpen(window.id);
          },
          enabled: (window) => !(window.onlyIfSaved && isNew),
          dirty: (window) =>
              widget.panel.recordsWindowId == window.id &&
              widget.panel.owned.any((owned) => owned.hasPendingEdits),
          onToggle: (window) {
            final carried = _carriedWindowOf(window);
            if (carried != null) {
              widget.panel.workspace.toggle(carried.id, slot: kAttachedSlot);
            } else {
              widget.panel.workspace.toggle(window.id);
            }
          },
        );
      },
    );
  }

  /// The window a carried record puts in [window]'s place — a visit's chart for
  /// the patient's — or null when the panel's own window is the one on screen.
  PanelWindow? _carriedWindowOf(PanelWindow window) {
    final attached = widget.panel.attached;
    final group = window.replacementGroup;
    if (attached == null || group == null) return null;
    return attached.windows
        .where((carried) => carried.replacementGroup == group)
        .firstOrNull;
  }

  /// The band the record this panel **carries** draws for itself.
  ///
  /// It reads the count of dirty carried records live — a draft hidden behind
  /// another visit is exactly the one a close prompt has to name (§2.4).
  Widget _buildVisitBand(HostedRecordSession session) {
    return StreamBuilder<bool>(
      stream: widget.panel.hasUnsavedChanges.stream,
      key: ValueKey('visit-band-${session.itemId}'),
      builder: (context, _) => _VisitBand(
        panel: widget.panel,
        session: session,
        dirtyVisits:
            widget.panel.owned.where((owned) => owned.hasPendingEdits).length,
      ),
    );
  }

  /// The switches for everything the panel does not keep inline: one labelled
  /// pill per window, showing whether it is on screen.
  ///
  /// The panel's own record only. A record it carries beside itself draws its own
  /// dock — the visit band — with its own accent and its own label line, so two
  /// docks cannot be mistaken for one list (plan §4.4).
  ///
  /// **One chart on screen**: while a visit is attached, the visit's chart *is*
  /// the chart, so the patient's entry for the same editor is not offered again
  /// (plan §4.3).
  Widget _buildWindowDock() {
    return StreamBuilder<int>(
      stream: widget.panel.workspace.revision.stream,
      builder: (context, _) => StreamBuilder<bool>(
        stream: widget.panel.hasUnsavedChanges.stream,
        builder: (context, _) {
          final carried = widget.panel.attached;
          final carriedGroups = <String>{
            if (carried != null)
              for (final window in carried.windows)
                if (window.replacementGroup != null) window.replacementGroup!,
          };
          final windows = <PanelWindow>[
            for (final window in widget.panel.floatingWindows)
              if (!carriedGroups.contains(window.replacementGroup)) window,
          ];
          final recordsWindow = widget.panel.recordsWindowId;
          return WindowDock(
            windows: windows,
            isOpen: (window) => widget.panel.workspace.isOpen(window.id),
            enabled: (window) => !(window.onlyIfSaved && isNew),
            accent: _accent,
            // A retained draft whose windows are not on screen still has a mark
            // here: the Visits pill is what makes §2.4 visible.
            dirty: (window) =>
                recordsWindow != null &&
                window.id == recordsWindow &&
                widget.panel.owned.any((owned) => owned.hasPendingEdits),
            onToggle: (window) => widget.panel.workspace.toggle(window.id),
          );
        },
      ),
    );
  }

  /// The colour this kind of record is known by, so a patient's panel and a
  /// visit's are told apart at a glance instead of by reading the header.
  Color get _accent =>
      widget.panel.accent ?? FluentTheme.of(context).accentColor;

  Widget _buildPanelHeader() {
    return GestureDetector(
      onTap: () {
        if (PanelsManager.minimize()) PanelsManager.minimize(false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2.8, horizontal: 5),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            _accent.withValues(alpha: 0.10),
            FluentTheme.of(context).resources.solidBackgroundFillColorSecondary,
          ),
          border:
              Border(bottom: BorderSide(color: _accent.withValues(alpha: 0.5))),
        ),
        child: StreamBuilder(
            stream: widget.panel.inProgress.stream,
            builder: (context, snapshot) {
              return Row(
                children: [
                  _buildPanelHeaderStoreName(),
                  // The record's name. Its workspaces are no longer header
                  // icons: they are the labelled buttons at the top of the body,
                  // where the record they open is.
                  Expanded(child: _buildPanelHeaderItemName()),
                  Row(children: [
                    if (PanelsManager.active().length > 1)
                      _buildPanelSwitcher(),
                    // minimization is useless is prevented in big screens
                    if (widget.layoutWidth < kWindowsBreakpoint)
                      _buildPanelMinimizeButton(),
                    widget.panel.inProgress()
                        ? const SizedBox(
                            height: 20, width: 20, child: ProgressRing())
                        : _buildPanelCloseButton()
                  ])
                ],
              );
            }),
      ),
    );
  }

  Widget _buildPanelCloseButton() {
    return FlyoutTarget(
      controller: confirmCancelController,
      child: IconButton(
        icon: const Icon(WindowsIcons.cancel),
        onPressed: closeOrConfirmCancel,
      ),
    );
  }

  IconButton _buildPanelMinimizeButton() {
    return IconButton(
      key: WK.panelMinimize,
      icon: Icon(PanelsManager.minimize()
          ? WindowsIcons.chevron_up
          : WindowsIcons.chevron_down),
      onPressed: () => PanelsManager.minimize(!PanelsManager.minimize()),
    );
  }

  FlyoutTarget _buildPanelSwitcher() {
    return FlyoutTarget(
      controller: panelSwitchController,
      child: IconButton(
        icon: Row(
          spacing: 2,
          children: [
            const Icon(FluentIcons.reopen_pages),
            Text(
              PanelsManager.active().length.toString(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            )
          ],
        ),
        onPressed: openPanelSwitch,
      ),
    );
  }

  Widget _buildPanelHeaderStoreName() {
    return SizedBox(
      width: 105,
      child: Row(
        children: [
          // The record kind, as a badge in the kind's own colour: the header of
          // a patient's panel and of a visit's look the same otherwise.
          Flexible(
            child: StreamBuilder<bool>(
              // Whether this record holds work that has not been stored: the dot
              // sits on the badge, above everything else the panel shows.
              stream: widget.panel.hasUnsavedChanges.stream,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsetsDirectional.fromSTEB(4, 1, 6, 1),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                      border:
                          Border.all(color: _accent.withValues(alpha: 0.45)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Txt(widget.panel.unicodeSymbol,
                            style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Txt(
                            txt(widget.panel.singularName),
                            style: TextStyle(
                                fontSize: 11,
                                color: _accent,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.panel.hasUnsavedChanges())
                    PositionedDirectional(
                      top: -4,
                      start: -4,
                      child: Tooltip(
                        message: txt('unsavedChanges'),
                        child: const UnsavedDot(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelHeaderItemName() {
    return widget.panel.buildTitle(context);
  }

  PanelWindow? _windowById(String id) {
    for (final window in widget.panel.rowWindows) {
      if (window.id == id) return window;
    }
    return null;
  }

  Widget _buildBottomControls() {
    return Container(
      constraints: const BoxConstraints(minHeight: 50, minWidth: 350),
      child: StreamBuilder(
          stream: widget.panel.inProgress.stream,
          builder: (context, snapshot) {
            return Container(
              decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
              child: widget.panel.inProgress()
                  ? const Center(child: ProgressBar())
                  // A wrap rather than a row: three labelled buttons and a
                  // language that spells them out at length are wider than a
                  // 350-pixel panel, and a second line reads better than a bar
                  // that clips its own Save.
                  : Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (widget.panel.additionalControls != null)
                          widget.panel.additionalControls!,
                        if (widget.panel.showBottomControls) ...[
                          if (isNew == false) _buildArchiveButton(),
                          _buildSaveButton(),
                        ],
                        _buildCancelButton(),
                      ],
                    ),
            );
          }),
    );
  }

  Widget _buildCancelButton() {
    return FlyoutTarget(
      controller: confirmCancelController,
      child: StreamBuilder<bool>(
          stream: widget.panel.hasUnsavedChanges.stream,
          builder: (context, _) {
            return IconButton(
              key: WK.panelClose,
              onPressed: closeOrConfirmCancel,
              style: greyButtonStyle.copyWith(
                textStyle:
                    const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
                backgroundColor: widget.panel.hasUnsavedChanges()
                    ? WidgetStatePropertyAll(Colors.orange)
                    : const WidgetStatePropertyAll(Colors.grey),
              ),
              icon: ButtonContent(
                WindowsIcons.cancel,
                widget.panel.hasUnsavedChanges() ? txt("cancel") : txt("close"),
              ),
            );
          }),
    );
  }

  Widget _buildSaveButton() {
    return StreamBuilder<bool>(
        stream: widget.panel.hasUnsavedChanges.stream,
        builder: (context, _) {
          // This button writes **this panel's** record and nothing else: a visit
          // attached to the panel is saved by its own Save, in the band or in one
          // of its windows. Only the workspace close command offers Save all.
          final hasChanges = widget.panel.hasPendingEdits;
          return IconButton(
            key: WK.panelSave,
            onPressed: hasChanges
                ? () async {
                    try {
                      await widget.panel.save();
                    } catch (e, st) {
                      logger('Saving "${widget.panel.itemId}" failed', st);
                      showErrorMessage(e, "savingFailed");
                      return;
                    }
                    if (!mounted) return;
                    _syncPendingEdits();
                    setState(() => isNew = widget.panel.isNew);
                  }
                : null,
            style: greyButtonStyle.copyWith(
              textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
              backgroundColor: WidgetStatePropertyAll(hasChanges
                  ? Colors.blue
                  : Colors.grey.withValues(alpha: 0.25)),
            ),
            icon: ButtonContent(WindowsIcons.save, txt(widget.panel.saveLabel)),
          );
        });
  }

  Widget _buildArchiveButton() {
    final isArchived = widget.panel.isArchived;
    final icon = isArchived ? WindowsIcons.undo : WindowsIcons.delete;
    final action = txt(isArchived ? "restore" : "delete");
    final color = isArchived ? Colors.teal : Colors.grey;
    return widget.panel.archiveButtonReplacement ??
        DeleteButton(
          key: WK.panelArchive,
          actionText: action,
          actionIcon: icon,
          restorable: true,
          preview: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 5,
            children: [
              Icon(widget.panel.icon),
              Txt(
                "${txt(widget.panel.singularName)}:",
                style: FluentTheme.of(context).typography.bodyStrong,
              ),
              widget.panel.buildTitle(context),
            ],
          ),
          onConfirm: () async {
            try {
              await widget.panel.setArchived(!isArchived);
            } catch (e, st) {
              logger('Archiving "${widget.panel.itemId}" failed', st);
              showErrorMessage(e, "savingFailed");
              return;
            }
            if (!mounted) return;
            _syncPendingEdits();
            setState(() {});
          },
          style: greyButtonStyle.copyWith(
            backgroundColor: WidgetStatePropertyAll(color),
            textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
          ),
          child:
              ButtonContent(icon, "$action ${txt(widget.panel.singularName)}"),
        );
  }

  void closeOrConfirmCancel() async {
    if (widget.panel.anyUnsavedChanges == false) {
      PanelsManager.close(widget.panel.itemId);
    } else {
      await flyoutFocusFix(context);
      if (!mounted) return;
      unawaited(confirmCancelController.showFlyout<void>(builder: (context) {
        // Every record this panel is responsible for holding work: its own, and
        // every visit it carries — including ones whose windows are not on
        // screen (plan §2.4, §4.6).
        final dirtyVisits = widget.panel.owned
            .where((session) => session.hasPendingEdits)
            .toList();
        return FlyoutContent(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            spacing: 10,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Txt(txt("sureClosePanel")),
              if (dirtyVisits.isNotEmpty) ...[
                Txt(
                  txt('closePatientClosesVisits'),
                  style: FluentTheme.of(context)
                      .typography
                      .caption
                      ?.copyWith(fontSize: 11),
                ),
                for (final session in dirtyVisits)
                  Row(
                    children: [
                      Txt(session.unicodeSymbol,
                          style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Txt(
                          session.displayTitle,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  FilledButton(
                    style: filledButtonStyle(Colors.blue),
                    onPressed: () {
                      Flyout.of(context).close();
                      unawaited(_saveAllAndClose());
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.save, size: 14),
                        const SizedBox(width: 5),
                        Txt(txt('closePromptSaveAll')),
                      ],
                    ),
                  ),
                  // Offered whenever anything here is dirty — the panel's own
                  // record as much as a visit it carries. Without it a panel
                  // dirty only in its own fields would have no way out but Save.
                  FilledButton(
                    style: filledButtonStyle(Colors.warningPrimaryColor),
                    onPressed: () {
                      Flyout.of(context).close();
                      // Discarding means the drafts go with the panel — the
                      // only path that loses work, and it says so.
                      PanelsManager.close(widget.panel.itemId);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.delete, size: 14),
                        const SizedBox(width: 5),
                        Txt(txt('closePromptDiscardAll')),
                      ],
                    ),
                  ),
                  CloseButtonInDialog(
                      buttonText: txt('closePromptKeepEditing')),
                ],
              ),
            ],
          ),
        );
      }));
    }
  }

  /// Writes every record this panel holds — its own and each carried visit —
  /// and closes it once they are all written.
  ///
  /// Not atomic: a failure is reported by name and the panel stays open, so a
  /// record that could not be written is not thrown away with the ones that
  /// were (plan §4.6).
  Future<void> _saveAllAndClose() async {
    final panel = widget.panel;
    final owners = <WindowRecordSession>[panel, ...panel.owned];
    if (owners.any((owner) => owner.inProgress())) return;
    final failed = <String>[];
    if (panel.hasPendingEdits) {
      try {
        await panel.save();
      } catch (e, st) {
        logger('Saving "${panel.itemId}" failed', st);
        failed.add(panel.displayTitle);
      }
    }
    for (final session in owners.whereType<HostedRecordSession>()) {
      if (!mounted ||
          !identical(widget.panel, panel) ||
          !PanelsManager.active().contains(panel) ||
          !panel.owned.contains(session)) {
        return;
      }
      if (!session.hasPendingEdits) continue;
      try {
        await session.save();
      } catch (e, st) {
        logger('Saving "${session.itemId}" failed', st);
        failed.add(session.displayTitle);
      }
    }
    if (!mounted) return;
    if (failed.isNotEmpty) {
      showErrorMessage(
        Exception('${txt('savingFailed')}: ${failed.join(' · ')}'),
        'savingFailed',
      );
      return;
    }
    if (!identical(widget.panel, panel) ||
        !PanelsManager.active().contains(panel) ||
        panel.anyUnsavedChanges ||
        owners.any((owner) => owner.inProgress()) ||
        panel.owned.length != owners.length - 1 ||
        !panel.owned.every(owners.contains)) {
      return;
    }
    PanelsManager.close(panel.itemId);
  }

  void openPanelSwitch() async {
    await flyoutFocusFix(context);
    unawaited(panelSwitchController.showFlyout<void>(
      barrierDismissible: widget.layoutWidth < kWindowsBreakpoint,
      dismissWithEsc: true,
      dismissOnPointerMoveAway: true,
      builder: (context) => MenuFlyout(items: [
        ...([...PanelsManager.active()]
              ..sort((a, b) => b.creationDate - a.creationDate))
            .map((panel) {
          return MenuFlyoutItem(
            selected: panel == widget.panel,
            leading: Icon(panel.icon),
            trailing: panel.inProgress()
                ? const SizedBox(height: 20, width: 20, child: ProgressRing())
                : Icon(panel.isNew ? FluentIcons.add : FluentIcons.edit),
            // `displayTitle` is a key while the record is new, so it is
            // translated here like the header: a language switch relabels a
            // panel that is already open.
            text: Txt("${txt(panel.singularName)}: ${txt(panel.displayTitle)}",
                style: TextStyle(
                    fontWeight:
                        panel == widget.panel ? FontWeight.w500 : null)),
            onPressed: () => PanelsManager.bringToFront(
                PanelsManager.active().indexOf(panel)),
            closeAfterClick: true,
          );
        })
      ]),
    ));
  }
}
