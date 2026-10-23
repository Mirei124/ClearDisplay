import CoreGraphics
import Foundation

/// DDC controls use monitor readback. Software transfer controls are session-local;
/// their readback confirms coefficients, not the perceived image or panel state.
enum ImageAdjustmentSource { case ddc, softwareTransfer }

struct ImageAdjustmentStatus {
  let source: ImageAdjustmentSource
  let value: Double?
  let isAdjustable: Bool
  let reason: String?
}

enum ImageAdjustmentError: Error, LocalizedError {
  case invalidValue
  case unavailable(String)
  case writeFailed, verificationFailed

  var errorDescription: String? {
    switch self {
    case .invalidValue: "Value is outside the supported range."
    case .unavailable(let reason): reason
    case .writeFailed: "The display rejected the image adjustment."
    case .verificationFailed: "The image adjustment could not be verified."
    }
  }
}

/// Call DDC methods off the main thread. DDC pairing intentionally fails closed
/// when more than one external display is connected.
enum DisplayImageAdjustmentService {
  /// MCCS VCP 0x04 is a write-only factory reset. The monitor chooses the
  /// resulting values; there is no DDC value to compare against beforehand.
  static func restoreFactoryDefaults(for id: CGDirectDisplayID)
    -> Result<Void, ImageAdjustmentError>
  {
    guard CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0,
      let channel = DisplayBrightnessService.uniqueExternalChannel(for: id)
    else { return .failure(.unavailable("No unambiguous DDC monitor is available.")) }
    guard DisplayBrightnessService.writeVCP(0x04, channel: channel, raw: 1) else {
      return .failure(.writeFailed)
    }
    // The command is write-only. Wait for the monitor to apply it, then require
    // a fresh DDC response before reporting that the resulting state is readable.
    Thread.sleep(forTimeInterval: 0.5)
    for _ in 0..<4 {
      if DisplayBrightnessService.readVCP(0x10, channel: channel) != nil
        || DisplayBrightnessService.readVCP(0x12, channel: channel) != nil
        || DisplayBrightnessService.readVCP(0x14, channel: channel) != nil
      {
        return .success(())
      }
      Thread.sleep(forTimeInterval: 0.25)
    }
    return .failure(
      .unavailable(
        "Factory reset was sent, but the monitor did not return a readable DDC value."))
  }

  static func contrast(for id: CGDirectDisplayID) -> ImageAdjustmentStatus {
    guard CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0,
      let channel = DisplayBrightnessService.uniqueExternalChannel(for: id),
      let value = DisplayBrightnessService.readVCP(0x12, channel: channel),
      value.max > 0, value.current <= value.max
    else {
      return .init(
        source: .ddc, value: nil, isAdjustable: false,
        reason: "No readable, unambiguous DDC contrast control is available.")
    }
    return .init(
      source: .ddc, value: Double(value.current) * 100 / Double(value.max),
      isAdjustable: true, reason: nil)
  }

  static func setContrast(_ percent: Double, for id: CGDirectDisplayID)
    -> Result<ImageAdjustmentStatus, ImageAdjustmentError>
  {
    guard percent.isFinite, (0...100).contains(percent) else { return .failure(.invalidValue) }
    guard contrast(for: id).isAdjustable,
      let channel = DisplayBrightnessService.uniqueExternalChannel(for: id),
      let before = DisplayBrightnessService.readVCP(0x12, channel: channel), before.max > 0
    else { return .failure(.unavailable("DDC contrast is unavailable.")) }
    let raw = UInt16((percent * Double(before.max) / 100).rounded())
    guard DisplayBrightnessService.writeVCP(0x12, channel: channel, raw: raw) else {
      return .failure(.writeFailed)
    }
    for _ in 0..<4 {
      Thread.sleep(forTimeInterval: 0.15)
      let after = contrast(for: id)
      if let measured = after.value, abs(measured - percent) <= 3 {
        return .success(after)
      }
    }
    return .failure(.verificationFailed)
  }

  /// MCCS color-temperature preset VCP 0x14. Only these standard presets are
  /// offered, and only after a successful monitor response.
  static let hardwareTemperaturePresets: [UInt16: Int] = [
    0x04: 5000, 0x05: 6500,
    0x06: 7500, 0x08: 9300,
  ]

