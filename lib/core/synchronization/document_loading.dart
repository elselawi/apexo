import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../model.dart';

typedef ModellingFunc<G> = G Function(Map<String, dynamic> input);
typedef DocumentLoader<G extends Model> = Future<List<Map<String, G>>> Function(
  ModellingFunc<G> modeling,
  Map<String, Map<String, dynamic>> decoded,
);

Map<String, Map<String, dynamic>> decodeStoreDocuments(Map<String, String> encoded) {
  return Map.fromEntries(encoded.entries.map((entry) => MapEntry(
    entry.key, jsonDecode(entry.value) as Map<String, dynamic>,
  )));
}

class DocumentBatch<G extends Model> {
  const DocumentBatch(this.modeling, this.decoded);
  final ModellingFunc<G> modeling;
  final Map<String, Map<String, dynamic>> decoded;
}

Future<List<Map<String, G>>> loadStoreDocuments<G extends Model>(
  ModellingFunc<G> modeling,
  Map<String, Map<String, dynamic>> decoded,
) => compute(modelStoreDocuments<G>, DocumentBatch(modeling, decoded));

List<Map<String, G>> modelStoreDocuments<G extends Model>(DocumentBatch<G> batch) {
  final archived = <String, G>{};
  final mapped = Map<String, G>.fromEntries(batch.decoded.entries.map((entry) {
    final modeled = batch.modeling(entry.value);
    if (modeled.archived == true) archived[modeled.id] = modeled;
    return MapEntry(entry.key, modeled);
  }));
  return [mapped, archived];
}
