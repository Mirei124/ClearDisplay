import SwiftUI

struct DisplayMenuView: View {
  private enum MenuSection: Equatable {
    case resolution(String)
    case refresh(String)
    case rotation(String)
    case mirror(String)
    case color(String)
    case profile(String)

    func isVisible(when expanded: MenuSection?) -> Bool {
      if self == expanded { return true }
      if case .color(let id) = self, expanded == .profile(id) { return true }
      return false
    }
  }

  @ObservedObject var controller: DisplayController
  @Environment(\.colorScheme) private var colorScheme
  @State private var expandedDisplays: Set<String> = []
  @State private var expandedSection: MenuSection?
  @State private var arrangementExpanded = false
  @State private var primaryListExpanded = false

  private var menuContentHeight: CGFloat {
    var height: CGFloat =
      210 + CGFloat(controller.displays.count + controller.disconnectedDisplays.count) * 55
    for display in controller.displays where expandedDisplays.contains(display.stableID) {
      height += 280
      if MenuSection.resolution(display.stableID).isVisible(when: expandedSection) {
        let modes = controller.modesByDisplay[display.id] ?? []
        let density = modes.first(where: \.isCurrent)?.isHiDPI ?? display.hiDPIEnabled
        let count = DisplayModeCatalog.desktopResolutions(modes, hiDPI: density).count
        height += CGFloat(count) * 30
      }
      if MenuSection.refresh(display.stableID).isVisible(when: expandedSection) { height += 100 }
      if MenuSection.rotation(display.stableID).isVisible(when: expandedSection) { height += 125 }
      if MenuSection.mirror(display.stableID).isVisible(when: expandedSection) {
        height += CGFloat(controller.displays.count) * 30
      }
      if MenuSection.color(display.stableID).isVisible(when: expandedSection) { height += 250 }
      if MenuSection.profile(display.stableID).isVisible(when: expandedSection) {
        height += CGFloat(controller.profilesByDisplay[display.id]?.profiles.count ?? 1) * 30
      }
    }
    if arrangementExpanded {
      height += 230
      if primaryListExpanded { height += CGFloat(controller.layout.count) * 30 }
    }
    if controller.launchAtLoginStatus.reason != nil { height += 22 }
    return height
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("ClearDisplay").font(.headline)
        Spacer()
        Button {
          controller.refresh()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help("刷新显示器状态")
        .disabled(controller.isBusy)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)

      Divider()
      ScrollView {
        VStack(spacing: 0) {
          if controller.displays.isEmpty && controller.disconnectedDisplays.isEmpty {
            ContentUnavailableView("未检测到显示器", systemImage: "display.slash")
              .frame(height: 150)
          }
          ForEach(controller.displays) { display in
            displayCard(display)
            Divider()
          }
          ForEach(controller.disconnectedDisplays) { display in
            disconnectedCard(display)
            Divider()
          }
          globalControls
        }
        .frame(width: 390)
      }
      .scrollIndicators(.hidden)
      .frame(
        height: min(menuContentHeight, max(400, (NSScreen.main?.visibleFrame.height ?? 900) - 140))
      )
      .animation(.easeInOut(duration: 0.18), value: menuContentHeight)

      if let error = controller.errorMessage {
        Divider()
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .padding(12)
      }
      Divider()
      HStack {
        Text("状态以系统读取结果为准")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer()
        Button("退出") { NSApplication.shared.terminate(nil) }
          .buttonStyle(.borderless)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
    .frame(width: 390)
  }

  private func displayCard(_ display: DisplayInfo) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Button {
          toggleExpansion(display.stableID)
        } label: {
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              Text(display.name).font(.subheadline.weight(.semibold)).lineLimit(1)
              Text(
                "\(display.isBuiltin ? "内建显示器" : "外接显示器") · \(dimensions(display.logicalSize)) · \(refreshValue(display.refreshRate))"
              )
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
            }
            Spacer(minLength: 0)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expandedDisplays.contains(display.stableID) ? "已展开" : "已折叠")
        Toggle(
          "连接 \(display.name)",
          isOn: Binding(
            get: { true },
            set: { enabled in
              if !enabled { Task { await controller.disconnect(display) } }
            }
          )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
        .disabled(controller.isBusy || !controller.connectionSupported)
        .help("断开此显示器；至少保留一台活动显示器")
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)

