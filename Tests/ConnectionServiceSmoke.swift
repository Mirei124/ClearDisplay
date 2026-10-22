import CoreGraphics
import Foundation

@main
enum ConnectionServiceSmoke {
  static func main() async throws {
    guard CommandLine.arguments.count == 2,
      let id = CGDirectDisplayID(CommandLine.arguments[1])
    else {
      fputs("Usage: ConnectionServiceSmoke display-id\n", stderr)
      exit(2)
    }
    let service = DisplayConnectionService.shared
    let original = CGDisplayIsOnline(id) != 0 && CGDisplayIsActive(id) != 0
    guard original else { fatalError("display is not active before test") }
    let name = "Smoke display \(id)"
    do {
      try await service.disconnect(id: id, name: name, isBuiltin: CGDisplayIsBuiltin(id) != 0)
      let records = await service.disconnected()
      print(
        "after disconnect active=\(CGDisplayIsActive(id) != 0) recorded=\(records.contains { $0.lastDisplayID == id })"
      )
      guard let record = records.first(where: { $0.lastDisplayID == id }) else {
        fatalError("disconnected record missing")
      }
      try await service.reconnect(uuid: record.id)
      print(
        "after reconnect active=\(CGDisplayIsActive(id) != 0) records=\(await service.disconnected().count)"
      )
    } catch {
      _ = HDSetDisplayEnabled(id, true)
      throw error
    }
  }
}
