@Tags(['serial'])
library;

import 'package:apexo/app/optional_features.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/notes/notes_model.dart';
import 'package:apexo/features/notes/notes_store.dart';
import 'package:apexo/features/settings/settings_stores.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/model_factory.dart';

/// Notes and expenses became optional features: the whole point is that an
/// upgrade never hides records a clinic already has, so that rule is pinned
/// here — explicit choice, then existing data, then off.
void main() {
  late String previousNotesChoice;
  late String previousExpensesChoice;
  late List<Note> previousNotes;
  late List<Expense> previousExpenses;

  setUp(() {
    previousNotesChoice = globalSettings.notesFeatureChoice;
    previousExpensesChoice = globalSettings.expensesFeatureChoice;
    previousNotes = notes.docs.values.toList();
    previousExpenses = expenses.docs.values.toList();
    notes.observableMap.clear();
    expenses.observableMap.clear();
  });

  tearDown(() {
    globalSettings.notesFeatureChoice = previousNotesChoice;
    globalSettings.expensesFeatureChoice = previousExpensesChoice;
    notes.observableMap.clear();
    notes.setAll(previousNotes);
    expenses.observableMap.clear();
    expenses.setAll(previousExpenses);
  });

  test('a feature nobody chose is off while it holds nothing', () {
    expect(globalSettings.notesFeatureChoice, '');
    expect(notesFeatureEnabled, isFalse);
    expect(expensesFeatureEnabled, isFalse);
  });

  test('existing records keep a feature visible without a setting', () {
    notes.set(testNote(id: 'n1'));
    expenses.set(testExpense(id: 'e1'));

    expect(globalSettings.notesFeatureChoice, isEmpty);
    expect(notesFeatureEnabled, isTrue);
    expect(expensesFeatureEnabled, isTrue);
  });

  test('archived records count as existing records', () {
    notes.set(testNote(id: 'n1', archived: true));

    expect(notesFeatureEnabled, isTrue);
  });

  test('an explicit choice wins over existing records', () {
    notes.set(testNote(id: 'n1'));
    expenses.set(testExpense(id: 'e1'));
    globalSettings.notesFeatureChoice = '0';
    globalSettings.expensesFeatureChoice = '0';

    expect(notesFeatureEnabled, isFalse);
    expect(expensesFeatureEnabled, isFalse);
  });

  test('an explicit on shows a feature that holds nothing yet', () {
    globalSettings.notesFeatureChoice = '1';
    globalSettings.expensesFeatureChoice = '1';

    expect(notesFeatureEnabled, isTrue);
    expect(expensesFeatureEnabled, isTrue);
  });
}
