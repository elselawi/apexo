import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/palmer.dart';
import 'package:apexo/common_widgets/teeth_selector/tx_options.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
import 'dart:math' as math;

class ToothStateWheel extends StatefulWidget {
  final String toothName;
  final String iso;
  final String? initialValue;
  final ValueChanged<String?> onSet;
  final VoidCallback onTapClose;

  const ToothStateWheel({
    super.key,
    this.initialValue,
    required this.iso,
    required this.toothName,
    required this.onSet,
    required this.onTapClose,
  });

  @override
  State<ToothStateWheel> createState() => _ToothStateWheelState();
}

class _ToothStateWheelState extends State<ToothStateWheel> {
  String? _selectedLabel;
  bool _isOtherMode = false;
  final TextEditingController _otherController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedLabel = widget.initialValue;

    if (txOptions.where((x) => x.label == _selectedLabel).isEmpty &&
        _selectedLabel != null &&
        _selectedLabel != "") {
      _isOtherMode = true;
      _otherController.text = _selectedLabel ?? "";
    }
  }

  void _select(String? label) {
    setState(() {
      _selectedLabel = label;
      _isOtherMode = false;
    });
    widget.onSet(label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    const double size = 400.0;

    return Container(
      width: size,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // The Wheel
          Container(
            height: 335,
            width: 335,
            decoration: BoxDecoration(
              color: theme.menuColor,
              borderRadius: BorderRadius.circular(1000),
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0.0, 6.0),
                  blurRadius: 30.0,
                  spreadRadius: 5.0,
                  color: Colors.grey.withAlpha(50),
                )
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Inner Circle Display
                SizedBox(
                  width: 190,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(scale: 1.5,child: PalmerNotation(iso: widget.iso, color: labelToColor(_selectedLabel ?? ""),)),
                      const SizedBox(height: 10),
                      Text(
                        softWrap: true,
                        textAlign: TextAlign.center,
                        widget.toothName,
                        style: theme.typography.caption!
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      _isOtherMode
                          ? CupertinoTextField(
                              controller: _otherController,
                              placeholder: 'Describe state...',
                              autofocus: true,
                            )
                          : Txt(
                              txt(_selectedLabel ?? ""),
                              style: theme.typography.bodyStrong!.copyWith(
                                  backgroundColor: (txOptions
                                              .where((x) =>
                                                  x.label == _selectedLabel)
                                              .firstOrNull ??
                                          TxOption(
                                            "label",
                                            FluentIcons.activity_feed,
                                            Colors.black,
                                          ))
                                      .color,
                                  color: Colors.white),
                            ),
                      const SizedBox(height: 10),
                      if (_selectedLabel != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_selectedLabel != null)
                              FilledButton(
                                style: const ButtonStyle(
                                    backgroundColor: WidgetStatePropertyAll(
                                        Colors.errorPrimaryColor)),
                                child: ButtonContent(
                                    FluentIcons.delete, txt("delete")),
                                onPressed: () => _select(null),
                              ),
                            const SizedBox(width: 5),
                            if (_isOtherMode)
                              FilledButton(
                                child: ButtonContent(
                                    FluentIcons.save, txt("save")),
                                onPressed: () => _select(_otherController.text),
                              )
                            else
                              FilledButton(
                                style: const ButtonStyle(
                                    backgroundColor:
                                        WidgetStatePropertyAll(Colors.grey)),
                                onPressed: widget.onTapClose,
                                child: ButtonContent(
                                    FluentIcons.cancel, txt("close")),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                // The Buttons
                ...List.generate(txOptions.length, (index) {
                  final double angle =
                      (index * 2 * math.pi / txOptions.length) - (math.pi / 2);
                  const double radius = 135.0;

                  return Transform.translate(
                    offset: Offset(
                        radius * math.cos(angle), radius * math.sin(angle)),
                    child: _RadialButton(
                      transparent: _isOtherMode && index != txOptions.length - 1,
                      state: txOptions[index],
                      isSelected: _selectedLabel == txOptions[index].label ||
                          index == txOptions.length - 1 && _isOtherMode == true,
                      onTap: () {
                        if (index == txOptions.length - 1) {
                          setState(() {
                            _selectedLabel = "";
                            _isOtherMode = true;
                          });
                        } else {
                          _select(txOptions[index].label);
                        }
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RadialButton extends StatelessWidget {
  final TxOption state;
  final bool isSelected;
  final VoidCallback onTap;
  final bool transparent;

  const _RadialButton({
    required this.state,
    required this.isSelected,
    required this.onTap,
    required this.transparent,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: state.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          height: 55,
          width: 55,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: transparent ? state.color.withAlpha(0) : state.color,
            border: Border.all(
              color: isSelected
                  ? Colors.transparent
                  : state.color.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: state.color.withValues(alpha: 0.7),
                      blurRadius: 7,
                      spreadRadius: 7,
                    )
                  ]
                : [
                    BoxShadow(
                      color: state.color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 4,
                    )
                  ],
          ),
          child: Center(
              child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(state.icon, size: 25, color: Colors.white),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                child: Txt(
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  txt(state.label),
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              )
            ],
          )),
        ),
      ),
    );
  }
}
