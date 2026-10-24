import CoreGraphics
import Foundation
import IOKit

/// Manual read-only resource check. Creates channels without sending VCP commands.
@main enum DDCChannelLifetimeSmoke {
  static func clients() -> Int {
    let root = IORegistryGetRootEntry(kIOMainPortDefault)
    defer { IOObjectRelease(root) }
    var iterator: io_iterator_t = 0
    guard
      IORegistryEntryCreateIterator(
        root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator)
        == KERN_SUCCESS
    else { return -1 }
    defer { IOObjectRelease(iterator) }
    var n = 0
    var entry = IOIteratorNext(iterator)
    while entry != 0 {
      if let creator = IORegistryEntryCreateCFProperty(
        entry, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        as? String, creator.hasPrefix("pid \(getpid()),")
      {
        n += 1
      }
      IOObjectRelease(entry)
      entry = IOIteratorNext(iterator)
    }
    return n
  }
  static func main() {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &ids, &count) == .success,
      let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) == 0 })
    else { fatalError("No external display") }
    let before = clients()
    guard before >= 0 else { fatalError("Could not enumerate I/O user clients") }
    for _ in 0..<50 {
      autoreleasepool {
        guard let channel = DisplayBrightnessService.uniqueExternalChannel(for: id) else {
          fatalError("No DDC channel")
        }
        withExtendedLifetime(channel) {}
      }
    }
    let after = clients()
    print("channels_created=50 user_clients_before=\(before) after=\(after)")
    if before != after { exit(1) }
  }
}
