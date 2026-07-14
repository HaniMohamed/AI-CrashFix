import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "ai_crash_fix/backend",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "registerBackendPid":
        if let pid = call.arguments as? Int {
          AppDelegate.shared?.registerBackendPid(pid)
          result(nil)
        } else {
          result(
            FlutterError(
              code: "bad_args",
              message: "registerBackendPid expects an Int pid",
              details: nil
            )
          )
        }
      case "clearBackendPid":
        AppDelegate.shared?.clearBackendPid()
        result(nil)
      case "terminateBackendNow":
        AppDelegate.shared?.terminateBackendSynchronously()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
