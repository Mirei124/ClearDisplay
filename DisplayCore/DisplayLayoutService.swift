import CoreGraphics
import Foundation

struct DisplayLayoutItem: Identifiable, Equatable {
  let id: CGDirectDisplayID
  let origin: CGPoint
  let size: CGSize
  let isMain: Bool
  let isBuiltin: Bool

  var frame: CGRect { CGRect(origin: origin, size: size) }
}

struct DisplayLayoutPlan {
  let items: [DisplayLayoutItem]
  let primaryID: CGDirectDisplayID
  let originalItems: [DisplayLayoutItem]
}

enum DisplayLayoutError: LocalizedError {
  case enumeration(CGError)
  case noDisplays
  case staleDisplays
  case mirroredDisplay
  case invalidGeometry
  case overlappingDisplays
  case configuration(CGError)
  case verificationFailed

  var errorDescription: String? {
    switch self {
    case .enumeration(let code): "Could not read the display layout (\(code.rawValue))."
    case .noDisplays: "No active displays were found."
    case .staleDisplays: "The connected displays changed. Refresh the layout and try again."
    case .mirroredDisplay: "End mirroring before changing the display arrangement."
    case .invalidGeometry: "The display arrangement contains invalid positions or sizes."
    case .overlappingDisplays: "Displays cannot overlap in an extended arrangement."
    case .configuration(let code): "macOS could not apply the display layout (\(code.rawValue))."
    case .verificationFailed: "The applied display layout could not be verified."
    }
  }
}

enum DisplayLayoutService {
  static func snapshot() throws -> [DisplayLayoutItem] {
    var count: UInt32 = 0
    var code = CGGetActiveDisplayList(0, nil, &count)
    guard code == .success else { throw DisplayLayoutError.enumeration(code) }
    guard count > 0 else { throw DisplayLayoutError.noDisplays }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    code = CGGetActiveDisplayList(count, &ids, &count)
    guard code == .success else { throw DisplayLayoutError.enumeration(code) }
    return ids.prefix(Int(count)).map { id in
      let bounds = CGDisplayBounds(id)
      return DisplayLayoutItem(
        id: id, origin: bounds.origin, size: bounds.size,
        isMain: CGDisplayIsMain(id) != 0, isBuiltin: CGDisplayIsBuiltin(id) != 0
      )
    }
  }

  /// Keeps the current display sizes and moves their origins. A primary change shifts
  /// every origin by the same amount so the selected display starts at (0, 0).
  static func plan(
    from current: [DisplayLayoutItem],
    proposedOrigins: [CGDirectDisplayID: CGPoint],
    primaryID: CGDirectDisplayID
  ) throws -> DisplayLayoutPlan {
    guard !current.isEmpty else { throw DisplayLayoutError.noDisplays }
    let ids = Set(current.map(\.id))
    guard ids.count == current.count, ids == Set(proposedOrigins.keys), ids.contains(primaryID)
    else { throw DisplayLayoutError.staleDisplays }
    let primaryOrigin = proposedOrigins[primaryID]!
    guard primaryOrigin.x.isFinite, primaryOrigin.y.isFinite else {
      throw DisplayLayoutError.invalidGeometry
    }
    let items = try current.map { item -> DisplayLayoutItem in
      guard let origin = proposedOrigins[item.id], origin.x.isFinite, origin.y.isFinite,
        item.size.width > 0, item.size.height > 0
      else { throw DisplayLayoutError.invalidGeometry }
      let normalized = CGPoint(x: origin.x - primaryOrigin.x, y: origin.y - primaryOrigin.y)
      guard normalized.x.isFinite, normalized.y.isFinite,
        normalized.x >= Double(Int32.min), normalized.x <= Double(Int32.max),
        normalized.y >= Double(Int32.min), normalized.y <= Double(Int32.max)
      else { throw DisplayLayoutError.invalidGeometry }
      return DisplayLayoutItem(
        id: item.id, origin: normalized, size: item.size,
        isMain: item.id == primaryID, isBuiltin: item.isBuiltin
      )
    }
    for first in items.indices {
      for second in items.indices where second > first {
        if items[first].frame.intersects(items[second].frame) {
          throw DisplayLayoutError.overlappingDisplays
        }
      }
    }
    return DisplayLayoutPlan(items: items, primaryID: primaryID, originalItems: current)
  }

  /// Applies one atomic CoreGraphics transaction, then checks the system's actual layout.
  /// Call from a background task; the display configuration APIs may block briefly.
  static func apply(_ plan: DisplayLayoutPlan) throws -> [DisplayLayoutItem] {
    let current = try snapshot()
    guard Set(current.map(\.id)) == Set(plan.items.map(\.id)),
      current.count == plan.items.count,
      current.allSatisfy({ observed in
        guard let original = plan.originalItems.first(where: { $0.id == observed.id }) else {
          return false
        }
        return original.size == observed.size && original.origin == observed.origin
          && original.isMain == observed.isMain
      })
    else { throw DisplayLayoutError.staleDisplays }
    guard current.allSatisfy({ CGDisplayIsInMirrorSet($0.id) == 0 }) else {
      throw DisplayLayoutError.mirroredDisplay
    }
    let validated = try self.plan(
      from: current,
      proposedOrigins: Dictionary(uniqueKeysWithValues: plan.items.map { ($0.id, $0.origin) }),
      primaryID: plan.primaryID
    )
    var configuration: CGDisplayConfigRef?
    var code = CGBeginDisplayConfiguration(&configuration)
    guard code == .success, let configuration else {
      throw DisplayLayoutError.configuration(code)
    }
    for item in validated.items {
      code = CGConfigureDisplayOrigin(
        configuration, item.id, Int32(item.origin.x.rounded()), Int32(item.origin.y.rounded())
      )
      guard code == .success else {
        CGCancelDisplayConfiguration(configuration)
        throw DisplayLayoutError.configuration(code)
      }
    }
    code = CGCompleteDisplayConfiguration(configuration, .permanently)
    guard code == .success else { throw DisplayLayoutError.configuration(code) }
    let actual = try snapshot()
    guard actual.count == validated.items.count,
      actual.first(where: { $0.id == plan.primaryID })?.isMain == true,
      validated.items.allSatisfy({ expected in
        guard let observed = actual.first(where: { $0.id == expected.id }) else { return false }
        return abs(observed.origin.x - expected.origin.x.rounded()) < 1
          && abs(observed.origin.y - expected.origin.y.rounded()) < 1
      })
    else { throw DisplayLayoutError.verificationFailed }
    return actual
  }
}
