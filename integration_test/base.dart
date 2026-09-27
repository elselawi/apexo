import 'dart:io';
import 'package:apexo/utils/logger.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, List<String>> passedTests = {};

enum WhichTests {
  all, // run all tests including skipped (--) tests
  onlyRequired, // run only important tests (++)
  regular, // run regular and important tests (++)
}

abstract class IntegrationTestBase {
  IntegrationTestBase({required this.tester});
  String get name;
  Map<String, Future<Null> Function()> get tests;
  final WidgetTester tester;

  Future<void> run([WhichTests level = WhichTests.regular]) async {
    final modeFile = (await File("./integration_test/mode").readAsString());
    late WhichTests whichTests;

    // mode has been defined for all groups
    if (modeFile == "--onlyRequired") {
      whichTests = WhichTests.onlyRequired;
    } else if (modeFile == "--all") {
      whichTests = WhichTests.all;
    } else if (modeFile == "--regular") {
      whichTests = WhichTests.regular;
    }
    // a specific group is being run all tests
    else if (modeFile == name) {
      whichTests = WhichTests.all;
    } else {
      whichTests = WhichTests.onlyRequired;
    }

    List<String> sortedTests = tests.keys.toList()
      ..sort((a, b) => a.compareTo(b));
    if (whichTests == WhichTests.onlyRequired) {
      sortedTests = sortedTests.where((t) => t.endsWith("++")).toList();
    }
    if (whichTests == WhichTests.regular) {
      sortedTests = sortedTests.where((t) => !t.endsWith("--")).toList();
    }
    logger(
        "⭐ Starting test group: $name, in $whichTests mode, will run ${sortedTests.length} out of ${tests.keys.length}",
        null,
        3);
    for (var testName in sortedTests) {
      logger("🧪 Running test: $testName", null, 2);
      await tests[testName]!();
      logger("\x1B[32m👌 Test $testName passed\x1B[0m", null, 3);
      // register the test as passed
      if (passedTests[name] == null) {
        passedTests[name] = [];
      }
      passedTests[name]!.add(testName);
    }
  }
}
