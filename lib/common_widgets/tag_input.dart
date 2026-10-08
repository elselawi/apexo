import 'dart:async';
import 'dart:math' as math;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

class TagInputItem extends AutoSuggestBoxItem<String> {
  TagInputItem({required super.value, required super.label});
}

class TagInputWidget extends StatefulWidget {
  const TagInputWidget({
    super.key,
    required this.suggestions,
    required this.onChanged,
    required this.initialValue,
    required this.strict,
    required this.limit,
    this.placeholder = "",
    this.onItemTap,
    this.multiline = false,
    this.inactiveColor,
    this.enabled = true,
  });
  final List<TagInputItem> suggestions;
  final List<TagInputItem> initialValue;
  final bool strict;
  final int limit;
  final void Function(List<TagInputItem>) onChanged;
  final void Function(TagInputItem)? onItemTap;
  final String placeholder;
  final bool multiline;
  final Color? inactiveColor;
  final bool enabled;

  @override
  State<TagInputWidget> createState() => _TagInputWidgetState();
}

class _TagInputWidgetState extends State<TagInputWidget> {
  final TextEditingController _controller = TextEditingController();
  final _hiddenTappedFlyoutController = FlyoutController();
  final autoSuggestBoxRef = GlobalKey<AutoSuggestBoxState<String>>();
  late FocusNode _focusNode;
  late List<TagInputItem> _tags;
  late List<TagInputItem> _suggestions;
  bool _isFocused = false;

  /// The suggestion the keyboard has landed on, for the dropdown's highlight.
  ///
  /// `AutoSuggestBox` keeps that for itself (`AutoSuggestBoxItem._selected` is
  /// private), so the rows — which this widget draws — track it through
  /// `onFocusChange` instead.
  String? _focusedSuggestion;

  bool get tapable {
    return widget.onItemTap != null;
  }

