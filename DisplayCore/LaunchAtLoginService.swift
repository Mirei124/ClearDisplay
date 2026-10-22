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
        reason: "请在系统设置 → 通用 → 登录项中允许 ClearDisplay。")
    case .notFound:
      return .init(
        isEnabled: false, isAvailable: false,
        reason: "请先将 ClearDisplay.app 移到“应用程序”文件夹，再开启开机自启动。")
    @unknown default:
      return .init(
        isEnabled: false, isAvailable: false,
        reason: "当前无法读取开机自启动状态。")
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
