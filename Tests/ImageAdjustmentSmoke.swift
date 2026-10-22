import CoreGraphics
import Foundation

@main
enum ImageAdjustmentSmoke {
  static func main() {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success else { exit(1) }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { exit(1) }
    let service = DisplaySoftwareTransferService()
    for id in ids.prefix(Int(count)) {
      let c = DisplayImageAdjustmentService.contrast(for: id)
      let t = DisplayImageAdjustmentService.hardwareTemperature(for: id)
      let s = service.status(for: id)
      print(
        "display=\(id) builtin=\(CGDisplayIsBuiltin(id) != 0) "
          + "contrast=\(String(describing: c.value)) adjustable=\(c.isAdjustable) "
          + "reason=\(c.reason ?? "none") "
          + "hardwareKelvin=\(String(describing: t.value)) adjustable=\(t.isAdjustable) "
          + "reason=\(t.reason ?? "none") " + "softwareCapacity=\(CGDisplayGammaTableCapacity(id)) "
          + "appGamma=\(String(describing: s.gamma)) " + "appKelvin=\(String(describing: s.kelvin))"
      )
      var r0: Float = 0
      var r1: Float = 0
      var rg: Float = 0
      var g0: Float = 0
      var g1: Float = 0
      var gg: Float = 0
      var b0: Float = 0
      var b1: Float = 0
      var bg: Float = 0
      let result = CGGetDisplayTransferByFormula(
        id, &r0, &r1, &rg,
        &g0, &g1, &gg, &b0, &b1, &bg)
      print(
        "formula display=\(id) result=\(result.rawValue) "
          + "values=\([r0,r1,rg,g0,g1,gg,b0,b1,bg])")
    }
    print("pendingRecovery=\(service.pendingRecoveryUUIDs)")
  }
}