  static func hardwareTemperature(for id: CGDirectDisplayID) -> ImageAdjustmentStatus {
    guard CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0,
      let channel = DisplayBrightnessService.uniqueExternalChannel(for: id),
      let value = DisplayBrightnessService.readVCP(0x14, channel: channel),
      let kelvin = hardwareTemperaturePresets[value.current]
    else {
      return .init(
        source: .ddc, value: nil, isAdjustable: false,
        reason: "No supported DDC color-temperature preset is readable.")
    }
    return .init(source: .ddc, value: Double(kelvin), isAdjustable: true, reason: nil)
  }

  static func setHardwareTemperature(_ kelvin: Int, for id: CGDirectDisplayID)
    -> Result<ImageAdjustmentStatus, ImageAdjustmentError>
  {
    guard let preset = hardwareTemperaturePresets.first(where: { $0.value == kelvin })?.key else {
      return .failure(.invalidValue)
    }
    guard hardwareTemperature(for: id).isAdjustable,
      let channel = DisplayBrightnessService.uniqueExternalChannel(for: id)
    else { return .failure(.unavailable("DDC color temperature is unavailable.")) }
    guard DisplayBrightnessService.writeVCP(0x14, channel: channel, raw: preset) else {
      return .failure(.writeFailed)
    }
    for _ in 0..<4 {
      Thread.sleep(forTimeInterval: 0.15)
      let after = hardwareTemperature(for: id)
      if after.value == Double(kelvin) { return .success(after) }
    }
    return .failure(.verificationFailed)
  }
}

/// Serial access required. Captures the initial formula per display for a
/// reversible session adjustment. Gamma and temperature share one transfer.
/// Call restoreAll() on normal quit. A crash bypasses deinit and may leave
/// changed transfer tables active; automatic process-exit restoration is not
/// documented by CoreGraphics and has not been verified on target hardware.
final class DisplaySoftwareTransferService {
  private struct Formula {
    var min: (Float, Float, Float)
    var max: (Float, Float, Float)
    var gamma: (Float, Float, Float)
  }
  private var original: [CGDirectDisplayID: Formula] = [:]
  private var settings: [CGDirectDisplayID: (gamma: Double, kelvin: Int)] = [:]
  private var ownerUUID: [CGDirectDisplayID: String] = [:]
  private var pending: [String: [Float]]
  private let recoveryURL: URL
  private var recoveryFileUnreadable: Bool

  init(recoveryURL: URL? = nil) {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    self.recoveryURL =
      recoveryURL
      ?? base
      .appendingPathComponent("HiDPI", isDirectory: true)
      .appendingPathComponent("transfer-recovery.json")
    if let data = try? Data(contentsOf: self.recoveryURL),
      let decoded = try? JSONDecoder().decode([String: [Float]].self, from: data)
    {
      pending = decoded
      recoveryFileUnreadable = false
    } else {
      // A corrupt or unreadable recovery file must not be overwritten by a new adjustment.
      pending = [:]
      recoveryFileUnreadable = FileManager.default.fileExists(atPath: self.recoveryURL.path)
    }
  }

  /// The owner must call this from its normal application-termination path.
  /// This is also a best-effort fallback when the service is released.
  deinit { _ = restoreAll() }

  func status(for id: CGDirectDisplayID) -> (gamma: Double?, kelvin: Int?, reason: String?) {
    guard CGDisplayIsOnline(id) != 0, CGDisplayGammaTableCapacity(id) > 0 else {
      return (nil, nil, "Software transfer is unavailable for this display.")
    }
    guard let uuid = displayUUID(id), ownerUUID[id] == uuid, let setting = settings[id] else {
      return (nil, nil, "No app-managed transfer is active.")
    }
    return (setting.gamma, setting.kelvin, nil)
  }

