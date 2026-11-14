import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/ui/design/fluent_materials.dart';
import 'package:apexo/widget_keys.dart';
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
    final materials = FluentMaterials.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: materials.glassTint,
        border: Border.symmetric(
          horizontal: BorderSide(
            color: materials.divider,
            width: FluentMaterials.hairlineWidth,
          ),
        ),
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

BoxDecoration topBarDecoration(BuildContext context) {
  return BoxDecoration(
    gradient: LinearGradient(colors: [
      FluentMaterials.of(context).glassTint.withAlpha(0),
      FluentMaterials.of(context).glassTint,
    ], begin: AlignmentGeometry.topCenter, end: AlignmentGeometry.bottomCenter),
    border: BorderDirectional(
      bottom: BorderSide(
        color: FluentMaterials.of(context).divider,
        width: FluentMaterials.hairlineWidth,
      ),
    ),
  );
}

Border listDividerBorder(BuildContext context) {
  return Border(
    bottom: BorderSide(
      color: FluentMaterials.of(context).divider,
      width: FluentMaterials.hairlineWidth,
    ),
  );
}

class TopSearch extends StatelessWidget {
  const TopSearch({
    super.key,
    required this.controller,
    required this.setState,
  });
  final TextEditingController controller;
  final void Function(void Function()) setState;

  @override
  Widget build(BuildContext context) {
    final materials = FluentMaterials.of(context);
    return Semantics(
      key: WK.listSearch,
      container: true,
      textField: true,
      child: CupertinoTextField(
        decoration: BoxDecoration(
          border: Border.all(color: materials.stroke),
          color: materials.glassTint,
          borderRadius: BorderRadius.circular(50),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        placeholder: txt("searchPlaceholder"),
        prefix: Padding(
          padding: const EdgeInsetsDirectional.only(start: 10, end: 6),
          child: Icon(
            WindowsIcons.search,
            color: materials.textSecondary,
          ),
        ),
        controller: controller,
        onChanged: (text) => setState(() {}),
        suffix: controller.text.isNotEmpty
            ? Padding(
                padding: const EdgeInsetsDirectional.only(end: 5),
                child: IconButton(
                    icon: const Icon(
                      WindowsIcons.clear,
                      size: 14,
                    ),
                    onPressed: () {
                      controller.clear();
                      setState(() {});
                    }),
              )
            : null,
      ),
    );
  }
}
