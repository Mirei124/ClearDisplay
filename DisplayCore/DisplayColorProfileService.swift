import ColorSync
import CoreGraphics
import Foundation

struct DisplayColorProfile: Identifiable, Hashable {
  let url: URL
  let name: String
  var id: URL { url }
}

struct DisplayColorProfileStatus {
  let profiles: [DisplayColorProfile]
  let currentURL: URL?
  let currentName: String?
}

enum DisplayColorProfileError: Error, LocalizedError {
  case displayGone, invalidProfile, unsupportedProfile, writeFailed, verificationFailed

  var errorDescription: String? {
    switch self {
    case .displayGone: "Display is disconnected."
    case .invalidProfile: "The selected ICC profile is missing or invalid."
    case .unsupportedProfile: "Only RGB monitor or color-space profiles can be assigned."
    case .writeFailed: "macOS rejected the color profile."
    case .verificationFailed: "The color profile change could not be verified."
    }
  }
}

enum DisplayColorProfileService {
  static func status(for displayID: CGDirectDisplayID) -> DisplayColorProfileStatus {
    let uuid = displayUUID(for: displayID)
    let profiles = installedProfiles(for: uuid)
    let currentURL = currentProfileURL(for: displayID)
    let currentName: String? = {
      guard let raw = ColorSyncProfileCreateWithDisplayID(displayID) else { return nil }
      let profile = raw.takeRetainedValue()
      return ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() as String?
    }()
    return .init(profiles: profiles, currentURL: currentURL, currentName: currentName)
  }

  static func installedProfiles(for displayUUID: String?) -> [DisplayColorProfile] {
    let roots = [
      URL(fileURLWithPath: "/Library/ColorSync/Profiles"),
      URL(fileURLWithPath: "/System/Library/ColorSync/Profiles"),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/ColorSync/Profiles"),
    ]
    var found: [DisplayColorProfile] = []
    var seen = Set<URL>()
    for root in roots {
      guard
        let files = FileManager.default.enumerator(
          at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
      else { continue }
      for case let url as URL in files {
        let ext = url.pathExtension.lowercased()
        guard ext == "icc" || ext == "icm" else { continue }
        let path = url.standardizedFileURL
        guard seen.insert(path).inserted else { continue }
        if path.path.contains("/ColorSync/Profiles/Displays/") {
          guard let displayUUID,
            path.lastPathComponent.range(of: displayUUID, options: .caseInsensitive) != nil
          else { continue }
        }
        guard let profile = validatedProfile(at: path) else { continue }
        found.append(profile)
      }
    }
    return found.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  @discardableResult
  static func apply(_ url: URL, to displayID: CGDirectDisplayID) async throws
    -> DisplayColorProfileStatus
  {
    guard CGDisplayIsOnline(displayID) != 0, let uuid = displayUUID(for: displayID),
      let rawUUID = CGDisplayCreateUUIDFromDisplayID(displayID)
    else { throw DisplayColorProfileError.displayGone }
    guard FileManager.default.fileExists(atPath: url.path),
      ColorSyncProfileCreateWithURL(url as CFURL, nil) != nil
    else { throw DisplayColorProfileError.invalidProfile }
    guard let selected = validatedProfile(at: url) else {
      throw DisplayColorProfileError.unsupportedProfile
    }
    guard installedProfiles(for: uuid).contains(where: { $0.url == selected.url }) else {
      throw DisplayColorProfileError.unsupportedProfile
    }
    guard let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
      let defaultID = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue()
    else { throw DisplayColorProfileError.writeFailed }
    guard displayUUID(for: displayID) == uuid else { throw DisplayColorProfileError.displayGone }
    let info: NSDictionary = [defaultID: selected.url as NSURL]
    guard
      ColorSyncDeviceSetCustomProfiles(
        deviceClass, rawUUID.takeRetainedValue(), info as CFDictionary)
    else { throw DisplayColorProfileError.writeFailed }
    for _ in 0..<10 {
      try await Task.sleep(for: .milliseconds(100))
      guard displayUUID(for: displayID) == uuid else { throw DisplayColorProfileError.displayGone }
      let after = status(for: displayID)
      if after.currentURL?.standardizedFileURL == selected.url { return after }
    }
    throw DisplayColorProfileError.verificationFailed
  }

  private static func validatedProfile(at url: URL) -> DisplayColorProfile? {
    guard let raw = ColorSyncProfileCreateWithURL(url as CFURL, nil) else { return nil }
    let profile = raw.takeRetainedValue()
    guard let rawHeader = ColorSyncProfileCopyHeader(profile) else { return nil }
    let header = rawHeader.takeRetainedValue() as Data
    guard header.count >= 20 else { return nil }
    // ColorSync's header data stores these 4CC fields in host byte order.
    let deviceClass = String(bytes: header[12..<16].reversed(), encoding: .ascii)
    let colorSpace = String(bytes: header[16..<20].reversed(), encoding: .ascii)
    guard let deviceClass, let colorSpace,
      ["mntr", "spac"].contains(deviceClass), colorSpace == "RGB "
    else { return nil }
    let name = ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() as String?
    return .init(
      url: url.standardizedFileURL, name: name ?? url.deletingPathExtension().lastPathComponent)
  }

  private static func displayUUID(for id: CGDirectDisplayID) -> String? {
    guard CGDisplayIsOnline(id) != 0, let raw = CGDisplayCreateUUIDFromDisplayID(id),
      let string = CFUUIDCreateString(nil, raw.takeRetainedValue())
    else { return nil }
    return string as String
  }

  private static func currentProfileURL(for id: CGDirectDisplayID) -> URL? {
    guard let rawUUID = CGDisplayCreateUUIDFromDisplayID(id),
      let deviceClass = kColorSyncDisplayDeviceClass?.takeUnretainedValue(),
      let defaultID = kColorSyncDeviceDefaultProfileID?.takeUnretainedValue(),
      let rawInfo = ColorSyncDeviceCopyDeviceInfo(deviceClass, rawUUID.takeRetainedValue())
    else { return nil }
    let info = rawInfo.takeRetainedValue() as NSDictionary
    guard let factory = info["FactoryProfiles"] as? NSDictionary,
      let mode = factory[defaultID]
    else { return nil }
    let value =
      (info["CustomProfiles"] as? NSDictionary)?[mode]
      ?? (factory[mode] as? NSDictionary)?["DeviceProfileURL"]
    if let url = value as? URL { return url.standardizedFileURL }
    if let string = value as? String { return URL(string: string)?.standardizedFileURL }
    return nil
  }
}
