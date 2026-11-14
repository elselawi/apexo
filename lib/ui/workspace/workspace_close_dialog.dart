import 'dart:async';

import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/workspace/floating_window.dart';
import 'package:apexo/ui/workspace/panel.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/record_session.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// Captures owners, not editors: a panel's windows share its one draft.
final class WorkspaceCloseRequest {
  WorkspaceCloseRequest() {
    records = _currentRecords;
  }

  final List<Panel> panels = PanelsManager.active().toList();
  final List<FloatingWindow> windows = WindowsManager.open();
  late final List<WindowRecordSession> records;

  List<WindowRecordSession> get _currentRecords => <WindowRecordSession>{
        for (final panel in panels) ...[panel, ...panel.owned],
        for (final window in windows)
          if (window.recordSession case final owner?) owner,
      }.toList();

  List<FloatingWindow> get independentWindows => [
        for (final window in windows)
          if (window.recordSession == null) window,
      ];

  int get dirtyCount =>
      records.where((record) => record.hasPendingEdits).length +
      independentWindows
          .where((window) => window.hasChanges?.call() ?? false)
          .length;

  bool get saving => records.any((record) => record.inProgress());

  static String windowTitle(FloatingWindow window) {
    final title = txt(window.window.title);
    final subtitle = window.window.subtitle?.call();
    return subtitle == null || subtitle.trim().isEmpty
        ? title
        : '$title — ${txt(subtitle)}';
  }

  bool get isCurrent {
    final currentPanels = PanelsManager.active();
    final currentWindows = WindowsManager.open();
    return panels.length == currentPanels.length &&
        panels.every((panel) => currentPanels.contains(panel)) &&
        windows.length == currentWindows.length &&
        windows.every((window) => currentWindows.contains(window)) &&
        records.length == _currentRecords.length &&
        records.every((record) => _currentRecords.contains(record));
  }

  void close() {
    final hosted = {for (final panel in panels) ...panel.owned};
    WindowsManager.closeAll();
    PanelsManager.closeAll();
    for (final record in records.whereType<HostedRecordSession>()) {
      if (!hosted.contains(record)) record.dispose();
    }
  }
}

class WorkspaceCloseDialog extends StatefulWidget {
  const WorkspaceCloseDialog({super.key, required this.request});

  final WorkspaceCloseRequest request;

  @override
  State<WorkspaceCloseDialog> createState() => _WorkspaceCloseDialogState();
}

class _WorkspaceCloseDialogState extends State<WorkspaceCloseDialog> {
  Timer? _sampler;
  bool _saving = false;
  String? _error;
  String? _savingTitle;
  bool _dismissing = false;
  bool _flyoutOpen = false;
  VoidCallback? _pendingItemAction;
  late WorkspaceCloseRequest _request;

  bool get _busy => _saving || _request.saving;

  @override
  void initState() {
    super.initState();
    _request = widget.request;
    _sampler = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _sampler?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _sampler?.cancel();
    Navigator.of(context).pop();
  }

  void _refresh() {
    if (!mounted || _dismissing || _flyoutOpen) return;
    if (!_busy && _error == null && _request.isCurrent && _request.dirtyCount == 0) {
      _request.close();
      _dismiss();
      return;
    }
    setState(() {});
  }

  bool _checkWorkspace() {
    if (_dismissing) return false;
    if (_request.isCurrent) return true;
    setState(() => _error = txt('workspaceChanged'));
    return false;
  }

  void _close() {
    if (_busy || !_checkWorkspace()) return;
    _request.close();
    _dismiss();
  }

  void _reviewRecord(WindowRecordSession record) {
    if (_busy || !_checkWorkspace()) return;
    final panels = PanelsManager.active();
    final index = panels.indexWhere((panel) =>
        identical(panel, record) ||
        panel.owned.any((session) => identical(session, record)));
    if (index < 0) {
      final window = _request.windows
          .where((window) => identical(window.recordSession, record))
          .lastOrNull;
      if (window != null) _reviewWindow(window);
      return;
    }
    final panel = panels[index];
    if (record is HostedRecordSession) {
      // Reattach the existing draft; opening a fresh record would hide its edits.
      final editor = record.windows
          .where((window) =>
              window.editsRecord &&
              !window.isAttachment &&
              !(window.onlyIfSaved && record.isNew))
          .firstOrNull;
      panel.attach(record, focus: editor?.id);
    }
    PanelsManager.bringToFront(index);
    _dismiss();
  }

