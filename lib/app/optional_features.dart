import 'dart:async';

import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';

/// Optional features are hidden from the shell — not deleted — while they are
/// off. An explicit on/off choice in settings always wins; until a clinic makes
/// one, a feature stays visible as soon as it already holds data, so upgrading
/// never hides records someone created before the feature became optional.
bool get notesFeatureEnabled => _resolve(
    globalSettings.notesFeatureChoice, notes.observableMap.docs.isNotEmpty);

bool get expensesFeatureEnabled => _resolve(
    globalSettings.expensesFeatureChoice,
    expenses.observableMap.docs.isNotEmpty);

bool _resolve(String choice, bool hasData) => switch (choice) {
      "1" => true,
      "0" => false,
      _ => hasData,
    };

/// What can change a feature's availability: the choice itself and the moment a
/// store stops or starts being empty. Watched by the shell so turning a feature
/// on or off shows (or hides) it without a restart.
List<Stream<dynamic>> get optionalFeatureStreams => [
      globalSettings.observableMap.stream,
      notes.hasContent.stream,
      expenses.hasContent.stream,
    ];
