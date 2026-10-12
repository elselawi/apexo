import 'dart:async';

import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/widget_keys.dart';
import 'package:apexo/common_widgets/context_menu_region.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/common_widgets/transitions/rotate.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/accounts/open_account_panel.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:pocketbase/pocketbase.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool get inProgress {
    return accounts.creating() ||
        accounts.deleting().isNotEmpty ||
        accounts.loading() ||
        accounts.updating().isNotEmpty;
  }

  final _searchController = TextEditingController();

  List<RecordModel> get admins {
    return accounts
        .list()
        .where((e) => e.getStringValue("type") == "admin")
        .toList();
  }

  List<RecordModel> get users {
    return accounts
        .list()
        .where((e) => e.getStringValue("type") != "admin")
        .toList();
  }

  List<RecordModel> get filteredList {
    final term = _searchController.text.toLowerCase();
    return [...admins, ...users]
        .where(
          (e) =>
              e.getStringValue("name").toLowerCase().contains(term) ||
              e.getStringValue("email").toLowerCase().contains(term),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MStreamBuilder(
        streams: [
          accounts.list.stream,
          accounts.loaded.stream,
          accounts.loading.stream,
          accounts.creating.stream,
          accounts.updating.stream,
          accounts.deleting.stream,
        ],
        builder: (context, snapshot) {
          return Column(
            children: [
              _buildCommandBar(context),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [_buildSearch()],
                ),
              ),
              Container(
                decoration: topBarDecoration(context, Colors.grey),
                padding: const EdgeInsets.all(8),
                child: Row(
                  spacing: 10,
                  //crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildRefreshButton(),
                    Txt(txt("${txt("admins")}: ${admins.length}")),
                    Txt(txt("${txt("users")}: ${users.length}")),
                  ],
                ),
              ),
              Expanded(
                  child: filteredList.isEmpty
                      ? const NoItemsFound()
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemExtent: 95,
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final account = filteredList[index];
                            final isAdmin =
                                account.getStringValue("type") == "admin";
                            final name = account.getStringValue("name");
                            final email = account.getStringValue("email");
                            void open() {
                              unawaited(
                                  openAccount(accountFromJson(account.toJson()
                                    ..addAll({
                                      "name": name,
                                      "email": email,
                                      "permissions":
                                          account.getStringValue("permissions"),
                                      "operate": account.getIntValue("operate"),
                                      "type": account.getStringValue("type"),
                                      "id": account.id,
                                    }))));
                            }

                            return ContextMenuRegion(
                              items: (context, controller) => [
                                MenuFlyoutItem(
                                  text: Txt(txt("open")),
                                  leading: const Icon(
                                      WindowsIcons.open_in_new_window),
                                  onPressed: open,
                                ),
                                // Deleting yourself would sign you out mid-air.
                                if (login.currentAccountID != account.id)
                                  MenuFlyoutItem(
                                    text: Txt(txt("delete")),
                                    leading: const Icon(WindowsIcons.delete),
                                    onPressed: () {
                                      controller.close<void>();
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) async {
                                        await flyoutFocusFix(context);
                                        unawaited(controller.showFlyout(
                                            builder: (ctx) =>
                                                ConfirmDeleteFlyout(
                                                  restorable: false,
                                                  controller: controller,
                                                  actionIcon:
                                                      WindowsIcons.delete,
                                                  actionText: txt("delete"),
                                                  preview: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    spacing: 5,
                                                    children: [
                                                      const Icon(
                                                          FluentIcons.people),
                                                      Txt(name)
                                                    ],
                                                  ),
                                                  onConfirm: () {
                                                    unawaited(accounts.delete(
                                                        isAdmin: isAdmin,
                                                        id: account.id));
                                                  },
                                                )));
                                      });
                                    },
                                  ),
                              ],
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(10),
                                margin: EdgeInsets.zero,
                                shape: listDividerBorder(context),
                                tileColor: WidgetStatePropertyAll(
                                  FluentTheme.of(context)
                                      .resources
                                      .solidBackgroundFillColorBase,
                                ),
                                leading: Icon(isAdmin
                                    ? FluentIcons.contact_lock
                                    : FluentIcons.contact),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 5, horizontal: 10),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: isAdmin
                                        ? Colors.red.withValues(alpha: 0.3)
                                        : Colors.teal.withValues(alpha: 0.3),
                                  ),
                                  child: isAdmin
                                      ? Txt(txt("admin"))
                                      : Txt(txt("user")),
                                ),
                                title: Txt(name),
                                subtitle: Txt(email),
                                onPressed: open,
                              ),
                            );
                          },
                        )),
            ],
          );
        });
  }

  Widget _buildRefreshButton() {
    return Button(
      style: inProgress
          ? ButtonStyle(
              backgroundColor:
                  WidgetStatePropertyAll(Colors.grey.withAlpha(30)))
          : null,
      child: Row(
        // A `Row` defaults to `mainAxisSize.max`, and a `Row` hands a non-flex
        // child **unbounded** width — so this one claimed whatever the command
        // bar had and reported `A RenderFlex overflowed by 16 pixels on the
        // right` at a 1280px window (and 5.3px from the counts row it sat in).
        mainAxisSize: MainAxisSize.min,
        children: [
          RotatingWrapper(
            rotate: inProgress,
            child: const Icon(FluentIcons.sync),
          ),
          const SizedBox(width: 5),
          Txt(txt("refresh"))
        ],
      ),
      onPressed: () async {
        try {
          await accounts.reloadFromRemote();
          // ignore: empty_catches
        } catch (e) {}
      },
    );
  }

  Expanded _buildSearch() {
    return Expanded(
      child: TopSearch(controller: _searchController, setState: setState),
    );
  }

  Widget _buildCommandBar(BuildContext context) {
    return ScreenCommandBar(
      mainButton: IconButton(
        key: WK.btnNewAccount,
        icon: ButtonContent(FluentIcons.add_friend, txt("newUser")),
        onPressed: () {
          unawaited(openAccount(accountFromJson({"type": "user"})));
        },
      ),
      otherButtons: [
        IconButton(
          key: WK.btnNewAdmin,
          icon: ButtonContent(FluentIcons.contact_lock, txt("newAdmin")),
          onPressed: () {
            unawaited(openAccount(accountFromJson({"type": "admin"})));
          },
        ),
      ],
    );
  }
}
