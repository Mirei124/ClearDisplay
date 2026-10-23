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
    case .notRegistered, .notFound:
      let installed = isInstalledInApplications
      return .init(
        isEnabled: false, isAvailable: installed,
        reason: installed
          ? nil : "当前运行的副本不在“应用程序”文件夹；请退出后从该文件夹重新打开 ClearDisplay。")
    case .requiresApproval:
      return .init(
        isEnabled: false, isAvailable: true,
        reason: "请在系统设置 → 通用 → 登录项中允许 ClearDisplay。")
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

  private static var isInstalledInApplications: Bool {
    let appURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
    let locations = [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Applications", isDirectory: true),
    ]
    return locations.contains {
      appURL.deletingLastPathComponent() == $0.resolvingSymlinksInPath()
    }
  }
}
