import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
    if runningApps.count > 1 {
      self.orderOut(nil) // Hide the window while the alert is active
      
      let alert = NSAlert()
      alert.messageText = "Error"
      alert.informativeText = "The application is already running, Please quit."
      alert.alertStyle = .critical
      alert.addButton(withTitle: "OK")
      alert.runModal()
      
      NSApp.terminate(nil)
      return
    }

    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
