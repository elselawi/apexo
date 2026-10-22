@Tags(['serial'])
library;

import 'dart:async';

import 'package:apexo/ui/workspace/panel_screen.dart';
import 'package:apexo/ui/workspace/panels_manager.dart';
import 'package:apexo/ui/workspace/windows_layer.dart';
import 'package:apexo/ui/workspace/windows_manager.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/money_display.dart';
import 'package:apexo/features/expenses/expense_model.dart';
import 'package:apexo/features/expenses/expense_summary.dart';
import 'package:apexo/features/expenses/expenses_screen.dart';
import 'package:apexo/features/expenses/expenses_store.dart';
import 'package:apexo/features/expenses/open_expense_panel.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/services/perm.dart';
import 'package:apexo/widget_keys.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/model_factory.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/window_defaults.dart';

/// The orders panel: the supplier's figures are the panel, their orders are the
/// windows beside it, and a row that names one window gets that window alone.
void main() {
  late List<Expense> previous;
  late List<int> previousPermissions;

  setUp(() async {
    previous = expenses.docs.values.toList();
    previousPermissions = login.savedPermissions;
    expenses.observableMap.clear();
    login.savedPermissions = Perm.full;
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    await resetWindowDefaults();
  });

  tearDown(() async {
    PanelsManager.closeAll();
    WindowsManager.closeAll();
    expenses.observableMap.clear();
    expenses.setAll(previous);
    login.savedPermissions = previousPermissions;
    // The windows a panel was left with are a device preference: they are put
    // back as they were, so the next test starts from the user's own.
    await resetWindowDefaults();
  });

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A supplier with two orders: one half paid, one settled.
  List<Expense> supplierOrders(String supplierId) {
    expenses.set(testExpense(
      id: supplierId,
      isSupplier: true,
      supplierName: 'Acme Supplies',
    ));
    final due = testExpense(
      id: '$supplierId-due',
      supplierId: supplierId,
      cost: 200,
      paidAmount: 50,
    );
    final paid = testExpense(
      id: '$supplierId-paid',
      supplierId: supplierId,
      cost: 100,
      paidAmount: 100,
      processed: true,
    );
    expenses.set(due);
    expenses.set(paid);
    return [due, paid];
  }

  Future<void> pumpLayer(WidgetTester tester, double width) async {
    await pumpApexoApp(
      tester,
      Stack(
        children: [WindowsLayer(visible: true, screenWidth: width)],
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The panel and the layer the shell stacks above it — where a panel's own
  /// body lives.
  Future<void> pumpShell(WidgetTester tester, double width) async {
    final panel = PanelsManager.active().last;
    PanelsManager.active([panel]);
    await pumpApexoApp(
      tester,
      Stack(
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: SizedBox(
              width: width < 490 ? width : 350,
              height: double.infinity,
              child: PanelScreen(panel: panel, layoutWidth: width),
            ),
          ),
          WindowsLayer(visible: true, screenWidth: width),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The text a widget shows, joined as it is drawn.
  String textUnder(WidgetTester tester, Finder finder) {
    final texts = tester.widgetList<Text>(
      find.descendant(of: finder, matching: find.byType(Text)),
    );
    return texts.map((text) => text.data ?? '').join();
  }

  /// The digits a tile shows, so a test can read a formatted amount.
  String textOf(WidgetTester tester, Key key) =>
      textUnder(tester, find.byKey(key));

  testWidgets('the supplier panel leads with the figures and can rename them',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = supplierOrders('supplier-a');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(orders, 'Acme Supplies', 'supplier-a'));
    await tester.pumpAndSettle();

    final panel = PanelsManager.active().last;
    expect(panel.primaryWindow?.id, expenseSummaryWindowId);
    expect(
      panel.windows.any((window) => window.id == ExpenseWindow.due.id),
      isTrue,
      reason: 'the unpaid orders are a window, not the panel',
    );

    await pumpShell(tester, 1600);
    expect(find.byType(ExpenseSummary), findsOneWidget);
    // 200 - 50 is owed on the first order; the second is settled in full.
    expect(textOf(tester, WK.expenseSummaryDue), contains('150'));
    expect(textOf(tester, WK.expenseSummaryPaid), contains('150'));

    await tester.tap(find.byKey(WK.editSupplierName));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).last, 'Acme Dental');
    await tester.tap(find.text(txt('save')).last);
    await tester.pumpAndSettle();

    expect(expenses.get('supplier-a')!.supplierName, 'Acme Dental');
    expect(
      expenses.get('supplier-a-due')!.supplierName,
      isEmpty,
      reason: 'the name belongs to the supplier record, not to every order',
    );
  });

  testWidgets('the whole clinic\'s orders lead with figures but no rename',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = [
      ...supplierOrders('supplier-c'),
      ...supplierOrders('supplier-d'),
    ];

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(orders, txt('viewAllOrders'), null));
    await tester.pumpAndSettle();
    await pumpShell(tester, 1600);

    expect(find.byType(ExpenseSummary), findsOneWidget);
    expect(
      find.byKey(WK.editSupplierName),
      findsNothing,
      reason: 'orders spanning suppliers have no one name to rename',
    );
  });

  testWidgets('a supplier with no orders at all can still be renamed',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    // A supplier with no orders is the common case for a new one: the rename
    // belongs to the supplier, not to the orders that happen to name it.
    expenses.set(testExpense(
      id: 'supplier-empty',
      isSupplier: true,
      supplierName: 'Acme Supplies',
    ));

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses([], 'Acme Supplies', 'supplier-empty'));
    await tester.pumpAndSettle();
    await pumpShell(tester, 1600);

    expect(find.byKey(WK.editSupplierName), findsOneWidget);
  });

  testWidgets('the header and the window follow a rename', (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = supplierOrders('supplier-renamed');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(orders, 'Acme Supplies', 'supplier-renamed'));
    await tester.pumpAndSettle();
    await pumpShell(tester, 1600);

    await tester.tap(find.byKey(WK.editSupplierName));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextBox).last, 'Acme Dental');
    await tester.tap(find.text(txt('save')).last);
    await tester.pumpAndSettle();

    // The name belongs to the supplier's own record, and everything that shows
    // it reads that record: the panel's header and the window's own line.
    expect(expenses.get('supplier-renamed')!.supplierName, 'Acme Dental');
    expect(
      find.text('Acme Dental'),
      findsWidgets,
      reason: 'the header follows the rename that happened inside the panel',
    );
  });

  testWidgets('the panel and the window beside it report the same totals',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = supplierOrders('supplier-totals');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(orders, 'Acme Supplies', 'supplier-totals'));
    await tester.pumpAndSettle();
    await pumpShell(tester, 1600);

    // The panel's figure and the window's own footer are the same orders,
    // counted the same way: the amount the panel shows is the amount the
    // window beside it shows.
    final dueWindow = find.byKey(const ValueKey('window-card-due'));
    expect(dueWindow, findsOneWidget);
    final footerRow = find
        .ancestor(
          of: find.descendant(
              of: dueWindow, matching: find.text(txt('totalDue'))),
          matching: find.byType(Row),
        )
        .first;
    final footerAmount = textUnder(
      tester,
      find.descendant(of: footerRow, matching: find.byType(MoneyDisplay)),
    );
    expect(
      textOf(tester, WK.expenseSummaryDue),
      endsWith(footerAmount),
      reason: 'the same orders must not be reported two different ways',
    );
  });

  testWidgets('a supplier row opens one window, not the supplier panel',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = supplierOrders('supplier-b');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(
      orders,
      'Acme Supplies',
      'supplier-b',
      null,
      ExpenseWindow.due,
    ));
    await tester.pumpAndSettle();

    expect(
      PanelsManager.active(),
      isEmpty,
      reason: 'asking for the unpaid orders does not unfold the supplier',
    );
    expect(WindowsManager.open(), hasLength(1));

    await pumpLayer(tester, 1600);
    expect(tester.takeException(), isNull);
    expect(find.byKey(WK.windowSave), findsOneWidget);
    expect(find.byKey(WK.windowClose), findsOneWidget);
  });

  testWidgets('a standalone orders window steps aside for its panel',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = supplierOrders('supplier-record');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(
      orders,
      'Acme Supplies',
      'supplier-record',
      null,
      ExpenseWindow.due,
    ));
    await tester.pumpAndSettle();
    expect(WindowsManager.open(), hasLength(1));

    await pumpLayer(tester, 1600);
    await tester.tap(find.byKey(WK.windowOpenRecord));
    await tester.pumpAndSettle();

    expect(PanelsManager.active(), hasLength(1));
    expect(
      WindowsManager.open(),
      isEmpty,
      reason: 'the panel holds these orders now; the window has nothing to show',
    );
  });

  testWidgets('asking for a window of an open supplier panel stays in it',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = supplierOrders('supplier-open');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(orders, 'Acme Supplies', 'supplier-open'));
    await tester.pumpAndSettle();
    expect(PanelsManager.active(), hasLength(1));

    // The row asks for the paid orders while the supplier is already unfolding.
    unawaited(openExpenses(
        orders, 'Acme Supplies', 'supplier-open', null, ExpenseWindow.paid));
    await tester.pumpAndSettle();

    expect(
      WindowsManager.open(),
      isEmpty,
      reason: 'the open panel is the window the caller asked for',
    );
    expect(PanelsManager.active(), hasLength(1));
  });

  testWidgets('an order added on the spot is not left as unsaved work',
      (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = supplierOrders('supplier-added');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(
        orders, 'Acme Supplies', 'supplier-added', null, ExpenseWindow.due));
    await tester.pumpAndSettle();
    final window = WindowsManager.open().single;
    expect(window.hasChanges!(), isFalse);

    await pumpLayer(tester, 1600);
    await tester.tap(find.byKey(WK.btnAddOrder));
    await tester.pumpAndSettle();

    expect(
      window.hasChanges!(),
      isFalse,
      reason: 'the order is written as it is added, so there is nothing to save',
    );
  });

  testWidgets('a dirty orders window makes the panel open dirty', (tester) async {
    setViewport(tester, const Size(1600, 1000));
    final orders = supplierOrders('supplier-carry');

    await pumpApexoApp(tester, const SizedBox.shrink());
    unawaited(openExpenses(
        orders, 'Acme Supplies', 'supplier-carry', null, ExpenseWindow.due));
    await tester.pumpAndSettle();
    final window = WindowsManager.open().single;

    // An edit made in the window, not yet written.
    orders.first.cost = 999;
    expect(window.hasChanges!(), isTrue);

    unawaited(openExpenses(orders, 'Acme Supplies', 'supplier-carry'));
    await tester.pumpAndSettle();

    expect(WindowsManager.open(), isEmpty,
        reason: 'the window moved into the panel');
    expect(
      PanelsManager.active().single.hasPendingEdits,
      isTrue,
      reason: 'the panel carries the edit, so its Save is the one write',
    );
  });

  testWidgets('a supplier row deletes from its context menu', (tester) async {
    setViewport(tester, const Size(1600, 1000));
    supplierOrders('supplier-menu');
    addTearDown(() => expenses.archived.clear());

    await pumpApexoApp(
      tester,
      SizedBox(
        width: 900,
        height: 200,
        child: SupplierListTile(
          supplier: expenses.get('supplier-menu')!,
          onOpen: (_) {},
        ),
      ),
    );

    await tester.longPress(find.text('Acme Supplies').first);
    await tester.pumpAndSettle();

    Finder suffix(Finder finder) => find.descendant(
          of: find.byType(MenuFlyout),
          matching: finder,
        );
    // Each item appends how many orders it opens: two in all, one due and one
    // paid, the same split the windows make.
    expect(suffix(find.text('(2)')), findsOneWidget);
    expect(suffix(find.text('(1)')), findsNWidgets(2));

    await tester.tap(find
        .descendant(
          of: find.byType(MenuFlyout),
          matching: find.text(txt("delete")),
        )
        .first);
    await tester.pumpAndSettle();

    // The menu steps aside for the confirmation, anchored where it was.
    expect(find.byType(MenuFlyout), findsNothing);
    expect(find.byType(ConfirmDeleteFlyout), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, txt("delete")).first);
    await tester.pumpAndSettle();

    expect(expenses.archived.containsKey('supplier-menu'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
