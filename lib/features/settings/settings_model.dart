import 'package:apexo/core/model.dart';

class Setting extends Model {
  String value = "";

  Setting.fromJson(super.json) : super.fromJson();

  @override
  Setting copy(bool blank) {
    return Setting.fromJson(blank ? {} : toJson());
  }

  @override
  void fromJson(Map<String, dynamic> json) {
    super.fromJson(json);
    value = json["value"] ?? value;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    final d = Setting.fromJson({});
    if (value != d.value) json['value'] = value;
    return json;
  }
}
