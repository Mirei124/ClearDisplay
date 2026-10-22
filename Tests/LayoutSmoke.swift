import CoreGraphics
import Foundation

@main
enum LayoutSmoke {
  static func main() throws {
    let before = try DisplayLayoutService.snapshot()
    for item in before {
      print("display \(item.id) origin=\(item.origin) size=\(item.size) main=\(item.isMain)")
    }
    var origins = Dictionary(uniqueKeysWithValues: before.map { ($0.id, $0.origin) })
    var target = before.first(where: \.isMain)?.id ?? 0
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "primary",
      let id = CGDirectDisplayID(CommandLine.arguments[2])
    {
      target = id
    } else if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "move",
      let id = CGDirectDisplayID(CommandLine.arguments[2]),
      let x = Double(CommandLine.arguments[3]), let y = Double(CommandLine.arguments[4])
    {
      origins[id] = CGPoint(x: x, y: y)
    } else {
      return
    }
    let plan = try DisplayLayoutService.plan(
      from: before, proposedOrigins: origins, primaryID: target)
    let after = try DisplayLayoutService.apply(plan)
    for item in after {
      print("after display \(item.id) origin=\(item.origin) main=\(item.isMain)")
    }
  }
}
