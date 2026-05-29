import 'dart:convert';
import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/confirm_delete_flyout.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/services/launch.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

accountFromJson(Map<String, dynamic> json) {
  return AccountModel.fromJson(json);
}

class AccountModel extends Model {
  String email = "";
  String password = "";
  String name = "";
  List<int> permissions = [0, 0, 0, 0, 0, 0, 0, 0];
  bool operates = false;
  bool isAdmin = false;

  AccountModel.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    email = json["email"] ?? email;
    password = json["password"] ?? password;
    name = json["name"] ?? name;
    if (json["permissions"] != null) {
      if (json["permissions"] is String) {
        permissions = List<int>.from(jsonDecode(json["permissions"]));
      } else {
        permissions = List<int>.from(json["permissions"]);
      }
    }
    if (permissions.length < 12) {
      permissions = [
        ...permissions,
        ...List.filled(12 - permissions.length, 0)
      ];
    }
    operates = json["operate"] == 1 ||
        json["operate"] == true ||
        json["operates"] == true;
    isAdmin = json["type"] == "admin" || json["isAdmin"] == true;
    title = name.isNotEmpty ? name : email;
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json["email"] = email;
    json["password"] = password;
    json["name"] = name;
    json["permissions"] = permissions;
    json["operate"] = operates ? 1 : 0;
    json["type"] = isAdmin ? "admin" : "user";
    return json;
  }
}

class _AccountStore extends Store<AccountModel> {
  _AccountStore()
      : super(
          modeling: (json) => AccountModel.fromJson(json),
          isDemo: launch.isDemo,
        );

  void deleteAccount(String id) {
    final filtered = accounts.list().where((e) => e.id == id);
    if (filtered.isNotEmpty) {
      final record = filtered.first;
      final isAdmin = record.getStringValue("type") == "admin";
      accounts.delete(isAdmin: isAdmin, id: id);
    }
  }

  @override
  AccountModel? get(String id) {
    final filtered = accounts.list().where((e) => e.id == id);
    if (filtered.isEmpty) return null;
    final record = filtered.first;
    return AccountModel.fromJson(record.toJson()
      ..addAll({
        "name": record.getStringValue("name"),
        "email": record.getStringValue("email"),
        "permissions": record.getStringValue("permissions"),
        "operate": record.getIntValue("operate"),
        "type": record.getStringValue("type"),
        "id": record.id,
      }));
  }

  @override
  void set(AccountModel item) {
    final editing = accounts.list().any((e) => e.id == item.id);
    if (editing) {
      accounts.update(
        id: item.id,
        isAdmin: item.isAdmin,
        email: item.email,
        password: item.password,
        name: item.name,
        permissions: item.permissions,
        operates: item.operates,
      );
    } else {
      accounts.newAccount(
        isAdmin: item.isAdmin,
        email: item.email,
        password: item.password,
        name: item.name,
        permissions: item.permissions,
        operates: item.operates,
      );
    }
  }
}

final _accountStore = _AccountStore();

final deleteConfirmFlyoutController = FlyoutController();

Future<AccountModel> openAccount([AccountModel? account]) {
  final editingCopy = AccountModel.fromJson(account?.toJson() ?? {});
  final isNew = accounts.list().every((e) => e.id != editingCopy.id);
  final panel = Panel<AccountModel>(
    archiveButtonReplacement: FlyoutTarget(
      controller: deleteConfirmFlyoutController,
      child: FilledButton(
          style: filledButtonStyle(login.currentAccountID == editingCopy.id
              ? Colors.grey.withAlpha(60)
              : Colors.errorPrimaryColor),
          child: ButtonContent(WindowsIcons.delete, txt("delete")),
          onPressed: () async {
            await flyoutFocusFix(null);
            if (login.currentAccountID == editingCopy.id) return;
            deleteConfirmFlyoutController.showFlyout(builder: (ctx) {
              return ConfirmDeleteFlyout(
                  onConfirm: () {
                    _accountStore.deleteAccount(editingCopy.id);
                    routes.closePanel(editingCopy.id);
                  },
                  controller: deleteConfirmFlyoutController);
            });
          }),
    ),
    singularName: editingCopy.isAdmin ? "admin" : "user",
    unicodeSymbol: "🧑‍💼",
    item: editingCopy,
    store: _accountStore,
    icon: FluentIcons.people,
    title: isNew
        ? txt(editingCopy.isAdmin ? "newAdmin" : "newUser")
        : editingCopy.title,
    tabs: [
      PanelTab(
        title: isNew
            ? txt(editingCopy.isAdmin ? "newAdmin" : "newUser")
            : txt(editingCopy.isAdmin ? "admin" : "user"),
        icon: FluentIcons.people,
        body: _AccountDetails(editingCopy),
      ),
    ],
  );
  routes.openPanel(panel);
  return panel.result.future;
}

class _AccountDetails extends StatefulWidget {
  final AccountModel account;
  const _AccountDetails(this.account);

