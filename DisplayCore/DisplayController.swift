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
  @Published private(set) var trueToneStatus: DisplayTrueToneStatus?
  @Published private(set) var globalControlsBusy = false
  @Published private(set) var hdrByDisplay: [CGDirectDisplayID: DisplayHDRStatus] = [:]
  @Published private(set) var profilesByDisplay: [CGDirectDisplayID: DisplayColorProfileStatus] =
    [:]
  @Published private(set) var contrastByDisplay: [CGDirectDisplayID: ImageAdjustmentStatus] = [:]
  @Published private(set) var temperatureByDisplay: [CGDirectDisplayID: ImageAdjustmentStatus] = [:]
  @Published var contrastDrafts: [CGDirectDisplayID: Double] = [:]
  @Published var hardwareTemperatureDrafts: [CGDirectDisplayID: Double] = [:]
  @Published private(set) var softwareByDisplay:
    [CGDirectDisplayID: (gamma: Double?, kelvin: Int?, reason: String?)] = [:]
  @Published var gammaDrafts: [CGDirectDisplayID: Double] = [:]
  @Published var softwareTemperatureDrafts: [CGDirectDisplayID: Double] = [:]
  @Published private(set) var launchAtLoginStatus = LaunchAtLoginService.status()
  var launchAtLoginEnabled: Bool { launchAtLoginStatus.isEnabled }
  var launchAtLoginSupported: Bool { launchAtLoginStatus.isAvailable }
  private let softwareTransfer = DisplaySoftwareTransferService()
  private let nightShiftService = DisplayNightShiftService()
  private var terminationObserver: NSObjectProtocol?
  private var editingBrightness: Set<CGDirectDisplayID> = []
  private var pendingBrightness: [CGDirectDisplayID: Double] = [:]
  private var brightnessTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
  private var brightnessWorkerIDs: [CGDirectDisplayID: String] = [:]
  private var editingContrast: Set<CGDirectDisplayID> = []
  private var editingHardwareTemperature: Set<CGDirectDisplayID> = []
  private var pendingDDCContrast: [CGDirectDisplayID: Double] = [:]
  private var pendingDDCTemperature: [CGDirectDisplayID: Int] = [:]
  private var ddcTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
  private var ddcWorkerIdentities: [CGDirectDisplayID: (stableID: String, token: UUID)] = [:]
  private var softwareTransferTasks: [CGDirectDisplayID: Task<Void, Never>] = [:]
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
    for task in brightnessTasks.values { task.cancel() }
    for task in softwareTransferTasks.values { task.cancel() }
    for task in ddcTasks.values { task.cancel() }
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
      trueToneStatus = DisplayTrueToneService.status()
      launchAtLoginStatus = LaunchAtLoginService.status()
    }
    let count = HDReadDisplays(nil, 0)
    guard count > 0 else {
      cancelAllBrightnessWorkers()
      cancelAllDDCWorkers()
      for task in softwareTransferTasks.values { task.cancel() }
      softwareTransferTasks.removeAll()
      brightnessDrafts.removeAll()
      contrastDrafts.removeAll()
      hardwareTemperatureDrafts.removeAll()
      gammaDrafts.removeAll()
      softwareTemperatureDrafts.removeAll()
      editingBrightness.removeAll()
      editingContrast.removeAll()
      editingHardwareTemperature.removeAll()
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
    for (id, stableID) in brightnessWorkerIDs {
      if displays.first(where: { $0.id == id })?.stableID != stableID {
        brightnessTasks[id]?.cancel()
        brightnessTasks.removeValue(forKey: id)
        brightnessWorkerIDs.removeValue(forKey: id)
        pendingBrightness.removeValue(forKey: id)
      }
    }
    for (id, identity) in Array(ddcWorkerIdentities) {
      if displays.first(where: { $0.id == id })?.stableID != identity.stableID {
        cancelDDCWorker(for: id)
      }
    }
    for id in softwareTransferTasks.keys.filter({ !ids.contains($0) }) {
      softwareTransferTasks[id]?.cancel()
      softwareTransferTasks.removeValue(forKey: id)
    }
    brightnessDrafts = brightnessDrafts.filter { ids.contains($0.key) }
    contrastDrafts = contrastDrafts.filter { ids.contains($0.key) }
    hardwareTemperatureDrafts = hardwareTemperatureDrafts.filter { ids.contains($0.key) }
    gammaDrafts = gammaDrafts.filter { ids.contains($0.key) }
    softwareTemperatureDrafts = softwareTemperatureDrafts.filter { ids.contains($0.key) }
    editingBrightness.formIntersection(ids)
    editingContrast.formIntersection(ids)
    editingHardwareTemperature.formIntersection(ids)
    modesByDisplay = modesByDisplay.filter { ids.contains($0.key) }
    brightnessByDisplay = brightnessByDisplay.filter { ids.contains($0.key) }
    hdrByDisplay = hdrByDisplay.filter { ids.contains($0.key) }
    profilesByDisplay = profilesByDisplay.filter { ids.contains($0.key) }
    contrastByDisplay = contrastByDisplay.filter { ids.contains($0.key) }
    temperatureByDisplay = temperatureByDisplay.filter { ids.contains($0.key) }
    softwareByDisplay = softwareByDisplay.filter { ids.contains($0.key) }
    for display in displays {
      modesByDisplay[display.id] = DisplayModeCatalog.modes(for: display.id)
      if !busyDisplays.contains(display.id) { loadBrightness(for: display.id) }
      if !busyDisplays.contains(display.id) { loadColorControls(for: display.id) }
      let softwareStatus = softwareTransfer.status(for: display.id)
      softwareByDisplay[display.id] = softwareStatus
      if gammaDrafts[display.id] == nil { gammaDrafts[display.id] = softwareStatus.gamma ?? 1.0 }
      if softwareTemperatureDrafts[display.id] == nil {
        softwareTemperatureDrafts[display.id] = Double(softwareStatus.kelvin ?? 6500)
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

  func setTrueTone(_ enabled: Bool) async {
    guard !isBusy, !globalControlsBusy,
      trueToneStatus?.isSupported == true,
      trueToneStatus?.isAvailable == true
    else { return }
    globalControlsBusy = true
    errorMessage = nil
    do {
      trueToneStatus = try await DisplayTrueToneService.setEnabled(enabled)
    } catch { errorMessage = error.localizedDescription }
    trueToneStatus = DisplayTrueToneService.status()
    globalControlsBusy = false
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

  /// Coalesce slider changes so each display receives at most one transfer
  /// update after a short pause. The editing-end call below applies the final
  /// value even if the user releases the slider before the delay expires.
  func scheduleSoftwareTransfer(for id: CGDirectDisplayID) {
    softwareTransferTasks[id]?.cancel()
    softwareTransferTasks[id] = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(75))
      guard !Task.isCancelled else { return }
      self?.applySoftwareTransfer(for: id)
      self?.softwareTransferTasks.removeValue(forKey: id)
    }
  }

  func setSoftwareTransferLive(for id: CGDirectDisplayID) {
    scheduleSoftwareTransfer(for: id)
  }

  func finishSoftwareTransferEditing(for id: CGDirectDisplayID) {
    softwareTransferTasks[id]?.cancel()
    softwareTransferTasks.removeValue(forKey: id)
    applySoftwareTransfer(for: id)
  }

  func resetSoftwareTransfer(for id: CGDirectDisplayID) {
    softwareTransferTasks[id]?.cancel()
    softwareTransferTasks.removeValue(forKey: id)
    guard !isBusy, !busyDisplays.contains(id) else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    // Neutral coefficients reproduce the captured baseline while keeping the
    // durable recovery snapshot available until normal app termination.
    switch softwareTransfer.set(gamma: 1.0, kelvin: 6500, for: id) {
    case .success:
      softwareByDisplay[id] = softwareTransfer.status(for: id)
      gammaDrafts[id] = 1.0
      softwareTemperatureDrafts[id] = 6500
    case .failure(let error): errorMessage = error.localizedDescription
    }
    busyDisplays.remove(id)
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard !globalControlsBusy else { return }
    globalControlsBusy = true
    errorMessage = nil
    do { try LaunchAtLoginService.setEnabled(enabled) } catch {
      errorMessage = error.localizedDescription
    }
    launchAtLoginStatus = LaunchAtLoginService.status()
    globalControlsBusy = false
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
      if let kelvin = values.1.value, !busyDisplays.contains(id),
        !editingHardwareTemperature.contains(id)
      {
        hardwareTemperatureDrafts[id] = kelvin
      }
      if let value = values.0.value, !busyDisplays.contains(id), !editingContrast.contains(id) {
        contrastDrafts[id] = value
      }
    }
  }

  func contrastEditingChanged(for id: CGDirectDisplayID, editing: Bool) {
    if editing {
      editingContrast.insert(id)
    } else {
      editingContrast.remove(id)
      contrastDraftChanged(for: id)
    }
  }

  func contrastDraftChanged(for id: CGDirectDisplayID) {
    guard displays.contains(where: { $0.id == id }), let value = contrastDrafts[id] else {
      return
    }
    pendingDDCContrast[id] = value
    scheduleDDCWorker(for: id)
  }

  func hardwareTemperatureDraftChanged(for id: CGDirectDisplayID) {
    guard displays.contains(where: { $0.id == id }),
      let value = hardwareTemperatureDrafts[id]
    else { return }
    let presets = DisplayImageAdjustmentService.hardwareTemperaturePresets.values
    guard let nearest = presets.min(by: { abs(Double($0) - value) < abs(Double($1) - value) })
    else { return }
    // Replace the pending intent even when the slider returns to the value
    // currently reported by the display. An older queued preset must not win.
    pendingDDCTemperature[id] = nearest
    scheduleDDCWorker(for: id)
  }

  private func scheduleDDCWorker(for id: CGDirectDisplayID) {
    guard ddcTasks[id] == nil else { return }
    guard let stableID = displays.first(where: { $0.id == id })?.stableID else { return }
    let token = UUID()
    ddcWorkerIdentities[id] = (stableID, token)
    ddcTasks[id] = Task { @MainActor [weak self] in
      // DDC transactions are slow and monitors can drop closely spaced writes.
      try? await Task.sleep(for: .milliseconds(150))
      guard let self else { return }
      while !Task.isCancelled {
        guard self.ddcWorkerIdentities[id]?.token == token,
          self.displays.contains(where: { $0.id == id && $0.stableID == stableID })
        else { break }
        if self.isBusy || self.busyDisplays.contains(id) {
          try? await Task.sleep(for: .milliseconds(100))
          continue
        }
        if let value = self.pendingDDCContrast.removeValue(forKey: id) {
          if abs((self.contrastByDisplay[id]?.value ?? -1) - value) > 1 {
            self.contrastDrafts[id] = value
            await self.setContrast(for: id)
          }
        } else if let kelvin = self.pendingDDCTemperature.removeValue(forKey: id) {
          if Int(self.temperatureByDisplay[id]?.value ?? -1) != kelvin {
            await self.setHardwareTemperature(kelvin, for: id)
          }
        } else {
          break
        }
      }
      if self.ddcWorkerIdentities[id]?.token == token {
        self.ddcTasks.removeValue(forKey: id)
        self.ddcWorkerIdentities.removeValue(forKey: id)
      }
    }
  }

  private func cancelDDCWorker(for id: CGDirectDisplayID) {
    ddcTasks[id]?.cancel()
    ddcTasks.removeValue(forKey: id)
    ddcWorkerIdentities.removeValue(forKey: id)
    pendingDDCContrast.removeValue(forKey: id)
    pendingDDCTemperature.removeValue(forKey: id)
    editingContrast.remove(id)
    editingHardwareTemperature.remove(id)
    contrastDrafts.removeValue(forKey: id)
    hardwareTemperatureDrafts.removeValue(forKey: id)
  }

  private func cancelAllDDCWorkers() {
    for id in Array(ddcWorkerIdentities.keys) { cancelDDCWorker(for: id) }
  }

  private func cancelAllBrightnessWorkers() {
    for task in brightnessTasks.values { task.cancel() }
    brightnessTasks.removeAll()
    brightnessWorkerIDs.removeAll()
    pendingBrightness.removeAll()
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
    guard !isBusy, !busyDisplays.contains(id), let value = contrastDrafts[id],
      let stableID = displays.first(where: { $0.id == id })?.stableID
    else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    let result = await Task.detached(priority: .userInitiated) {
      guard displayStableID(id) == stableID else {
        return Result<ImageAdjustmentStatus, ImageAdjustmentError>.failure(
          .unavailable("The display changed before the DDC write."))
      }
      return DisplayImageAdjustmentService.setContrast(value, for: id)
    }.value
    guard displays.contains(where: { $0.id == id && $0.stableID == stableID }) else {
      busyDisplays.remove(id)
      return
    }
    switch result {
    case .success(let status):
      contrastByDisplay[id] = status
      if !editingContrast.contains(id), pendingDDCContrast[id] == nil {
        contrastDrafts[id] = status.value ?? value
      }
    case .failure(let error):
      errorMessage = error.localizedDescription
    }
    busyDisplays.remove(id)
  }

  func setHardwareTemperature(_ kelvin: Int, for id: CGDirectDisplayID) async {
    guard !isBusy, !busyDisplays.contains(id),
      let stableID = displays.first(where: { $0.id == id })?.stableID
    else { return }
    busyDisplays.insert(id)
    errorMessage = nil
    let result = await Task.detached(priority: .userInitiated) {
      guard displayStableID(id) == stableID else {
        return Result<ImageAdjustmentStatus, ImageAdjustmentError>.failure(
          .unavailable("The display changed before the DDC write."))
      }
      return DisplayImageAdjustmentService.setHardwareTemperature(kelvin, for: id)
    }.value
    guard displays.contains(where: { $0.id == id && $0.stableID == stableID }) else {
      busyDisplays.remove(id)
      return
    }
    switch result {
    case .success(let status):
      temperatureByDisplay[id] = status
      if !editingHardwareTemperature.contains(id), pendingDDCTemperature[id] == nil {
        hardwareTemperatureDrafts[id] = status.value ?? Double(kelvin)
      }
    case .failure(let error): errorMessage = error.localizedDescription
    }
    busyDisplays.remove(id)
  }

  func hardwareTemperatureEditingChanged(for id: CGDirectDisplayID, editing: Bool) {
    if editing {
      editingHardwareTemperature.insert(id)
    } else {
      editingHardwareTemperature.remove(id)
      hardwareTemperatureDraftChanged(for: id)
    }
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
      editingBrightness.remove(id)
      brightnessDraftChanged(for: id)
    }
  }

  func brightnessDraftChanged(for id: CGDirectDisplayID) {
    guard !isBusy, !busyDisplays.contains(id),
      let percent = brightnessDrafts[id],
      let stableID = displays.first(where: { $0.id == id })?.stableID,
      brightnessByDisplay[id]?.isAdjustable == true
    else { return }
    pendingBrightness[id] = percent
    guard brightnessTasks[id] == nil else { return }
    brightnessWorkerIDs[id] = stableID
    brightnessTasks[id] = Task { [weak self] in
      while let self, !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(40))
        guard !Task.isCancelled,
          self.displays.contains(where: { $0.id == id && $0.stableID == stableID }),
          let next = self.pendingBrightness.removeValue(forKey: id)
        else { break }
        let result = await Task.detached(priority: .userInitiated) {
          DisplayBrightnessService.setPercent(next, for: id)
        }.value
        guard self.displays.contains(where: { $0.id == id && $0.stableID == stableID }) else {
          break
        }
        switch result {
        case .success(let status):
          self.brightnessByDisplay[id] = status
          if !self.editingBrightness.contains(id), self.pendingBrightness[id] == nil {
            self.brightnessDrafts[id] = status.percent ?? next
          }
        case .failure(let error):
          self.errorMessage = error.localizedDescription
          break
        }
      }
      if self?.brightnessWorkerIDs[id] == stableID {
        self?.brightnessTasks.removeValue(forKey: id)
        self?.brightnessWorkerIDs.removeValue(forKey: id)
        if self?.pendingBrightness[id] != nil { self?.brightnessDraftChanged(for: id) }
      }
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

private func displayStableID(_ id: CGDirectDisplayID) -> String? {
  guard let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(id) else { return nil }
  return CFUUIDCreateString(nil, unmanagedUUID.takeRetainedValue()) as String
}

extension Notification.Name {
  fileprivate static let displayModeDidChange = Notification.Name("DisplayModeDidChange")
}
