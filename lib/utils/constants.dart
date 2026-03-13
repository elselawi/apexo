import 'package:pocketbase/pocketbase.dart';

/// shared constants

class PInt {
  static const int patients = 0;
  static const int appointments = 1;
  static const int postOp = 2;
  static const int stats = 3;
  static const int expenses = 4;
  static const int setting = 5;
  static const int photos = 6;
  static const int notes = 7;
}

const String alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
const String dataCollectionName = "data";
const String publicCollectionName = "public";
const String webImagesStore = "web-images";
const String profilesCollectionName = "profiles";
const String profilesViewCollectionName = "profiles_view";
final dataCollectionImport = CollectionModel(
  name: dataCollectionName,
  type: "base",
  fields: [
    CollectionField({
      "autogeneratePattern": "[a-z0-9]{15}",
      "hidden": false,
      "max": 15,
      "min": 15,
      "name": "id",
      "pattern": "^[a-zA-Z0-9_]+\$",
      "presentable": false,
      "primaryKey": true,
      "required": true,
      "system": true,
      "type": "text"
    }),
    CollectionField({
      "hidden": false,
      "maxSize": 2000000,
      "name": "data",
      "presentable": false,
      "required": false,
      "system": false,
      "type": "json"
    }),
    CollectionField({
      "autogeneratePattern": "",
      "hidden": false,
      "max": 0,
      "min": 0,
      "name": "store",
      "pattern": "",
      "presentable": false,
      "primaryKey": false,
      "required": false,
      "system": false,
      "type": "text"
    }),
    CollectionField({
      "hidden": false,
      "maxSelect": 99,
      "maxSize": 157286400,
      "mimeTypes": null,
      "name": "imgs",
      "presentable": false,
      "protected": false,
      "required": false,
      "system": false,
      "thumbs": null,
      "type": "file"
    }),
    CollectionField({
      "hidden": false,
      "name": "created",
      "onCreate": true,
      "onUpdate": false,
      "presentable": false,
      "system": false,
      "type": "autodate"
    }),
    CollectionField({
      "hidden": false,
      "name": "updated",
      "onCreate": true,
      "onUpdate": true,
      "presentable": false,
      "system": false,
      "type": "autodate"
    })
  ],
  indexes: [
    "CREATE INDEX `idx_get_since` ON `$dataCollectionName` (\n  `store`,\n  `updated`\n)",
    "CREATE INDEX `idx_get_version` ON `$dataCollectionName` (\n  `store`,\n  `updated` DESC\n)"
  ],
  listRule: ruleEitherLoggedOrSettings,
  viewRule: ruleEitherLoggedOrSettings,
  createRule: ruleLoggedUsersExceptForSettings,
  updateRule: ruleLoggedUsersExceptForSettings,
  deleteRule: ruleLoggedUsersExceptForSettings,
);

final publicCollectionImport = CollectionModel(
  name: "public",
  type: "view",
  listRule: "",
  viewRule: "",
  createRule: null,
  updateRule: null,
  deleteRule: null,
  viewQuery:
      "SELECT\n    data.id,\n    imgs,\n    json_extract(data.data, '\$.patientID') AS pid,\n    json_extract(data.data, '\$.date') AS date,\n    json_extract(data.data, '\$.prescriptions') AS prescriptions,\n    json_extract(data.data, '\$.price') AS price,\n    json_extract(data.data, '\$.paid') AS paid\nFROM data\nWHERE data.store = 'appointments';",
);

final profilesViewCollectionImport = CollectionModel(
  name: profilesViewCollectionName,
  type: "view",
  listRule: "",
  viewRule: "",
  createRule: null,
  updateRule: null,
  deleteRule: null,
  viewQuery:
      "SELECT \n    `final_id` as `id`, \n    `final_email` as `email`, \n    `final_name` as `name`,\n     `final_operate` as `operate`,\n    `final_permissions` as `permissions`,\n    `final_type` as `type`\nFROM (\n    SELECT \n        u.id as `final_id`,\n        \"user\" as `final_type`,\n        p.operate as `final_operate`,\n        u.email as `final_email`, \n        p.permissions as `final_permissions`,\n        COALESCE(p.name, u.name) as `final_name`\n    FROM `users` u\n    LEFT JOIN `profiles` p ON p.account_id = u.id\n\n    UNION ALL\n\n    SELECT \n        s.id as `final_id`,\n        \"admin\" as `final_type`,\n        p.operate as `final_operate`,\n        s.email as `final_email`, \n        '[2, 2, 2, 2, 2, 1, 1]' as `final_permissions`,\n        COALESCE(p.name, 'System Admin') as `final_name`\n    FROM `_superusers` s\n    LEFT JOIN `profiles` p ON p.account_id = s.id\n)",
);

final profilesCollectionImport = CollectionModel(
  name: profilesCollectionName,
  type: "base",
  listRule: "",
  viewRule: "",
  createRule: null,
  updateRule: null,
  deleteRule: null,
  fields: [
    CollectionField({
      "autogeneratePattern": "[a-z0-9]{15}",
      "hidden": false,
      "id": "text3208210256",
      "max": 15,
      "min": 15,
      "name": "id",
      "pattern": "^[a-z0-9]+\$",
      "presentable": false,
      "primaryKey": true,
      "required": true,
      "system": true,
      "type": "text"
    }),
    CollectionField({
      "autogeneratePattern": "",
      "hidden": false,
      "id": "text2607505338",
      "max": 0,
      "min": 0,
      "name": "account_id",
      "pattern": "",
      "presentable": false,
      "primaryKey": false,
      "required": true,
      "system": false,
      "type": "text"
    }),
    CollectionField({
      "autogeneratePattern": "",
      "hidden": false,
      "id": "text1579384326",
      "max": 0,
      "min": 0,
      "name": "name",
      "pattern": "",
      "presentable": false,
      "primaryKey": false,
      "required": false,
      "system": false,
      "type": "text"
    }),
    CollectionField({
      "autogeneratePattern": "",
      "hidden": false,
      "id": "text770559087",
      "max": 0,
      "min": 0,
      "name": "permissions",
      "pattern": "",
      "presentable": false,
      "primaryKey": false,
      "required": false,
      "system": false,
      "type": "text"
    }),
    CollectionField({
      "hidden": false,
      "id": "bool1154152107",
      "name": "operate",
      "presentable": false,
      "required": false,
      "system": false,
      "type": "bool"
    }),
    CollectionField({
      "hidden": false,
      "id": "autodate2990389176",
      "name": "created",
      "onCreate": true,
      "onUpdate": false,
      "presentable": false,
      "system": false,
      "type": "autodate"
    }),
    CollectionField({
      "hidden": false,
      "id": "autodate3332085495",
      "name": "updated",
      "onCreate": true,
      "onUpdate": true,
      "presentable": false,
      "system": false,
      "type": "autodate"
    })
  ],
);

const ruleLoggedUsersExceptForSettings =
    "@request.auth.id != \"\" && store != \"settings_global\"";
const ruleEitherLoggedOrSettings =
    "@request.auth.id != \"\" || store = \"settings_global\"";
