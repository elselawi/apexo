import 'dart:async';
import 'dart:math' as math;
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
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

  // AutoSuggestBox keeps its selected item private, so these custom rows track
  // the highlight themselves via `onFocusChange`.
  String? _focusedSuggestion;

  bool get tapable {
    return widget.onItemTap != null;
  }

  void _onSuggestionSelected(AutoSuggestBoxItem<String> suggestion) {
    if (!mounted || !context.mounted) return;
    setState(() {
      _tags.add(TagInputItem(value: suggestion.value, label: suggestion.label));
      _controller.clear();
    });

    // Force the text field to clear by updating the text field directly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.text = '';
    });

    // Leaving the overlay open strands a "No results found" flyout over the
    // panel and swallows clicks meant for its tabs.
    autoSuggestBoxRef.currentState?.dismissOverlay();

    widget.onChanged(_tags);
    if (_tags.length < widget.limit) {
      _focusNode.requestFocus();
    }
  }

  // `setState` is illegal while the tree is locked, and AutoSuggestBox calls us
  // from mid-frame (focus changes, dismissOverlay, dispose). `mounted` does not
  // cover that window, so the rebuild waits for the frame to end.
  void _rebuild(VoidCallback fn) {
    void apply() {
      if (!mounted) return;
      setState(fn);
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    final locked = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  // Several focus changes can queue behind one lock, so the rebuild recomputes
  // the highlight instead of capturing it here.
  void _setFocusedSuggestion(String label, {required bool focused}) {
    final next = focused
        ? label
        : (_focusedSuggestion == label ? null : _focusedSuggestion);
    if (next == _focusedSuggestion) return;

    _rebuild(() {
      if (focused) {
        _focusedSuggestion = label;
      } else if (_focusedSuggestion == label) {
        _focusedSuggestion = null;
      }
    });
  }

  // `AutoSuggestBox` only submits an arrow-key-highlighted item; Enter otherwise
  // closes the dropdown, so the typed text is matched against suggestions first.
  bool _commitTypedText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return false;
    final folded = text.toLowerCase();
    // The suggestion list hides existing tags, but a non-strict box mirrors the
    // typed text into the suggestions, so the duplicate check is explicit.
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
      // Enter is caught on the text box's focus node so it never reaches the
      // editable's submit path, which would unfocus and close the dropdown.
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
    if (oldWidget.initialValue != widget.initialValue &&
        !_listEquals(_tags, widget.initialValue)) {
      _tags = List.of(widget.initialValue);
      _updateSuggestions();
      // Don't mark dirty if the widget is no longer mounted
      if (mounted) setState(() {});
    }
    // `AutoSuggestBox` repaints its dropdown only when the text changes, so a
    // list that arrives late is hidden until the overlay reopens.
    if (!_listEquals(oldWidget.suggestions, widget.suggestions)) {
      _updateSuggestions();
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) => _reopenOverlay());
      }
    }
  }

  // Deferred to a frame: inserting an overlay entry from `didUpdateWidget`
  // would mark the tree dirty while it is being built.
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
    _rebuild(() => _isFocused = _focusNode.hasFocus);
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
        // The container below spends 3px padding and 1px border per side;
        // subtract it to get the row's real width.
        const fieldChrome = 3.0 * 2 + 1.0 * 2;
        // The chip row is unbounded, so the widest chip sets the row width; cap
        // it to leave room for the input, or to fit the field at the limit.
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
            // Multiline fields size themselves: a fixed height ignored the
            // chrome, chip spacing and `AnimatedSize`'s settle, and overflowed.
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
                          // Not an `Expanded`: a flex child of an unbounded
                          // `Column` is an error; the box sizes itself.
                          _buildAutoSuggestInputTextBox(expand: false),
                      ])
                : Row(
                    children: [
                      // A long chip (a patient's name in a `limit: 1` picker)
                      // can outgrow the field, so cap it at the row's width.
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: availableWidth),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: _tags.isEmpty
                              ? const SizedBox.shrink()
                              // A focused field folds its chips to leave the
                              // input room, but at the limit they stay visible.
                              : (_isFocused && inputVisible
                                  ? _buildHiddenTagsIndicator(
                                      tokenSpacing, _tags)
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
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
              // AutoSuggestBox only invokes `onSelected` from its own rows, so
              // the callback has to travel with each item for ours.
              onSelected: () => _onSuggestionSelected(s),
              onFocusChange: (focused) =>
                  _setFocusedSuggestion(s.label, focused: focused),
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

  // `AutoSuggestBox`'s own rows wrap a long label past the fixed item extent
  // and overflow, so this draws one ellipsized line instead.
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
