import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

class ScreenCommandBar extends StatelessWidget {
  const ScreenCommandBar({
    super.key,
    required this.mainButton,
    this.otherButtons = const [],
    this.farItems = const [],
  });

  final Widget mainButton;
  final List<Widget> otherButtons;
  final List<Widget> farItems;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            offset: const Offset(0.0, 6.0),
            blurRadius: 30.0,
            spreadRadius: 5.0,
            color: Colors.grey.withAlpha(50),
          )
        ],
        color: FluentTheme.of(context).menuColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            spacing: 8,
            children: [
              mainButton,
              const Divider(size: 20, direction: Axis.vertical),
              ...otherButtons
            ],
          ),
          Row(
            spacing: 5,
            children: [...farItems],
          )
        ],
      ),
    );
  }
}

BoxDecoration topBarDecoration(BuildContext context, Color color) {
  return BoxDecoration(
      border: BorderDirectional(
        bottom: BorderSide(
            color:
                FluentTheme.of(context).inactiveColor.withValues(alpha: 0.1)),
      ),
      gradient: LinearGradient(
        colors: [
          Colors.transparent,
          color.withAlpha(30),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ));
}

Border listDividerBorder(BuildContext context) {
  return Border(
    bottom: BorderSide(
      color: FluentTheme.of(context).inactiveColor.withValues(alpha: 0.1),
      width: 1,
    ),
  );
}

class TopSearch extends StatelessWidget {
  final TextEditingController controller;
  final void Function(void Function()) setState;
  const TopSearch({
    super.key,
    required this.controller,
    required this.setState,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      decoration: BoxDecoration(
          color: Colors.transparent,
          border: Border.all(color: Colors.transparent)),
      placeholder: txt("searchPlaceholder"),
      placeholderStyle: TextStyle(
          fontSize: 18,
          color: FluentTheme.of(context).inactiveColor.withAlpha(140)),
      prefix: const Text(
        "🔍",
        style: TextStyle(fontSize: 18),
      ),
      controller: controller,
      onChanged: (text) => setState(() {}),
      suffix: controller.text.isNotEmpty
          ? IconButton(
              icon: const Icon(
                WindowsIcons.clear,
                size: 20,
              ),
              onPressed: () {
                controller.clear();
                setState(() {});
              })
          : null,
    );
  }
}
