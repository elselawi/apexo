/// The identity the Windows build presents to the notification platform.
///
/// `flutter_local_notifications` (through the pinned
/// `flutter_local_notifications_windows`) reads both values, and the MSIX
/// packaging must declare exactly the same ones: a mismatch means Windows
/// shows the toast under another name or cannot activate the app when the
/// toast is clicked.
abstract final class WindowsNotificationIdentity {
  /// The name shown on the toast.
  static const String appName = "Apexo";

  /// The MSIX Application User Model ID: `<PackageFamilyName>!<Application Id>`.
  ///
  /// The package family name is `msix_config.identity_name` plus the publisher
  /// hash the `msix` tool derives from the publisher, and the application id is
  /// the id in the packaged `AppxManifest.xml`.
  static const String appUserModelId = "alisaleem.apexo.app_e460fpmm323ja!apexo";

  /// The COM class id of the **local notification activation** callback.
  ///
  /// `flutter_local_notifications_windows` registers this class under
  /// `HKCU\Software\Classes\CLSID\{guid}` and points the AUMID's
  /// `CustomActivator` at it, so clicking a toast wakes this app. It is not
  /// the Windows App SDK push COM CLSID (which activates a WNS background
  /// task) and not an Entra client id — those are separate identifiers that
  /// belong to the native and packaging work and must not reuse this value.
  ///
  /// The native side expects 36 characters, without braces.
  static const String activationGuid = "51fc2ec1-f21e-4b3c-9f2b-71c28c7b0f7e";
}