  void _onSuggestionSelected(AutoSuggestBoxItem<String> suggestion) {
    // Same window as `onFocusChange` above (fluent runs both from its own
    // dispose path), so the same early return applies.
    if (!mounted || !context.mounted) return;
    setState(() {
      _tags.add(TagInputItem(value: suggestion.value, label: suggestion.label));
      _controller.clear();
    });

    // Force the text field to clear by updating the text field directly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.text = '';
    });

    // The list is done with. Leaving the overlay open after a selection left a
    // stranded "No results found" flyout floating over the panel, which then
    // swallowed clicks meant for the panel's own tabs.
    autoSuggestBoxRef.currentState?.dismissOverlay();

    widget.onChanged(_tags);
    if (_tags.length < widget.limit) {
      _focusNode.requestFocus();
    }
  }

  /// Commits whatever is in the text box as a tag, returning whether one was
  /// added.
  ///
  /// `AutoSuggestBox` only submits an item the user highlighted with the arrow
  /// keys — with nothing highlighted, Enter falls through to the text box's own
  /// submit handling, which drops focus and closes the dropdown. The manual
  /// says "type and press Enter to add", and it did nothing at all. Matching the
  /// typed text against the suggestions first keeps a strict picker (the doctor
  /// selector) honest: there, only a known value can be added.
  bool _commitTypedText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return false;
    final folded = text.toLowerCase();
    // Already a tag: pressing Enter again must not add a second copy of it.
    // The suggestion list hides it, but in a non-strict box the typed text is
    // also mirrored into the suggestions, so the check has to be explicit.
    if (_tags.any((tag) => tag.label.toLowerCase() == folded)) {
      _controller.clear();
      return true;
    }
    for (final suggestion in _suggestions) {
      if (suggestion.label.toLowerCase() == folded ||
          suggestion.value?.toLowerCase() == folded) {
        _onSuggestionSelected(suggestion);
        return true;
      }
    }
    if (widget.strict) return false;
    _onSuggestionSelected(TagInputItem(value: text, label: text));
    return true;
  }

  @override
  void initState() {
    super.initState();
    _tags = List.of(widget.initialValue);
    _updateSuggestions();

    _focusNode = FocusNode(onKeyEvent: (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      // Enter commits the typed text. Handled here — on the text box's own
      // focus node — so the event never reaches the editable's submit path,
      // which would unfocus the box and close the dropdown instead of adding
      // the tag.
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter) {
        return _commitTypedText()
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      if (_controller.text.isEmpty &&
          event.logicalKey == LogicalKeyboardKey.backspace) {
        backspaceRemove();
      }
      return KeyEventResult.ignored;
    });

    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(TagInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync internal _tags when the parent updates initialValue externally
    // (e.g. after AI receipt scanning populates items).
    if (oldWidget.initialValue != widget.initialValue &&
        !_listEquals(_tags, widget.initialValue)) {
      _tags = List.of(widget.initialValue);
      _updateSuggestions();
      // Don't mark dirty if the widget is no longer mounted
      if (mounted) setState(() {});
    }
    // A picker whose list is read asynchronously (patients, labs, operators) is
    // built with no suggestions and gets them a moment later. `AutoSuggestBox`
    // only paints its dropdown when the *text* changes, and it reads the items
    // it was last given, so a list that arrives late is never shown: the field
    // keeps saying "no results found" until another key is pressed.
    if (!_listEquals(oldWidget.suggestions, widget.suggestions)) {
      _updateSuggestions();
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _reopenOverlay());
      }
    }
  }

  /// Reopens the dropdown so a list that arrived after the field was built is
  /// the list the user sees.
  ///
  /// Deferred to a frame: inserting an overlay entry from `didUpdateWidget`
  /// would mark the tree dirty while it is being built.
  void _reopenOverlay() {
    if (!mounted || !_focusNode.hasFocus || _controller.text.isEmpty) return;
    final box = autoSuggestBoxRef.currentState;
    if (box == null || !box.isOverlayVisible) return;
    box
      ..dismissOverlay()
      ..showOverlay();
  }

  void _updateSuggestions() {
    if (widget.strict == false) {
      _suggestions = [
        TagInputItem(value: "", label: ""),
        ...widget.suggestions
      ];
    } else {
      _suggestions = widget.suggestions;
    }
  }

  /// Shallow comparison — sufficient since TagInputItems are value objects.
  bool _listEquals(List<TagInputItem> a, List<TagInputItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].value != b[i].value || a[i].label != b[i].label) return false;
    }
    return true;
  }

  void _onFocusChanged() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _hiddenTappedFlyoutController.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<TagInputItem> get _filteredSuggestions {
    return _suggestions.where(
      (s) {
        return !_tags
                .map((e) => e.label.toLowerCase())
                .contains(s.label.toLowerCase()) &&
            s.label.isNotEmpty;
      },
    ).toList();
  }

  void _removeTag(TagInputItem tag) {
    setState(() {
      _tags.removeWhere((e) => e.value == tag.value);
    });
    if (_hiddenTappedFlyoutController.isOpen &&
        _hiddenTappedFlyoutController.isAttached) {
      _hiddenTappedFlyoutController.close<void>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showAllTags();
      });
    }
    widget.onChanged(_tags);
  }

  void backspaceRemove() {
    if (_tags.isEmpty) return;
    setState(() {
      _tags.removeLast();
    });
    widget.onChanged(_tags);
  }

  void showAllTags() async {
    if (_tags.isEmpty) return;
    await flyoutFocusFix(context);
    unawaited(_hiddenTappedFlyoutController.showFlyout<void>(
        builder: (context) {
          return FlyoutContent(
              key: Key(_tags.map((e) => e.value).join("")),
              child: Wrap(children: _tags.map((e) => _buildTag(e)).toList()));
        },
        dismissWithEsc: true));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const tokenPadding = EdgeInsets.symmetric(horizontal: 8);
        const tokenSpacing = 4.0;
        const collapseWidth = 36.0;
        // What this widget's own container spends on its padding and border on
        // each side, so the row inside it knows its real width.
        const fieldChrome = 3.0 * 2 + 1.0 * 2;
        // The chips are laid out by a row that hands them unbounded width, so
        // the widest one decides the row's width: cap each chip so the row can
        // still hold the input next to it (or fit the field when the input is
        // gone because the limit is reached).
        final inputVisible = _tags.length < widget.limit && widget.enabled;
        final availableWidth =
            math.max(0.0, constraints.maxWidth - fieldChrome);
        final chipLimit = math.max(
          0.0,
          availableWidth - tokenSpacing - (inputVisible ? 80 : 0),
        );

        double usedWidth = 0;
        final visibleTags = <TagInputItem>[];
        final hiddenTags = <TagInputItem>[];

        for (final tag in _tags.reversed) {
          final textPainter = TextPainter(
            text: TextSpan(text: tag.label),
            maxLines: 1,
            textDirection: TextDirection.ltr,
          )..layout();

          final tokenWidth = textPainter.width + tokenPadding.horizontal + 24;

          if (widget.multiline == false &&
              ((visibleTags.isNotEmpty &&
                      usedWidth + tokenWidth + collapseWidth >
                          constraints.maxWidth - 80) ||
                  tag.label.length > 20) &&
              _tags.length > 1) {
            hiddenTags.add(tag);
          } else {
            usedWidth += tokenWidth + tokenSpacing;
            visibleTags.add(tag);
          }
        }

        return FlyoutTarget(
          controller: _hiddenTappedFlyoutController,
          child: Container(
            // **Multiline fields size themselves.** The height used to be
            // `visibleTags.length * 40 + 40` for both modes — a number that
            // ignores three things: the border and padding (4px a side, 8px
            // together, not the 6 the formula assumed), the `spacing: 3` between
            // the chips in a `Column`, and the 250ms its `AnimatedSize` spends
            // still taller than its target after a tag is removed. Adding then
            // removing a prescription (the appointment panel's field) reported
            // `A RenderFlex overflowed by 4.0 pixels on the bottom` for exactly
            // that window (`appointments 14`). The row case keeps its height: it
            // is one line by construction.
            height: widget.multiline ? null : 40,
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            decoration: BoxDecoration(
              color: FluentTheme.of(context).cardColor,
              border: Border.all(
                  color: FluentTheme.of(context).inactiveColor.withAlpha(30)),
              borderRadius: BorderRadius.circular(5),
            ),
            child: widget.multiline
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: _tags.isEmpty
                              ? const SizedBox.shrink()
                              : ((_isFocused && !widget.multiline)
                                  ? _buildHiddenTagsIndicator(
                                      tokenSpacing, _tags)
                                  : _buildVisibleTags(
                                      visibleTags, tokenSpacing)),
                        ),
                        if (_tags.length < widget.limit && widget.enabled)
                          // Not an `Expanded`: the field is only bounded in the
                          // row case, and a flex child of an unbounded `Column`
                          // is an error. `AutoSuggestBox` knows its own height.
                          _buildAutoSuggestInputTextBox(expand: false),
                      ])
                : Row(
                    children: [
                      // A chip is sized by its text, and one long value (a
                      // patient's name in a `limit: 1` picker) can be wider than
                      // the field itself — which the row then overflows, since
                      // the input next to it is already gone. Cap the chip at the
                      // width the row actually has: `fieldChrome` is what the
                      // container below spends on its own padding and border.
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: availableWidth),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: _tags.isEmpty
                              ? const SizedBox.shrink()
                              : (_isFocused
                                  ? _buildHiddenTagsIndicator(
                                      tokenSpacing, _tags)
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // A row lays its non-flexible children
                                        // out with unbounded width, so the widest
                                        // chip decides the row's width and can
                                        // push it past the field. Cap each chip at
                                        // what the row has, minus the spacing it
                                        // also adds (and the input's room, while
                                        // there is an input).
                                        _buildVisibleTags(
                                            visibleTags, tokenSpacing,
                                            maxWidth: chipLimit),
                                        if (hiddenTags.isNotEmpty)
                                          _buildHiddenTagsIndicator(
                                              tokenSpacing, hiddenTags),
                                      ],
                                    )),
                        ),
                      ),
                      if (_tags.length < widget.limit && widget.enabled)
                        _buildAutoSuggestInputTextBox(),
                    ],
                  ),
          ),
        );
      },
    );
  }

  /// The box the user types a new tag into.
  ///
  /// [expand] is the **row** case: there the field shares one line with the
  /// chips and takes what is left of it. A multiline field sizes itself (see the
  /// container above), so there the box keeps its own height — a flex child of
  /// an unbounded `Column` is a layout error, not a layout.
  Widget _buildAutoSuggestInputTextBox({bool expand = true}) {
    final box = AutoSuggestBox<String>(
      clearButtonEnabled: _tags.isEmpty ? true : false,
      decoration: _tags.isNotEmpty
          ? null
          : WidgetStatePropertyAll(BoxDecoration(
              color: Colors.transparent,
              border: Border.all(color: Colors.transparent))),
      unfocusedColor: widget.inactiveColor ??
          (_tags.isNotEmpty ? null : Colors.transparent),
      highlightColor: _tags.isNotEmpty ? null : Colors.transparent,
      enabled: widget.enabled,
      noResultsFoundBuilder: (context) => Padding(
        padding: const EdgeInsets.all(10),
        child: widget.strict
            ? Txt(
                txt("noResultsFound"),
                style: TextStyle(
                  color: FluentTheme.of(context).shadowColor,
                  fontStyle: FontStyle.italic,
                ),
              )
            : Text(
                txt("startTyping"),
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                    color:
                        FluentTheme.of(context).inactiveColor.withAlpha(155)),
              ),
      ),
      controller: _controller,
      focusNode: _focusNode,
      placeholder: widget.placeholder,
      key: autoSuggestBoxRef,
      trailingIcon: widget.enabled
          ? IconButton(
              icon: autoSuggestBoxRef.currentState == null
                  ? const Icon(WindowsIcons.chevron_down)
                  : autoSuggestBoxRef.currentState!.isOverlayVisible
                      ? const Icon(WindowsIcons.chevron_up)
                      : const Icon(WindowsIcons.chevron_down),
              iconButtonMode: IconButtonMode.large,
              style: const ButtonStyle(iconSize: WidgetStatePropertyAll(14)),
              onPressed: () {
                setState(() {
                  _focusNode.requestFocus();
                  if (autoSuggestBoxRef.currentState == null) return;
                  if (autoSuggestBoxRef.currentState!.isOverlayVisible ==
                      false) {
                    autoSuggestBoxRef.currentState!.showOverlay();
                  } else {
                    autoSuggestBoxRef.currentState!.dismissOverlay();
                  }
                });
              })
          : null,
      items: _filteredSuggestions
          .map(
            (s) => AutoSuggestBoxItem(
              value: s.value,
              label: s.label,
              // The rows are drawn by [_buildSuggestionRow], so the selection
              // callback has to travel with the item: `AutoSuggestBox` only
              // invokes `onSelected` from its own row widget.
              onSelected: () => _onSuggestionSelected(s),
              onFocusChange: (focused) {
                // fluent calls this from its own `dispose()`: `_unselectAll()`
                // walks every item and fires `onFocusChange(false)`, at which
                // point the element is already defunct and the widget tree is
                // locked — so this `setState` cannot be taken.
                //
                // Note that **no guard expresses that window**: during it
                // `State.mounted` is still true (`_element` is cleared after
                // `dispose()` returns) and `context.mounted` is still true too
                // (`Element.mounted` is `_parent != null`). The harness drops
                // the resulting assertion on the fluent frame
                // (`E2E.installKnownFlutterIssueFilters`, which matches the
                // stack, not the message); this early return only covers the
                // ordinary case of a callback after our own dispose.
                if (!mounted || !context.mounted) return;
                setState(() {
                  if (focused) {
                    _focusedSuggestion = s.label;
                  } else if (_focusedSuggestion == s.label) {
                    _focusedSuggestion = null;
                  }
                });
              },
            ),
          )
          .toList(),
      itemBuilder: (context, item) => _buildSuggestionRow(context, item),
      onSelected: _onSuggestionSelected,
      onChanged: (text, reason) {
        if (widget.strict) return;
        setState(() {
          _suggestions.setAll(0, [TagInputItem(value: text, label: text)]);
        });
      },
    );
    return expand ? Expanded(child: box) : box;
  }

  /// One row of the suggestion dropdown.
  ///
  /// `AutoSuggestBox` draws its own rows, and nothing in them keeps a long label
  /// on one line: a patient's full name wraps to a second line, and the row —
  /// only as tall as the list's item extent — then reports
  /// "A RenderFlex overflowed by 14 pixels" (and clips the second line). The
  /// rows are drawn here instead: one line, ellipsized, with the same hover and
  /// keyboard highlight the library's row had.
  Widget _buildSuggestionRow(
    BuildContext context,
    AutoSuggestBoxItem<dynamic> item,
  ) {
    return _SuggestionRow(
      label: item.label,
      selected: _focusedSuggestion == item.label,
      child: item.child,
      onTap: () => item.onSelected?.call(),
    );
  }

  Padding _buildHiddenTagsIndicator(
      double tokenSpacing, List<TagInputItem> hiddenTags) {
    return Padding(
      padding: EdgeInsets.only(right: tokenSpacing),
      child: Tooltip(
        message: hiddenTags.map((e) => e.label).join(", "),
        child: IconButton(
          onPressed: showAllTags,
          style: ButtonStyle(
              elevation: const WidgetStatePropertyAll(1),
              backgroundColor: WidgetStatePropertyAll(
                  FluentTheme.of(context).cardColor.toAccentColor().dark)),
          icon: SizedBox(
            height: 26,
            child: Text(
              '+${hiddenTags.length}',
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisibleTags(List<TagInputItem> visibleTags, double tokenSpacing,
      {double? maxWidth}) {
    final childrenToBuild = [
      ...visibleTags.reversed.map((tag) => Padding(
            padding: EdgeInsets.only(right: tokenSpacing),
            child: maxWidth == null
                ? _buildTag(tag)
                : ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: _buildTag(tag),
                  ),
          ))
    ];
    return widget.multiline
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: childrenToBuild,
          )
        : Row(children: childrenToBuild);
  }

  Widget _buildTag(TagInputItem tag) {
    return Container(
      height: widget.multiline ? 36 : null,
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withAlpha(100)),
        borderRadius: BorderRadius.circular(5),
        color: tapable ? Colors.blue : FluentTheme.of(context).cardColor,
      ),
      child: IconButton(
        onPressed: () {
          if (_hiddenTappedFlyoutController.isOpen) {
            _hiddenTappedFlyoutController.close<void>();
          }
          if (tapable) {
            widget.onItemTap!(tag);
          }
        },
        style: const ButtonStyle(
          padding: WidgetStatePropertyAll(
              EdgeInsets.only(left: 10, right: 5, top: 5, bottom: 5)),
        ),
        icon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tapable) ...[
              const Icon(FluentIcons.contact, size: 12, color: Colors.white),
              const SizedBox(width: 5)
            ],
            Flexible(
              child: Txt(tag.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: tapable ? Colors.white : null)),
            ),
            const SizedBox(width: 5),
            if (widget.enabled)
              IconButton(
                key: Key("${tag.label}_clear"),
                icon: Icon(
                  FluentIcons.clear,
                  size: 10,
                  color: tapable ? Colors.white : null,
                ),
                onPressed: () => _removeTag(tag),
              ),
          ],
        ),
      ),
    );
  }
}

/// One row of a suggestion dropdown (see `_buildSuggestionRow`).
///
/// A single line, ellipsized, highlighted on hover and while the keyboard is on
/// it — the three things the library's own row cannot do without overflowing.
class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? child;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final highlighted = widget.selected || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: highlighted
              ? theme.resources.controlAltFillColorTertiary
              : Colors.transparent,
          child: DefaultTextStyle.merge(
            style: theme.typography.body,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            child: widget.child ?? Text(widget.label),
          ),
        ),
      ),
    );
  }
}
