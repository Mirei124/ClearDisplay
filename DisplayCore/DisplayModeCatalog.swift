import CoreGraphics
import Foundation

struct DisplayModeOption: Identifiable, Hashable {
  let id: UInt32
  let logicalWidth: UInt32
  let logicalHeight: UInt32
  let pixelWidth: UInt32
  let pixelHeight: UInt32
  let refreshRateHz: Double
  let colorDepth: UInt32
  let isHiDPI: Bool
  let isCurrent: Bool
  let isNative: Bool
  let isSelectable: Bool

  var resolutionKey: ResolutionKey {
    ResolutionKey(width: logicalWidth, height: logicalHeight, isHiDPI: isHiDPI)
  }
}

struct ResolutionKey: Hashable, Comparable {
  let width: UInt32
  let height: UInt32
  let isHiDPI: Bool

  static func < (lhs: Self, rhs: Self) -> Bool {
    let lhsArea = UInt64(lhs.width) * UInt64(lhs.height)
    let rhsArea = UInt64(rhs.width) * UInt64(rhs.height)
    if lhsArea != rhsArea { return lhsArea > rhsArea }
    if lhs.width != rhs.width { return lhs.width > rhs.width }
    if lhs.height != rhs.height { return lhs.height > rhs.height }
    return lhs.isHiDPI && !rhs.isHiDPI
  }
}

enum DisplayModeApplyError: Error, LocalizedError {
  case displayGone, modeGone, unsafeColorChange, beginFailed
  case configureFailed, commitFailed, readbackFailed

  var errorDescription: String? {
    switch self {
    case .displayGone: "Display is no longer connected."
    case .modeGone: "Display mode is no longer available."
    case .unsafeColorChange: "Mode would change the current color depth or type."
    case .beginFailed: "Could not begin display configuration."
    case .configureFailed: "macOS rejected the display mode."
    case .commitFailed: "Could not commit display configuration."
    case .readbackFailed: "Could not verify the new display mode."
    }
  }
}

enum DisplayModeCatalog {
  static func modes(for displayID: CGDirectDisplayID) -> [DisplayModeOption] {
    let count = HDEnumerateModes(displayID, nil, 0)
    guard count > 0 else { return [] }
    var raw = [HDModeOption](repeating: HDModeOption(), count: Int(count))
    let actual = HDEnumerateModes(displayID, &raw, count)
    return raw.prefix(Int(min(count, actual))).map {
      DisplayModeOption(
        id: $0.modeID,
        logicalWidth: $0.logicalWidth,
        logicalHeight: $0.logicalHeight,
        pixelWidth: $0.pixelWidth,
        pixelHeight: $0.pixelHeight,
        refreshRateHz: Double($0.refreshMilliHz) / 1000,
        colorDepth: $0.depth,
        isHiDPI: $0.isHiDPI,
        isCurrent: $0.isCurrent,
        isNative: $0.isNative,
        isSelectable: $0.isSelectable
      )
    }
  }

  static func desktopResolutions(_ modes: [DisplayModeOption], hiDPI: Bool) -> [ResolutionKey] {
    Array(Set(modes.filter { $0.isSelectable && $0.isHiDPI == hiDPI }.map(\.resolutionKey)))
      .sorted()
  }

  /// ClearDisplay's contextual recommendation keeps the current desktop size
  /// while using HiDPI. This is an app recommendation, not a macOS default flag.
  static func recommendedResolution(_ modes: [DisplayModeOption]) -> ResolutionKey? {
    guard let current = modes.first(where: \.isCurrent) else { return nil }
    return modes.first {
      $0.isSelectable && $0.isHiDPI
        && $0.logicalWidth == current.logicalWidth
        && $0.logicalHeight == current.logicalHeight
        && abs($0.refreshRateHz - current.refreshRateHz) < 0.01
    }?.resolutionKey
  }

  static func refreshChoices(for key: ResolutionKey, in modes: [DisplayModeOption])
    -> [DisplayModeOption]
  {
    modes.filter { $0.isSelectable && $0.resolutionKey == key }
      .sorted { $0.refreshRateHz > $1.refreshRateHz }
  }

  static func apply(modeID: UInt32, to displayID: CGDirectDisplayID) async throws {
    let result = await Task.detached(priority: .userInitiated) {
      HDApplyMode(displayID, modeID)
    }.value
    switch result {
    case HDModeApplyOK: return
    case HDModeApplyDisplayGone: throw DisplayModeApplyError.displayGone
    case HDModeApplyModeGone: throw DisplayModeApplyError.modeGone
    case HDModeApplyUnsafeColorChange: throw DisplayModeApplyError.unsafeColorChange
    case HDModeApplyBeginFailed: throw DisplayModeApplyError.beginFailed
    case HDModeApplyConfigureFailed: throw DisplayModeApplyError.configureFailed
    case HDModeApplyCommitFailed: throw DisplayModeApplyError.commitFailed
    default: throw DisplayModeApplyError.readbackFailed
    }
  }
}