  func set(gamma: Double, kelvin: Int, for id: CGDirectDisplayID)
    -> Result<Void, ImageAdjustmentError>
  {
    guard gamma.isFinite, (0.5...2.0).contains(gamma), (4000...10000).contains(kelvin) else {
      return .failure(.invalidValue)
    }
    guard CGDisplayIsOnline(id) != 0, CGDisplayGammaTableCapacity(id) > 0 else {
      return .failure(.unavailable("Software transfer is unavailable for this display."))
    }
    guard let uuid = displayUUID(id) else {
      return .failure(.unavailable("The display has no stable UUID for crash recovery."))
    }
    forgetReassignedID(id, currentUUID: uuid)
    guard !recoveryFileUnreadable else {
      return .failure(
        .unavailable("The recovery file cannot be decoded; no new adjustment is safe."))
    }
    guard pending[uuid] == nil || original[id] != nil else {
      return .failure(
        .unavailable("A pending transfer must be recovered before changing this display."))
    }
    guard let baseline = original[id] ?? readFormula(id) else {
      return .failure(.unavailable("The current transfer formula cannot be read safely."))
    }
    if original[id] == nil {
      pending[uuid] = values(baseline)
      guard savePending() else {
        pending.removeValue(forKey: uuid)
        return .failure(.unavailable("Could not persist the recovery snapshot."))
      }
    }
    // A warm/cool white-point approximation; preserves baseline channel minima.
    let warmth = Double(kelvin - 6500) / 3500
    let red = Float(max(0.72, 1 - max(0, warmth) * 0.20))
    let blue = Float(max(0.72, 1 + min(0, warmth) * 0.20))
    let target = Formula(
      min: baseline.min,
      max: (baseline.max.0 * red, baseline.max.1, baseline.max.2 * blue),
      gamma: (
        baseline.gamma.0 * Float(gamma), baseline.gamma.1 * Float(gamma),
        baseline.gamma.2 * Float(gamma)
      ))
    guard writeFormula(target, id: id) else { return .failure(.writeFailed) }
    guard let measured = readFormula(id), approximatelyEqual(target, measured) else {
      _ = writeFormula(baseline, id: id)
      return .failure(.verificationFailed)
    }
    original[id] = baseline
    settings[id] = (gamma, kelvin)
    ownerUUID[id] = uuid
    return .success(())
  }

  func reset(for id: CGDirectDisplayID) -> Result<Void, ImageAdjustmentError> {
    guard let uuid = displayUUID(id) else {
      return .failure(.unavailable("The display UUID is unavailable."))
    }
    // A numeric display ID can be assigned to a different physical screen.
    // Keep the former screen's recovery record and never apply its formula here.
    forgetReassignedID(id, currentUUID: uuid)
    guard let baseline = original[id] ?? pending[uuid].flatMap(formula) else {
      return .success(())
    }
    guard CGDisplayIsOnline(id) != 0, writeFormula(baseline, id: id),
      let measured = readFormula(id), approximatelyEqual(baseline, measured)
    else { return .failure(.verificationFailed) }
    original.removeValue(forKey: id)
    settings.removeValue(forKey: id)
    ownerUUID.removeValue(forKey: id)
    pending.removeValue(forKey: uuid)
    guard savePending() else {
      pending[uuid] = values(baseline)
      return .failure(.unavailable("Restored, but could not clear the recovery snapshot."))
    }
    return .success(())
  }

  /// Restore every display changed by this service, continuing after failures.
  /// Call during normal quit and before replacing this service instance.
  @discardableResult
  func restoreAll() -> [CGDirectDisplayID: ImageAdjustmentError] {
    var failures: [CGDirectDisplayID: ImageAdjustmentError] = [:]
    let recoverable = onlineDisplayIDs().filter {
      guard let uuid = displayUUID($0) else { return false }
      return pending[uuid] != nil
    }
    for id in Set(original.keys).union(recoverable) {
      if case .failure(let error) = reset(for: id) { failures[id] = error }
    }
    return failures
  }

  /// Retry snapshots after launch or a display-reconnection callback. Offline
  /// displays retain their recovery record until they appear again.
  @discardableResult
  func recoverPending() -> [String: ImageAdjustmentError] {
    var failures: [String: ImageAdjustmentError] = [:]
    for id in onlineDisplayIDs() {
      guard let uuid = displayUUID(id), pending[uuid] != nil else { continue }
      forgetReassignedID(id, currentUUID: uuid)
      // A pending file also backs an active setting in this process. Display
      // reconfiguration must not undo that setting; only stale records recover.
      guard original[id] == nil, settings[id] == nil else { continue }
      if case .failure(let error) = reset(for: id) { failures[uuid] = error }
    }
    return failures
  }

