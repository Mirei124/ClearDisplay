import CoreGraphics
import Foundation

@main
enum TopologySmoke {
  static func main() throws {
    for id in DisplayTopologyService.onlineDisplayIDs() {
      if let state = DisplayTopologyService.relationship(for: id) {
        print(
          "display \(id) rotation=\(state.rotationDegrees) mirrors=\(String(describing: state.mirrorsDisplayID)) mirroredBy=\(state.mirroredByDisplayIDs)"
        )
      }
    }
    let args = CommandLine.arguments
    if args.count == 4, args[1] == "mirror",
      let source = CGDirectDisplayID(args[2]), let target = CGDirectDisplayID(args[3])
    {
      try DisplayTopologyService.mirror(source: source, target: target)
    } else if args.count == 3, args[1] == "extend",
      let id = CGDirectDisplayID(args[2])
    {
      try DisplayTopologyService.extend(displayID: id)
    } else if args.count == 4, args[1] == "rotate",
      let id = CGDirectDisplayID(args[2]), let angle = Int(args[3])
    {
      try DisplayTopologyService.setRotation(angle, for: id)
    } else if args.count != 1 {
      fputs("Usage: TopologySmoke [mirror source target|extend id|rotate id angle]\n", stderr)
      exit(2)
    }
    if args.count != 1 {
      for id in DisplayTopologyService.onlineDisplayIDs() {
        if let state = DisplayTopologyService.relationship(for: id) {
          print(
            "after display \(id) rotation=\(state.rotationDegrees) mirrors=\(String(describing: state.mirrorsDisplayID))"
          )
        }
      }
    }
  }
}
