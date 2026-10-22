import Foundation

@main
struct TrueToneSmoke {
  static func main() async throws {
    let before = DisplayTrueToneService.status()
    print(
      "before supported=\(before.isSupported) available=\(before.isAvailable) enabled=\(String(describing: before.isEnabled))"
    )
    guard CommandLine.arguments.contains("--round-trip") else { return }
    guard before.isSupported, before.isAvailable, let original = before.isEnabled else {
      throw DisplayTrueToneError.unavailable(
        before.unavailableReason ?? "True Tone is unavailable.")
    }
    do {
      let changed = try await DisplayTrueToneService.setEnabled(!original)
      print("changed enabled=\(String(describing: changed.isEnabled))")
    } catch {
      print("change error=\(error.localizedDescription)")
    }
    let restored = try await DisplayTrueToneService.setEnabled(original)
    print("restored enabled=\(String(describing: restored.isEnabled))")
  }
}
