import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/common_widgets/dialogs/close_dialog_button.dart';
import 'package:apexo/common_widgets/dialogs/dialog_styling.dart';
import 'package:apexo/common_widgets/transitions/rotate.dart';
import 'package:apexo/core/multi_stream_builder.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';
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

  TextEditingController nameController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  bool operate = false;
  List<int> permissions = zeroPermissions;

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      resizeToAvoidBottomInset: true,
      padding: EdgeInsets.zero,
      content: MStreamBuilder(
          streams: [
            accounts.list.stream,
            accounts.loaded.stream,
            accounts.loading.stream,
            accounts.creating.stream,
            accounts.errorMessage.stream,
            accounts.updating.stream,
            accounts.deleting.stream,
          ],
          builder: (context, snapshot) {
            return Column(
              children: [
                _buildCommandBar(context),
                _buildAccountsList(
                    context,
                    true,
                    accounts
                        .list()
                        .where((e) => e.getStringValue("type") == "admin")
                        .toList()),
                _buildAccountsList(
                    context,
                    false,
                    accounts
                        .list()
                        .where((e) => e.getStringValue("type") != "admin")
                        .toList()),
                if (accounts.errorMessage().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: InfoBar(
                      title: Text(accounts.errorMessage()),
                      severity: InfoBarSeverity.error,
                    ),
                  ),
              ],
            );
          }),
    );
  }

  Widget _buildAccountsList(
      BuildContext context, bool isAdmin, List<RecordModel> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Txt(
            "${isAdmin ? txt("admins") : txt("users")}:",
            style: FluentTheme.of(context).typography.bodyStrong,
          ),
        ),
        SizedBox(
          width: MediaQuery.of(context).size.width,
          height: 160,
          child: ListView(
            primary: true,
            scrollDirection: Axis.horizontal,
            children: List.generate(list.length, (index) {
              return _buildAccountCard(context, isAdmin, list[index]);
            }),
          ),
        ),
      ],
    );
  }

  Container _buildAccountCard(
    BuildContext context,
    bool isAdmin,
    RecordModel account,
  ) {
    bool isCurrent = login.email == account.getStringValue("email");
    final deletingLists = accounts.deleting().keys;
    final updaingLists = accounts.updating().keys;

    return Container(
      key: Key(account.id),
      width: 290,
      decoration: BoxDecoration(
          color: FluentTheme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
              offset: const Offset(0.0, 0.0),
              blurRadius: 20.0,
              spreadRadius: 2.0,
              color: Colors.grey.withAlpha(50),
            ),
          ],
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: deletingLists.contains(account.id)
                  ? Colors.errorPrimaryColor
                  : updaingLists.contains(account.id)
                      ? Colors.blue
                      : Colors.transparent)),
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isAdmin
                            ? FluentIcons.contact_lock
                            : FluentIcons.contact,
                        size: 30,
                        color: FluentTheme.of(context)
                            .inactiveColor
                            .withAlpha(180),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.getStringValue("name"),
                            style:
                                FluentTheme.of(context).typography.bodyStrong,
                          ),
                          Txt(
                            isAdmin ? txt("modeAdmin") : txt("modeUser"),
                            style: FluentTheme.of(context).typography.caption,
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (isCurrent)
                    Txt(
                      txt("you"),
                      style: FluentTheme.of(context)
                          .typography
                          .bodyStrong
                          ?.copyWith(color: Colors.errorPrimaryColor),
                    )
                ],
              ),
              const SizedBox(height: 10),
              const Divider(),
              const SizedBox(height: 10),
              SizedBox(
                width: 255,
                child: Text(account.data["email"],
                    overflow: TextOverflow.ellipsis),
              )
            ],
          ),
          Row(
            children: [
              Button(
                child: ButtonContent(
                  FluentIcons.edit_contact,
                  txt("edit"),
                ),
                onPressed: () {
                  showDialog(
                      context: context,
                      barrierDismissible: true,
                      dismissWithEsc: true,
                      builder: (ctx) {
                        return dialog(isAdmin: isAdmin, account: account);
                      });
                },
              ),
              const SizedBox(width: 10),
              if (!isCurrent)
                _DeleteAccountButton(isAdmin: isAdmin, account: account)
            ],
          )
        ],
      ),
    );
  }

  Widget _buildCommandBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            offset: const Offset(0.0, 6.0),
            blurRadius: 30.0,
            spreadRadius: 5.0,
            color: Colors.grey.withAlpha(50),
          )
        ],
        color: FluentTheme.of(context).menuColor,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: ButtonContent(FluentIcons.add_friend, txt("newUser")),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (contest) {
                      return dialog(isAdmin: false);
                    },
                  );
                },
              ),
              const SizedBox(width: 5),
              IconButton(
                icon: ButtonContent(FluentIcons.contact_lock, txt("newAdmin")),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (contest) {
                      return dialog(isAdmin: true);
                    },
                  );
                },
              ),
            ],
          ),
          IconButton(
            style: inProgress
                ? ButtonStyle(
                    backgroundColor:
                        WidgetStatePropertyAll(Colors.grey.withAlpha(30)))
                : null,
            icon: Row(
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
          ),
        ],
      ),
    );
  }

  ContentDialog dialog({required bool isAdmin, RecordModel? account}) {
    final bool editing = account != null;
    final String title =
        "${editing ? "edit" : "new"}${isAdmin ? "Admin" : "User"}";

    if (editing) {
      emailController.text = account.getStringValue("email");
      nameController.text = account.getStringValue("name");
      operate = account.getIntValue("operate") == 1;
      passwordController.text = "";
      permissions =
          accounts.parsePermissions(account.getStringValue("permissions"));
    } else {
      emailController.text = "";
      nameController.text = "";
      operate = false;
      passwordController.text = "";
      permissions = [...zeroPermissions];
    }

    return ContentDialog(
      title: Column(
        children: [
          Row(
            children: [
              Icon(editing ? FluentIcons.edit_contact : FluentIcons.add_friend),
              const SizedBox(width: 10),
              Txt((txt(title)))
            ],
          ),
          const SizedBox(height: 5),
          const Divider(),
          const SizedBox(height: 5),
        ],
      ),
      style: dialogStyling(context, false),
      content: SizedBox(
        height: MediaQuery.of(context).size.height,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OperatesToggle(
                initial: operate,
                onChanged: (selected) => operate = selected,
              ),
              const SizedBox(height: 15),
              InfoLabel(
                label: txt("name"),
                child: CupertinoTextField(
                    controller: nameController, placeholder: txt("name")),
              ),
              const SizedBox(height: 5),
              InfoLabel(
                label: txt("email"),
                child: CupertinoTextField(
                    controller: emailController,
                    placeholder: txt("validEmailMustBeProvided")),
              ),
              const SizedBox(height: 5),
              InfoLabel(
                label: txt("password"),
                child: CupertinoTextField(
                  controller: passwordController,
                  obscureText: true,
                  placeholder: txt("minimumPasswordLength"),
                ),
              ),
              if (editing) ...[
                const SizedBox(height: 5),
                InfoBar(
                    title: Txt(txt("updatingPassword")),
                    content: Txt(txt("leaveItEmpty"))),
              ],
              if (isAdmin == false)
                Builder(builder: (context) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 20),
                      Txt(
                        txt("permissions"),
                        style: FluentTheme.of(context)
                            .typography
                            .bodyStrong
                            ?.copyWith(fontSize: 16),
                      ),
                      const SizedBox(height: 10),
                      PermissionSelector(
                        title: txt("patients"),
                        initialSelected: permissions[PInt.patients],
                        levels: [
                          PermissionLevel(value: 0, label: txt("restricted")),
                          PermissionLevel(value: 1, label: txt("personal")),
                          PermissionLevel(value: 2, label: txt("full"))
                        ],
                        onChanged: (level) =>
                            permissions[PInt.patients] = level,
                      ),
                      PermissionSelector(
                        title: txt("appointments"),
                        initialSelected: permissions[PInt.appointments],
                        levels: [
                          PermissionLevel(value: 0, label: txt("restricted")),
                          PermissionLevel(value: 1, label: txt("personal")),
                          PermissionLevel(value: 2, label: txt("full"))
                        ],
                        onChanged: (level) =>
                            permissions[PInt.appointments] = level,
                      ),
                      PermissionSelector(
                        title: txt("post-opNotes"),
                        initialSelected: permissions[PInt.postOp],
                        levels: [
                          PermissionLevel(value: 0, label: txt("restricted")),
                          PermissionLevel(value: 1, label: txt("personal")),
                          PermissionLevel(value: 2, label: txt("full"))
                        ],
                        onChanged: (level) => permissions[PInt.postOp] = level,
                      ),
                      PermissionSelector(
                        title: txt("insights"),
                        initialSelected: permissions[PInt.stats],
                        levels: [
                          PermissionLevel(value: 0, label: txt("restricted")),
                          PermissionLevel(value: 1, label: txt("personal")),
                          PermissionLevel(value: 2, label: txt("full"))
                        ],
                        onChanged: (level) => permissions[PInt.stats] = level,
                      ),
                      PermissionSelector(
                        title: txt("expenses"),
                        initialSelected: permissions[PInt.expenses],
                        levels: [
                          PermissionLevel(value: 0, label: txt("restricted")),
                          PermissionLevel(value: 1, label: txt("view")),
                          PermissionLevel(value: 2, label: txt("full"))
                        ],
                        onChanged: (level) =>
                            permissions[PInt.expenses] = level,
                      ),
                      PermissionSelector(
                        title: txt("notes"),
                        initialSelected: permissions[PInt.notes],
                        levels: [
                          PermissionLevel(value: 0, label: txt("personal")),
                          PermissionLevel(value: 1, label: txt("all")),
                        ],
                        onChanged: (level) => permissions[PInt.notes] = level,
                      ),
                      PermissionSelector(
                        title: txt("settings"),
                        initialSelected: permissions[PInt.setting],
                        levels: [
                          PermissionLevel(value: 0, label: txt("local")),
                        ],
                        onChanged: (level) => permissions[PInt.setting] = level,
                      ),
                      PermissionSelector(
                        title: txt("photos"),
                        initialSelected: permissions[PInt.photos],
                        levels: [
                          PermissionLevel(value: 0, label: txt("cantUpload")),
                          PermissionLevel(value: 1, label: txt("canUpload")),
                        ],
                        onChanged: (level) => permissions[PInt.photos] = level,
                      ),
                      const SizedBox(height: 25)
                    ],
                  );
                })
            ],
          ),
        ),
      ),
      actions: [
        const CloseButtonInDialog(),
        FilledButton(
          style:
              ButtonStyle(backgroundColor: WidgetStatePropertyAll(Colors.blue)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(FluentIcons.save),
            const SizedBox(width: 5),
            Txt(txt("save"))
          ]),
          onPressed: () async {
            Navigator.pop(context);
            if (editing) {
              accounts.update(
                id: account.id,
                isAdmin: isAdmin,
                email: emailController.text,
                password: passwordController.text,
                name: nameController.text,
                permissions: permissions,
                operates: operate,
              );
            } else {
              accounts.newAccount(
                isAdmin: isAdmin,
                email: emailController.text,
                password: passwordController.text,
                name: nameController.text,
                permissions: permissions,
                operates: operate,
              );
            }
          },
        ),
      ],
    );
  }
}

