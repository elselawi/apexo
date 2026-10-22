import 'dart:async';

import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/unsaved_dot.dart';
import 'package:apexo/ui/workspace/windows_layout.dart';
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

  /// Copies the panel's verdict on [Panel.hasPendingEdits] into the observable
  /// the bottom controls watch, so Save is enabled exactly while a save would
  /// write something.
  void _syncPendingEdits() {
    final hasPendingEdits = widget.panel.hasPendingEdits;
    if (widget.panel.hasUnsavedChanges() != hasPendingEdits) {
      widget.panel.hasUnsavedChanges(hasPendingEdits);
    }
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
            boxShadow: kElevationToShadow[24],
            color: FluentTheme.of(context)
                .resources
                .solidBackgroundFillColorBaseAlt,
            border: Border.all(color: Colors.grey.withAlpha(150)),
            borderRadius: BorderRadius.circular(5)),
        child: MStreamBuilder(
            streams: [
              locale.selected.stream,
              PanelsManager.minimize.stream,
            ],
            builder: (context, snapshot) {
              return Column(
                key: Key(locale.selected().toString()),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPanelHeader(),
                  if (PanelsManager.minimize() == false ||
                      widget.layoutWidth >= kWindowsBreakpoint) ...[
                    if (widget.panel.floatingWindows.isNotEmpty)
                      _buildWindowDock(),
                    Expanded(child: _buildPrimaryWindow()),
                    _buildBottomControls(),
                  ],
                ],
              );
            }),
      ),
    );
  }

  /// The panel's first window: the record's own editor, drawn in the panel
  /// itself just as the first tab used to be.
  Widget _buildPrimaryWindow() {
    final window = widget.panel.primaryWindow;
    if (window == null) return const SizedBox.shrink();
    final body = window.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ColoredBox(
            color: FluentTheme.of(context).scaffoldBackgroundColor,
            child: window.scrollable
                ? SingleChildScrollView(
                    padding: EdgeInsets.all(window.padding),
                    child: body,
                  )
                : Padding(
                    padding: EdgeInsets.all(window.padding),
                    child: body,
                  ),
          ),
        ),
        if (window.footer != null) window.footer!,
      ],
    );
  }

  /// The switches for everything the panel does not keep inline: one labelled
  /// pill per window, showing whether it is on screen.
  Widget _buildWindowDock() {
    return StreamBuilder<int>(
      stream: widget.panel.workspace.revision.stream,
      builder: (context, _) {
        return WindowDock(
          windows: widget.panel.floatingWindows,
          isOpen: (window) => widget.panel.workspace.isOpen(window.id),
          enabled: (window) => !(window.onlyIfSaved && isNew),
          accent: _accent,
          onToggle: (window) => widget.panel.workspace.toggle(window.id),
        );
      },
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
            FluentTheme.of(context).menuColor,
          ),
          border:
              Border(bottom: BorderSide(color: _accent.withValues(alpha: 0.5))),
        ),
        child: StreamBuilder(
            stream: widget.panel.inProgress.stream,
            builder: (context, snapshot) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(spacing: 2, children: [
                    _buildPanelHeaderStoreName(),
                    _buildPanelHeaderItemName(),
                  ]),
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
    return SizedBox(
      width: 134,
      child: widget.panel.buildTitle(context),
    );
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
          final hasChanges = widget.panel.hasUnsavedChanges();
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
            icon: ButtonContent(WindowsIcons.save, txt("save")),
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
    if (widget.panel.hasUnsavedChanges() == false) {
      PanelsManager.close(widget.panel.itemId);
    } else {
      await flyoutFocusFix(context);
      unawaited(confirmCancelController.showFlyout<void>(builder: (context) {
        return FlyoutContent(
          constraints: const BoxConstraints(maxWidth: 350),
          child: Column(
            spacing: 12,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Txt(txt("sureClosePanel")),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    style: filledButtonStyle(Colors.warningPrimaryColor),
                    onPressed: () {
                      Flyout.of(context).close();
                      PanelsManager.close(widget.panel.itemId);
                    },
                    child: Row(
                      children: [
                        const Icon(FluentIcons.check_mark, size: 16),
                        const SizedBox(width: 5),
                        Txt(txt("sure")),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  CloseButtonInDialog(buttonText: txt("back")),
                ],
              ),
            ],
          ),
        );
      }));
    }
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
