import CoreGraphics
import Foundation

@main
enum ImageAdjustmentMutationSmoke {
  static func main() {
    guard CommandLine.arguments.count == 2,
      let id = CGDirectDisplayID(CommandLine.arguments[1]),
      CGDisplayIsOnline(id) != 0, CGDisplayIsBuiltin(id) == 0
    else { exit(2) }
    let software = DisplaySoftwareTransferService()
    let beforeContrast = DisplayImageAdjustmentService.contrast(for: id)
    let beforeTemperature = DisplayImageAdjustmentService.hardwareTemperature(for: id)
    guard let contrast = beforeContrast.value, let temperature = beforeTemperature.value else {
      print("DDC controls unavailable; no mutations")
      exit(3)
    }
    print("before contrast=\(contrast) temperature=\(temperature)")
    defer {
      let contrastRestore = DisplayImageAdjustmentService.setContrast(contrast, for: id)
      let temperatureRestore = DisplayImageAdjustmentService.setHardwareTemperature(
        Int(temperature), for: id)
      let softwareRestore = software.reset(for: id)
      print(
        "defer restore contrast=\(contrastRestore) temperature=\(temperatureRestore) "
          + "software=\(softwareRestore) pending=\(software.pendingRecoveryUUIDs)")
    }
    let contrastTarget = contrast < 99 ? contrast + 1 : contrast - 1
    print("contrast changed=\(DisplayImageAdjustmentService.setContrast(contrastTarget, for: id))")
    print("contrast restored=\(DisplayImageAdjustmentService.setContrast(contrast, for: id))")
    let alternate = Int(temperature) == 7500 ? 6500 : 7500
    print(
      "temperature changed=\(DisplayImageAdjustmentService.setHardwareTemperature(alternate, for: id))"
    )
    print(
      "temperature restored=\(DisplayImageAdjustmentService.setHardwareTemperature(Int(temperature), for: id))"
    )
    print("gamma changed=\(software.set(gamma: 1.05, kelvin: 6500, for: id))")
    print("gamma restored=\(software.reset(for: id))")
    print("software temperature changed=\(software.set(gamma: 1, kelvin: 6700, for: id))")
    print("software temperature restored=\(software.reset(for: id))")
  }
}
