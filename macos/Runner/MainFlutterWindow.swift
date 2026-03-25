import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Make titlebar transparent so Flutter content extends behind traffic lights
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false
    self.toolbar = nil

    // Follow system dark/light mode (nil = inherit from system)
    self.appearance = nil

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
