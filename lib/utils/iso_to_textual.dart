import 'package:apexo/services/localization/locale.dart';

String isoToTextualNotation(String iso) {
  final quadrant = int.parse(iso.substring(0, 1));
  final tooth = int.parse(iso.substring(1));
  return """
          ${txt(stage[quadrant] ?? "")}
          ${txt(jaw[quadrant] ?? "")}
          ${txt(direction[quadrant] ?? "")}
          ${quadrant < 5 ? txt(namePermanent[tooth] ?? "") : txt(namePrimary[tooth] ?? "")}
    """
      .replaceAll(RegExp(r"\s+"), " ")
      .trim();
}

final Map<int, String> stage = {
  1: "permanent",
  2: "permanent",
  3: "permanent",
  4: "permanent",
  5: "primary",
  6: "primary",
  7: "primary",
  8: "primary",
};

final Map<int, String> jaw = {
  1: "upper",
  2: "upper",
  3: "lower",
  4: "lower",
  5: "upper",
  6: "upper",
  7: "lower",
  8: "lower",
};

final Map<int, String> direction = {
  1: "right",
  2: "left",
  3: "left",
  4: "right",
  5: "right",
  6: "left",
  7: "left",
  8: "right",
};

final Map<int, String> namePermanent = {
  1: "centralIncisor",
  2: "lateralIncisor",
  3: "canine",
  4: "firstPremolar",
  5: "secondPremolar",
  6: "firstMolar",
  7: "secondMolar",
  8: "thirdMolar",
};

final Map<int, String> namePrimary = {
  1: "centralIncisor",
  2: "lateralIncisor",
  3: "canine",
  4: "firstMolar",
  5: "secondMolar",
};
