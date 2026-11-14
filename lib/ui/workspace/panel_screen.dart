import 'dart:async';

import 'package:apexo/common_widgets/app_menu_flyout.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
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
import 'package:apexo/utils/app_flyout_controller.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

part 'panel_visit_band.dart';

/// The chrome around whatever [Panel] is on screen: its first window is the body.
/// Reaches the panel only through [Panel], never the records behind it.
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
  final panelSwitchController = AppFlyoutController();
  final confirmCancelController = AppFlyoutController();
  Timer? saveButtonCheckTimer;
  StreamSubscription<int>? pendingEditsSub;
  StreamSubscription<bool>? savingSub;

  /// The visit the band last drew: a band replacing another visit's replays its
  /// arrival faster than the panel's first band.
  String? _bandSessionId;

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

  void _syncPendingEdits() {
    widget.panel.refreshDirty();
  }

  @override
  void initState() {
    super.initState();
    isNew = widget.panel.isNew;
    // The opener reads the title first; this covers a panel added without one.
    unawaited(widget.panel.readTitle());
    final signal = widget.panel.pendingEditsSignal;
    if (signal == null) {
      // This kind can only be asked, not pushed, so it is sampled.
      saveButtonCheckTimer = Timer.periodic(
        const Duration(milliseconds: 750),
        (_) => _syncPendingEdits(),
      );
    } else {
      pendingEditsSub = signal.stream.listen((_) => _syncPendingEdits());
    }
    // A window saves with the panel's own write, so isNew is re-read after it.
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
    final materials = FluentMaterials.of(context);
    // Below the breakpoint the panel is an overlay that covers the screen, app
    // bar included; a translucent fill would let the bar read through it.
    final covering = widget.layoutWidth < kWindowsBreakpoint;
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
          color: covering ? materials.layerOpaque : materials.layer,
          boxShadow: materials.windowShadowInactive,
          border: Border.all(
            color: materials.strongStroke,
            width: FluentMaterials.hairlineWidth,
          ),
          borderRadius: FluentMaterials.surfaceRadius,
        ),
        child: MStreamBuilder(
            streams: [
              locale.selected.stream,
              PanelsManager.minimize.stream,
              // Attaching or detaching a visit mutates the panel in place; only this
              // stream announces it.
              widget.panel.attachments.stream,
            ],
            builder: (context, snapshot) {
              // Where the shell leaves the status bar over the panel — a page
              // that runs to the top edge — the content starts below it.
              final collapsed = PanelsManager.minimize() &&
                  widget.layoutWidth < kWindowsBreakpoint;
              final statusBar =
                  collapsed ? 0.0 : MediaQuery.paddingOf(context).top;
              final attached = widget.panel.attached;
              // Only the panel's first band unfolds with the record; a band
              // that takes another visit's place arrives quicker and keeps its
              // height, so switching visits does not shove the record about.
              final replacing = attached != null &&
                  _bandSessionId != null &&
                  _bandSessionId != attached.itemId;
              _bandSessionId = attached?.itemId;
              return Column(
                key: Key(locale.selected().toString()),
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (statusBar > 0) SizedBox(height: statusBar),
                  _buildPanelHeader(),
                  if (PanelsManager.minimize() == false ||
                      widget.layoutWidth >= kWindowsBreakpoint) ...[
                    if (widget.panel.workspaceWindows.isNotEmpty)
                      _buildWorkspaceBar(),
                    if (widget.panel.attached case final session?)
                      _buildVisitBand(session, replacing: replacing),
                    if (widget.panel.carriedBandFooter case final footer?)
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.fromSTEB(8, 0, 8, 4),
                        child: footer,
                      ),
                    // Attachment-layout panels already show these controls on the
                    // header and the frames.
                    if (!widget.panel.attachmentLayout &&
                        widget.panel.floatingWindows.isNotEmpty) ...[
                      // Two docks can be on screen at once, so this label says whose
                      // windows it switches.
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

  /// The panel's first window, drawn inline. While a visit is carried, the record's
  /// fields are read-only so the panel's Save cannot write an accidental edit.
  Widget _buildPrimaryWindow() {
    final window = widget.panel.primaryWindow;
    if (window == null) return const SizedBox.shrink();
    final readOnly = widget.panel.attached != null;
    // Blocking inside the scroll view keeps its scrollable ancestor hit-testable,
    // so read-only content can still be scrolled but never edited.
    final body = readOnly
        ? AbsorbPointer(
            child: Focus(
              canRequestFocus: false,
              descendantsAreFocusable: false,
              child: window.body,
            ),
          )
        : window.body;
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
            color: Colors.transparent,
            child: readOnly ? Opacity(opacity: 0.55, child: editor) : editor,
          ),
        ),
        if (window.footer != null) window.footer!,
      ],
    );
  }

  Widget _buildReadOnlyNotice() {
    final theme = FluentTheme.of(context);
    // Revealed rather than inserted, so the record under it slides down with
    // the band that takes the edits away.
    return _Reveal(
      child: Container(
        key: WK.patientReadOnly,
        width: double.infinity,
        padding: const EdgeInsetsDirectional.fromSTEB(8, 14, 8, 4),
        decoration: topBarDecoration(context),
        child: Row(
          children: [
            Icon(WindowsIcons.lock, size: 16, color: theme.inactiveColor),
            const SizedBox(width: 6),
            Expanded(
              child: Txt(
                txt('patientReadOnlyWhileVisit'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.body?.copyWith(
                  fontSize: 12,
                  color: theme.inactiveColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildWorkspaceBar() {
    return MStreamBuilder(
      streams: [
        widget.panel.workspace.revision.stream,
        // A retained visit's draft marks the chart button while its windows are
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
              widget.panel.carriedDraftWindowId == window.id &&
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

  /// The carried record's window standing in for [window] — a visit's chart for
  /// the patient's — or null when [window] is not replaced.
  PanelWindow? _carriedWindowOf(PanelWindow window) {
    final attached = widget.panel.attached;
    final group = window.replacementGroup;
    if (attached == null || group == null) return null;
    return attached.windows
        .where((carried) => carried.replacementGroup == group)
        .firstOrNull;
  }

  /// The band a carried record draws for itself. It counts dirty carried records
  /// live, so a draft hidden behind another visit is still named on close.
  Widget _buildVisitBand(
    HostedRecordSession session, {
    required bool replacing,
  }) {
    return StreamBuilder<bool>(
      stream: widget.panel.hasUnsavedChanges.stream,
      key: ValueKey('visit-band-${session.itemId}'),
      builder: (context, _) => _VisitBand(
        panel: widget.panel,
        session: session,
        dirtyVisits:
            widget.panel.owned.where((owned) => owned.hasPendingEdits).length,
        replacing: replacing,
      ),
    );
  }

  /// Switches for the panel's own floating windows. A carried record's chart takes
  /// the place of the patient's, so that group is not offered twice.
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
          final draftWindow = widget.panel.carriedDraftWindowId;
          return WindowDock(
            windows: windows,
            isOpen: (window) => widget.panel.workspace.isOpen(window.id),
            enabled: (window) => !(window.onlyIfSaved && isNew),
            accent: _accent,
            // A carried draft whose windows are closed still marks its pill.
            dirty: (window) =>
                draftWindow != null &&
                window.id == draftWindow &&
                widget.panel.owned.any((owned) => owned.hasPendingEdits),
            onToggle: (window) => widget.panel.workspace.toggle(window.id),
          );
        },
      ),
    );
  }

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
          color: FluentMaterials.of(context).selected,
          border: Border(
            bottom: BorderSide(
              color: FluentMaterials.of(context).divider,
              width: 1,
            ),
          ),
        ),
        child: StreamBuilder(
            stream: widget.panel.inProgress.stream,
            builder: (context, snapshot) {
              return Row(
                children: [
                  _buildPanelHeaderStoreName(),
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
          Flexible(
            child: StreamBuilder<bool>(
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
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 40, minWidth: 350),
      child: StreamBuilder(
          stream: widget.panel.inProgress.stream,
          builder: (context, snapshot) {
            return Container(
              decoration: BoxDecoration(
                color: FluentMaterials.of(context).glassTint,
                border: Border(
                    top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
              ),
              padding: const EdgeInsets.symmetric(vertical: 6.5, horizontal: 5),
              child: widget.panel.inProgress()
                  ? const Center(child: ProgressBar())
                  // Wrap, not Row: long translations overflow the 350-pixel minimum,
                  // and a second line beats a bar that clips its own Save.
                  : Wrap(
                      alignment: WrapAlignment.spaceEvenly,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (widget.panel.additionalControls != null)
                          widget.panel.additionalControls!,
                        // While the band's record is on screen it owns the work;
                        // this record's Save and Delete would strand the visit,
                        // so only Close stays.
                        if (widget.panel.showBottomControls &&
                            widget.panel.attached == null) ...[
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
              style: ButtonStyle(
                textStyle:
                    const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
                foregroundColor: widget.panel.hasUnsavedChanges()
                    ? WidgetStatePropertyAll(
                        FluentTheme.of(context)
                            .resources
                            .systemFillColorCritical,
                      )
                    : null,
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
          // This writes this panel's record only; a carried visit is saved by its
          // own Save. Save all is offered only by the close prompt.
          final hasChanges = widget.panel.hasPendingEdits;
          final content =
              ButtonContent(WindowsIcons.save, txt(widget.panel.saveLabel));
          final onPressed = hasChanges
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
              : null;
          return hasChanges
              ? FilledButton(
                  key: WK.panelSave,
                  onPressed: onPressed,
                  child: content,
                )
              : Button(
                  key: WK.panelSave,
                  onPressed: onPressed,
                  child: content,
                );
        });
  }

  Widget _buildArchiveButton() {
    final isArchived = widget.panel.isArchived;
    final icon = isArchived ? WindowsIcons.undo : WindowsIcons.delete;
    final action = txt(isArchived ? "restore" : "delete");
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
          style: panelDeleteButtonStyle(context, restoring: isArchived),
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
        // Includes carried visits whose windows are closed: their drafts still
        // block a clean close.
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
                  // Offered whenever anything is dirty, so a panel dirty only in
                  // its own fields is not left with Save as its only way out.
                  FilledButton(
                    style: filledButtonStyle(Colors.warningPrimaryColor),
                    onPressed: () {
                      Flyout.of(context).close();
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

  /// Saves every record this panel holds, then closes it. Not atomic: a failure is
  /// named and the panel stays open, so written records are not thrown away.
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
      builder: (context) => AppMenuFlyout(items: [
        ...([...PanelsManager.active()]
              ..sort((a, b) => b.creationDate - a.creationDate))
            .map((panel) {
          return MenuFlyoutItem(
            selected: panel == widget.panel,
            leading: Icon(panel.icon),
            trailing: panel.inProgress()
                ? const SizedBox(height: 20, width: 20, child: ProgressRing())
                : Icon(panel.isNew ? FluentIcons.add : FluentIcons.edit),
            // `displayTitle` is a translation key while the record is new, so it is
            // passed through `txt` here as in the header.
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
