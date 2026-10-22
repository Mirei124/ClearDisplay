import CoreGraphics
import Foundation

struct ConnectionColorModeOption: Identifiable, Hashable {
  let id: UInt32
  let bitsPerComponent: UInt32
  let pixelEncodingRaw: UInt32
  let dynamicRangeRaw: UInt32
  let eotfRaw: UInt32
}

/// A CGS mode's `depth` field is an opaque mode attribute. It is not the
/// DisplayPort/HDMI bits per color component shown by BetterDisplay.
struct DisplayColorModeEvidence: Identifiable, Hashable {
  let id: UInt32
  let rawCGSDepth: UInt32
  let isCurrent: Bool
  let matchingModeIDs: [UInt32]

  // No supported API used here proves these signal properties. Callers must
  // leave them absent instead of labelling a framebuffer depth as bit depth.
  var bitsPerComponent: Int? { nil }
  var encoding: String? { nil }
  var chromaSubsampling: String? { nil }
  var dynamicRange: String? { nil }
}

enum DisplayColorModeService {
  /// Color elements reported by the active IOMobileFramebuffer timing. `Depth`
  /// is the physical connection's bits per component; numeric encoding and
  /// transfer-function tags remain raw until their meanings are validated.
  static func connectionElements(displayID: CGDirectDisplayID) -> [ConnectionColorModeOption] {
    let count = HDEnumerateColorElements(displayID, nil, 0)
    guard count > 0 else { return [] }
    var elements = [HDColorElement](repeating: HDColorElement(), count: Int(count))
    let actual = HDEnumerateColorElements(displayID, &elements, count)
    return elements.prefix(Int(min(count, actual))).map {
      ConnectionColorModeOption(
        id: $0.elementID,
        bitsPerComponent: $0.bitsPerComponent,
        pixelEncodingRaw: $0.pixelEncodingRaw,
        dynamicRangeRaw: $0.dynamicRangeRaw,
        eotfRaw: $0.eotfRaw
      )
    }
  }

  /// Reports only CGS mode variants at the current geometry, density and
  /// refresh rate. This is diagnostic evidence, not a user-selectable list.
  static func inspect(displayID: CGDirectDisplayID) -> [DisplayColorModeEvidence] {
    let modes = DisplayModeCatalog.modes(for: displayID)
    guard let current = modes.first(where: \.isCurrent) else { return [] }
    let variants = modes.filter {
      $0.logicalWidth == current.logicalWidth && $0.logicalHeight == current.logicalHeight
        && $0.pixelWidth == current.pixelWidth && $0.pixelHeight == current.pixelHeight
        && abs($0.refreshRateHz - current.refreshRateHz) < 0.5
    }
    let groups = Dictionary(grouping: variants, by: \.colorDepth)
    return groups.keys.sorted().map { rawDepth in
      let group = groups[rawDepth] ?? []
      return DisplayColorModeEvidence(
        id: rawDepth,
        rawCGSDepth: rawDepth,
        isCurrent: group.contains(where: \.isCurrent),
        matchingModeIDs: group.map(\.id).sorted()
      )
    }
  }
}
