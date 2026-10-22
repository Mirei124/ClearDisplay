import SwiftUI

@main
struct HiDPIApp: App {
  @StateObject private var displays = DisplayController()
  #if DEBUG
    @NSApplicationDelegateAdaptor(PreviewAppDelegate.self) private var previewDelegate
  #endif

  var body: some Scene {
    MenuBarExtra("HiDPI", systemImage: "display") {
      DisplayMenuView(controller: displays)
    }
    .menuBarExtraStyle(.window)
  }
}

#if DEBUG
  private final class PreviewAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var controller: DisplayController?

    func applicationDidFinishLaunching(_ notification: Notification) {
      guard ProcessInfo.processInfo.environment["HIDPI_UI_PREVIEW"] == "1" else { return }
      let controller = DisplayController()
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 380, height: 650),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
      )
      window.title = "HiDPI Preview"
      window.contentView = NSHostingView(rootView: DisplayMenuView(controller: controller))
      window.center()
      window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
      self.controller = controller
      self.window = window
    }
  }
#endif
