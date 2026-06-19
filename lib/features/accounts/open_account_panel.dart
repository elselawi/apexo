import 'package:apexo/app/routes.dart';
import 'package:apexo/common_widgets/button_styles.dart';
import 'package:apexo/common_widgets/delete_button.dart';
import 'package:apexo/core/model.dart';
import 'package:apexo/core/store.dart';
import 'package:apexo/features/accounts/accounts_controller.dart';
import 'package:apexo/services/localization/locale.dart';
import 'package:apexo/services/login.dart';
import 'package:apexo/utils/constants.dart';
import 'package:apexo/utils/flyout_focus_fix.dart';
import 'package:apexo/services/launch.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/cupertino.dart';

accountFromJson(Map<String, dynamic> json) {
  return AccountModel.fromJson(json);
}

class AccountModel extends Model {
  String email = "";
  String password = "";
  String name = "";
  List<int> permissions = List.filled(Perm.count, 0);
  bool operates = false;
  bool isAdmin = false;

  AccountModel.fromJson(Map<String, dynamic> json) : super.fromJson(json) {
    email = json["email"] ?? email;
    password = json["password"] ?? password;
    name = json["name"] ?? name;
    permissions = Perm.parse(json["permissions"]);
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
    archiveButtonReplacement: login.currentAccountID == editingCopy.id
        ? const SizedBox.shrink()
        : DeleteButton(
            onConfirm: () {
              _accountStore.deleteAccount(editingCopy.id);
              routes.closePanel(editingCopy.id);
            },
            style: filledButtonStyle(Colors.grey),
            preview: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 5,
              children: [
                const Icon(FluentIcons.people),
                Txt(editingCopy.title)
              ],
            ),
            actionText: txt("delete"),
            actionIcon: WindowsIcons.delete,
            restorable: false,
            child: ButtonContent(WindowsIcons.delete, txt("delete")),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                ..._permissionDefs.map((def) => PermissionSelector(
                      title: txt(def.titleKey),
                      initialSelected: widget.account.permissions[def.index],
                      levels: def.levels
                          .map((l) => PermissionLevel(
                                value: l.value,
                                label: txt(l.labelKey),
                              ))
                          .toList(),
                      onChanged: (level) =>
                          widget.account.permissions[def.index] = level,
                    )),
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

/// Lightweight descriptor for a single permission level option (const-safe).
class _PermLevelDef {
  final int value;
  final String labelKey;
  const _PermLevelDef(this.value, this.labelKey);
}

/// Lightweight descriptor for a permission slot (const-safe).
class _PermDef {
  final int index;
  final String titleKey;
  final List<_PermLevelDef> levels;
  const _PermDef(this.index, this.titleKey, this.levels);
}

const _threeLevel = [
  _PermLevelDef(0, "restricted"),
  _PermLevelDef(1, "personal"),
  _PermLevelDef(2, "full"),
];

/// Central registry of all permission selectors. Add a new entry here to
/// add a permission slot everywhere (UI, padding, defaults, etc.).
const _permissionDefs = [
  _PermDef(Perm.patients, "patients", _threeLevel),
  _PermDef(Perm.appointments, "appointments", _threeLevel),
  _PermDef(Perm.postOp, "post-opNotes", _threeLevel),
  _PermDef(Perm.revenue, "revenue", [
    _PermLevelDef(0, "canNotSee"),
    _PermLevelDef(1, "canSee"),
  ]),
  _PermDef(Perm.stats, "insights", _threeLevel),
  _PermDef(Perm.expenses, "expenses", [
    _PermLevelDef(0, "restricted"),
    _PermLevelDef(1, "view"),
    _PermLevelDef(2, "full"),
  ]),
  _PermDef(Perm.notes, "notes", [
    _PermLevelDef(0, "personal"),
    _PermLevelDef(1, "all"),
  ]),
  _PermDef(Perm.setting, "settings", [
    _PermLevelDef(0, "local"),
  ]),
  _PermDef(Perm.photos, "photos", [
    _PermLevelDef(0, "cantUpload"),
    _PermLevelDef(1, "canUpload"),
  ]),
];

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
  final FlyoutController _flyoutCtrl = FlyoutController();

  @override
  void initState() {
    selected = widget.initialSelected;
    super.initState();
  }

  @override
  void dispose() {
    _flyoutCtrl.dispose();
    super.dispose();
  }

  String get _selectedLabel =>
      widget.levels.firstWhere((l) => l.value == selected).label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: FlyoutTarget(
        controller: _flyoutCtrl,
        child: Button(
          onPressed: () async {
            await flyoutFocusFix(context);
            _flyoutCtrl.showFlyout(builder: (ctx) {
              return MenuFlyout(items: [
                MenuFlyoutItem(
                  leading: const Icon(FluentIcons.settings, size: 16),
                  text: Txt(widget.title),
                  onPressed: null,
                ),
                const MenuFlyoutSeparator(),
                ...widget.levels.map((l) => MenuFlyoutItem(
                      leading: l.value == selected
                          ? const Icon(FluentIcons.accept, size: 16)
                          : const SizedBox(width: 16),
                      text: Txt(l.label),
                      onPressed: () {
                        setState(() {
                          selected = l.value;
                          widget.onChanged(l.value);
                        });
                      },
                    )),
              ]);
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              spacing: 5,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  spacing: 5,
                  children: [
                    Txt("${widget.title}:",
                        style: FluentTheme.of(context)
                            .typography
                            .bodyStrong
                            ?.copyWith(fontSize: 14)),
                    Txt(_selectedLabel,
                        style: FluentTheme.of(context)
                            .typography
                            .body
                            ?.copyWith(fontSize: 12))
                  ],
                ),
                const Icon(FluentIcons.chevron_down, size: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
