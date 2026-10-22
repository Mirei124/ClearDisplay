import AppKit
import Combine
import CoreGraphics
import Foundation

struct DisplayInfo: Identifiable {
  let id: CGDirectDisplayID
  let stableID: String
  let name: String
  let isBuiltin: Bool
  let logicalSize: CGSize
  let pixelSize: CGSize
  let refreshRate: Double
  let hiDPIEnabled: Bool
  let canToggleHiDPI: Bool
  let unavailableReason: String?
}

@MainActor
final class DisplayController: ObservableObject {
  @Published private(set) var displays: [DisplayInfo] = []
  @Published private(set) var isBusy = false
  @Published private(set) var errorMessage: String?
  @Published private(set) var modesByDisplay: [CGDirectDisplayID: [DisplayModeOption]] = [:]
  @Published private(set) var brightnessByDisplay: [CGDirectDisplayID: BrightnessStatus] = [:]
  @Published var brightnessDrafts: [CGDirectDisplayID: Double] = [:]
  @Published private(set) var busyDisplays: Set<CGDirectDisplayID> = []
  @Published private(set) var layout: [DisplayLayoutItem] = []
  @Published private(set) var relationships:
    [CGDirectDisplayID: DisplayTopologyService.Relationship] = [:]
  @Published private(set) var disconnectedDisplays: [DisconnectedDisplay] = []
  @Published private(set) var connectionSupported = false
  @Published private(set) var appearanceMode: SystemAppearanceMode?
  @Published private(set) var nightShiftState: DisplayNightShiftState?
  @Published private(set) var trueToneByDisplay: [CGDirectDisplayID: DisplayTrueToneStatus] = [:]
  @Published private(set) var globalControlsBusy = false
  @Published private(set) var hdrByDisplay: [CGDirectDisplayID: DisplayHDRStatus] = [:]
  @Published private(set) var profilesByDisplay: [CGDirectDisplayID: DisplayColorProfileStatus] =
    [:]
  @Published private(set) var contrastByDisplay: [CGDirectDisplayID: ImageAdjustmentStatus] = [:]
  @Published private(set) var temperatureByDisplay: [CGDirectDisplayID: ImageAdjustmentStatus] = [:]
  @Published var contrastDrafts: [CGDirectDisplayID: Double] = [:]
  @Published private(set) var softwareByDisplay:
    [CGDirectDisplayID: (gamma: Double?, kelvin: Int?, reason: String?)] = [:]
  @Published var gammaDrafts: [CGDirectDisplayID: Double] = [:]
  @Published var softwareTemperatureDrafts: [CGDirectDisplayID: Double] = [:]
  private let softwareTransfer = DisplaySoftwareTransferService()
  private let nightShiftService = DisplayNightShiftService()
  private var terminationObserver: NSObjectProtocol?
  private var editingBrightness: Set<CGDirectDisplayID> = []
  private var editingContrast: Set<CGDirectDisplayID> = []
  private var refreshGeneration = 0
  private var reconfigurationObserver: NSObjectProtocol?

