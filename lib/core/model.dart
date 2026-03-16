import 'package:apexo/utils/colors_without_yellow.dart';
import 'package:apexo/utils/get_deterministic_item.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../utils/uuid.dart';

class Model {
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

  Model.fromJson(Map<String, dynamic> json)
      : id = uuid(),
        title = "" {
    if (json["id"] != null) id = json["id"];
    if (json["archived"] != null) archived = json["archived"];
    if (json["title"] != null) title = json["title"];
  }

  Map<String, String> get labels {
    return {};
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


/**
 ********* Example usage

class MyClass extends Doc {
  String name = '';
  int age = 0;

  MyClass.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    name = json["name"] ?? name;
    age = json["age"] ?? age;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = MyClass.fromJson({});
    if (name != d.name) json['name'] = name;
    if (age != d.age) json['age'] = age;
    return json;
  }

  get ageInDays => age * 365;
}
*/