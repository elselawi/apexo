import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/keyboard_aware.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';

class DialogWithTextBox extends StatefulWidget {
  const DialogWithTextBox({
    super.key,
    required this.title,
    required this.onSave,
    required this.icon,
    this.initialValue,
  });

  final String title;
  final void Function(String input) onSave;
  final IconData icon;
  final String? initialValue;

  @override
  State<DialogWithTextBox> createState() => _DialogWithTextBoxState();
}

class _DialogWithTextBoxState extends State<DialogWithTextBox> {
  late final TextEditingController _input;

  @override
  void initState() {
    super.initState();
    _input = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardAwareView(
      child: ContentDialog(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 200),
        style: dialogStyling(context, false, false),
        title: Row(children: [
          Icon(widget.icon),
          const SizedBox(width: 5),
          Txt(widget.title)
        ]),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 5,
          children: [
            Txt("${txt("name")}:"),
            SizedBox(
              height: 40,
              child: TextBox(
                controller: _input, // Use the state-bound controller
                autofocus: true,
                expands: false,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon),
                const SizedBox(width: 10),
                Txt(txt("save")),
              ],
            ),
            onPressed: () {
              // 4. Pass the text back to your callback safely
              widget.onSave(_input.text);
              Navigator.of(context).pop();
            },
          ),
          const CloseButtonInDialog(),
        ],
      ),
    );
  }
}