  init() {
    _ = softwareTransfer.recoverPending()
    CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, nil)
    reconfigurationObserver = NotificationCenter.default.addObserver(
      forName: .displayModeDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        _ = self.softwareTransfer.recoverPending()
        self.refresh()
      }
    }
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        _ = self.softwareTransfer.restoreAll()
      }
    }
    refresh()
  }

  deinit {
    CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, nil)
    if let reconfigurationObserver {
      NotificationCenter.default.removeObserver(reconfigurationObserver)
    }
    if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
  }

  func refresh() {
    refreshGeneration += 1
    let generation = refreshGeneration
    if !globalControlsBusy {
      appearanceMode = try? DisplayAppearanceService.readMode()
      nightShiftState = try? nightShiftService?.readState()
    }
    let count = HDReadDisplays(nil, 0)
    guard count > 0 else {
      displays = []
      layout = []
      relationships = [:]
      modesByDisplay = [:]
      brightnessByDisplay = [:]
      hdrByDisplay = [:]
      profilesByDisplay = [:]
      contrastByDisplay = [:]
      temperatureByDisplay = [:]
      softwareByDisplay = [:]
      trueToneByDisplay = [:]
      Task {
        let service = DisplayConnectionService.shared
        let supported = await service.isSupported
        let disconnected = await service.disconnected()
        guard generation == refreshGeneration else { return }
        connectionSupported = supported
        disconnectedDisplays = disconnected
      }
      return
    }
    var states = [HDDisplayState](repeating: HDDisplayState(), count: Int(count))
    let actualCount = HDReadDisplays(&states, count)
    let screens = NSScreen.screens
    displays = states.prefix(Int(min(count, actualCount))).filter { $0.displayID != 0 }.map {
      state in
      let name =
        screens.first { screen in
          (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value == state.displayID
        }?.localizedName ?? (state.isBuiltin ? "Built-in Display" : "Display \(state.displayID)")
      let stableID: String
      if let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(state.displayID) {
        stableID = CFUUIDCreateString(nil, unmanagedUUID.takeRetainedValue()) as String
      } else {
        stableID = "display-id-\(state.displayID)"
      }
      return DisplayInfo(
        id: state.displayID,
        stableID: stableID,
        name: name,
        isBuiltin: state.isBuiltin,
        logicalSize: CGSize(width: Int(state.logicalWidth), height: Int(state.logicalHeight)),
        pixelSize: CGSize(width: Int(state.pixelWidth), height: Int(state.pixelHeight)),
        refreshRate: state.refreshRateHz,
        hiDPIEnabled: state.isHiDPI,
        canToggleHiDPI: state.canToggle,
        unavailableReason: state.canToggle
          ? nil : "No matching 1× and 2× modes at the current size and refresh rate"
      )
    }
    let ids = Set(displays.map(\.id))
    modesByDisplay = modesByDisplay.filter { ids.contains($0.key) }
    brightnessByDisplay = brightnessByDisplay.filter { ids.contains($0.key) }
    hdrByDisplay = hdrByDisplay.filter { ids.contains($0.key) }
    profilesByDisplay = profilesByDisplay.filter { ids.contains($0.key) }
    contrastByDisplay = contrastByDisplay.filter { ids.contains($0.key) }
    temperatureByDisplay = temperatureByDisplay.filter { ids.contains($0.key) }
    softwareByDisplay = softwareByDisplay.filter { ids.contains($0.key) }
    trueToneByDisplay = trueToneByDisplay.filter { ids.contains($0.key) }
    for display in displays {
      if !busyDisplays.contains(display.id) {
        trueToneByDisplay[display.id] = DisplayTrueToneService.status(for: display.id)
      }
      modesByDisplay[display.id] = DisplayModeCatalog.modes(for: display.id)
      if !busyDisplays.contains(display.id) { loadBrightness(for: display.id) }
      if !busyDisplays.contains(display.id) { loadColorControls(for: display.id) }
      softwareByDisplay[display.id] = softwareTransfer.status(for: display.id)
      if gammaDrafts[display.id] == nil { gammaDrafts[display.id] = 1.0 }
      if softwareTemperatureDrafts[display.id] == nil {
        softwareTemperatureDrafts[display.id] = 6500
      }
    }
    layout = (try? DisplayLayoutService.snapshot()) ?? []
    relationships = Dictionary(
      uniqueKeysWithValues: displays.compactMap { display in
        DisplayTopologyService.relationship(for: display.id).map { (display.id, $0) }
      })
    Task {
      let service = DisplayConnectionService.shared
      let supported = await service.isSupported
      let disconnected = await service.disconnected()
      guard generation == refreshGeneration else { return }
      connectionSupported = supported
      disconnectedDisplays = disconnected
    }
  }

  func setAppearance(_ mode: SystemAppearanceMode) {
    guard !isBusy, !globalControlsBusy, mode != .automatic else { return }
    globalControlsBusy = true
    errorMessage = nil
    defer {
      appearanceMode = try? DisplayAppearanceService.readMode()
      globalControlsBusy = false
    }
    do { try DisplayAppearanceService.setMode(mode) } catch {
      errorMessage = error.localizedDescription
    }
  }

  func setNightShift(_ enabled: Bool) {
    guard !isBusy, !globalControlsBusy, let nightShiftService else { return }
    globalControlsBusy = true
    errorMessage = nil
    defer {
      nightShiftState = try? nightShiftService.readState()
      globalControlsBusy = false
    }
    do { nightShiftState = try nightShiftService.setEnabled(enabled) } catch {
      errorMessage = error.localizedDescription
    }
  }

  func setTrueTone(_ enabled: Bool, for id: CGDirectDisplayID) async {
    guard !isBusy, !busyDisplays.contains(id),
      let stableID = displays.first(where: { $0.id == id })?.stableID,
      trueToneByDisplay[id]?.isSupported == true
    else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    do {
      let status = try await DisplayTrueToneService.setEnabled(enabled, for: id)
      if displays.contains(where: { $0.id == id && $0.stableID == stableID }) {
        trueToneByDisplay[id] = status
      }
    } catch { errorMessage = error.localizedDescription }
    busyDisplays.remove(id)
    refresh()
  }

  func applySoftwareTransfer(for id: CGDirectDisplayID) {
    guard !isBusy, !busyDisplays.contains(id), hdrByDisplay[id]?.isEnabled != true else { return }
    let gamma = gammaDrafts[id] ?? 1.0
    let kelvin = Int((softwareTemperatureDrafts[id] ?? 6500).rounded())
    busyDisplays.insert(id)
    errorMessage = nil
    switch softwareTransfer.set(gamma: gamma, kelvin: kelvin, for: id) {
    case .success:
      softwareByDisplay[id] = softwareTransfer.status(for: id)
    case .failure(let error): errorMessage = error.localizedDescription
    }
    busyDisplays.remove(id)
  }

  func resetSoftwareTransfer(for id: CGDirectDisplayID) {
    guard !isBusy, !busyDisplays.contains(id) else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    switch softwareTransfer.reset(for: id) {
    case .success:
      softwareByDisplay[id] = softwareTransfer.status(for: id)
      gammaDrafts[id] = 1.0
      softwareTemperatureDrafts[id] = 6500
    case .failure(let error): errorMessage = error.localizedDescription
    }
    busyDisplays.remove(id)
  }

  func loadColorControls(for id: CGDirectDisplayID) {
    let generation = refreshGeneration
    guard let stableID = displays.first(where: { $0.id == id })?.stableID else { return }
    hdrByDisplay[id] = DisplayHDRService.status(for: id)
    Task {
      let profile = await Task.detached(priority: .utility) {
        DisplayColorProfileService.status(for: id)
      }.value
      guard generation == refreshGeneration,
        displays.contains(where: { $0.id == id && $0.stableID == stableID })
      else {
        return
      }
      profilesByDisplay[id] = profile
    }
    guard displays.contains(where: { $0.id == id && !$0.isBuiltin }) else { return }
    Task {
      let values = await Task.detached(priority: .utility) {
        (
          DisplayImageAdjustmentService.contrast(for: id),
          DisplayImageAdjustmentService.hardwareTemperature(for: id)
        )
      }.value
      guard generation == refreshGeneration,
        displays.contains(where: { $0.id == id && $0.stableID == stableID })
      else {
        return
      }
      contrastByDisplay[id] = values.0
      temperatureByDisplay[id] = values.1
      if let value = values.0.value, !busyDisplays.contains(id), !editingContrast.contains(id) {
        contrastDrafts[id] = value
      }
    }
  }

  func contrastEditingChanged(for id: CGDirectDisplayID, editing: Bool) {
    if editing {
      editingContrast.insert(id)
    } else {
      Task {
        await setContrast(for: id)
        editingContrast.remove(id)
      }
    }
  }

  func setHDR(_ enabled: Bool, for id: CGDirectDisplayID) async {
    guard !isBusy, !busyDisplays.contains(id) else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    do { hdrByDisplay[id] = try await DisplayHDRService.setEnabled(enabled, for: id) } catch {
      errorMessage = error.localizedDescription
    }
    busyDisplays.remove(id)
    refresh()
  }

  func setProfile(_ profile: DisplayColorProfile, for id: CGDirectDisplayID) async {
    guard !isBusy, !busyDisplays.contains(id) else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    do {
      profilesByDisplay[id] = try await DisplayColorProfileService.apply(profile.url, to: id)
    } catch { errorMessage = error.localizedDescription }
    busyDisplays.remove(id)
    refresh()
  }

  func setContrast(for id: CGDirectDisplayID) async {
    guard !isBusy, !busyDisplays.contains(id), let value = contrastDrafts[id] else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    let result = await Task.detached(priority: .userInitiated) {
      DisplayImageAdjustmentService.setContrast(value, for: id)
    }.value
    switch result {
    case .success(let status):
      contrastByDisplay[id] = status
      contrastDrafts[id] = status.value ?? value
    case .failure(let error):
      errorMessage = error.localizedDescription
    }
    busyDisplays.remove(id)
  }

  func setHardwareTemperature(_ kelvin: Int, for id: CGDirectDisplayID) async {
    guard !isBusy, !busyDisplays.contains(id) else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    let result = await Task.detached(priority: .userInitiated) {
      DisplayImageAdjustmentService.setHardwareTemperature(kelvin, for: id)
    }.value
    switch result {
    case .success(let status): temperatureByDisplay[id] = status
    case .failure(let error): errorMessage = error.localizedDescription
    }
    busyDisplays.remove(id)
  }

  func applyLayout(origins: [CGDirectDisplayID: CGPoint], primaryID: CGDirectDisplayID) async {
    guard !isBusy else { return }
    isBusy = true
    errorMessage = nil
    do {
      let plan = try DisplayLayoutService.plan(
        from: layout, proposedOrigins: origins, primaryID: primaryID)
      _ = try await Task.detached(priority: .userInitiated) { try DisplayLayoutService.apply(plan) }
        .value
    } catch { errorMessage = error.localizedDescription }
    refresh()
    isBusy = false
  }

  func setRotation(_ degrees: Int, for id: CGDirectDisplayID) async {
    guard !isBusy else { return }
    isBusy = true
    errorMessage = nil
    do {
      try await Task.detached(priority: .userInitiated) {
        try DisplayTopologyService.setRotation(degrees, for: id)
      }.value
    } catch { errorMessage = error.localizedDescription }
    refresh()
    isBusy = false
  }

  func setMirror(source: CGDirectDisplayID?, for id: CGDirectDisplayID) async {
    guard !isBusy else { return }
    isBusy = true
    errorMessage = nil
    do {
      try await Task.detached(priority: .userInitiated) {
        if let source {
          try DisplayTopologyService.mirror(source: source, target: id)
        } else {
          try DisplayTopologyService.extend(displayID: id)
        }
      }.value
    } catch { errorMessage = error.localizedDescription }
    refresh()
    isBusy = false
  }

  func disconnect(_ display: DisplayInfo) async {
    guard !isBusy, connectionSupported else { return }
    isBusy = true
    errorMessage = nil
    do {
      try await DisplayConnectionService.shared.disconnect(
        id: display.id, name: display.name, isBuiltin: display.isBuiltin)
    } catch { errorMessage = error.localizedDescription }
    refresh()
    isBusy = false
  }

  func reconnect(_ display: DisconnectedDisplay) async {
    guard !isBusy, connectionSupported else { return }
    isBusy = true
    errorMessage = nil
    do { try await DisplayConnectionService.shared.reconnect(uuid: display.id) } catch {
      errorMessage = error.localizedDescription
    }
    refresh()
    isBusy = false
  }

  func loadBrightness(for id: CGDirectDisplayID) {
    let generation = refreshGeneration
    guard let stableID = displays.first(where: { $0.id == id })?.stableID else { return }
    Task {
      let status = await Task.detached(priority: .utility) {
        DisplayBrightnessService.status(for: id)
      }.value
      guard generation == refreshGeneration,
        displays.contains(where: { $0.id == id && $0.stableID == stableID })
      else {
        return
      }
      brightnessByDisplay[id] = status
      if let percent = status.percent, !busyDisplays.contains(id), !editingBrightness.contains(id) {
        brightnessDrafts[id] = percent
      }
    }
  }

  func brightnessEditingChanged(for id: CGDirectDisplayID, editing: Bool) {
    if editing {
      editingBrightness.insert(id)
    } else {
      Task {
        await setBrightness(for: id)
        editingBrightness.remove(id)
      }
    }
  }

  func setBrightness(for id: CGDirectDisplayID) async {
    guard !isBusy, !busyDisplays.contains(id), let percent = brightnessDrafts[id] else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    let result = await Task.detached(priority: .userInitiated) {
      DisplayBrightnessService.setPercent(percent, for: id)
    }.value
    busyDisplays.remove(id)
    switch result {
    case .success(let status):
      brightnessByDisplay[id] = status
      brightnessDrafts[id] = status.percent ?? percent
    case .failure(let error):
      errorMessage = error.localizedDescription
      loadBrightness(for: id)
    }
  }

  func setMode(_ mode: DisplayModeOption, for id: CGDirectDisplayID) async {
    guard !isBusy, !busyDisplays.contains(id), mode.isSelectable else { return }
    isBusy = true
    errorMessage = nil
    do {
      try await DisplayModeCatalog.apply(modeID: mode.id, to: id)
    } catch {
      errorMessage = error.localizedDescription
    }
    refresh()
    isBusy = false
  }

  func setHiDPI(for id: CGDirectDisplayID, enabled: Bool) async {
    guard !isBusy else { return }
    isBusy = true
    errorMessage = nil
    let result = await Task.detached(priority: .userInitiated) {
      HDSetHiDPI(id, enabled, nil)
    }.value
    refresh()
    isBusy = false
    if result != HDResultOK {
      switch result {
      case HDResultDisplayNotFound:
        errorMessage = "The display is no longer connected."
      case HDResultModeUnavailable:
        errorMessage = "A matching HiDPI mode is not available at this size and refresh rate."
      case HDResultBeginFailed, HDResultConfigureFailed, HDResultCommitFailed:
        errorMessage = "macOS could not change the display mode (error \(result.rawValue))."
      case HDResultVerificationFailed:
        errorMessage = "The mode change could not be verified. Check the current display state."
      default:
        errorMessage = "Could not change the display mode."
      }
    }
  }
}

private func displayReconfigurationCallback(
  _: CGDirectDisplayID,
  _: CGDisplayChangeSummaryFlags,
  _: UnsafeMutableRawPointer?
) {
  Task { @MainActor in
    NotificationCenter.default.post(name: .displayModeDidChange, object: nil)
  }
}

extension Notification.Name {
  fileprivate static let displayModeDidChange = Notification.Name("DisplayModeDidChange")
}
