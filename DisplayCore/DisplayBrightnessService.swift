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

/// Owns the retained CoreFoundation service returned by IOAVServiceCreateWithService.
/// A raw void pointer is not managed by Swift ARC; failing to release it leaks
/// a kernel user client on every DDC read and write.
final class DisplayDDCChannel {
  fileprivate let service: IOAVServiceRef
  fileprivate var lastIOError: IOReturn?

  fileprivate init(_ service: IOAVServiceRef) { self.service = service }

  deinit { Unmanaged<AnyObject>.fromOpaque(service).release() }
}

enum DisplayBrightnessService {
  // Brightness, contrast and color temperature share the same DDC/CI channel.
  // Keep each write/read exchange intact when the menu loads them concurrently.
  private static let requests = DDCRequestScheduler()

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
    return status(channel: channel)
  }

  private static func status(channel: DisplayDDCChannel) -> BrightnessStatus {
    guard let value = readBrightness(channel), value.max > 0, value.current <= value.max else {
      let reason = readFailure(channel)
      return .init(
        source: .ddc, percent: nil, isAdjustable: false,
        unavailableReason: reason)
    }
    return .init(
      source: .ddc, percent: Double(value.current) / Double(value.max) * 100,
      isAdjustable: true, unavailableReason: nil)
  }

  static func setPercent(_ percent: Double, for displayID: CGDirectDisplayID) -> Result<
    BrightnessStatus, BrightnessError
  > {
    guard percent.isFinite, (0...100).contains(percent) else { return .failure(.invalidValue) }
    if CGDisplayIsBuiltin(displayID) != 0 {
      let before = status(for: displayID)
      guard before.isAdjustable else {
        return .failure(
          .unavailable(before.unavailableReason ?? "Brightness control is unavailable."))
      }
      guard dsSet?(displayID, Float(percent / 100)) == 0 else { return .failure(.writeFailed) }
      let after = status(for: displayID)
      guard let measured = after.percent, after.isAdjustable, abs(measured - percent) <= 3 else {
        return .failure(.verificationFailed)
      }
      return .success(after)
    }
    return requests.transaction {
      // One freshly paired channel and one maximum read for the entire operation.
      // Keep background contrast/temperature requests out until readback completes.
      guard let channel = uniqueExternalChannel(for: displayID) else {
        return .failure(.unavailable("No unambiguous DDC/CI channel is available."))
      }
      guard let current = readBrightness(channel), current.max > 0,
        current.current <= current.max
      else { return .failure(.unavailable(readFailure(channel))) }
      let raw = UInt16((percent / 100 * Double(current.max)).rounded())
      if raw == current.current {
        return .success(
          .init(
            source: .ddc,
            percent: Double(current.current) / Double(current.max) * 100,
            isAdjustable: true, unavailableReason: nil))
      }
      guard writeBrightness(channel, raw: raw) else {
        return .failure(.unavailable(readFailure(channel)))
      }
      for attempt in 0..<4 {
        if attempt > 0 { Thread.sleep(forTimeInterval: 0.15) }
        let after = status(channel: channel)
        if after.isAdjustable, let measured = after.percent, abs(measured - percent) <= 3 {
          return .success(after)
        }
        if !after.isAdjustable {
          return .failure(.unavailable(after.unavailableReason ?? "DDC readback is unavailable."))
        }
      }
      return .failure(.verificationFailed)
    }
  }

  private static func readFailure(_ channel: DisplayDDCChannel) -> String {
    if let code = channel.lastIOError {
      return String(
        format: "The monitor did not respond to DDC/CI (I/O 0x%08X). ",
        UInt32(bitPattern: code))
        + "DDC requests are paused briefly. Check the display connection before retrying."
    }
    return "The monitor did not return a valid DDC/CI brightness value."
  }

  /// A proxy cannot safely be assigned by enumeration order when multiple external
  /// displays are attached. This conservative P1 path only pairs one external to one proxy.
  static func uniqueExternalChannel(for id: CGDirectDisplayID) -> DisplayDDCChannel? {
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
    var channels: [DisplayDDCChannel] = []
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
          channels.append(DisplayDDCChannel(service))
        }
      }
      IOObjectRelease(entry)
      entry = IOIteratorNext(iterator)
    }
    return channels.count == 1 ? channels[0] : nil
  }

  static func readVCP(_ code: UInt8, channel: DisplayDDCChannel) -> (current: UInt16, max: UInt16)?
  {
    return requests.transaction {
      for attempt in 0..<2 {
        let started = ProcessInfo.processInfo.systemUptime
        if let value = readVCPOnce(code, channel: channel) { return value }
        // A blocked I2C call already waited for the driver timeout. Repeating it
        // immediately keeps every queued slider operation waiting behind it.
        if channel.lastIOError != nil || ProcessInfo.processInfo.systemUptime - started >= 3 {
          break
        }
        if attempt == 0 { Thread.sleep(forTimeInterval: 0.08) }
      }
      return nil
    }
  }

  private static func readVCPOnce(
    _ code: UInt8, channel: DisplayDDCChannel
  ) -> (current: UInt16, max: UInt16)? {
    var request: [UInt8] = [0x82, 0x01, code]
    request.append(request.reduce(UInt8(0x6E ^ 0x51), ^))
    let writeResult = requests.perform {
      IOAVServiceWriteI2C(
        channel.service, 0x37, 0x51, &request, UInt32(request.count))
    }
    channel.lastIOError = writeResult == kIOReturnSuccess ? nil : writeResult
    guard writeResult == kIOReturnSuccess else { return nil }
    var reply = [UInt8](repeating: 0, count: 12)
    let readResult = requests.perform {
      IOAVServiceReadI2C(channel.service, 0x37, 0x51, &reply, UInt32(reply.count))
    }
    channel.lastIOError = readResult == kIOReturnSuccess ? nil : readResult
    guard
      readResult == kIOReturnSuccess,
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

  static func writeVCP(_ code: UInt8, channel: DisplayDDCChannel, raw: UInt16) -> Bool {
    return requests.transaction {
      var request: [UInt8] = [0x84, 0x03, code, UInt8(raw >> 8), UInt8(raw & 0xFF)]
      request.append(request.reduce(UInt8(0x6E ^ 0x51), ^))
      let result = requests.perform {
        IOAVServiceWriteI2C(channel.service, 0x37, 0x51, &request, UInt32(request.count))
      }
      channel.lastIOError = result == kIOReturnSuccess ? nil : result
      return result == kIOReturnSuccess
    }
  }

  private static func readBrightness(_ channel: DisplayDDCChannel) -> (
    current: UInt16, max: UInt16
  )? {
    readVCP(0x10, channel: channel)
  }

  private static func writeBrightness(_ channel: DisplayDDCChannel, raw: UInt16) -> Bool {
    writeVCP(0x10, channel: channel, raw: raw)
  }
}