class _OperatesToggle extends StatefulWidget {
  const _OperatesToggle({
    required this.onChanged,
    required this.initial,
  });

  final bool initial;
  final void Function(bool selected) onChanged;

  @override
  State<_OperatesToggle> createState() => _OperatesToggleState();
}

class _OperatesToggleState extends State<_OperatesToggle> {
  late bool checked;

  @override
  void initState() {
    checked = widget.initial;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      checked: checked,
      onChanged: (state) {
        setState(() {
          checked = state ?? false;
          widget.onChanged(state ?? false);
        });
      },
      content: Txt(txt("operatesOnPatients")),
    );
  }
}

class PermissionLevel {
  const PermissionLevel({required this.value, required this.label});
  final int value;
  final String label;
}

class PermissionSelector extends StatefulWidget {
  const PermissionSelector(
      {super.key,
      required this.title,
      required this.levels,
      required this.initialSelected,
      required this.onChanged});

  final String title;
  final List<PermissionLevel> levels;
  final int initialSelected;
  final void Function(int selected) onChanged;

  @override
  State<PermissionSelector> createState() => _PermissionSelectorState();
}

class _PermissionSelectorState extends State<PermissionSelector> {
  late int selected;

  @override
  void initState() {
    selected = widget.initialSelected;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Txt(widget.title,
              style: FluentTheme.of(context).typography.bodyStrong),
          Row(
            children: [
              const SizedBox(width: 10),
              ...widget.levels.map((l) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ToggleButton(
                        checked: l.value == selected,
                        child: Txt(l.label),
                        onChanged: (checked) {
                          if (checked == true) {
                            setState(() {
                              selected = l.value;
                              widget.onChanged(l.value);
                            });
                          }
                        }),
                  ))
            ],
          ),
        ],
      ),
    );
  }
}

class _DeleteAccountButton extends StatelessWidget {
  _DeleteAccountButton({
    required this.isAdmin,
    required this.account,
  });

  final bool isAdmin;
  final RecordModel account;
  final FlyoutController confrimationFlyoutController = FlyoutController();

  @override
  Widget build(BuildContext context) {
    return FlyoutTarget(
      controller: confrimationFlyoutController,
      child: FilledButton(
        style: filledButtonStyle(Colors.grey.withAlpha(255)),
        child: ButtonContent(
          FluentIcons.delete,
          txt("delete"),
        ),
        onPressed: () {
          confrimationFlyoutController.showFlyout(builder: (ctx) {
            return ConfirmDeleteFlyout(
              onConfirm: () {
                accounts.delete(isAdmin: isAdmin, id: account.id);
              },
              controller: confrimationFlyoutController,
            );
          });
        },
      ),
    );
  }
}
