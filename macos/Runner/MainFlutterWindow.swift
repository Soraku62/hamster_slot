import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 480, height: 860)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    DispatchQueue.main.async {
      // WIN_W / WIN_H env vars override the size (used to test landscape).
      let env = ProcessInfo.processInfo.environment
      let w = Double(env["WIN_W"] ?? "") ?? 480
      let h = Double(env["WIN_H"] ?? "") ?? 860
      self.setContentSize(NSSize(width: w, height: h))
      self.center()
    }
  }
}
