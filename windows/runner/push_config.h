#ifndef RUNNER_PUSH_CONFIG_H_
#define RUNNER_PUSH_CONFIG_H_

// Identifiers and activation arguments for Windows push notifications.
//
// Four identifiers are involved and they are deliberately different values:
//
//   * the Entra application (service principal) **Object ID**, used only as the
//     remote id of PushNotificationManager::CreateChannelAsync;
//   * the Azure application (client) **ID**, which is the COM class id of the
//     push activator in the package manifest and the identity Microsoft maps to
//     the package family name;
//   * the local-toast activation CLSID, which belongs to
//     flutter_local_notifications_windows and lives in Dart
//     (`WindowsNotificationIdentity.activationGuid`) and in
//     pubspec.yaml msix_config.toast_activator — never here;
//   * the package AUMID.
//
// The all-zero GUID means "not configured": the service then reports
// isSupported from the environment but returns a null channel URI without
// asking WNS, so a build with placeholders still starts normally.
//
// tools/patch_push_manifest.dart reads APEXO_WNS_APP_ID from this file when it
// adds the push COM activator to the generated AppxManifest.xml, so this header
// is the single source of truth for the push class id.

// Microsoft Entra application (service principal) Object ID.
#define APEXO_WNS_OBJECT_ID "431f890b-3a77-4d0b-b52a-aa684ffed80d"

// Azure application (client) ID — also the push COM class id.
#define APEXO_WNS_APP_ID "8f4d5ac1-5142-44fb-928a-6ce05c641dd0"

// The argument Windows passes when it starts the executable for the push COM
// server declared in the package manifest.
#define APEXO_PUSH_ACTIVATION_ARGUMENTS L"----WindowsAppRuntimePushServer:"

// The argument Windows passes when it starts the executable for a local toast
// activation (declared by the msix toast_activator configuration).
#define APEXO_TOAST_ACTIVATION_ARGUMENTS L"----AppNotificationActivationServer"

#endif  // RUNNER_PUSH_CONFIG_H_
