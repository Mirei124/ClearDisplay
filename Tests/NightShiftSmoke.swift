import Foundation
import ObjectiveC.runtime

private struct RawStatus {
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

private struct Snapshot: Equatable, CustomStringConvertible {
  let active: Bool
  let enabled: Bool
  let available: Bool
  let mode: Int32
  let fromHour: Int32
  let fromMinute: Int32
  let toHour: Int32
  let toMinute: Int32
  let strength: Float
  let cct: Float

  var configuration: [String] {
    ["\(mode)", "\(fromHour):\(fromMinute)", "\(toHour):\(toMinute)", "\(strength)", "\(cct)"]
  }

  var description: String {
    "active=\(active) enabled=\(enabled) available=\(available) mode=\(mode) "
      + "schedule=\(fromHour):\(fromMinute)-\(toHour):\(toMinute) "
      + "strength=\(strength) cct=\(cct)"
  }
}

private func snapshot() throws -> Snapshot {
  let client = (NSClassFromString("CBBlueLightClient") as! NSObject.Type).init()
  let statusSelector = NSSelectorFromString("getBlueLightStatus:")
  let strengthSelector = NSSelectorFromString("getStrength:")
  let cctSelector = NSSelectorFromString("getCCT:")
  typealias Getter = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
  let statusGetter = unsafeBitCast(
    method_getImplementation(class_getInstanceMethod(type(of: client), statusSelector)!),
    to: Getter.self
  )
  let strengthGetter = unsafeBitCast(
    method_getImplementation(class_getInstanceMethod(type(of: client), strengthSelector)!),
    to: Getter.self
  )
  let cctGetter = unsafeBitCast(
    method_getImplementation(class_getInstanceMethod(type(of: client), cctSelector)!),
    to: Getter.self
  )
  var status = RawStatus()
  var strength: Float = 0
  var cct: Float = 0
  guard
    withUnsafeMutablePointer(to: &status, { statusGetter(client, statusSelector, $0) }),
    withUnsafeMutablePointer(to: &strength, { strengthGetter(client, strengthSelector, $0) }),
    withUnsafeMutablePointer(to: &cct, { cctGetter(client, cctSelector, $0) })
  else { throw DisplayNightShiftError.readFailed }
  return Snapshot(
    active: status.active != 0,
    enabled: status.enabled != 0,
    available: status.available != 0,
    mode: status.mode,
    fromHour: status.fromHour,
    fromMinute: status.fromMinute,
    toHour: status.toHour,
    toMinute: status.toMinute,
    strength: strength,
    cct: cct
  )
}

@main
struct NightShiftSmoke {
  static func main() throws {
    guard let service = DisplayNightShiftService() else {
      print("Night Shift client unavailable")
      return
    }
    let before = try snapshot()
    print("before", before)
    guard CommandLine.arguments.contains("--toggle") && before.available else { return }
    defer { _ = try? service.setEnabled(before.enabled) }
    _ = try service.setEnabled(!before.enabled)
    let changed = try snapshot()
    print("changed", changed)
    _ = try service.setEnabled(before.enabled)
    let restored = try snapshot()
    print("restored", restored)
    print(
      "configurationPreserved=\(before.configuration == changed.configuration && before.configuration == restored.configuration)"
    )
  }
}
