#ifndef RUNNER_PUSH_CONFIG_H_
#define RUNNER_PUSH_CONFIG_H_

// Identifiers and activation arguments for Windows push notifications.
//
// WNS authenticates a send as an Azure app registration, and
// PushNotificationManager::CreateChannelAsync binds the channel to that same
// registration: its `remoteId` parameter is documented as "the Azure AppId ... a
// GUID that matches the application ID specified in Azure Active Directory".
// One identifier therefore covers both directions — the application (client) ID
// below — and no package-family-name mapping is involved. The app registration's
// *object ID* (the "Object ID" on the Overview blade) is not used anywhere here:
// passing it makes WNS answer 403 to every send, because the channel then
// belongs to an identity the relay never authenticates as.
//
// Two further identifiers are deliberately different values:
//
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

// Azure application (client) ID: the remoteId of CreateChannelAsync, the push
// COM class id in the package manifest, and the identity the relay's
// WNS_CLIENT_ID authenticates as when it sends.
#define APEXO_WNS_APP_ID "8f4d5ac1-5142-44fb-928a-6ce05c641dd0"

// The argument Windows passes when it starts the executable for the push COM
// server declared in the package manifest.
#define APEXO_PUSH_ACTIVATION_ARGUMENTS L"----WindowsAppRuntimePushServer:"

// The argument Windows passes when it starts the executable for a local toast
// activation (declared by the msix toast_activator configuration).
#define APEXO_TOAST_ACTIVATION_ARGUMENTS L"----AppNotificationActivationServer"

#endif  // RUNNER_PUSH_CONFIG_H_
