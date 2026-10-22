import CoreGraphics
import Foundation

@main
struct TrueToneSmoke {
  static func main() async throws {
    let displayID = CGMainDisplayID()
    let before = DisplayTrueToneService.status(for: displayID)
    print("before supported=\(before.isSupported) enabled=\(String(describing: before.isEnabled))")
    guard before.isSupported, let original = before.isEnabled else { return }
    do {
      let changed = try await DisplayTrueToneService.setEnabled(!original, for: displayID)
      print("changed enabled=\(String(describing: changed.isEnabled))")
    } catch {
      print("change error=\(error.localizedDescription)")
    }
    let restored = try await DisplayTrueToneService.setEnabled(original, for: displayID)
    print("restored enabled=\(String(describing: restored.isEnabled))")
  }
}