  @override
  State<_AccountDetails> createState() => _AccountDetailsState();
}

class _AccountDetailsState extends State<_AccountDetails> {
  late TextEditingController nameController;
  late TextEditingController emailController;
  late TextEditingController passwordController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.account.name);
    emailController = TextEditingController(text: widget.account.email);
    passwordController = TextEditingController(text: widget.account.password);
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = accounts.list().every((e) => e.id != widget.account.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OperatesToggle(
          initial: widget.account.operates,
          onChanged: (selected) => widget.account.operates = selected,
        ),
        const SizedBox(height: 15),
        InfoLabel(
          label: txt("name"),
          child: CupertinoTextField(
            controller: nameController,
            placeholder: txt("name"),
            onChanged: (value) => widget.account.name = value,
          ),
        ),
        const SizedBox(height: 10),
        InfoLabel(
          label: txt("email"),
          child: CupertinoTextField(
            controller: emailController,
            placeholder: txt("validEmailMustBeProvided"),
            onChanged: (value) => widget.account.email = value,
          ),
        ),
        const SizedBox(height: 10),
        InfoLabel(
          label: txt("password"),
          child: CupertinoTextField(
            controller: passwordController,
            obscureText: true,
            placeholder: txt("minimumPasswordLength"),
            onChanged: (value) => widget.account.password = value,
          ),
        ),
        if (!isNew) ...[
          const SizedBox(height: 5),
          InfoBar(
            title: Txt(txt("updatingPassword")),
            content: Txt(txt("leaveItEmpty")),
          ),
        ],
        if (widget.account.isAdmin == false)
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
                  initialSelected: widget.account.permissions[PInt.patients],
                  levels: [
                    PermissionLevel(value: 0, label: txt("restricted")),
                    PermissionLevel(value: 1, label: txt("personal")),
                    PermissionLevel(value: 2, label: txt("full"))
                  ],
                  onChanged: (level) =>
                      widget.account.permissions[PInt.patients] = level,
                ),
                PermissionSelector(
                  title: txt("appointments"),
                  initialSelected:
                      widget.account.permissions[PInt.appointments],
                  levels: [
                    PermissionLevel(value: 0, label: txt("restricted")),
                    PermissionLevel(value: 1, label: txt("personal")),
                    PermissionLevel(value: 2, label: txt("full"))
                  ],
                  onChanged: (level) =>
                      widget.account.permissions[PInt.appointments] = level,
                ),
                PermissionSelector(
                  title: txt("post-opNotes"),
                  initialSelected: widget.account.permissions[PInt.postOp],
                  levels: [
                    PermissionLevel(value: 0, label: txt("restricted")),
                    PermissionLevel(value: 1, label: txt("personal")),
                    PermissionLevel(value: 2, label: txt("full"))
                  ],
                  onChanged: (level) =>
                      widget.account.permissions[PInt.postOp] = level,
                ),
                PermissionSelector(
                  title: txt("insights"),
                  initialSelected: widget.account.permissions[PInt.stats],
                  levels: [
                    PermissionLevel(value: 0, label: txt("restricted")),
                    PermissionLevel(value: 1, label: txt("personal")),
                    PermissionLevel(value: 2, label: txt("full"))
                  ],
                  onChanged: (level) =>
                      widget.account.permissions[PInt.stats] = level,
                ),
                PermissionSelector(
                  title: txt("expenses"),
                  initialSelected: widget.account.permissions[PInt.expenses],
                  levels: [
                    PermissionLevel(value: 0, label: txt("restricted")),
                    PermissionLevel(value: 1, label: txt("view")),
                    PermissionLevel(value: 2, label: txt("full"))
                  ],
                  onChanged: (level) =>
                      widget.account.permissions[PInt.expenses] = level,
                ),
                PermissionSelector(
                  title: txt("notes"),
                  initialSelected: widget.account.permissions[PInt.notes],
                  levels: [
                    PermissionLevel(value: 0, label: txt("personal")),
                    PermissionLevel(value: 1, label: txt("all")),
                  ],
                  onChanged: (level) =>
                      widget.account.permissions[PInt.notes] = level,
                ),
                PermissionSelector(
                  title: txt("settings"),
                  initialSelected: widget.account.permissions[PInt.setting],
                  levels: [
                    PermissionLevel(value: 0, label: txt("local")),
                  ],
                  onChanged: (level) =>
                      widget.account.permissions[PInt.setting] = level,
                ),
                PermissionSelector(
                  title: txt("photos"),
                  initialSelected: widget.account.permissions[PInt.photos],
                  levels: [
                    PermissionLevel(value: 0, label: txt("cantUpload")),
                    PermissionLevel(value: 1, label: txt("canUpload")),
                  ],
                  onChanged: (level) =>
                      widget.account.permissions[PInt.photos] = level,
                ),
                const SizedBox(height: 25)
              ],
            );
          })
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
  const PermissionSelector({
    super.key,
    required this.title,
    required this.levels,
    required this.initialSelected,
    required this.onChanged,
  });

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
