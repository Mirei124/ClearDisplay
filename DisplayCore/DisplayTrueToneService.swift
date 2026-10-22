import Darwin
import Foundation
import ObjectiveC.runtime

struct DisplayTrueToneStatus {
  let isSupported: Bool
  let isAvailable: Bool
  let isEnabled: Bool?
  let unavailableReason: String?
}

enum DisplayTrueToneError: Error, LocalizedError {
  case unavailable(String)
  case setterFailed
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .unavailable(let reason): reason
    case .setterFailed: "macOS rejected the True Tone setting."
    case .verificationFailed: "The True Tone setting could not be verified."
    }
  }
}

/// CoreBrightness exposes one machine-wide True Tone client. This does not
/// control or report a setting for an individual display.
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

  static func status() -> DisplayTrueToneStatus {
    guard let client else {
      return .init(
        isSupported: false, isAvailable: false, isEnabled: nil,
        unavailableReason: "CoreBrightness is unavailable.")
    }
    let supported = read("supported", from: client) == true
    let available = read("available", from: client) == true
    let enabled = supported && available ? read("enabled", from: client) : nil
    let reason: String?
    if !supported {
      reason = "True Tone is unsupported on this Mac."
    } else if !available {
      reason = "True Tone is currently unavailable."
    } else if enabled == nil {
      reason = "True Tone state could not be read."
    } else {
      reason = nil
    }
    return .init(
      isSupported: supported, isAvailable: available, isEnabled: enabled,
      unavailableReason: reason)
  }

  @discardableResult
  static func setEnabled(_ enabled: Bool) async throws
    -> DisplayTrueToneStatus
  {
    let before = status()
    guard before.isSupported && before.isAvailable && before.isEnabled != nil else {
      throw DisplayTrueToneError.unavailable(
        before.unavailableReason ?? "True Tone is unavailable.")
    }
    guard let client else {
      throw DisplayTrueToneError.unavailable("CoreBrightness is unavailable.")
    }
    if before.isEnabled == enabled { return before }
    let selector = NSSelectorFromString("setEnabled:")
    guard client.responds(to: selector) else { throw DisplayTrueToneError.setterFailed }
    typealias Setter = @convention(c) (NSObject, Selector, Bool) -> Bool
    let setter = unsafeBitCast(client.method(for: selector), to: Setter.self)
    guard setter(client, selector, enabled) else { throw DisplayTrueToneError.setterFailed }
    for _ in 0..<12 {
      try await Task.sleep(for: .milliseconds(100))
      let after = status()
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
}
