import ColorSync
import CoreGraphics
import Foundation

@main
@MainActor
enum HDRICCMutationSmoke {
  static func main() async {
    let id: CGDirectDisplayID = 2
    guard CGDisplayIsOnline(id) != 0 else { fail("external display offline") }
    let hdr = DisplayHDRService.status(for: id)
    let icc = DisplayColorProfileService.status(for: id)
    guard let originalHDR = hdr.isEnabled, let originalURL = icc.currentURL else {
      fail("cannot capture original HDR/ICC settings")
    }
    print("BEFORE HDR=\(originalHDR) ICC=\(originalURL.path)")
    guard
      let alternate = icc.profiles.first(where: {
        $0.url != originalURL && $0.name == "Display P3"
      })
    else { fail("Display P3 alternate unavailable") }

    var changedHDR = false
    var changedICC = false
    defer {
      if changedHDR || changedICC {
        fputs("RESTORE REQUIRED: smoke exited before automatic restoration\n", stderr)
      }
    }
    do {
      let enabled = try await DisplayHDRService.setEnabled(!originalHDR, for: id)
      changedHDR = true
      print("HDR switched=\(String(describing: enabled.isEnabled))")
      let restored = try await DisplayHDRService.setEnabled(originalHDR, for: id)
      guard restored.isEnabled == originalHDR else { throw SmokeError.restoreFailed }
      changedHDR = false
      print("HDR restored=\(String(describing: restored.isEnabled))")

      let selected = try await DisplayColorProfileService.apply(alternate.url, to: id)
      changedICC = true
      print("ICC switched=\(String(describing: selected.currentURL?.path))")
      let restoredICC = try await DisplayColorProfileService.apply(originalURL, to: id)
      guard restoredICC.currentURL?.standardizedFileURL == originalURL.standardizedFileURL else {
        throw SmokeError.restoreFailed
      }
      changedICC = false
      print("ICC restored=\(String(describing: restoredICC.currentURL?.path))")
    } catch {
      fputs("Smoke error: \(error)\n", stderr)
      if changedICC {
        do {
          _ = try await DisplayColorProfileService.apply(originalURL, to: id)
          changedICC = false
        } catch { fputs("ICC restoration error: \(error)\n", stderr) }
      }
      if changedHDR {
        do {
          _ = try await DisplayHDRService.setEnabled(originalHDR, for: id)
          changedHDR = false
        } catch { fputs("HDR restoration error: \(error)\n", stderr) }
      }
      exit(1)
    }
  }

  enum SmokeError: Error { case restoreFailed }
  static func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
  }
}
