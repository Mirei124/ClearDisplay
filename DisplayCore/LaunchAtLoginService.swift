import Foundation
import ServiceManagement

struct LaunchAtLoginStatus {
  let isEnabled: Bool
  let isAvailable: Bool
  let reason: String?
}

enum LaunchAtLoginService {
  static func status() -> LaunchAtLoginStatus {
    switch SMAppService.mainApp.status {
    case .enabled:
      return .init(isEnabled: true, isAvailable: true, reason: nil)
    case .notRegistered:
      return .init(isEnabled: false, isAvailable: true, reason: nil)
    case .requiresApproval:
      return .init(
        isEnabled: false, isAvailable: true,
        reason: "Allow ClearDisplay in System Settings → General → Login Items.")
    case .notFound:
      return .init(
        isEnabled: false, isAvailable: false,
        reason: "Move ClearDisplay to Applications before enabling launch at login.")
    @unknown default:
      return .init(
        isEnabled: false, isAvailable: false,
        reason: "The launch-at-login state is unavailable.")
    }
  }

  static func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}
