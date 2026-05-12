import AppKit
import Foundation

struct Env {
  static func get(_ key: String) -> String? {
    let v = ProcessInfo.processInfo.environment[key]
    return v?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? v : nil
  }
}

func stderrLog(_ s: String) {
  FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

func usageAndExit(code: Int32) -> Never {
  stderrLog(
    """
    Usage:
      open -a "AI Crash Fix" --args [options]

    Options (mapped to backend env vars):
      --llm-provider <openai|gemini|gosi-brain>     -> LLM_PROVIDER
      --openai-url <url>                -> OPENAI_URL
      --openai-model <model>            -> OPENAI_MODEL
      --openai-api-key <key>            -> OPENAI_API_KEY
      --google-api-key <key>            -> GOOGLE_API_KEY
      --gemini-model <model>            -> GEMINI_MODEL
      --gosi-brain-url <url>            -> GOSI_BRAIN_URL
      --gosi-brain-model <model>        -> GOSI_BRAIN_MODEL
      --gosi-brain-api-key <key>        -> GOSI_BRAIN_API_KEY
      --gosi-brain-authorization <hdr>  -> GOSI_BRAIN_AUTHORIZATION
      --gosi-brain-oauth-domain <name>  -> GOSI_BRAIN_OAUTH_IDENTITY_DOMAIN_NAME
      --gosi-brain-temperature <n>      -> GOSI_BRAIN_TEMPERATURE

    Advanced:
      --env KEY=VALUE                    -> sets arbitrary environment variable

    Notes:
      - Passing API keys via --args can expose them in process listings.
      - The launcher will NOT print secrets to its log file.

    Example:
      open -a "AI Crash Fix" --args --llm-provider openai --openai-model gpt-4o-mini --openai-url https://api.openai.com/v1 --openai-api-key $OPENAI_API_KEY
    """
  )
  exit(code)
}

func parseLauncherEnvOverrides(_ argv: [String]) -> (overrides: [String: String], redactedKeys: Set<String>, unknownArgs: [String]) {
  var overrides: [String: String] = [:]
  var unknown: [String] = []

  // Keys we should never write verbatim into logs.
  let secretKeys: Set<String> = [
    "OPENAI_API_KEY",
    "GOOGLE_API_KEY",
    "GOSI_BRAIN_API_KEY",
    "GOSI_BRAIN_AUTHORIZATION",
  ]

  func set(_ envKey: String, _ value: String) {
    overrides[envKey] = value
  }

  // Support both: "--flag value" and "--flag=value"
  func nextValue(_ i: inout Int, _ current: String) -> String? {
    if let eq = current.firstIndex(of: "=") {
      return String(current[current.index(after: eq)...])
    }
    let ni = i + 1
    if ni >= argv.count { return nil }
    i = ni
    return argv[ni]
  }

  var i = 1 // skip argv[0]
  while i < argv.count {
    let a = argv[i]

    switch a {
    case "-h", "--help":
      usageAndExit(code: 0)

    case "--llm-provider":
      if let v = nextValue(&i, a) { set("LLM_PROVIDER", v) } else { usageAndExit(code: 2) }

    case "--openai-url":
      if let v = nextValue(&i, a) { set("OPENAI_URL", v) } else { usageAndExit(code: 2) }

    case "--openai-model":
      if let v = nextValue(&i, a) { set("OPENAI_MODEL", v) } else { usageAndExit(code: 2) }

    case "--openai-api-key":
      if let v = nextValue(&i, a) { set("OPENAI_API_KEY", v) } else { usageAndExit(code: 2) }

    case "--google-api-key":
      if let v = nextValue(&i, a) { set("GOOGLE_API_KEY", v) } else { usageAndExit(code: 2) }

    case "--gemini-model":
      if let v = nextValue(&i, a) { set("GEMINI_MODEL", v) } else { usageAndExit(code: 2) }

    case "--gosi-brain-url":
      if let v = nextValue(&i, a) { set("GOSI_BRAIN_URL", v) } else { usageAndExit(code: 2) }

    case "--gosi-brain-model":
      if let v = nextValue(&i, a) { set("GOSI_BRAIN_MODEL", v) } else { usageAndExit(code: 2) }

    case "--gosi-brain-api-key":
      if let v = nextValue(&i, a) { set("GOSI_BRAIN_API_KEY", v) } else { usageAndExit(code: 2) }

    case "--gosi-brain-authorization":
      if let v = nextValue(&i, a) { set("GOSI_BRAIN_AUTHORIZATION", v) } else { usageAndExit(code: 2) }

    case "--gosi-brain-oauth-domain":
      if let v = nextValue(&i, a) { set("GOSI_BRAIN_OAUTH_IDENTITY_DOMAIN_NAME", v) } else { usageAndExit(code: 2) }

    case "--gosi-brain-temperature":
      if let v = nextValue(&i, a) { set("GOSI_BRAIN_TEMPERATURE", v) } else { usageAndExit(code: 2) }

    case "--env":
      if let kv = nextValue(&i, a) {
        if let eq = kv.firstIndex(of: "=") {
          let k = String(kv[..<eq]).trimmingCharacters(in: .whitespacesAndNewlines)
          let v = String(kv[kv.index(after: eq)...])
          if !k.isEmpty { set(k, v) } else { usageAndExit(code: 2) }
        } else {
          usageAndExit(code: 2)
        }
      } else {
        usageAndExit(code: 2)
      }

    default:
      // Support "--flag=value" variants for known flags.
      if a.hasPrefix("--llm-provider=") {
        set("LLM_PROVIDER", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--openai-url=") {
        set("OPENAI_URL", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--openai-model=") {
        set("OPENAI_MODEL", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--openai-api-key=") {
        set("OPENAI_API_KEY", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--google-api-key=") {
        set("GOOGLE_API_KEY", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--gemini-model=") {
        set("GEMINI_MODEL", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--gosi-brain-url=") {
        set("GOSI_BRAIN_URL", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--gosi-brain-model=") {
        set("GOSI_BRAIN_MODEL", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--gosi-brain-api-key=") {
        set("GOSI_BRAIN_API_KEY", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--gosi-brain-authorization=") {
        set("GOSI_BRAIN_AUTHORIZATION", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--gosi-brain-oauth-domain=") {
        set("GOSI_BRAIN_OAUTH_IDENTITY_DOMAIN_NAME", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else if a.hasPrefix("--gosi-brain-temperature=") {
        set("GOSI_BRAIN_TEMPERATURE", String(a.split(separator: "=", maxSplits: 1)[1]))
      } else {
        unknown.append(a)
      }
    }

    i += 1
  }

  // Return the *env keys* that are secrets (not the flag names).
  let redacted = Set(overrides.keys).intersection(secretKeys)
  return (overrides, redacted, unknown)
}

func appendLine(_ s: String, to url: URL) {
  let line = (s + "\n").data(using: .utf8)!
  if FileManager.default.fileExists(atPath: url.path) {
    if let fh = try? FileHandle(forWritingTo: url) {
      try? fh.seekToEnd()
      try? fh.write(contentsOf: line)
      try? fh.close()
    }
  } else {
    try? line.write(to: url)
  }
}

func findFreePort() throws -> Int {
  // Bind to port 0 to let the OS choose a free port.
  var hints = addrinfo(
    ai_flags: AI_PASSIVE,
    ai_family: AF_INET,
    ai_socktype: SOCK_STREAM,
    ai_protocol: IPPROTO_TCP,
    ai_addrlen: 0,
    ai_canonname: nil,
    ai_addr: nil,
    ai_next: nil
  )
  var res: UnsafeMutablePointer<addrinfo>?
  let err = getaddrinfo("127.0.0.1", "0", &hints, &res)
  if err != 0 { throw NSError(domain: "launcher", code: Int(err), userInfo: [NSLocalizedDescriptionKey: "getaddrinfo failed"]) }
  defer { if res != nil { freeaddrinfo(res) } }
  guard let ai = res else { throw NSError(domain: "launcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "no addrinfo"]) }

  let sock = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
  if sock < 0 { throw NSError(domain: "launcher", code: 2, userInfo: [NSLocalizedDescriptionKey: "socket() failed"]) }
  defer { close(sock) }

  if bind(sock, ai.pointee.ai_addr, ai.pointee.ai_addrlen) != 0 {
    throw NSError(domain: "launcher", code: 3, userInfo: [NSLocalizedDescriptionKey: "bind() failed"])
  }

  var addr = sockaddr_in()
  var len = socklen_t(MemoryLayout<sockaddr_in>.stride)
  withUnsafeMutablePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
      getsockname(sock, saPtr, &len)
    }
  }
  return Int(UInt16(bigEndian: addr.sin_port))
}

func resourcePath() -> String {
  // .../AI Crash Fix.app/Contents/MacOS/<exe> -> Resources is sibling under Contents
  let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
  let contentsURL = execURL.deletingLastPathComponent().deletingLastPathComponent()
  return contentsURL.appendingPathComponent("Resources").path
}

func applicationSupportDir() -> URL {
  let fm = FileManager.default
  let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
  let dir = base.appendingPathComponent("AI Crash Fix", isDirectory: true)
  try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

func resolveBackendExecutable(backendPath: String) -> String {
  // Support both:
  // - onefile/hand-copied binary: .../bin/ai_crash_fix_backend
  // - onedir bundle:            .../bin/ai_crash_fix_backend/ai_crash_fix_backend
  var isDir: ObjCBool = false
  if FileManager.default.fileExists(atPath: backendPath, isDirectory: &isDir), isDir.boolValue {
    let nested = URL(fileURLWithPath: backendPath).appendingPathComponent("ai_crash_fix_backend").path
    return nested
  }
  return backendPath
}

func waitForHealth(baseURL: String, timeoutSeconds: Double) -> Bool {
  let deadline = Date().addingTimeInterval(timeoutSeconds)
  let session = URLSession(configuration: .ephemeral)
  while Date() < deadline {
    guard let url = URL(string: baseURL + "/api/health") else { return false }
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    let task = session.dataTask(with: url) { data, resp, err in
      defer { sem.signal() }
      if err != nil { return }
      guard let http = resp as? HTTPURLResponse else { return }
      ok = (http.statusCode == 200)
      _ = data
    }
    task.resume()
    _ = sem.wait(timeout: .now() + 1.0)
    if ok { return true }
    Thread.sleep(forTimeInterval: 0.25)
  }
  return false
}

func openBrowser(url: String) {
  guard let u = URL(string: url) else { return }
  NSWorkspace.shared.open(u)
}

final class LauncherUI {
  private let window: NSWindow
  private let label: NSTextField
  private let spinner: NSProgressIndicator

  init() {
    let size = NSSize(width: 420, height: 160)
    window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    window.title = "AI Crash Fix"
    window.center()
    window.isReleasedWhenClosed = false

    let content = NSView(frame: NSRect(origin: .zero, size: size))
    window.contentView = content

    label = NSTextField(labelWithString: "Starting…")
    label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
    label.frame = NSRect(x: 24, y: 90, width: size.width - 48, height: 22)
    content.addSubview(label)

    let sub = NSTextField(labelWithString: "This may take a few seconds on first launch.")
    sub.textColor = .secondaryLabelColor
    sub.frame = NSRect(x: 24, y: 66, width: size.width - 48, height: 18)
    content.addSubview(sub)

    spinner = NSProgressIndicator(frame: NSRect(x: 24, y: 24, width: 20, height: 20))
    spinner.style = .spinning
    spinner.controlSize = .regular
    spinner.startAnimation(nil)
    content.addSubview(spinner)

    let hint = NSTextField(labelWithString: "Opening browser when ready…")
    hint.textColor = .secondaryLabelColor
    hint.frame = NSRect(x: 52, y: 24, width: size.width - 76, height: 20)
    content.addSubview(hint)
  }

  func show() {
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func setStatus(_ s: String) {
    label.stringValue = s
  }

  func showFailure(title: String, message: String) {
    spinner.stopAnimation(nil)
    label.stringValue = title
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  func close() {
    window.close()
  }
}

// ---- main ----

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let res = resourcePath()
let binDir = URL(fileURLWithPath: res).appendingPathComponent("bin", isDirectory: true).path
let backendPath = Env.get("AI_CRASH_FIX_BACKEND_BIN") ?? (binDir + "/ai_crash_fix_backend")
let rgPath = binDir + "/rg"

final class OpenUiAction: NSObject {
  let getBaseUrl: () -> String
  init(getBaseUrl: @escaping () -> String) { self.getBaseUrl = getBaseUrl }
  @objc func run() { openBrowser(url: getBaseUrl() + "/") }
}

final class QuitAction: NSObject {
  let terminateBackend: () -> Void
  init(terminateBackend: @escaping () -> Void) { self.terminateBackend = terminateBackend }
  @objc func run() {
    terminateBackend()
    NSApp.terminate(nil)
  }
}

/// Vector-drawn template icon (dot + arrow). Avoids bundled PNGs from `qlmanage`, which often break alpha
/// and render as a solid black square when `isTemplate` is true.
func makeMenuBarStatusIcon() -> NSImage {
  let side: CGFloat = 18
  let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
    NSColor.clear.setFill()
    rect.fill()
    NSColor.black.setFill()
    NSColor.black.setStroke()
    let dotRect = CGRect(x: 4, y: 6.5, width: 5, height: 5)
    NSBezierPath(ovalIn: dotRect).fill()
    let shaft = NSBezierPath()
    shaft.move(to: CGPoint(x: 10.5, y: 9))
    shaft.line(to: CGPoint(x: 15.25, y: 9))
    shaft.lineWidth = 1.35
    shaft.lineCapStyle = .round
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: 14, y: 7.6))
    head.line(to: CGPoint(x: 15.25, y: 9))
    head.line(to: CGPoint(x: 14, y: 10.4))
    head.lineWidth = 1.35
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()
    return true
  }
  img.isTemplate = true
  return img
}

func installMenuBar(getBaseUrl: @escaping () -> String, terminateBackend: @escaping () -> Void) {
  let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  statusItem.button?.image = makeMenuBarStatusIcon()
  statusItem.button?.title = ""
  let menu = NSMenu()
  let openAction = OpenUiAction(getBaseUrl: getBaseUrl)
  let quitAction = QuitAction(terminateBackend: terminateBackend)
  // add app name as title on top of menu
  let appNameItem = NSMenuItem(title: "AI Crash Fix", action: nil, keyEquivalent: "")
  appNameItem.isEnabled = false
  appNameItem.target = nil
  menu.addItem(appNameItem)
  let openItem = NSMenuItem(title: "Open UI", action: #selector(OpenUiAction.run), keyEquivalent: "o")
  openItem.target = openAction
  let quitItem = NSMenuItem(title: "Quit", action: #selector(QuitAction.run), keyEquivalent: "q")
  quitItem.target = quitAction
  menu.addItem(openItem)
  menu.addItem(NSMenuItem.separator())
  menu.addItem(quitItem)
  statusItem.menu = menu
  // Keep actions alive by associating them with the status item button.
  objc_setAssociatedObject(statusItem, "openAction", openAction, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  objc_setAssociatedObject(statusItem, "quitAction", quitAction, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}

let port: Int
do {
  port = try findFreePort()
} catch {
  stderrLog("Failed to pick a free port: \(error)")
  exit(1)
}

let baseURL = "http://127.0.0.1:\(port)"
let dataDir = Env.get("AI_CRASH_FIX_DATA_DIR") ?? applicationSupportDir().path
let logURL = URL(fileURLWithPath: dataDir).appendingPathComponent("launcher.log")
let backendLogURL = URL(fileURLWithPath: dataDir).appendingPathComponent("backend.log")

appendLine("Launcher starting. baseURL=\(baseURL)", to: logURL)
appendLine("binDir=\(binDir)", to: logURL)
appendLine("dataDir=\(dataDir)", to: logURL)

let proc = Process()
let backendExe = resolveBackendExecutable(backendPath: backendPath)
proc.executableURL = URL(fileURLWithPath: backendExe)
proc.arguments = ["--host", "127.0.0.1", "--port", "\(port)"]

var env = ProcessInfo.processInfo.environment
env["AI_CRASH_FIX_RG_PATH"] = rgPath
env["AI_CRASH_FIX_WEB_ROOT"] = "" // backend will use bundled web/ in frozen builds
env["AI_CRASH_FIX_DATA_DIR"] = dataDir
let parsed = parseLauncherEnvOverrides(CommandLine.arguments)
for (k, v) in parsed.overrides {
  env[k] = v
}
// Let backend resolve its own storage layout; launcher only provides a shared base.
proc.environment = env
appendLine("Starting backend executable: \(backendExe)", to: logURL)
appendLine("rgPath=\(rgPath)", to: logURL)
if !parsed.overrides.isEmpty {
  let sortedKeys = parsed.overrides.keys.sorted()
  let rendered = sortedKeys.map { k in
    if parsed.redactedKeys.contains(k) { return "\(k)=[redacted]" }
    return "\(k)=\(parsed.overrides[k] ?? "")"
  }.joined(separator: " ")
  appendLine("Applied launch args (env overrides): \(rendered)", to: logURL)
}
if !parsed.unknownArgs.isEmpty {
  appendLine("Unknown launch args ignored: \(parsed.unknownArgs.joined(separator: " "))", to: logURL)
}

// Capture backend logs for debugging.
FileManager.default.createFile(atPath: backendLogURL.path, contents: nil)
if let fh = try? FileHandle(forWritingTo: backendLogURL) {
  proc.standardOutput = fh
  proc.standardError = fh
}

let ui = LauncherUI()
ui.setStatus("Starting backend…")
ui.show()

installMenuBar(
  getBaseUrl: { baseURL },
  terminateBackend: {
    if proc.isRunning {
      proc.terminate()
    }
  }
)

proc.terminationHandler = { p in
  appendLine("Backend exited with code \(p.terminationStatus)", to: logURL)
  DispatchQueue.main.async {
    ui.showFailure(
      title: "AI Crash Fix stopped",
      message: "The backend process exited (code \(p.terminationStatus)).\n\nLogs:\n\(backendLogURL.path)"
    )
    NSApp.terminate(nil)
  }
}

DispatchQueue.global(qos: .userInitiated).async {
  do {
    try proc.run()
  } catch {
    appendLine("Failed to start backend at \(backendExe): \(error)", to: logURL)
    DispatchQueue.main.async {
      ui.showFailure(
        title: "Failed to start",
        message: "Could not start the backend.\n\n\(error)\n\nLogs:\n\(backendLogURL.path)"
      )
      NSApp.terminate(nil)
    }
    return
  }

  DispatchQueue.main.async {
    ui.setStatus("Warming up…")
  }

  let ok = waitForHealth(baseURL: baseURL, timeoutSeconds: 25.0)
  if !ok {
    appendLine("Backend did not become healthy in time. UI may not load.", to: logURL)
    appendLine("See backend log at: \(backendLogURL.path)", to: logURL)
    DispatchQueue.main.async {
      ui.showFailure(
        title: "Startup timed out",
        message: "Backend did not become healthy in time.\n\nLogs:\n\(backendLogURL.path)"
      )
    }
    return
  }

  DispatchQueue.main.async {
    ui.setStatus("Opening browser…")
  }

  openBrowser(url: baseURL + "/")
  appendLine("Opened browser at: \(baseURL)/", to: logURL)

  DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
    ui.close()
  }
}

app.run()
