import AppKit
import Foundation

enum SystemAppearanceMode: String, CaseIterable {
  case light
  case dark
  case automatic
}

enum DisplayAppearanceError: Error, LocalizedError {
  case automation(String)
  case automaticUnsupported
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .automation(let message):
      "System Events could not change the system appearance: \(message)"
    case .automaticUnsupported:
      "Automatic appearance cannot be changed through the available system interface."
    case .verificationFailed: "The system appearance did not change as requested."
    }
  }
}

/// Reads global appearance preferences without Automation access. Writes use
/// System Events and require Automation access to it from the signed app.
@MainActor
enum DisplayAppearanceService {
  static func readMode() throws -> SystemAppearanceMode {
    if automaticallySwitches { return .automatic }
    return (preferenceValue("AppleInterfaceStyle") as? String) == "Dark" ? .dark : .light
  }

  static func setMode(_ mode: SystemAppearanceMode) throws {
    guard mode != .automatic else { throw DisplayAppearanceError.automaticUnsupported }
    let current = try readMode()
    if current == mode { return }
    // A boolean System Events command cannot preserve the user's Auto schedule.
    guard current != .automatic else { throw DisplayAppearanceError.automaticUnsupported }
    _ = try runScript("set dark mode of appearance preferences to \(mode == .dark)")
    guard try readMode() == mode else { throw DisplayAppearanceError.verificationFailed }
  }

  private static var automaticallySwitches: Bool {
    guard let value = preferenceValue("AppleInterfaceStyleSwitchesAutomatically") else {
      return false
    }
    return (value as? Bool) == true
  }

  private static func preferenceValue(_ key: String) -> Any? {
    CFPreferencesCopyValue(
      key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost)
  }

  private static func runScript(_ command: String) throws -> Bool {
    guard let script = NSAppleScript(source: "tell application \"System Events\" to \(command)")
    else { throw DisplayAppearanceError.automation("Could not create AppleScript.") }
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    if let error {
      throw DisplayAppearanceError.automation(error.description)
    }
    return result.booleanValue
  }
}