  void _reviewWindow(FloatingWindow window) {
    if (_busy || !_checkWorkspace()) return;
    // Raising the same instance preserves its draft instead of reopening it.
    WindowsManager.show(window);
    _dismiss();
  }

  bool _hasDirtyVisits(WindowRecordSession record) =>
      record is Panel && record.owned.any((visit) => visit.hasPendingEdits);

  Future<void> _saveRecord(WindowRecordSession record) async {
    if (!record.hasPendingEdits) return;
    setState(() => _savingTitle = txt(record.displayTitle));
    if (!record.showBottomControls || record.inProgress()) {
      throw StateError('Record cannot be saved');
    }
    await record.save();
    record.refreshDirty();
    if (record.hasPendingEdits) throw StateError('Record remains unsaved');
  }

  Future<void> _saveWindow(FloatingWindow window) async {
    if (!(window.hasChanges?.call() ?? false)) return;
    setState(() => _savingTitle = WorkspaceCloseRequest.windowTitle(window));
    final save = window.onSave;
    if (save == null) throw StateError('Window cannot be saved');
    await save();
    if (window.hasChanges?.call() ?? false) {
      throw StateError('Window remains unsaved');
    }
  }

  void _showSaveError() {
    if (!mounted) return;
    setState(() => _error = txt('workspaceSaveFailed')
        .replaceAll('{name}', _savingTitle ?? ''));
  }

  Future<void> _closeRecord(WindowRecordSession record, {required bool save}) async {
    if (_busy || !_checkWorkspace()) return;
    if (_hasDirtyVisits(record)) {
      setState(() => _error = txt('workspaceResolveVisitsFirst'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (save) await _saveRecord(record);
      if (!mounted || !_checkWorkspace()) return;
      // A visit can acquire edits while its parent is saving.
      if (_hasDirtyVisits(record)) {
        setState(() => _error = txt('workspaceResolveVisitsFirst'));
        return;
      }
      final closingOwners = <WindowRecordSession>{
        record,
        if (record is Panel) ...record.owned,
      };
      for (final window in _request.windows) {
        if (closingOwners.contains(window.recordSession)) {
          WindowsManager.close(window);
        }
      }
      if (record is Panel) {
        PanelsManager.close(record.identifier);
      } else if (record is HostedRecordSession) {
        final owner = _request.panels
            .where((panel) => panel.owned.contains(record))
            .firstOrNull;
        if (owner == null) {
          record.dispose();
        } else {
          owner.disposeSession(record);
        }
      }
      _request = WorkspaceCloseRequest();
    } catch (_) {
      _showSaveError();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _refresh();
      }
    }
  }

  Future<void> _closeWindow(FloatingWindow window, {required bool save}) async {
    if (_busy || !_checkWorkspace()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (save) await _saveWindow(window);
      if (!mounted || !_checkWorkspace()) return;
      WindowsManager.close(window);
      _request = WorkspaceCloseRequest();
    } catch (_) {
      _showSaveError();
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        _refresh();
      }
    }
  }

