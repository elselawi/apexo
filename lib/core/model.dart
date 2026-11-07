import 'package:apexo/utils/colors_without_yellow.dart';
import 'package:apexo/utils/get_deterministic_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../utils/uuid.dart';

class Model {
  Model.fromJson(Map<String, dynamic> json)
      : id = uuid(),
        title = "" {
    fromJson(json);
  }
  String id;
  bool? archived;
  bool get locked => false;
  String title;
  String? get avatar {
    return null;
  }

  String? get imageRowId {
    return null;
  }

  Color? _color;
  Color get color {
    return _color ??= getDeterministicItem<Color>(colorsWithoutYellow, id);
  }

  Map<String, String> get labels {
    return {};
  }

  Model copy(bool blank) {
    return Model.fromJson(blank ? {} : toJson());
  }

  void fromJson(Map<String, dynamic> json) {
    if (json["id"] != null) id = json["id"] as String;
    if (json["archived"] != null) archived = json["archived"] as bool?;
    if (json["title"] != null) title = json["title"] as String;
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    json['id'] = id;
    if (archived != null) json['archived'] = archived;
    if (title != "") json["title"] = title;
    return json;
  }

  Map<String, dynamic> get jsonCopyForPush {
    return {};
  }

  List<String> get targetsToPushTo {
    return [];
  }

  List<String> get pushIfChanged {
    return [];
  }

  bool get pushOnCreation {
    return false;
  }
}
