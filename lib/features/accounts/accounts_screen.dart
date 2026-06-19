import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/no_items_found.dart';
import 'package:apexo/common_widgets/screen_command_bar.dart';
import 'package:apexo/common_widgets/transitions/rotate.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/features/accounts/open_account_panel.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:pocketbase/pocketbase.dart';

const zeroPermissions = [0, 0, 0, 0, 0, 0, 0, 0];
const fullPermissions = [2, 2, 2, 2, 2, 1, 1, 1];

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
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            spacing: 20,
                            children: [
                              _buildRefreshButton(),
                              Txt(txt("${txt("admins")}: ${admins.length}")),
                              Txt(txt("${txt("users")}: ${users.length}")),
                            ],
                          ),
                        ],
                      ),
                    ),
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
                            return ListTile(
                              contentPadding: const EdgeInsets.all(10),
                              margin: EdgeInsets.zero,
                              shape: listDividerBorder(context),
                              tileColor: WidgetStatePropertyAll(
                                FluentTheme.of(context)
                                    .resources
                                    .solidBackgroundFillColorBase,
                              ),
                              leading: Icon(
                                  account.getStringValue("type") == "admin"
                                      ? FluentIcons.contact_lock
                                      : FluentIcons.contact),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 5, horizontal: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color:
                                      account.getStringValue("type") == "admin"
                                          ? Colors.red.withValues(alpha: 0.3)
                                          : Colors.teal.withValues(alpha: 0.3),
                                ),
                                child:
                                    (account.getStringValue("type") == "admin")
                                        ? Txt(txt("admin"))
                                        : Txt(txt("user")),
                              ),
                              title: Txt(
                                  filteredList[index].getStringValue("name")),
                              subtitle: Txt(
                                  filteredList[index].getStringValue("email")),
                              onPressed: () {
                                openAccount(accountFromJson(account.toJson()
                                  ..addAll({
                                    "name": account.getStringValue("name"),
                                    "email": account.getStringValue("email"),
                                    "permissions":
                                        account.getStringValue("permissions"),
                                    "operate": account.getIntValue("operate"),
                                    "type": account.getStringValue("type"),
                                    "id": account.id,
                                  })));
                              },
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
        icon: ButtonContent(FluentIcons.add_friend, txt("newUser")),
        onPressed: () {
          openAccount(accountFromJson({"type": "user"}));
        },
      ),
      otherButtons: [
        IconButton(
          icon: ButtonContent(FluentIcons.contact_lock, txt("newAdmin")),
          onPressed: () {
            openAccount(accountFromJson({"type": "admin"}));
          },
        ),
      ],
    );
  }
}
