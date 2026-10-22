import CoreGraphics
import Darwin
import Foundation

/// Physical display rotation and mirror relationships. Callers should supply only physical IDs;
/// CoreGraphics does not expose a reliable public virtual-display classification.
enum DisplayTopologyService {
  enum TopologyError: LocalizedError {
    case displayOffline
    case sameDisplay
    case sourceIsMirrored
    case unsupportedRotation
    case rotationAPIUnavailable
    case configurationFailed(CGError)
    case verificationFailed

    var errorDescription: String? {
      switch self {
      case .displayOffline: return "The display is no longer connected."
      case .sameDisplay: return "A display cannot mirror itself."
      case .sourceIsMirrored: return "Choose a display with its own desktop as the mirror source."
      case .unsupportedRotation: return "Choose 0°, 90°, 180°, or 270°."
      case .rotationAPIUnavailable: return "Display rotation is unavailable on this macOS version."
      case .configurationFailed(let error):
        return "macOS rejected the display configuration (\(error.rawValue))."
      case .verificationFailed: return "The display change could not be verified."
      }
    }
  }

  struct Relationship: Equatable {
    let displayID: CGDirectDisplayID
    let mirrorsDisplayID: CGDirectDisplayID?
    let mirroredByDisplayIDs: [CGDirectDisplayID]
    let rotationDegrees: Int
  }

  /// These are selectable angles, not a hardware capability guarantee. macOS decides whether
  /// a particular panel accepts a rotation when `setRotation` is called.
  static let candidateRotations = [0, 90, 180, 270]

  static func onlineDisplayIDs() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
  }

  static func relationship(for displayID: CGDirectDisplayID) -> Relationship? {
    let ids = onlineDisplayIDs()
    guard ids.contains(displayID) else { return nil }
    let source = CGDisplayMirrorsDisplay(displayID)
    return Relationship(
      displayID: displayID,
      mirrorsDisplayID: source == kCGNullDirectDisplay ? nil : source,
      mirroredByDisplayIDs: ids.filter {
        $0 != displayID && CGDisplayMirrorsDisplay($0) == displayID
      },
      rotationDegrees: normalizedRotation(CGDisplayRotation(displayID))
    )
  }

  /// Makes `target` mirror `source`. The source keeps its desktop; the target becomes a clone.
  static func mirror(source: CGDirectDisplayID, target: CGDirectDisplayID) throws {
    guard source != target else { throw TopologyError.sameDisplay }
    let ids = onlineDisplayIDs()
    guard ids.contains(source), ids.contains(target) else { throw TopologyError.displayOffline }
    guard CGDisplayMirrorsDisplay(source) == kCGNullDirectDisplay else {
      throw TopologyError.sourceIsMirrored
    }
    try configureMirror(target: target, source: source)
    guard CGDisplayMirrorsDisplay(target) == source else { throw TopologyError.verificationFailed }
  }

  /// Returns a mirror target to its own extended desktop.
  static func extend(displayID: CGDirectDisplayID) throws {
    guard onlineDisplayIDs().contains(displayID) else { throw TopologyError.displayOffline }
    if CGDisplayMirrorsDisplay(displayID) == kCGNullDirectDisplay { return }
    try configureMirror(target: displayID, source: kCGNullDirectDisplay)
    guard CGDisplayMirrorsDisplay(displayID) == kCGNullDirectDisplay else {
      throw TopologyError.verificationFailed
    }
  }

  static func setRotation(_ degrees: Int, for displayID: CGDirectDisplayID) throws {
    guard candidateRotations.contains(degrees) else { throw TopologyError.unsupportedRotation }
    guard onlineDisplayIDs().contains(displayID) else { throw TopologyError.displayOffline }
    guard let symbol = dlsym(rotationLibraryHandle, "SLSSetDisplayRotation") else {
      throw TopologyError.rotationAPIUnavailable
    }
    typealias RotationFunction = @convention(c) (CGDirectDisplayID, Int32) -> CGError
    let rotate = unsafeBitCast(symbol, to: RotationFunction.self)
    let result = rotate(displayID, Int32(degrees))
    guard result == .success else { throw TopologyError.configurationFailed(result) }
    guard normalizedRotation(CGDisplayRotation(displayID)) == degrees else {
      throw TopologyError.verificationFailed
    }
  }

  private static func configureMirror(target: CGDirectDisplayID, source: CGDirectDisplayID)
    throws
  {
    var configuration: CGDisplayConfigRef?
    let begin = CGBeginDisplayConfiguration(&configuration)
    guard begin == .success, let configuration else {
      throw TopologyError.configurationFailed(begin)
    }
    let configured = CGConfigureDisplayMirrorOfDisplay(configuration, target, source)
    guard configured == .success else {
      CGCancelDisplayConfiguration(configuration)
      throw TopologyError.configurationFailed(configured)
    }
    let committed = CGCompleteDisplayConfiguration(configuration, .forSession)
    guard committed == .success else { throw TopologyError.configurationFailed(committed) }
  }

  private static func normalizedRotation(_ degrees: Double) -> Int {
    (Int(degrees.rounded()) % 360 + 360) % 360
  }

  private static let rotationLibraryHandle: UnsafeMutableRawPointer? =
    dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
}
