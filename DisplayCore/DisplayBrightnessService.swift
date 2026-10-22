import CoreGraphics
import Foundation
import IOKit
import IOKit.i2c

/// Hardware brightness for the built-in panel and an unambiguously paired DDC monitor.
/// Call on a background queue: DDC reads can block while a monitor responds.
enum BrightnessSource {
  case builtIn
  case ddc
}

struct BrightnessStatus {
  let source: BrightnessSource?
  let percent: Double?
  let isAdjustable: Bool
  let unavailableReason: String?
}

enum BrightnessError: Error, LocalizedError {
  case invalidValue
  case unavailable(String)
  case writeFailed
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .invalidValue: "Brightness must be between 0 and 100%."
    case .unavailable(let reason): reason
    case .writeFailed: "The display rejected the brightness command."
    case .verificationFailed: "The brightness change could not be verified."
    }
  }
}

private let dsLibrary = dlopen(
  "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY
)
private let dsGet: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32)? = {
  guard let dsLibrary, let symbol = dlsym(dsLibrary, "DisplayServicesGetBrightness") else {
    return nil
  }
  return unsafeBitCast(
    symbol, to: (@convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32).self)
}()
private let dsSet: (@convention(c) (CGDirectDisplayID, Float) -> Int32)? = {
  guard let dsLibrary, let symbol = dlsym(dsLibrary, "DisplayServicesSetBrightness") else {
    return nil
  }
  return unsafeBitCast(symbol, to: (@convention(c) (CGDirectDisplayID, Float) -> Int32).self)
}()
private let dsCanSet: (@convention(c) (CGDirectDisplayID) -> Bool)? = {
  guard let dsLibrary, let symbol = dlsym(dsLibrary, "DisplayServicesCanChangeBrightness") else {
    return nil
  }
  return unsafeBitCast(symbol, to: (@convention(c) (CGDirectDisplayID) -> Bool).self)
}()

enum DisplayBrightnessService {
  // Brightness, contrast and color temperature share the same DDC/CI channel.
  // Keep each write/read exchange intact when the menu loads them concurrently.
  private static let ddcLock = NSLock()

  static func status(for displayID: CGDirectDisplayID) -> BrightnessStatus {
    guard CGDisplayIsOnline(displayID) != 0 else {
      return .init(
        source: nil, percent: nil, isAdjustable: false,
        unavailableReason: "Display is disconnected.")
    }
    if CGDisplayIsBuiltin(displayID) != 0 {
      guard let dsGet, let dsSet, dsCanSet?(displayID) == true else {
        return .init(
          source: .builtIn, percent: nil, isAdjustable: false,
          unavailableReason: "Built-in brightness control is unavailable.")
      }
      _ = dsSet  // Include setter availability in capability check without changing brightness.
      var value: Float = 0
      guard dsGet(displayID, &value) == 0, value.isFinite, (0...1).contains(value) else {
        return .init(
          source: .builtIn, percent: nil, isAdjustable: false,
          unavailableReason: "Could not read built-in brightness.")
      }
      return .init(
        source: .builtIn, percent: Double(value) * 100,
        isAdjustable: true, unavailableReason: nil)
    }
    guard let channel = uniqueExternalChannel(for: displayID) else {
      return .init(
        source: .ddc, percent: nil, isAdjustable: false,
        unavailableReason: "No unambiguous DDC/CI channel is available.")
    }
    guard let value = readBrightness(channel), value.max > 0, value.current <= value.max else {
      return .init(
        source: .ddc, percent: nil, isAdjustable: false,
        unavailableReason: "The monitor did not return a valid DDC/CI brightness value.")
    }
    return .init(
      source: .ddc, percent: Double(value.current) / Double(value.max) * 100,
      isAdjustable: true, unavailableReason: nil)
  }

  static func setPercent(_ percent: Double, for displayID: CGDirectDisplayID) -> Result<
    BrightnessStatus, BrightnessError
  > {
    guard percent.isFinite, (0...100).contains(percent) else { return .failure(.invalidValue) }
    let before = status(for: displayID)
    guard before.isAdjustable else {
      return .failure(
        .unavailable(before.unavailableReason ?? "Brightness control is unavailable."))
    }
    if CGDisplayIsBuiltin(displayID) != 0 {
      guard dsSet?(displayID, Float(percent / 100)) == 0 else { return .failure(.writeFailed) }
    } else {
      // Re-pair and re-read immediately before writing. Never use a stale raw maximum.
      guard let channel = uniqueExternalChannel(for: displayID),
        let current = readBrightness(channel), current.max > 0,
        current.current <= current.max
      else {
        return .failure(.unavailable("DDC/CI brightness became unavailable."))
      }
      let raw = UInt16((percent / 100 * Double(current.max)).rounded())
      guard writeBrightness(channel, raw: raw) else { return .failure(.writeFailed) }
    }
    let after = status(for: displayID)
    guard after.isAdjustable, let measured = after.percent,
      abs(measured - percent) <= 3
    else { return .failure(.verificationFailed) }
    return .success(after)
  }

