import ColorSync
import CoreGraphics
import Foundation

struct DisconnectedDisplay: Codable, Identifiable, Equatable {
  let id: String  // CGDisplay UUID; the numeric ID can change after reconnect.
  var lastDisplayID: CGDirectDisplayID
  var name: String
  var isBuiltin: Bool
}

enum DisplayConnectionError: LocalizedError {
  case unsupported
  case displayGone
  case lastDisplay
  case beginFailed
  case configureFailed
  case commitFailed
  case verificationFailed
  case unknown

  var errorDescription: String? {
    switch self {
    case .unsupported: "Physical display control is unavailable on this Mac."
    case .displayGone: "The display is no longer attached."
    case .lastDisplay: "Disconnecting this display would leave no active physical screen."
    case .beginFailed, .configureFailed, .commitFailed:
      "macOS could not change the display connection."
    case .verificationFailed:
      "The display change could not be verified. Refresh the display list before trying again."
    case .unknown: "An unknown display connection error occurred."
    }
  }
}

/// Serializes connection transactions so two requests cannot both pass the last-screen guard.
/// The caller should reflect `disconnected` in its menu: disabled screens disappear from
/// CoreGraphics's online list, but retain a SkyLight ID and a stable UUID for reconnect.
actor DisplayConnectionService {
  static let shared = DisplayConnectionService()
  private let recordKey = "HiDPIApp.disconnectedPhysicalDisplays"
  private var records: [DisconnectedDisplay]

  private init() {
    let data = UserDefaults.standard.data(forKey: recordKey)
    records = data.flatMap { try? JSONDecoder().decode([DisconnectedDisplay].self, from: $0) } ?? []
  }

  var isSupported: Bool { HDConnectionSupported() }

  func disconnected() -> [DisconnectedDisplay] {
    reconcile()
    return records
  }

  func disconnect(id: CGDirectDisplayID, name: String, isBuiltin: Bool) throws {
    guard HDConnectionSupported() else { throw DisplayConnectionError.unsupported }
    guard let uuid = Self.uuid(for: id) else { throw DisplayConnectionError.displayGone }
    let result = HDSetDisplayEnabled(id, false)
    guard result == HDConnectionOK else { throw Self.error(for: result) }
    records.removeAll { $0.id == uuid }
    records.append(
      DisconnectedDisplay(id: uuid, lastDisplayID: id, name: name, isBuiltin: isBuiltin))
    persist()
  }

  func reconnect(uuid: String) throws {
    guard HDConnectionSupported() else { throw DisplayConnectionError.unsupported }
    reconcile()
    guard let record = records.first(where: { $0.id == uuid }) else {
      throw DisplayConnectionError.displayGone
    }
    let ids = Self.allIDs()
    let id = Self.resolveID(for: record, among: ids)
    guard let id else { throw DisplayConnectionError.displayGone }
    let result = HDSetDisplayEnabled(id, true)
    guard result == HDConnectionOK else { throw Self.error(for: result) }
    records.removeAll { $0.id == uuid }
    persist()
  }

  private func reconcile() {
    let ids = Self.allIDs()
    records = records.compactMap { record in
      // UUID lookup may return nil while a display is disabled. Its SkyLight ID
      // remains available, so keep the saved record until it truly disappears.
      guard let id = Self.resolveID(for: record, among: ids) else {
        // A temporary enumeration gap must not erase our only reconnect handle.
        return record
      }
      guard !HDDisplayIsEnabled(id) else { return nil }
      var updated = record
      updated.lastDisplayID = id
      return updated
    }
    persist()
  }

  private func persist() {
    if let data = try? JSONEncoder().encode(records) {
      UserDefaults.standard.set(data, forKey: recordKey)
    }
  }

  private static func allIDs() -> [CGDirectDisplayID] {
    let count = HDAllDisplayIDs(nil, 0)
    guard count > 0, count <= 256 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    let actual = HDAllDisplayIDs(&ids, count)
    return Array(ids.prefix(Int(min(count, actual))))
  }

  private static func resolveID(
    for record: DisconnectedDisplay, among ids: [CGDirectDisplayID]
  ) -> CGDirectDisplayID? {
    if let match = ids.first(where: { uuid(for: $0) == record.id }) { return match }
    guard ids.contains(record.lastDisplayID) else { return nil }
    // Disabled displays can lose their UUID in CoreGraphics. A readable but different
    // UUID means the numeric ID was reused and must never be used for recovery.
    let observedUUID = uuid(for: record.lastDisplayID)
    return observedUUID == nil || observedUUID == record.id ? record.lastDisplayID : nil
  }

  private static func uuid(for id: CGDirectDisplayID) -> String? {
    guard let raw = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
    return CFUUIDCreateString(nil, raw.takeRetainedValue()) as String
  }

  private static func error(for result: HDConnectionResult) -> DisplayConnectionError {
    switch result {
    case HDConnectionUnsupported: .unsupported
    case HDConnectionDisplayGone: .displayGone
    case HDConnectionLastDisplay: .lastDisplay
    case HDConnectionBeginFailed: .beginFailed
    case HDConnectionConfigureFailed: .configureFailed
    case HDConnectionCommitFailed: .commitFailed
    case HDConnectionVerificationFailed: .verificationFailed
    default: .unknown
    }
  }
}
