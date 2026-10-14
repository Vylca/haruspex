import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Hands files opened from the Finder to Dart.
  private var files: FileOpener?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    files = FileOpener(
      channel: FlutterMethodChannel(
        name: "haruspex/files", binaryMessenger: flutterViewController.engine.binaryMessenger))

    super.awakeFromNib()
  }
}

/// Files opened with Haruspex from the Finder (Open With, a double click,
/// `open -a Haruspex notes.org`) arrive as an "open documents" Apple event.
/// Dart asks for the ones that came before it was ready ("pending"), and
/// gets the later ones as they come ("open").
class FileOpener: NSObject {
  private let channel: FlutterMethodChannel
  private var pending: [String] = []
  private var ready = false

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      if call.method == "pending" {
        result(self.pending)
        self.pending = []
        self.ready = true
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    // Installed when the app finishes launching, after AppKit's own
    // handlers, so it replaces them.
    NotificationCenter.default.addObserver(
      self, selector: #selector(install(_:)),
      name: NSApplication.willFinishLaunchingNotification, object: nil)
  }

  @objc private func install(_ note: Notification) {
    NSAppleEventManager.shared().setEventHandler(
      self, andSelector: #selector(openDocuments(_:withReply:)),
      forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenDocuments))
  }

  @objc private func openDocuments(
    _ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor
  ) {
    guard let list = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return }
    var paths: [String] = []
    if list.numberOfItems == 0 {
      if let url = list.fileURLValue { paths.append(url.path) }
    } else {
      for i in 1...list.numberOfItems {
        if let url = list.atIndex(i)?.fileURLValue { paths.append(url.path) }
      }
    }
    if paths.isEmpty { return }
    if ready {
      channel.invokeMethod("open", arguments: paths)
    } else {
      pending.append(contentsOf: paths)
    }
  }
}
