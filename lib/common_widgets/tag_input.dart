import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

class TagInputItem extends AutoSuggestBoxItem<String> {
  TagInputItem({required super.value, required super.label});
}

class TagInputWidget extends StatefulWidget {
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

  @override
  State<TagInputWidget> createState() => _TagInputWidgetState();
}

class _TagInputWidgetState extends State<TagInputWidget> {
  final TextEditingController _controller = TextEditingController();
  final _hiddenTappedFlyoutController = FlyoutController();
  final autoSuggestBoxRef = GlobalKey<AutoSuggestBoxState>();
  late FocusNode _focusNode;
  late List<TagInputItem> _tags;
  late List<TagInputItem> _suggestions;
  bool _isFocused = false;

  bool get tapable {
    return widget.onItemTap != null;
  }

  void _onSuggestionSelected(AutoSuggestBoxItem<String> suggestion) {
    setState(() {
      _tags.add(TagInputItem(value: suggestion.value, label: suggestion.label));
      _controller.clear();
    });

    // Force the text field to clear by updating the text field directly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.text = '';
    });

    widget.onChanged(_tags);
    if (_tags.length < widget.limit) {
      _focusNode.requestFocus();
    }
  }

  @override
  void initState() {
    super.initState();
    _tags = widget.initialValue;
    if (widget.strict == false) {
      _suggestions = [
        TagInputItem(value: "", label: ""),
        ...widget.suggestions
      ];
    } else {
      _suggestions = widget.suggestions;
    }

    _focusNode = FocusNode(onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          _controller.text.isEmpty &&
          event.logicalKey == LogicalKeyboardKey.backspace) {
        backspaceRemove();
      }
      return KeyEventResult.ignored;
    });

    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
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
      _hiddenTappedFlyoutController.close();
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
    _hiddenTappedFlyoutController.showFlyout(
        builder: (context) {
          return FlyoutContent(
              key: Key(_tags.map((e) => e.value).join("")),
              child: Wrap(children: _tags.map((e) => _buildTag(e)).toList()));
        },
        dismissWithEsc: true);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const tokenPadding = EdgeInsets.symmetric(horizontal: 8);
        const tokenSpacing = 4.0;
        const collapseWidth = 36.0;

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
                  tag.label.length > 20)) {
            hiddenTags.add(tag);
          } else {
            usedWidth += tokenWidth + tokenSpacing;
            visibleTags.add(tag);
          }
        }

        return FlyoutTarget(
          controller: _hiddenTappedFlyoutController,
          child: Container(
            height: widget.multiline ? visibleTags.length * 35 + 40 : 40,
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
                              : (_isFocused
                                  ? _buildHiddenTagsIndicator(
                                      tokenSpacing, _tags)
                                  : _buildVisibleTags(
                                      visibleTags, tokenSpacing)),
                        ),
                        if (_tags.length < widget.limit)
                          _buildAutoSuggestInputTextBox(),
                      ])
                : Row(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        child: _tags.isEmpty
                            ? const SizedBox.shrink()
                            : (_isFocused
                                ? _buildHiddenTagsIndicator(tokenSpacing, _tags)
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildVisibleTags(
                                          visibleTags, tokenSpacing),
                                      if (hiddenTags.isNotEmpty)
                                        _buildHiddenTagsIndicator(
                                            tokenSpacing, hiddenTags),
                                    ],
                                  )),
                      ),
                      if (_tags.length < widget.limit)
                        _buildAutoSuggestInputTextBox(),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Expanded _buildAutoSuggestInputTextBox() {
    return Expanded(
      child: AutoSuggestBox(
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
        trailingIcon: (_tags.length < 2 || widget.multiline) && widget.enabled
            ? (IconButton(
                icon: autoSuggestBoxRef.currentState == null
                    ? const Icon(FluentIcons.chevron_down)
                    : autoSuggestBoxRef.currentState!.isOverlayVisible
                        ? const Icon(FluentIcons.chevron_up)
                        : const Icon(FluentIcons.chevron_down),
                iconButtonMode: IconButtonMode.large,
                style: const ButtonStyle(iconSize: WidgetStatePropertyAll(14)),
                onPressed: () {
                  setState(() {
                    if (autoSuggestBoxRef.currentState == null) return;
                    if (autoSuggestBoxRef.currentState!.isOverlayVisible ==
                        false) {
                      autoSuggestBoxRef.currentState!.showOverlay();
                    } else {
                      autoSuggestBoxRef.currentState!.dismissOverlay();
                    }
                  });
                }))
            : null,
        items: _filteredSuggestions
            .map(
              (s) => AutoSuggestBoxItem(
                value: s.value,
                label: s.label,
              ),
            )
            .toList(),
        onSelected: _onSuggestionSelected,
        onChanged: (text, reason) {
          if (widget.strict) return;
          setState(() {
            _suggestions.setAll(0, [TagInputItem(value: text, label: text)]);
          });
        },
      ),
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

  Widget _buildVisibleTags(
      List<TagInputItem> visibleTags, double tokenSpacing) {
    final childrenToBuild = [
      ...visibleTags.reversed.map((tag) => Padding(
            padding: EdgeInsets.only(right: tokenSpacing),
            child: _buildTag(tag),
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
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withAlpha(100)),
        borderRadius: BorderRadius.circular(5),
        color: tapable ? Colors.blue : FluentTheme.of(context).cardColor,
      ),
      child: IconButton(
        onPressed: () {
          if (_hiddenTappedFlyoutController.isOpen) {
            _hiddenTappedFlyoutController.close();
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
            Txt(tag.label,
                style: TextStyle(color: tapable ? Colors.white : null)),
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