  Future<void> _saveAndClose() async {
    if (_busy || !_checkWorkspace()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Parents are written first, before the retained visits that depend on them.
      for (final record in _request.records) {
        if (!record.hasPendingEdits) continue;
        if (!mounted || !_checkWorkspace()) return;
        await _saveRecord(record);
      }
      for (final window in _request.independentWindows) {
        if (!(window.hasChanges?.call() ?? false)) continue;
        if (!mounted || !_checkWorkspace()) return;
        await _saveWindow(window);
      }
      if (!mounted || !_checkWorkspace()) return;
      if (_request.dirtyCount != 0 || _request.saving) {
        setState(() => _error = txt('workspaceStillUnsaved'));
        return;
      }
      _request.close();
      _dismiss();
    } catch (_) {
      _showSaveError();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _queueItemAction(VoidCallback action) {
    _pendingItemAction = action;
  }

  void _onItemMenuClosed() {
    _flyoutOpen = false;
    final action = _pendingItemAction;
    _pendingItemAction = null;
    if (!mounted || _dismissing) return;
    // Wait for the flyout route to leave before closing a record or the dialog.
    action?.call();
    _refresh();
  }

  Widget _itemMenu({
    required Object owner,
    required String title,
    required String openRecordLabel,
    required VoidCallback onReview,
    required VoidCallback onSave,
    required VoidCallback onDiscard,
    required bool canSave,
    bool blocked = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Tooltip(
          message: title,
          child: DropDownButton(
            key: ObjectKey(owner),
            disabled: _busy,
            onOpen: () => _flyoutOpen = true,
            onClose: _onItemMenuClosed,
            leading: const Icon(FluentIcons.edit, size: 14),
            title: Expanded(
              child: Txt(
                title,
                textAlign: TextAlign.start,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            items: [
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.view, size: 14),
                text: Txt(txt(openRecordLabel)),
                onPressed: _busy ? null : () => _queueItemAction(onReview),
              ),
              const MenuFlyoutSeparator(),
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.save, size: 14),
                text: Txt(txt('workspaceSaveItemAndClose')),
                onPressed: _busy || blocked || !canSave
                    ? null
                    : () => _queueItemAction(onSave),
              ),
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.clear, size: 14),
                text: Txt(txt('workspaceIgnoreItemAndClose')),
                onPressed: _busy || blocked
                    ? null
                    : () => _queueItemAction(onDiscard),
              ),
            ],
          ),
        ),
        if (blocked)
          Txt(
            txt('workspaceResolveVisitsFirst'),
            style: FluentTheme.of(context).typography.caption,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final record in _request.records)
        if (record.hasPendingEdits)
          _itemMenu(
            owner: record,
            title: txt(record.displayTitle),
            openRecordLabel: openRecordLabelFor(record.singularName),
            onReview: () => _reviewRecord(record),
            onSave: () => unawaited(_closeRecord(record, save: true)),
            onDiscard: () => unawaited(_closeRecord(record, save: false)),
            canSave: record.showBottomControls,
            blocked: _hasDirtyVisits(record),
          ),
      for (final window in _request.independentWindows)
        if (window.hasChanges?.call() ?? false)
          _itemMenu(
            owner: window,
            title: WorkspaceCloseRequest.windowTitle(window),
            openRecordLabel: window.openRecordLabel,
            onReview: () => _reviewWindow(window),
            onSave: () => unawaited(_closeWindow(window, save: true)),
            onDiscard: () => unawaited(_closeWindow(window, save: false)),
            canSave: window.canSave,
          ),
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_busy) _dismiss();
        },
      },
      child: PopScope(
        canPop: !_busy,
        child: ContentDialog(
          style: dialogStyling(context, true, true),
          title: Txt(txt('closeAllWindows')),
          constraints: const BoxConstraints(maxWidth: 548),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Txt(txt('workspaceClosePrompt')),
                if (_busy)
                  Row(
                    spacing: 8,
                    children: [
                      const SizedBox(
                          width: 16, height: 16, child: ProgressRing()),
                      Expanded(
                        child: Text(_savingTitle ?? txt('workspaceSaving')),
                      ),
                    ],
                  ),
                if (_error != null)
                  InfoBar(
                    title: Txt(txt('unsavedChanges')),
                    content: Text(_error!),
                    severity: InfoBarSeverity.error,
                  ),
                ...items,
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: _busy ? null : _saveAndClose,
              child: Txt(txt('workspaceSaveAndClose')),
            ),
            Button(
              onPressed: _busy ? null : _close,
              child: Txt(txt('workspaceDiscardAndClose')),
            ),
            Button(
              autofocus: true,
              onPressed: _busy ? null : _dismiss,
              child: Txt(txt('cancel')),
            ),
          ],
        ),
      ),
    );
  }
}
