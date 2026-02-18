import 'package:apexo/common_widgets/dental_icons/dental_icons.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ColorsDictionary {
  static const c01 = Color(0xFFE53935);
  static const c02 = Color(0xFFD81B60);
  static const c03 = Color(0xFF8E24AA);
  static const c04 = Color(0xFF5E35B1);
  static const c05 = Color(0xFF3949AB);
  static const c06 = Color(0xFF1E88E5);
  static const c07 = Color(0xFF039BE5);
  static const c08 = Color(0xFF00ACC1);
  static const c09 = Color(0xFF00897B);
  static const c10 = Color(0xFF2962FF);
  static const c11 = Color(0xFF43A047);
  static const c12 = Color(0xFF7CB342);
  static const c13 = Color(0xFFC0CA33);
  static const c14 = Color(0xFFC0CA33);
  static const c15 = Color.fromARGB(255, 202, 139, 51);
  static const c16 = Color.fromARGB(255, 57, 209, 93);
  static const c17 = Color.fromARGB(255, 1, 207, 131);
  static const c18 = Color(0xFF6D4C41);
}

enum StateType { treatment, state, both }

class TxOption {
  final String label;
  final Color color;
  final IconData icon;
  final StateType type;
  TxOption(this.label, this.icon, this.color, this.type);
}

final List<TxOption> txOptions = [
  TxOption('missing', DentalIcons.question, ColorsDictionary.c01, StateType.state),
  TxOption('extraction', DentalIcons.exo, ColorsDictionary.c01, StateType.treatment),
  TxOption('filling', DentalIcons.filling, ColorsDictionary.c02, StateType.both),
  TxOption('pulpotomy', DentalIcons.pulpotomy, ColorsDictionary.c03, StateType.treatment),
  TxOption('caries', DentalIcons.caries, ColorsDictionary.c03, StateType.state),
  TxOption('rCT', DentalIcons.rct, ColorsDictionary.c04, StateType.both),
  TxOption('fractured', DentalIcons.fractured, ColorsDictionary.c05, StateType.state),
  TxOption('re-RCT', DentalIcons.rerct, ColorsDictionary.c05, StateType.treatment),
  TxOption('mobility', DentalIcons.mobility, ColorsDictionary.c10, StateType.state),
  TxOption('ortho', DentalIcons.ortho, ColorsDictionary.c10, StateType.treatment),
  TxOption('recession', DentalIcons.recession, ColorsDictionary.c06, StateType.state),
  TxOption('whitening', DentalIcons.whiten, ColorsDictionary.c06, StateType.treatment),
  TxOption('rroot', DentalIcons.retainedroot, ColorsDictionary.c07, StateType.state),
  TxOption('clean', DentalIcons.clean, ColorsDictionary.c07, StateType.treatment),
  TxOption('implant', DentalIcons.implant, ColorsDictionary.c08, StateType.both),
  TxOption('rprimary', DentalIcons.retainedprimary, ColorsDictionary.c09, StateType.state),
  TxOption('surgery', DentalIcons.apiceoctomy, ColorsDictionary.c09, StateType.treatment),
  TxOption('malposition', DentalIcons.crowding, ColorsDictionary.c09, StateType.state),
  TxOption('crown', DentalIcons.crown, ColorsDictionary.c11, StateType.both),
  TxOption('veneer', DentalIcons.veneer, ColorsDictionary.c12, StateType.both),
  TxOption('overlay', DentalIcons.overlay, ColorsDictionary.c16, StateType.both),
  TxOption('impacted', DentalIcons.impacted, ColorsDictionary.c17, StateType.state),
  TxOption('temporary', DentalIcons.temp, ColorsDictionary.c17, StateType.treatment),
  TxOption('bridge', DentalIcons.bridge, ColorsDictionary.c13, StateType.both),
  TxOption('abutment', DentalIcons.abutment, ColorsDictionary.c14, StateType.both),
  TxOption('pontic', DentalIcons.pontic, ColorsDictionary.c15, StateType.both),
  TxOption('other', DentalIcons.question, ColorsDictionary.c18, StateType.both),
];

Color labelToColor(String label) {
  return txOptions.where((x) => x.label == label).firstOrNull?.color ??
      ColorsDictionary.c18;
}

IconData labelToIcon(String label) {
  return txOptions.where((x) => x.label == label).firstOrNull?.icon ??
      DentalIcons.question;
}
