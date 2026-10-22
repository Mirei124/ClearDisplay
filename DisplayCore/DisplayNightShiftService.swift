import Foundation
import ObjectiveC.runtime

struct DisplayNightShiftState: Equatable {
  let isEnabled: Bool
  let isSupported: Bool
}

enum DisplayNightShiftError: LocalizedError {
  case unavailable
  case readFailed
  case writeFailed
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .unavailable: "Night Shift is unavailable on this Mac."
    case .readFailed: "Could not read Night Shift status."
    case .writeFailed: "Could not change Night Shift status."
    case .verificationFailed: "Night Shift did not reach the requested state."
    }
  }
}

// Private CoreBrightness client. Only the temporary enabled state is changed;
// schedule, color temperature, and strength are never written here.
final class DisplayNightShiftService {
  private struct Status {
    var active: UInt8 = 0
    var enabled: UInt8 = 0
    var sunSchedulePermitted: UInt8 = 0
    var mode: Int32 = 0
    var fromHour: Int32 = 0
    var fromMinute: Int32 = 0
    var toHour: Int32 = 0
    var toMinute: Int32 = 0
    var disableFlags: UInt64 = 0
    var available: UInt8 = 0
  }

  private let client: NSObject

  init?() {
    guard
      dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
        != nil,
      let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type
    else { return nil }
    client = type.init()
  }

  func readState() throws -> DisplayNightShiftState {
    let selector = NSSelectorFromString("getBlueLightStatus:")
    guard let method = class_getInstanceMethod(type(of: client), selector) else {
      throw DisplayNightShiftError.unavailable
    }
    typealias Getter = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
    let getter = unsafeBitCast(method_getImplementation(method), to: Getter.self)
    var status = Status()
    let succeeded = withUnsafeMutablePointer(to: &status) { getter(client, selector, $0) }
    guard succeeded else { throw DisplayNightShiftError.readFailed }
    return DisplayNightShiftState(
      isEnabled: status.enabled != 0, isSupported: status.available != 0)
  }

  @discardableResult
  func setEnabled(_ enabled: Bool) throws -> DisplayNightShiftState {
    let current = try readState()
    guard current.isSupported else { throw DisplayNightShiftError.unavailable }
    if current.isEnabled == enabled { return current }
    let selector = NSSelectorFromString("setEnabled:")
    guard let method = class_getInstanceMethod(type(of: client), selector) else {
      throw DisplayNightShiftError.unavailable
    }
    typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Bool
    let setter = unsafeBitCast(method_getImplementation(method), to: Setter.self)
    guard setter(client, selector, enabled) else { throw DisplayNightShiftError.writeFailed }
    let updated = try readState()
    guard updated.isEnabled == enabled else { throw DisplayNightShiftError.verificationFailed }
    return updated
  }
}