  /// A proxy cannot safely be assigned by enumeration order when multiple external
  /// displays are attached. This conservative P1 path only pairs one external to one proxy.
  static func uniqueExternalChannel(for id: CGDirectDisplayID) -> IOAVServiceRef? {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return nil }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success,
      ids.prefix(Int(count)).filter({ CGDisplayIsBuiltin($0) == 0 }).count == 1,
      ids.prefix(Int(count)).contains(id)
    else { return nil }
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    guard root != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(root) }
    var iterator: io_iterator_t = 0
    guard
      IORegistryEntryCreateIterator(
        root, kIOServicePlane,
        IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
    else { return nil }
    defer { IOObjectRelease(iterator) }
    var channels: [IOAVServiceRef] = []
    var entry = IOIteratorNext(iterator)
    while entry != IO_OBJECT_NULL {
      var className = [CChar](repeating: 0, count: 128)
      if IOObjectGetClass(entry, &className) == KERN_SUCCESS,
        String(cString: className) == "DCPAVServiceProxy"
      {
        let location =
          IORegistryEntryCreateCFProperty(
            entry, "Location" as CFString,
            kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
        if location == nil || location == "External",
          let service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)
        {
          channels.append(service)
        }
      }
      IOObjectRelease(entry)
      entry = IOIteratorNext(iterator)
    }
    return channels.count == 1 ? channels[0] : nil
  }

  static func readVCP(_ code: UInt8, channel: IOAVServiceRef) -> (current: UInt16, max: UInt16)? {
    ddcLock.lock()
    defer { ddcLock.unlock() }
    for attempt in 0..<2 {
      if let value = readVCPOnce(code, channel: channel) { return value }
      if attempt == 0 { Thread.sleep(forTimeInterval: 0.08) }
    }
    return nil
  }

  private static func readVCPOnce(
    _ code: UInt8, channel: IOAVServiceRef
  ) -> (current: UInt16, max: UInt16)? {
    var request: [UInt8] = [0x82, 0x01, code]
    request.append(request.reduce(UInt8(0x6E ^ 0x51), ^))
    guard
      IOAVServiceWriteI2C(channel, 0x37, 0x51, &request, UInt32(request.count)) == kIOReturnSuccess
    else { return nil }
    Thread.sleep(forTimeInterval: 0.04)
    var reply = [UInt8](repeating: 0, count: 12)
    guard IOAVServiceReadI2C(channel, 0x37, 0x51, &reply, UInt32(reply.count)) == kIOReturnSuccess,
      reply[0] == 0x6E, reply[1] == 0x88,
      reply[2] == 0x02, reply[3] == 0,
      reply[4] == code, reply[5] == 0,
      reply[10] == reply.prefix(10).reduce(UInt8(0x50), ^)
    else { return nil }
    return (
      (UInt16(reply[8]) << 8) | UInt16(reply[9]),
      (UInt16(reply[6]) << 8) | UInt16(reply[7])
    )
  }

  static func writeVCP(_ code: UInt8, channel: IOAVServiceRef, raw: UInt16) -> Bool {
    ddcLock.lock()
    defer { ddcLock.unlock() }
    var request: [UInt8] = [0x84, 0x03, code, UInt8(raw >> 8), UInt8(raw & 0xFF)]
    request.append(request.reduce(UInt8(0x6E ^ 0x51), ^))
    return IOAVServiceWriteI2C(channel, 0x37, 0x51, &request, UInt32(request.count))
      == kIOReturnSuccess
  }

  private static func readBrightness(_ channel: IOAVServiceRef) -> (current: UInt16, max: UInt16)? {
    readVCP(0x10, channel: channel)
  }

  private static func writeBrightness(_ channel: IOAVServiceRef, raw: UInt16) -> Bool {
    writeVCP(0x10, channel: channel, raw: raw)
  }
}
