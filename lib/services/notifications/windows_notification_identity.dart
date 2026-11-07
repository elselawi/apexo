/// Identity the Windows build presents to the notification platform. It must match
/// the MSIX packaging, or toasts show another name and clicks cannot open the app.
abstract final class WindowsNotificationIdentity {
  /// The name shown on the toast.
  static const String appName = "Apexo";

  /// The AUMID, `<PackageFamilyName>!<Application Id>`: the msix identity name
  /// plus the publisher hash, then the application id in the packaged manifest.
  static const String appUserModelId = "alisaleem.apexo.app_e460fpmm323ja!apexo";

  /// COM CLSID of the local-notification activation callback, registered under
  /// `HKCU\Software\Classes\CLSID` and pointed at by the AUMID's `CustomActivator`.
  /// Not the WNS push CLSID or an Entra client id; native expects 36 chars, no braces.
  static const String activationGuid = "51fc2ec1-f21e-4b3c-9f2b-71c28c7b0f7e";
}
