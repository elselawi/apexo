import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

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

  const TagInputWidget(
      {super.key,
      required this.suggestions,
      required this.onChanged,
      required this.initialValue,
      required this.strict,
      required this.limit,
      this.placeholder = "",
      this.onItemTap});

  @override
  TagInputWidgetState createState() => TagInputWidgetState();
}

class TagInputWidgetState extends State<TagInputWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late List<TagInputItem> _tags;
  late List<TagInputItem> _filteredSuggestions;
  final key = GlobalKey<AutoSuggestBoxState>();

  @override
  void initState() {
    super.initState();
    _filteredSuggestions = widget.suggestions;
    _tags = widget.initialValue;
  }

  void _onTextChanged(String inputVal, _) {
    // this CAN be triggered while the widget has been unmounted/rebuilt
    // that's why we're keeping the "mounted" condition
    if (!mounted) return;

    setState(() {
      if (inputVal.isEmpty) {
        _filteredSuggestions = widget.suggestions;
      } else {
        _filteredSuggestions = widget.suggestions
            .where((suggestion) =>
                _tags.map((e) => e.label.toLowerCase()).contains(suggestion.label.toLowerCase()) == false)
            .toList();

        // Always add the current input value to the suggestions
        if (widget.strict == false && _filteredSuggestions.map((e) => e.label).contains(inputVal) == false) {
          _filteredSuggestions.insert(0, TagInputItem(value: inputVal.replaceAll(" ", "-"), label: inputVal));
        }
      }
    });

    // Refresh the AutoSuggestBox suggestions by slightly altering the input value
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.text.isNotEmpty) {
        final currentPosition = _controller.selection;
        _controller.text = _controller.text;
        _controller.selection = currentPosition;
        _focusNode.requestFocus();
      }
    });
  }

  void _onSuggestionSelected(AutoSuggestBoxItem<String> suggestion) {
    setState(() {
      _tags.add(TagInputItem(value: suggestion.value, label: suggestion.label));
      _controller.clear();
      _filteredSuggestions = widget.suggestions;
    });

    // Force the text field to clear by updating the text field directly
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.text = '';
      _onTextChanged('', null); // Refresh suggestions
    });

    widget.onChanged(_tags);
  }

  void _removeTag(TagInputItem tag) {
    setState(() {
      _tags.removeWhere((e) => e.value == tag.value);
    });
    widget.onChanged(_tags);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: _tags.isEmpty ? null : Border.all(color: const Color.fromARGB(255, 221, 221, 221)),
        borderRadius: _tags.isEmpty ? null : BorderRadius.circular(4),
        color: _tags.isEmpty ? null : FluentTheme.of(context).menuColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(_tags.isEmpty ? 0 : 3),
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: _tags.map((tag) {
                return _buildTag(tag);
              }).toList(),
            ),
          ),
          if (widget.limit > _tags.length)
            AutoSuggestBox<String>(
                key: key,
                controller: _controller,
                textInputAction: TextInputAction.none,
                decoration: WidgetStatePropertyAll(BoxDecoration(
                  border:
                      Border.all(color: const Color.fromARGB(255, 220, 220, 220), width: _tags.isEmpty ? 1.25 : 0.01),
                )),
                focusNode: _focusNode, // Attach the FocusNode to preserve focus
                items: _filteredSuggestions
                    .where((suggestion) => _tags.where((selected) => selected.value == suggestion.value).isEmpty)
                    .toList(),
                onSelected: _onSuggestionSelected,
                onChanged: _onTextChanged,
                placeholder: widget.placeholder,
                noResultsFoundBuilder: (context) =>
                    Padding(padding: const EdgeInsets.all(10), child: Txt(txt("noResultsFound"))),
                trailingIcon: GestureDetector(
                  child: const Icon(FluentIcons.grouped_descending),
                  onTap: () {
                    if (key.currentState != null) {
                      var state = key.currentState!;
                      if (state.isOverlayVisible) {
                        state.dismissOverlay();
                        _focusNode.unfocus();
                      } else {
                        state.showOverlay();
                        _focusNode.requestFocus();
                      }
                    }
                  },
                ))
        ],
      ),
    );
  }

  Padding _buildTag(TagInputItem tag) {
    return Padding(
      padding: const EdgeInsets.only(right: 2, bottom: 2),
      child: Acrylic(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        elevation: 1,
        child: IconButton(
          onPressed: () => widget.onItemTap == null ? null : widget.onItemTap!(tag),
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.only(left: 10, right: 5, top: 5, bottom: 5)),
          ),
          icon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Txt(tag.label),
              const SizedBox(width: 5),
              IconButton(
                key: Key("${tag.label}_clear"),
                icon: const Icon(FluentIcons.clear, size: 10),
                onPressed: () => _removeTag(tag),
                style: ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.05))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
