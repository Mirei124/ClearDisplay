import AppKit
import CoreGraphics
import Darwin
import Foundation
import ObjectiveC.runtime

struct DisplayTrueToneStatus {
  let isSupported: Bool
  let isEnabled: Bool?
  let unavailableReason: String?
}

enum DisplayTrueToneError: Error, LocalizedError {
  case unavailable(String)
  case displayChanged
  case setterFailed
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .unavailable(let reason): reason
    case .displayChanged: "The display changed while True Tone was being set."
    case .setterFailed: "macOS rejected the True Tone setting."
    case .verificationFailed: "The True Tone setting could not be verified."
    }
  }
}

/// CoreBrightness exposes a machine-wide client for integrated True Tone. It
/// does not identify an external display, so external controls are unavailable.
@MainActor
enum DisplayTrueToneService {
  private static let client: NSObject? = {
    guard
      dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        != nil,
      let type = NSClassFromString("CBTrueToneClient") as? NSObject.Type
    else { return nil }
    return type.init()
  }()

  static func status(for displayID: CGDirectDisplayID) -> DisplayTrueToneStatus {
    guard CGDisplayIsOnline(displayID) != 0 else {
      return .init(
        isSupported: false, isEnabled: nil, unavailableReason: "Display is disconnected.")
    }
    guard CGDisplayIsBuiltin(displayID) != 0 else {
      return .init(
        isSupported: false, isEnabled: nil,
        unavailableReason: "Per-display True Tone is unavailable for this external display.")
    }
    guard let client,
      read("supportIntegrated", from: client) == true,
      read("supported", from: client) == true,
      read("available", from: client) == true,
      let enabled = read("enabled", from: client)
    else {
      return .init(
        isSupported: false, isEnabled: nil,
        unavailableReason: "True Tone is unavailable for this display.")
    }
    return .init(isSupported: true, isEnabled: enabled, unavailableReason: nil)
  }

  @discardableResult
  static func setEnabled(_ enabled: Bool, for displayID: CGDirectDisplayID) async throws
    -> DisplayTrueToneStatus
  {
    let before = status(for: displayID)
    guard before.isSupported else {
      throw DisplayTrueToneError.unavailable(
        before.unavailableReason ?? "True Tone is unavailable.")
    }
    guard let uuid = displayUUID(for: displayID), let client else {
      throw DisplayTrueToneError.displayChanged
    }
    if before.isEnabled == enabled { return before }
    let selector = NSSelectorFromString("setEnabled:")
    guard client.responds(to: selector), displayUUID(for: displayID) == uuid else {
      throw DisplayTrueToneError.displayChanged
    }
    typealias Setter = @convention(c) (NSObject, Selector, Bool) -> Bool
    let setter = unsafeBitCast(client.method(for: selector), to: Setter.self)
    guard setter(client, selector, enabled) else { throw DisplayTrueToneError.setterFailed }
    for _ in 0..<12 {
      try await Task.sleep(for: .milliseconds(100))
      guard displayUUID(for: displayID) == uuid else { throw DisplayTrueToneError.displayChanged }
      let after = status(for: displayID)
      if after.isEnabled == enabled { return after }
    }
    throw DisplayTrueToneError.verificationFailed
  }

  private static func read(_ name: String, from client: NSObject) -> Bool? {
    let selector = NSSelectorFromString(name)
    guard client.responds(to: selector) else { return nil }
    typealias Getter = @convention(c) (NSObject, Selector) -> Bool
    return unsafeBitCast(client.method(for: selector), to: Getter.self)(client, selector)
  }

  private static func displayUUID(for id: CGDirectDisplayID) -> String? {
    guard CGDisplayIsOnline(id) != 0, let raw = CGDisplayCreateUUIDFromDisplayID(id),
      let string = CFUUIDCreateString(nil, raw.takeRetainedValue())
    else { return nil }
    return string as String
  }
}