      if expandedDisplays.contains(display.stableID) {
        VStack(alignment: .leading, spacing: 10) {
          Text("桌面 \(dimensions(display.logicalSize)) · 渲染 \(dimensions(display.pixelSize))")
            .font(.caption2)
            .foregroundStyle(.secondary)
          brightnessControl(display)
          if !display.isBuiltin {
            stateRow(
              "HiDPI", icon: "sparkles.rectangle.stack", enabled: display.hiDPIEnabled,
              disabled: !display.canToggleHiDPI || controller.isBusy
            ) {
              Task { await controller.setHiDPI(for: display.id, enabled: !display.hiDPIEnabled) }
            }
            .help(display.unavailableReason ?? "保持桌面大小和刷新率切换渲染密度")
            if !display.canToggleHiDPI, let reason = display.unavailableReason {
              Text(reason).font(.caption2).foregroundStyle(.secondary)
            }
          }
          resolutionControl(display)
          refreshControl(display)
          topologyControls(display)
          section(
            "色彩与图像", key: .color(display.stableID),
            detail: controller.profilesByDisplay[display.id]?.currentName
          ) {
            colorControls(display)
            softwareColorControls(display)
          }
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.bottom, 14)
      }
    }
  }

  private func disconnectedCard(_ display: DisconnectedDisplay) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "display.slash").frame(width: 14)
      VStack(alignment: .leading, spacing: 2) {
        Text(display.name).font(.subheadline.weight(.semibold))
        Text("已断开 · \(display.isBuiltin ? "内建显示器" : "外接显示器")")
          .font(.caption2).foregroundStyle(.secondary)
      }
      Spacer()
      Toggle(
        "连接 \(display.name)",
        isOn: Binding(
          get: { false },
          set: { enabled in if enabled { Task { await controller.reconnect(display) } } }
        )
      )
      .labelsHidden().toggleStyle(.switch).controlSize(.small)
      .disabled(controller.isBusy || !controller.connectionSupported)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var globalControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("通用设置")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      if !controller.layout.isEmpty {
        VStack(alignment: .leading, spacing: 9) {
          Button {
            withAnimation(.easeInOut(duration: 0.18)) {
              arrangementExpanded.toggle()
              expandedSection = nil
              if !arrangementExpanded { primaryListExpanded = false }
            }
          } label: {
            HStack {
              Text("显示器排列与主屏")
              Spacer()
              Image(systemName: arrangementExpanded ? "chevron.down" : "chevron.right")
            }
            .padding(9)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          if arrangementExpanded {
            DisplayArrangementView(
              controller: controller, primaryListExpanded: $primaryListExpanded
            )
            .padding(.horizontal, 9)
            .padding(.bottom, 9)
          }
        }
        .background(
          arrangementExpanded ? Color.white : Color.secondary.opacity(0.1),
          in: RoundedRectangle(cornerRadius: 8)
        )
        .environment(\.colorScheme, arrangementExpanded ? .light : colorScheme)
      }
      HStack(spacing: 8) {
        appearanceTile
        stateTile(
          "夜览", icon: "moon.stars.fill", enabled: controller.nightShiftState?.isEnabled == true,
          disabled: controller.isBusy || controller.globalControlsBusy
            || controller.nightShiftState?.isSupported != true
        ) {
          controller.setNightShift(controller.nightShiftState?.isEnabled != true)
        }
        stateTile(
          "原彩", icon: "sparkles", enabled: controller.trueToneStatus?.isEnabled == true,
          disabled: controller.isBusy || controller.globalControlsBusy
            || controller.trueToneStatus?.isAvailable != true
        ) {
          Task { await controller.setTrueTone(controller.trueToneStatus?.isEnabled != true) }
        }
        .help(controller.trueToneStatus?.unavailableReason ?? "切换系统原彩显示")
      }
      stateRow(
        "开机自启动", icon: "power", enabled: controller.launchAtLoginEnabled,
        disabled: !controller.launchAtLoginSupported
      ) {
        controller.setLaunchAtLogin(!controller.launchAtLoginEnabled)
      }
      .help(controller.launchAtLoginStatus.reason ?? "开机后自动启动 ClearDisplay")
      if let reason = controller.launchAtLoginStatus.reason {
        Text(reason).font(.caption2).foregroundStyle(.secondary)
      }
    }
    .padding(16)
  }

  private var appearanceTile: some View {
    stateTile(
      "外观", icon: controller.appearanceMode == .dark ? "moon.fill" : "sun.max.fill",
      enabled: controller.appearanceMode == .dark,
      disabled: controller.isBusy || controller.globalControlsBusy
        || controller.appearanceMode == nil || controller.appearanceMode == .automatic
    ) {
      controller.setAppearance(controller.appearanceMode == .dark ? .light : .dark)
    }
    .help(controller.appearanceMode == .automatic ? "自动外观请在系统设置中调整" : "切换浅色与深色外观")
  }

  private func stateTile(
    _ title: String, icon: String, enabled: Bool, disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) { tileLabel(title, icon: icon, enabled: enabled) }
      .buttonStyle(.plain)
      .disabled(disabled)
  }

  private func tileLabel(_ title: String, icon: String, enabled: Bool) -> some View {
    VStack(spacing: 5) {
      Image(systemName: icon).font(.system(size: 16, weight: .medium))
      Text(title).font(.caption)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 55)
    .background(
      enabled ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.1),
      in: RoundedRectangle(cornerRadius: 9)
    )
    .contentShape(RoundedRectangle(cornerRadius: 9))
  }

  private func stateRow(
    _ title: String, icon: String, enabled: Bool, disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .frame(width: 29, height: 29)
          .background(
            enabled ? Color.accentColor.opacity(0.24) : Color.secondary.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 7))
        Text(title)
        Spacer()
        Text(enabled ? "开启" : "关闭").font(.caption).foregroundStyle(.secondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(disabled)
  }

  private func section<Content: View>(
    _ title: String, key: MenuSection, detail: String?,
    @ViewBuilder content: () -> Content
  ) -> some View {
    let expanded = key.isVisible(when: expandedSection)
    return VStack(alignment: .leading, spacing: 9) {
      Button {
        toggleSection(key)
      } label: {
        HStack(spacing: 8) {
          Text(title).font(.caption.weight(.semibold))
          Spacer()
          if let detail { Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
          Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.caption2)
        }
        .padding(9)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if expanded {
        VStack(alignment: .leading, spacing: 9, content: content)
          .padding(.horizontal, 9)
          .padding(.bottom, 9)
      }
    }
    .background(
      expanded ? Color.white : Color.secondary.opacity(0.1),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .environment(\.colorScheme, expanded ? .light : colorScheme)
  }

  private func resolutionControl(_ display: DisplayInfo) -> some View {
    let modes = controller.modesByDisplay[display.id] ?? []
    let current = modes.first(where: \.isCurrent)
    let resolutions = DisplayModeCatalog.desktopResolutions(
      modes, hiDPI: current?.isHiDPI ?? display.hiDPIEnabled)
    let recommendation = DisplayModeCatalog.recommendedResolution(modes)
    let key = MenuSection.resolution(display.stableID)
    return section("分辨率", key: key, detail: current.map { resolutionLabel($0.resolutionKey) }) {
      ForEach(resolutions, id: \.self) { resolution in
        let options = DisplayModeCatalog.refreshChoices(for: resolution, in: modes)
        if let mode = preferredMode(options, current: current) {
          Button {
            Task { await controller.setMode(mode, for: display.id) }
          } label: {
            HStack {
              Text("\(resolution == recommendation ? "★ " : "")\(resolutionLabel(resolution))")
              Spacer()
              Text(
                resolutionDetail(
                  resolution, mode: mode, current: current,
                  recommended: recommendation)
              )
              .font(.caption2).foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)
          .padding(.vertical, 3)
          .disabled(controller.isBusy)
        }
      }
    }
  }

  private func refreshControl(_ display: DisplayInfo) -> some View {
    let modes = controller.modesByDisplay[display.id] ?? []
    let current = modes.first(where: \.isCurrent)
    let key = MenuSection.refresh(display.stableID)
    return section("刷新率", key: key, detail: current.map(refreshLabel)) {
      if let current {
        ForEach(distinctRefreshChoices(for: current.resolutionKey, in: modes)) { mode in
          Button {
            Task { await controller.setMode(mode, for: display.id) }
          } label: {
            HStack {
              Text(refreshLabel(mode))
              Spacer()
              if mode.isCurrent { Text("当前").font(.caption2).foregroundStyle(.secondary) }
            }
          }
          .buttonStyle(.plain)
          .padding(.vertical, 3)
          .disabled(controller.isBusy)
        }
      }
    }
  }

  private func topologyControls(_ display: DisplayInfo) -> some View {
    let relationship = controller.relationships[display.id]
    return VStack(alignment: .leading, spacing: 9) {
      section(
        "旋转", key: .rotation(display.stableID),
        detail: "\(relationship?.rotationDegrees ?? 0)°"
      ) {
        ForEach(DisplayTopologyService.candidateRotations, id: \.self) { degrees in
          Button {
            Task { await controller.setRotation(degrees, for: display.id) }
          } label: {
            HStack {
              Text("\(degrees)°")
              Spacer()
              if relationship?.rotationDegrees == degrees {
                Image(systemName: "checkmark").foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
          .padding(.vertical, 3)
          .disabled(controller.isBusy || relationship == nil)
        }
      }
      section("镜像", key: .mirror(display.stableID), detail: mirrorLabel(display)) {
        Button {
          Task { await controller.setMirror(source: nil, for: display.id) }
        } label: {
          HStack {
            Text("扩展桌面")
            Spacer()
            if relationship?.mirrorsDisplayID == nil {
              Image(systemName: "checkmark").foregroundStyle(.secondary)
            }
          }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
        .disabled(controller.isBusy || controller.displays.count < 2)
        ForEach(
          controller.displays.filter {
            $0.id != display.id && controller.relationships[$0.id]?.mirrorsDisplayID == nil
          }
        ) { source in
          Button {
            Task { await controller.setMirror(source: source.id, for: display.id) }
          } label: {
            HStack {
              Text("镜像 \(source.name)")
              Spacer()
              if relationship?.mirrorsDisplayID == source.id {
                Image(systemName: "checkmark").foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
          .padding(.vertical, 3)
          .disabled(controller.isBusy || controller.displays.count < 2)
        }
      }
    }
  }

  @ViewBuilder
  private func colorControls(_ display: DisplayInfo) -> some View {
    let busy = controller.isBusy || controller.busyDisplays.contains(display.id)
    if !display.isBuiltin, let hdr = controller.hdrByDisplay[display.id],
      hdr.isSupported, let enabled = hdr.isEnabled
    {
      stateRow("HDR", icon: "sun.max.fill", enabled: enabled, disabled: busy) {
        Task { await controller.setHDR(!enabled, for: display.id) }
      }
    }
    let profileStatus = controller.profilesByDisplay[display.id]
    section(
      "色彩文件", key: .profile(display.stableID),
      detail: profileStatus?.currentName ?? "未读取到当前配置"
    ) {
      if profileStatus?.profiles.isEmpty != false {
        Text("暂无可选色彩文件").font(.caption2).foregroundStyle(.secondary)
      } else {
        ForEach(profileStatus?.profiles ?? []) { profile in
          Button {
            Task { await controller.setProfile(profile, for: display.id) }
          } label: {
            HStack {
              Text(profile.name)
              Spacer()
              if profile.url == profileStatus?.currentURL {
                Image(systemName: "checkmark").foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
          .padding(.vertical, 3)
          .disabled(busy)
        }
      }
    }
    if !display.isBuiltin, let contrast = controller.contrastByDisplay[display.id],
      contrast.isAdjustable, let value = contrast.value
    {
      sliderRow(
        "对比度",
        value: Binding(
          get: { controller.contrastDrafts[display.id] ?? value },
          set: {
            controller.contrastDrafts[display.id] = $0
            controller.contrastDraftChanged(for: display.id)
          }
        ), range: 0...100, step: 1,
        label: "\(Int((controller.contrastDrafts[display.id] ?? value).rounded()))%",
        disabled: busy,
        onEditingChanged: { controller.contrastEditingChanged(for: display.id, editing: $0) })
    }
    if !display.isBuiltin, let temperature = controller.temperatureByDisplay[display.id],
      temperature.isAdjustable, let current = temperature.value
    {
      sliderRow(
        "硬件色温",
        value: Binding(
          get: {
            hardwareTemperatureIndex(controller.hardwareTemperatureDrafts[display.id] ?? current)
          },
          set: {
            controller.hardwareTemperatureDrafts[display.id] =
              hardwareTemperaturePresets[Int($0.rounded())]
            controller.hardwareTemperatureDraftChanged(for: display.id)
          }
        ), range: 0...3, step: 1,
        label: "\(Int((controller.hardwareTemperatureDrafts[display.id] ?? current).rounded())) K",
        disabled: busy,
        onEditingChanged: {
          controller.hardwareTemperatureEditingChanged(for: display.id, editing: $0)
        })
    }
  }

  @ViewBuilder
  private func softwareColorControls(_ display: DisplayInfo) -> some View {
    if let status = controller.softwareByDisplay[display.id],
      status.reason == nil || status.reason == "No app-managed transfer is active."
    {
      let busy = controller.isBusy || controller.busyDisplays.contains(display.id)
      let hdr = controller.hdrByDisplay[display.id]?.isEnabled == true
      sliderRow(
        "软件色温",
        value: Binding(
          get: {
            controller.softwareTemperatureDrafts[display.id] ?? Double(status.kelvin ?? 6500)
          },
          set: {
            controller.softwareTemperatureDrafts[display.id] = $0
            controller.setSoftwareTransferLive(for: display.id)
          }
        ), range: 4000...10000, step: 100,
        label:
          "\(Int((controller.softwareTemperatureDrafts[display.id] ?? Double(status.kelvin ?? 6500)).rounded())) K",
        disabled: busy || hdr,
        onEditingChanged: { if !$0 { controller.finishSoftwareTransferEditing(for: display.id) } })
      sliderRow(
        "Gamma",
        value: Binding(
          get: { controller.gammaDrafts[display.id] ?? status.gamma ?? 1.0 },
          set: {
            controller.gammaDrafts[display.id] = $0
            controller.setSoftwareTransferLive(for: display.id)
          }
        ), range: 0.5...2.0, step: 0.01,
        label: String(format: "%.2f", controller.gammaDrafts[display.id] ?? status.gamma ?? 1.0),
        disabled: busy || hdr,
        onEditingChanged: { if !$0 { controller.finishSoftwareTransferEditing(for: display.id) } })
      Button("还原默认值") { controller.resetSoftwareTransfer(for: display.id) }
        .font(.caption)
        .disabled(busy || hdr)
      if hdr {
        Text("HDR 开启时无法调整软件 Gamma / 色温")
          .font(.caption2).foregroundStyle(.secondary)
      }
    }
  }

  private func sliderRow(
    _ title: String, value: Binding<Double>, range: ClosedRange<Double>,
    step: Double, label: String, disabled: Bool,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.caption).foregroundStyle(.secondary)
      ContrastSlider(
        title: title, displayValue: label, value: value, range: range, step: step,
        onEditingChanged: onEditingChanged
      )
      .disabled(disabled)
    }
  }

  @ViewBuilder
  private func brightnessControl(_ display: DisplayInfo) -> some View {
    let status = controller.brightnessByDisplay[display.id]
    sliderRow(
      "亮度",
      value: Binding(
        get: { controller.brightnessDrafts[display.id] ?? status?.percent ?? 50 },
        set: {
          controller.brightnessDrafts[display.id] = $0
          controller.brightnessDraftChanged(for: display.id)
        }
      ), range: 0...100, step: 1,
      label: (controller.brightnessDrafts[display.id] ?? status?.percent)
        .map { "\(Int($0.rounded()))%" } ?? "—",
      disabled: status?.isAdjustable != true || controller.busyDisplays.contains(display.id)
        || controller.isBusy,
      onEditingChanged: { controller.brightnessEditingChanged(for: display.id, editing: $0) }
    )
    .help(status?.unavailableReason ?? "调节显示器亮度")
  }

  private func resolutionDetail(
    _ key: ResolutionKey, mode: DisplayModeOption,
    current: DisplayModeOption?, recommended: ResolutionKey?
  ) -> String {
    var parts: [String] = []
    if key == recommended { parts.append("ClearDisplay 推荐") }
    if key == current?.resolutionKey { parts.append("当前") }
    if mode.isNative && !mode.isHiDPI { parts.append("原生") }
    return parts.joined(separator: " · ")
  }

  private func preferredMode(_ options: [DisplayModeOption], current: DisplayModeOption?)
    -> DisplayModeOption?
  {
    options.first(where: { $0.isCurrent })
      ?? options.first(where: { abs($0.refreshRateHz - (current?.refreshRateHz ?? 60)) < 0.01 })
      ?? options.first
  }

  private func distinctRefreshChoices(for key: ResolutionKey, in modes: [DisplayModeOption])
    -> [DisplayModeOption]
  {
    let choices = DisplayModeCatalog.refreshChoices(for: key, in: modes)
    var distinct: [DisplayModeOption] = []
    for choice in choices {
      if let index = distinct.firstIndex(where: {
        abs($0.refreshRateHz - choice.refreshRateHz) < 0.01
      }) {
        if choice.isCurrent { distinct[index] = choice }
      } else {
        distinct.append(choice)
      }
    }
    return distinct
  }

  private func mirrorLabel(_ display: DisplayInfo) -> String {
    guard let id = controller.relationships[display.id]?.mirrorsDisplayID else { return "扩展" }
    return "镜像 \(controller.displays.first(where: { $0.id == id })?.name ?? "显示器")"
  }

  private func toggleExpansion(_ id: String) {
    withAnimation(.easeInOut(duration: 0.18)) {
      if expandedDisplays.contains(id) {
        expandedDisplays.remove(id)
      } else {
        expandedDisplays.insert(id)
      }
    }
  }

  private func toggleSection(_ key: MenuSection) {
    withAnimation(.easeInOut(duration: 0.18)) {
      arrangementExpanded = false
      primaryListExpanded = false
      if case .profile(let id) = key, expandedSection == key {
        expandedSection = .color(id)
      } else {
        expandedSection = expandedSection == key ? nil : key
      }
    }
  }

  private func resolutionLabel(_ key: ResolutionKey) -> String {
    "\(key.width)×\(key.height)"
  }

  private func refreshLabel(_ mode: DisplayModeOption) -> String {
    refreshValue(mode.refreshRateHz)
  }

  private func refreshValue(_ hertz: Double) -> String {
    hertz > 0 ? String(format: "%.2f Hz", hertz) : "刷新率未知"
  }

  private func dimensions(_ size: CGSize) -> String {
    "\(Int(size.width))×\(Int(size.height))"
  }

  private var hardwareTemperaturePresets: [Double] { [5000, 6500, 7500, 9300] }

  private func hardwareTemperatureIndex(_ kelvin: Double) -> Double {
    let closest = hardwareTemperaturePresets.enumerated().min {
      abs($0.element - kelvin) < abs($1.element - kelvin)
    }
    return Double(closest?.offset ?? 1)
  }
}
