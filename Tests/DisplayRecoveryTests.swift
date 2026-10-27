import CoreGraphics
import Foundation

private final class SimulatedDisplays {
  var ids: [CGDirectDisplayID] = [1, 3]
  var uuids: [CGDirectDisplayID: String] = [1: "internal", 3: "external"]
  var enabled: Set<CGDirectDisplayID> = [1, 3]
  var physicalCount: UInt32? = 2
  var countRead: (() -> UInt32?)?
  var result = HDConnectionOK
  var applyWrite = true
  var writes: [(CGDirectDisplayID, Bool)] = []

  var backend: DisplayConnectionService.Backend {
    .init(
      isSupported: { true }, allIDs: { self.ids },
      isEnabled: { self.enabled.contains($0) }, uuid: { self.uuids[$0] },
      activePhysicalCount: { self.countRead?() ?? self.physicalCount },
      setEnabled: { id, enabled in
        self.writes.append((id, enabled))
        if self.result == HDConnectionOK, self.applyWrite {
          if enabled { self.enabled.insert(id) } else { self.enabled.remove(id) }
          self.physicalCount = UInt32(self.enabled.count)
        }
        return self.result
      })
  }

  func unplugExternal() {
    ids.removeAll { $0 == 3 }
    enabled.remove(3)
    physicalCount = UInt32(enabled.count)
  }
}

/// Tests the real connection service using a fake backend and isolated records.
/// No CoreGraphics topology mutation or DDC operation is executed.
@main enum DisplayRecoveryTests {
  static func check(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }

  static func main() async throws {
    let suite = "ClearDisplay.RecoveryTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var tests = 0

    func scenario() async throws -> (SimulatedDisplays, DisplayConnectionService) {
      defaults.removePersistentDomain(forName: suite)
      let hardware = SimulatedDisplays()
      let service = DisplayConnectionService(defaults: defaults, backend: hardware.backend)
      try await service.disconnect(id: 1, name: "Built-in", isBuiltin: true)
      hardware.writes.removeAll()
      return (hardware, service)
    }

    do {
      let (hardware, service) = try await scenario()
      check(try await service.recoverBuiltinIfNeeded() == false, "External still active")
      check(hardware.writes.isEmpty, "Must not override external-only use")
      hardware.unplugExternal()
      check(try await service.recoverBuiltinIfNeeded(), "Unplug must restore internal")
      check(hardware.enabled.contains(1), "Internal must be enabled")
      check(await service.disconnected().isEmpty, "Verified recovery clears record")
      check(try await service.recoverBuiltinIfNeeded() == false, "Recovery is idempotent")
      tests += 1
    }
    do {
      let (hardware, _) = try await scenario()
      hardware.unplugExternal()
      let restarted = DisplayConnectionService(defaults: defaults, backend: hardware.backend)
      check(try await restarted.recoverBuiltinIfNeeded(), "Recover saved record after restart")
      tests += 1
    }
    do {
      let (hardware, service) = try await scenario()
      hardware.unplugExternal()
      hardware.physicalCount = nil
      check(try await service.recoverBuiltinIfNeeded() == false, "Unknown topology is not zero")
      check(hardware.writes.isEmpty, "Enumeration failure must not enable a screen")
      tests += 1
    }
    do {
      let (hardware, service) = try await scenario()
      hardware.unplugExternal()
      hardware.uuids[1] = "replacement-external"
      check(try await service.recoverBuiltinIfNeeded() == false, "Reject reused numeric ID")
      check(hardware.writes.isEmpty, "Wrong identity must never be enabled")
      tests += 1
    }
    do {
      let (hardware, service) = try await scenario()
      hardware.unplugExternal()
      hardware.ids = [8]
      hardware.uuids = [8: "internal"]
      check(try await service.recoverBuiltinIfNeeded(), "Resolve renumbered internal by UUID")
      check(hardware.writes.first?.0 == 8, "Use new ID, not saved ID")
      tests += 1
    }
    do {
      let (hardware, service) = try await scenario()
      hardware.unplugExternal()
      hardware.uuids[1] = nil
      check(try await service.recoverBuiltinIfNeeded(), "Disabled display may have no UUID")
      tests += 1
    }
    do {
      let (hardware, service) = try await scenario()
      hardware.unplugExternal()
      hardware.result = HDConnectionConfigureFailed
      do {
        _ = try await service.recoverBuiltinIfNeeded()
        preconditionFailure("Failed enable must throw")
      } catch {}
      check(await service.disconnected().count == 1, "Failure must keep reconnect record")
      hardware.result = HDConnectionOK
      check(try await service.recoverBuiltinIfNeeded(), "Retry must succeed")
      tests += 1
    }
    do {
      let (hardware, service) = try await scenario()
      hardware.unplugExternal()
      hardware.applyWrite = false
      do {
        _ = try await service.recoverBuiltinIfNeeded()
        preconditionFailure("Unverified success must throw")
      } catch {}
      check(await service.disconnected().count == 1, "Readback failure must keep record")
      tests += 1
    }
    do {
      defaults.removePersistentDomain(forName: suite)
      let hardware = SimulatedDisplays()
      hardware.ids = [1]
      hardware.enabled = []
      hardware.physicalCount = 0
      let service = DisplayConnectionService(defaults: defaults, backend: hardware.backend)
      check(try await service.recoverBuiltinIfNeeded() == false, "No app record means no recovery")
      check(hardware.writes.isEmpty, "Must not enable unrelated disabled screens")
      tests += 1
    }
    do {
      defaults.removePersistentDomain(forName: suite)
      let hardware = SimulatedDisplays()
      let service = DisplayConnectionService(defaults: defaults, backend: hardware.backend)
      try await service.disconnect(id: 3, name: "External", isBuiltin: false)
      hardware.enabled = []
      hardware.physicalCount = 0
      hardware.writes.removeAll()
      check(
        try await service.recoverBuiltinIfNeeded() == false, "Never auto-enable external records")
      check(hardware.writes.isEmpty, "Only app-disabled built-in screens qualify")
      tests += 1
    }
    do {
      let (hardware, service) = try await scenario()
      hardware.unplugExternal()
      var reads = 0
      hardware.countRead = {
        reads += 1
        return reads == 1 ? 0 : 1
      }
      check(try await service.recoverBuiltinIfNeeded() == false, "Recheck before enabling")
      check(hardware.writes.isEmpty, "Abort if another screen returned")
      tests += 1
    }
    print("Display recovery: \(tests) scenarios passed (simulated hardware)")
  }
}
