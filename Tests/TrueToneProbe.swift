import CoreGraphics
import Darwin
import Foundation
import ObjectiveC.runtime

guard
  dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
    != nil,
  let cls = NSClassFromString("CBTrueToneClient") as? NSObject.Type
else { fatalError("CoreBrightness unavailable") }
let client = cls.init()
for name in ["supported", "available", "enabled", "supportIntegrated"] {
  let selector = NSSelectorFromString(name)
  typealias Getter = @convention(c) (NSObject, Selector) -> Bool
  let getter = unsafeBitCast(client.method(for: selector), to: Getter.self)
  print("\(name)=\(getter(client, selector))")
}
var count: UInt32 = 0
var ids = [CGDirectDisplayID](repeating: 0, count: 16)
_ = CGGetOnlineDisplayList(16, &ids, &count)
for id in ids.prefix(Int(count)) { print("display=\(id) builtIn=\(CGDisplayIsBuiltin(id) != 0)") }
