import AppKit
import ColorSync
import CoreGraphics
import Foundation

struct DisplayHDRStatus {
  let isSupported: Bool
  let isEnabled: Bool?
  let unavailableReason: String?
}

enum DisplayHDRError: Error, LocalizedError {
  case unavailable(String)
  case displayChanged
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .unavailable(let reason): reason
    case .displayChanged: "The display changed while HDR was being set."
    case .verificationFailed: "The HDR setting could not be verified."
    }
  }
}

/// MonitorPanel is a private framework. Only call this on the main actor, and
/// identify the target by its stable UUID before mutating a recycled display ID.
@MainActor
enum DisplayHDRService {
  private static let manager: NSObject? = {
    guard
      dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY)
        != nil,
      let type = NSClassFromString("MPDisplayMgr") as? NSObject.Type
    else { return nil }
    return type.init()
  }()

  static func status(for displayID: CGDirectDisplayID) -> DisplayHDRStatus {
    guard CGDisplayIsOnline(displayID) != 0 else {
      return .init(
        isSupported: false, isEnabled: nil, unavailableReason: "Display is disconnected.")
    }
    guard CGDisplayIsBuiltin(displayID) == 0 else {
      return .init(
        isSupported: false, isEnabled: nil,
        unavailableReason: "Built-in HDR mode is managed by macOS.")
    }
    guard let display = mpDisplay(for: displayID),
      display.responds(to: NSSelectorFromString("setPreferHDRModes:")),
      (display.value(forKey: "hasHDRModes") as? Bool) == true,
      let enabled = display.value(forKey: "preferHDRModes") as? Bool
    else {
      return .init(
        isSupported: false, isEnabled: nil,
        unavailableReason: "HDR mode is unavailable for this display.")
    }
    return .init(isSupported: true, isEnabled: enabled, unavailableReason: nil)
  }

  @discardableResult
  static func setEnabled(_ enabled: Bool, for displayID: CGDirectDisplayID) async throws
    -> DisplayHDRStatus
  {
    let before = status(for: displayID)
    guard before.isSupported else {
      throw DisplayHDRError.unavailable(before.unavailableReason ?? "HDR mode is unavailable.")
    }
    guard let uuid = displayUUID(for: displayID), let display = mpDisplay(for: displayID) else {
      throw DisplayHDRError.displayChanged
    }
    if before.isEnabled == enabled { return before }
    let selector = NSSelectorFromString("setPreferHDRModes:")
    guard display.responds(to: selector), displayUUID(for: displayID) == uuid else {
      throw DisplayHDRError.displayChanged
    }
    typealias Setter = @convention(c) (NSObject, Selector, Bool) -> Void
    unsafeBitCast(display.method(for: selector), to: Setter.self)(display, selector, enabled)
    for _ in 0..<12 {
      try await Task.sleep(for: .milliseconds(100))
      guard displayUUID(for: displayID) == uuid else { throw DisplayHDRError.displayChanged }
      let after = status(for: displayID)
      if after.isEnabled == enabled { return after }
    }
    throw DisplayHDRError.verificationFailed
  }

  private static func mpDisplay(for id: CGDirectDisplayID) -> NSObject? {
    guard let displays = manager?.value(forKey: "displays") as? [NSObject] else { return nil }
    return displays.first { ($0.value(forKey: "displayID") as? UInt32) == id }
  }

  private static func displayUUID(for id: CGDirectDisplayID) -> String? {
    guard CGDisplayIsOnline(id) != 0, let raw = CGDisplayCreateUUIDFromDisplayID(id),
      let string = CFUUIDCreateString(nil, raw.takeRetainedValue())
    else { return nil }
    return string as String
  }
}
