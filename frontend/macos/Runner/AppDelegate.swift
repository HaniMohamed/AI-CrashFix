import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// PID of the embedded PyInstaller backend; set from Dart via MethodChannel.
  /// Killed synchronously on terminate because Dart async shutdown often does not
  /// finish before the Flutter process exits (child then reparents to launchd).
  private var backendPid: pid_t?

  static var shared: AppDelegate? {
    NSApp.delegate as? AppDelegate
  }

  func registerBackendPid(_ pid: Int) {
    guard pid > 1 else { return }
    backendPid = pid_t(pid)
  }

  func clearBackendPid() {
    backendPid = nil
  }

  /// SIGTERM → short wait → SIGKILL. Runs on the main thread during quit.
  func terminateBackendSynchronously() {
    guard let pid = backendPid, pid > 1 else { return }
    backendPid = nil

    kill(pid, SIGTERM)
    for _ in 0..<30 {
      // kill(..., 0) returns -1 with ESRCH when the process is gone.
      if kill(pid, 0) != 0 {
        return
      }
      usleep(100_000) // 100ms
    }
    kill(pid, SIGKILL)
    // Best-effort: if the freeze forked workers into the same process group.
    killpg(pid, SIGKILL)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    terminateBackendSynchronously()
    return .terminateNow
  }

  override func applicationWillTerminate(_ notification: Notification) {
    terminateBackendSynchronously()
  }
}