  var pendingRecoveryUUIDs: [String] { pending.keys.sorted() }

  private func forgetReassignedID(_ id: CGDirectDisplayID, currentUUID: String) {
    guard let owner = ownerUUID[id], owner != currentUUID else { return }
    original.removeValue(forKey: id)
    settings.removeValue(forKey: id)
    ownerUUID.removeValue(forKey: id)
    // The old UUID's durable snapshot remains pending for its eventual return.
  }

  private func savePending() -> Bool {
    do {
      if pending.isEmpty {
        if FileManager.default.fileExists(atPath: recoveryURL.path) {
          try FileManager.default.removeItem(at: recoveryURL)
        }
        return true
      }
      try FileManager.default.createDirectory(
        at: recoveryURL.deletingLastPathComponent(),
        withIntermediateDirectories: true)
      let data = try JSONEncoder().encode(pending)
      try data.write(to: recoveryURL, options: .atomic)
      return true
    } catch { return false }
  }

  private func values(_ f: Formula) -> [Float] {
    [
      f.min.0, f.max.0, f.gamma.0, f.min.1, f.max.1, f.gamma.1,
      f.min.2, f.max.2, f.gamma.2,
    ]
  }

  private func formula(_ v: [Float]) -> Formula? {
    guard v.count == 9, v.allSatisfy({ $0.isFinite }),
      v[2] > 0, v[5] > 0, v[8] > 0
    else { return nil }
    return Formula(
      min: (v[0], v[3], v[6]), max: (v[1], v[4], v[7]),
      gamma: (v[2], v[5], v[8]))
  }

  private func onlineDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
  }

  private func displayUUID(_ id: CGDirectDisplayID) -> String? {
    typealias UUIDFunction = @convention(c) (UInt32) -> UnsafeRawPointer?
    guard
      let library = dlopen("/System/Library/Frameworks/ColorSync.framework/ColorSync", RTLD_LAZY),
      let symbol = dlsym(library, "CGDisplayCreateUUIDFromDisplayID")
    else { return nil }
    defer { dlclose(library) }
    let function = unsafeBitCast(symbol, to: UUIDFunction.self)
    guard let pointer = function(id) else { return nil }
    let uuid = Unmanaged<CFUUID>.fromOpaque(pointer).takeRetainedValue()
    return CFUUIDCreateString(kCFAllocatorDefault, uuid) as String
  }

  private func readFormula(_ id: CGDirectDisplayID) -> Formula? {
    var r0: Float = 0
    var r1: Float = 0
    var rg: Float = 0
    var g0: Float = 0
    var g1: Float = 0
    var gg: Float = 0
    var b0: Float = 0
    var b1: Float = 0
    var bg: Float = 0
    guard
      CGGetDisplayTransferByFormula(
        id, &r0, &r1, &rg, &g0, &g1, &gg,
        &b0, &b1, &bg) == .success,
      [r0, r1, rg, g0, g1, gg, b0, b1, bg].allSatisfy({ $0.isFinite }),
      rg > 0, gg > 0, bg > 0
    else { return nil }
    return Formula(min: (r0, g0, b0), max: (r1, g1, b1), gamma: (rg, gg, bg))
  }

  private func writeFormula(_ f: Formula, id: CGDirectDisplayID) -> Bool {
    CGSetDisplayTransferByFormula(
      id, f.min.0, f.max.0, f.gamma.0,
      f.min.1, f.max.1, f.gamma.1,
      f.min.2, f.max.2, f.gamma.2) == .success
  }

  private func approximatelyEqual(_ a: Formula, _ b: Formula) -> Bool {
    let av = [
      a.min.0, a.min.1, a.min.2, a.max.0, a.max.1, a.max.2,
      a.gamma.0, a.gamma.1, a.gamma.2,
    ]
    let bv = [
      b.min.0, b.min.1, b.min.2, b.max.0, b.max.1, b.max.2,
      b.gamma.0, b.gamma.1, b.gamma.2,
    ]
    return zip(av, bv).allSatisfy { abs($0 - $1) < 0.02 }
  }
}
