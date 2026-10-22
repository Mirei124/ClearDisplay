import CoreGraphics
import Foundation

@main
@MainActor
enum ColorServicesSmoke {
  static func main() {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
      fputs("No online displays\n", stderr)
      exit(1)
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { exit(1) }
    for id in ids.prefix(Int(count)) {
      let hdr = DisplayHDRService.status(for: id)
      let icc = DisplayColorProfileService.status(for: id)
      print(
        "display \(id): HDR supported=\(hdr.isSupported) enabled=\(String(describing: hdr.isEnabled)); profiles=\(icc.profiles.count) current=\(icc.currentName ?? "none") url=\(String(describing: icc.currentURL))"
      )
      for profile in icc.profiles.prefix(3) {
        print("  \(profile.name): \(profile.url.path)")
      }
    }
  }
}
