import SwiftUI

@main
struct HiDPIApp: App {
  @StateObject private var displays = DisplayController()

  var body: some Scene {
    MenuBarExtra("HiDPI", systemImage: "display") {
      DisplayMenuView(controller: displays)
    }
    .menuBarExtraStyle(.window)
  }
}
