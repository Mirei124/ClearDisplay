import CoreGraphics
import Foundation

@main
enum BrightnessSmoke {
  static func main() {
    if CommandLine.arguments.count == 3 {
      let id = CGDirectDisplayID(CommandLine.arguments[1]) ?? 0
      let percent = Double(CommandLine.arguments[2]) ?? .nan
      switch DisplayBrightnessService.setPercent(percent, for: id) {
      case .success(let status):
        print(
          "set display \(id) requested=\(percent) measured=\(String(describing: status.percent))")
        return
      case .failure(let error):
        fputs("set failed: \(error.localizedDescription)\n", stderr)
        exit(1)
      }
    }
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
      fputs("No online displays\n", stderr)
      exit(1)
    }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { exit(1) }
    for id in ids.prefix(Int(count)) {
      let value = DisplayBrightnessService.status(for: id)
      print(
        "display \(id) builtin=\(CGDisplayIsBuiltin(id) != 0) "
          + "source=\(String(describing: value.source)) adjustable=\(value.isAdjustable) "
          + "percent=\(String(describing: value.percent)) reason=\(value.unavailableReason ?? "none")"
      )
    }
  }
}
