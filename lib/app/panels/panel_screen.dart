import 'dart:async';
import 'package:apexo/app/panels/panel.dart';
import 'package:apexo/app/panels/panels_manager.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/error_dialog.dart';
import 'package:apexo/common_widgets/swipe_detector.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/utils/logger.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// The panel host: the chrome drawn around whatever [Panel] is on screen —
/// header, tab strip, body, footer and the archive/save/close bar.
///
/// It reaches the panel only through [Panel] and never touches the records
/// behind it. That is what lets one host draw a row panel, a delegated panel and
/// a hand-written panel alike, and why this file must not learn about drafts,
/// stores or account models.
final class PanelScreen extends StatefulWidget {
  const PanelScreen({
    required this.panel,
    this.layoutHeight = 500,
    this.layoutWidth = 500,
    super.key,
  });
  final double layoutHeight;
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
  bool ctrlPressed = false;

  @override
  void dispose() {
    saveButtonCheckTimer?.cancel();
    unawaited(pendingEditsSub?.cancel());
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
          return;
        }

        if (value.logicalKey == LogicalKeyboardKey.controlLeft ||
                    value.logicalKey == LogicalKeyboardKey.controlRight) {
          if (value is KeyDownEvent) {
            ctrlPressed = true;
          } else {
            ctrlPressed = false;
          }
        }

        if (value is KeyDownEvent &&
            value.logicalKey == LogicalKeyboardKey.tab &&
            ctrlPressed) {
          if (widget.panel.selectedTab() == widget.panel.tabs.length - 1) {
            widget.panel.selectedTab(0);
          } else {
            widget.panel.selectedTab(widget.panel.selectedTab() + 1);
          }
        }
      },
      child: Container(
        margin: const EdgeInsetsDirectional.only(
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
              localSettings.stream,
              widget.panel.selectedTab.stream,
              PanelsManager.minimize.stream,
            ],
            builder: (context, snapshot) {
              return Column(
                key: Key(localSettings.selectedLocale.toString()),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPanelHeader(),
                  if (PanelsManager.minimize() == false ||
                      widget.layoutWidth >= 710) ...[
                    _buildTabsControllers(),
                    _buildTabBody(),
                    if (widget.panel.tabs[widget.panel.selectedTab()].footer !=
                        null)
                      widget.panel.tabs[widget.panel.selectedTab()].footer!,
                    _buildBottomControls(),
                  ],
                ],
              );
            }),
      ),
    );
  }

  Widget _buildTabBody() {
    return Expanded(
      child: widget.panel.inherentlyScrollable
          ? _buildBodyChild()
          : SingleChildScrollView(
              child: _buildBodyChild(),
            ),
    );
  }

  SwipeDetector _buildBodyChild() {
    return SwipeDetector(
      onSwipePrev: () {
        if (widget.panel.selectedTab() > 0) {
          widget.panel.selectedTab(widget.panel.selectedTab() - 1);
        }
      },
      onSwipeNext: () {
        if (widget.panel.selectedTab() < widget.panel.tabs.length - 1) {
          widget.panel.selectedTab(widget.panel.selectedTab() + 1);
        }
      },
      child: Container(
        color: FluentTheme.of(context).scaffoldBackgroundColor,
        padding: EdgeInsets.all(
            widget.panel.tabs[widget.panel.selectedTab()].padding.toDouble()),
        constraints: BoxConstraints(
            minHeight:
                widget.panel.tabs[widget.panel.selectedTab()].footer == null
                    ? widget.layoutHeight - 161
                    : widget.layoutHeight - 206),
        child: widget.panel.tabs[widget.panel.selectedTab()].body,
      ),
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
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
    final action = isArchived ? txt("restore") : txt("delete");
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

  Widget _buildTabsControllers() {
    return Container(
      decoration:
          BoxDecoration(color: FluentTheme.of(context).inactiveBackgroundColor),
      padding: const EdgeInsets.fromLTRB(3, 15, 3, 0),
      child: SizedBox(
        height: 39,
        child: TabView(
          closeButtonVisibility: CloseButtonVisibilityMode.never,
          onChanged: (value) => widget.panel.selectedTab(value),
          currentIndex: widget.panel.selectedTab(),
          showScrollButtons: false,
          shortcutsEnabled: true,
          tabWidthBehavior: widget.panel.showTitles
              ? TabWidthBehavior.equal
              : TabWidthBehavior.compact,
          header: widget.panel.selectedTab() != 0
              ? IconButton(
                  icon: Icon(Directionality.of(context) == TextDirection.rtl
                      ? WindowsIcons.chevron_right
                      : WindowsIcons.chevron_left),
                  onPressed: () =>
                      widget.panel.selectedTab(widget.panel.selectedTab() - 1),
                )
              : const SizedBox(width: 25),
          footer: widget.panel.selectedTab() <
                  widget.panel.tabs
                          .where((t) => t.onlyIfSaved ? (!isNew) : true)
                          .length -
                      1
              ? IconButton(
                  icon: Icon(Directionality.of(context) == TextDirection.rtl
                      ? WindowsIcons.chevron_left
                      : WindowsIcons.chevron_right),
                  onPressed: () =>
                      widget.panel.selectedTab(widget.panel.selectedTab() + 1),
                )
              : const SizedBox(width: 25),
          tabs: widget.panel.tabs
              .map((e) => Tab(
                    text: Txt(txt(e.title)),
                    icon: Icon(e.icon),
                    body: const SizedBox(),
                    disabled: e.onlyIfSaved && isNew,
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildPanelHeader() {
    return GestureDetector(
      onTap: () {
        if (PanelsManager.minimize()) PanelsManager.minimize(false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2.8, horizontal: 5),
        color: Colors.grey.withValues(alpha: 0.1),
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
                    if (widget.layoutWidth < 710) _buildPanelMinimizeButton(),
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
          Txt(
            widget.panel.unicodeSymbol,
            style: const TextStyle(fontSize: 20),
          ),
          Txt(
            txt(widget.panel.singularName),
            style: TextStyle(
                fontSize: 12,
                color: FluentTheme.of(context).shadowColor,
                fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
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
      barrierDismissible: widget.layoutWidth < 710,
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
