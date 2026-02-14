import 'package:apexo/common_widgets/dental_icons/dental_icons.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ColorsDictionary {
  static const extraction = Color(0xFFE53935);
  static const filling = Color(0xFFD81B60);
  static const pulpotomy = Color(0xFF8E24AA);
  static const rct = Color(0xFF5E35B1);
  static const reRct = Color(0xFF3949AB);
  static const whitening = Color(0xFF1E88E5);
  static const clean = Color(0xFF039BE5);
  static const implant = Color(0xFF00ACC1);
  static const surgery = Color(0xFF00897B);
  static const ortho = Color(0xFF2962FF);
  static const crown = Color(0xFF43A047);
  static const veneer = Color(0xFF7CB342);
  static const bridge = Color(0xFFC0CA33);
  static const overaly = Color(0xFFFDD835);
  static const temp = Color(0xFFFB8C00);
  static const other = Color(0xFF6D4C41);
}

class TxOption {
  final String label;
  final Color color;
  final IconData icon;
  TxOption(this.label, this.icon, this.color);
}

final List<TxOption> txOptions = [
  TxOption('extraction', DentalIcons.exo, ColorsDictionary.extraction),
  TxOption('filling', DentalIcons.filling, ColorsDictionary.filling),
  TxOption('pulpotomy', DentalIcons.pulpotomy, ColorsDictionary.pulpotomy),
  TxOption('rCT', DentalIcons.rct, ColorsDictionary.rct),
  TxOption('re-RCT', DentalIcons.rerct, ColorsDictionary.reRct),
  TxOption('ortho', DentalIcons.ortho, ColorsDictionary.ortho),
  TxOption('whitening', DentalIcons.whiten, ColorsDictionary.whitening),
  TxOption('clean', DentalIcons.clean, ColorsDictionary.clean),
  TxOption('implant', DentalIcons.implant, ColorsDictionary.implant),
  TxOption('surgery', DentalIcons.apiceoctomy, ColorsDictionary.surgery),
  TxOption('crown', DentalIcons.crown, ColorsDictionary.crown),
  TxOption('veneer', DentalIcons.veneer, ColorsDictionary.veneer),
  TxOption('bridge', DentalIcons.bridge, ColorsDictionary.bridge),
  TxOption('overlay', DentalIcons.overlay, ColorsDictionary.overaly),
  TxOption('temporary', DentalIcons.temp, ColorsDictionary.temp),
  TxOption('other', DentalIcons.question, ColorsDictionary.other),
];

Color labelToColor(String label) {
  return txOptions.where((x) => x.label == label).firstOrNull?.color ??
      ColorsDictionary.other;
}

IconData labelToIcon(String label) {
  return txOptions.where((x) => x.label == label).firstOrNull?.icon ??
      DentalIcons.question;
}
