import SwiftUI

struct DisplayMenuView: View {
  @ObservedObject var controller: DisplayController

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Label("显示器", systemImage: "display.2")
          .font(.headline)
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

      if controller.displays.isEmpty && controller.disconnectedDisplays.isEmpty {
        ContentUnavailableView("未检测到显示器", systemImage: "display.slash")
          .frame(width: 320, height: 150)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            if !controller.layout.isEmpty {
              DisplayArrangementView(controller: controller)
                .padding(16)
              Divider()
            }
            ForEach(controller.displays) { display in
              displayRow(display)
              if display.id != controller.displays.last?.id {
                Divider().padding(.leading, 16)
              }
            }
            ForEach(controller.disconnectedDisplays) { display in
              HStack {
                Label(display.name, systemImage: "display.slash")
                Spacer()
                Button("连接") { Task { await controller.reconnect(display) } }
                  .disabled(controller.isBusy || !controller.connectionSupported)
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
            }
          }
        }
        .frame(maxHeight: 570)
      }

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
    .frame(width: 380)
  }

  private func displayRow(_ display: DisplayInfo) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline) {
        Text(display.name)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
        Spacer(minLength: 8)
        Text(display.isBuiltin ? "内建" : "外接")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text("桌面 \(dimensions(display.logicalSize))  ·  渲染 \(dimensions(display.pixelSize))")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      brightnessControl(display)
      modeControls(display)
      topologyControls(display)
      colorControls(display)
      softwareColorControls(display)

      HStack {
        Text(display.refreshRate > 0 ? String(format: "%.2f Hz", display.refreshRate) : "刷新率未知")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        if !display.isBuiltin {
          Toggle(
            "HiDPI",
            isOn: Binding(
              get: { display.hiDPIEnabled },
              set: { newValue in
                Task { await controller.setHiDPI(for: display.id, enabled: newValue) }
              }
            )
          )
          .toggleStyle(.switch)
          .controlSize(.small)
          .disabled(!display.canToggleHiDPI || controller.isBusy)
          .help(display.unavailableReason ?? "保持桌面大小及刷新率切换渲染密度")
        }
      }

      if !display.isBuiltin, !display.canToggleHiDPI, let reason = display.unavailableReason {
        Text(reason)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
  }

  @ViewBuilder
  private func softwareColorControls(_ display: DisplayInfo) -> some View {
    if let status = controller.softwareByDisplay[display.id],
      status.reason == nil || status.reason == "No app-managed transfer is active."
    {
      let busy = controller.isBusy || controller.busyDisplays.contains(display.id)
      let hdr = controller.hdrByDisplay[display.id]?.isEnabled == true
      VStack(alignment: .leading, spacing: 5) {
        HStack {
          Text("软件 Gamma / 色温")
            .font(.caption.weight(.medium))
          Spacer()
          if status.gamma != nil {
            Button("重置") { controller.resetSoftwareTransfer(for: display.id) }
              .font(.caption)
              .disabled(busy)
          }
        }
        HStack {
          Text("Gamma").font(.caption)
          Slider(
            value: Binding(
              get: { controller.gammaDrafts[display.id] ?? status.gamma ?? 1.0 },
              set: { controller.gammaDrafts[display.id] = $0 }
            ), in: 0.5...2.0)
          Text(String(format: "%.2f", controller.gammaDrafts[display.id] ?? status.gamma ?? 1.0))
            .font(.caption.monospacedDigit())
            .frame(width: 38, alignment: .trailing)
        }
        HStack {
          Text("色温").font(.caption)
          Slider(
            value: Binding(
              get: {
                controller.softwareTemperatureDrafts[display.id] ?? Double(status.kelvin ?? 6500)
              },
              set: { controller.softwareTemperatureDrafts[display.id] = $0 }
            ), in: 4000...10000, step: 100)
          Text(
            "\(Int((controller.softwareTemperatureDrafts[display.id] ?? Double(status.kelvin ?? 6500)).rounded())) K"
          )
          .font(.caption.monospacedDigit())
          .frame(width: 54, alignment: .trailing)
        }
        HStack {
          if let gamma = status.gamma, let kelvin = status.kelvin {
            Text(String(format: "当前 %.2f / %d K", gamma, kelvin))
              .font(.caption2)
              .foregroundStyle(.secondary)
          } else {
            Text("当前未启用软件调整")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Button("应用") { controller.applySoftwareTransfer(for: display.id) }
            .font(.caption)
            .disabled(busy || hdr)
        }
        if hdr {
          Text("HDR 开启时无法应用软件 Gamma / 色温")
            .font(.caption2)
            .foregroundStyle(.secondary)
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
      Toggle(
        "HDR",
        isOn: Binding(
          get: { controller.hdrByDisplay[display.id]?.isEnabled ?? enabled },
          set: { value in Task { await controller.setHDR(value, for: display.id) } }
        )
      )
      .toggleStyle(.switch)
      .controlSize(.small)
      .disabled(busy)
    }

    if let profileStatus = controller.profilesByDisplay[display.id],
      !profileStatus.profiles.isEmpty
    {
      Menu {
        ForEach(profileStatus.profiles) { profile in
          Button {
            Task { await controller.setProfile(profile, for: display.id) }
          } label: {
            if profile.url == profileStatus.currentURL {
              Label(profile.name, systemImage: "checkmark")
            } else {
              Text(profile.name)
            }
          }
        }
      } label: {
        Label(profileStatus.currentName ?? "色彩描述文件", systemImage: "paintpalette")
          .font(.caption)
          .lineLimit(1)
      }
      .disabled(busy)
    }

    if !display.isBuiltin, let contrast = controller.contrastByDisplay[display.id],
      contrast.isAdjustable, let value = contrast.value
    {
      HStack {
        Text("对比度").font(.caption)
        Slider(
          value: Binding(
            get: { controller.contrastDrafts[display.id] ?? value },
            set: { controller.contrastDrafts[display.id] = $0 }
          ), in: 0...100,
          onEditingChanged: { editing in
            if !editing { Task { await controller.setContrast(for: display.id) } }
          }
        )
        .disabled(busy)
        Text("\(Int((controller.contrastDrafts[display.id] ?? value).rounded()))%")
          .font(.caption.monospacedDigit())
          .frame(width: 38, alignment: .trailing)
      }
    }

    if !display.isBuiltin, let temperature = controller.temperatureByDisplay[display.id],
      temperature.isAdjustable, let current = temperature.value
    {
      Menu {
        ForEach([5000, 6500, 7500, 9300], id: \.self) { kelvin in
          Button {
            Task { await controller.setHardwareTemperature(kelvin, for: display.id) }
          } label: {
            if current == Double(kelvin) {
              Label("\(kelvin) K", systemImage: "checkmark")
            } else {
              Text("\(kelvin) K")
            }
          }
        }
      } label: {
        Label("色温 \(Int(current)) K", systemImage: "thermometer.medium")
          .font(.caption)
      }
      .disabled(busy)
    }
  }

  private func topologyControls(_ display: DisplayInfo) -> some View {
    HStack {
      let relationship = controller.relationships[display.id]
      Menu {
        ForEach(DisplayTopologyService.candidateRotations, id: \.self) { degrees in
          Button {
            Task { await controller.setRotation(degrees, for: display.id) }
          } label: {
            if relationship?.rotationDegrees == degrees {
              Label("\(degrees)°", systemImage: "checkmark")
            } else {
              Text("\(degrees)°")
            }
          }
        }
      } label: {
        Label("旋转 \(relationship?.rotationDegrees ?? 0)°", systemImage: "rotate.right")
          .font(.caption)
      }
      .disabled(controller.isBusy || relationship == nil)

      Menu {
        Button {
          Task { await controller.setMirror(source: nil, for: display.id) }
        } label: {
          if relationship?.mirrorsDisplayID == nil {
            Label("扩展桌面", systemImage: "checkmark")
          } else {
            Text("扩展桌面")
          }
        }
        ForEach(
          controller.displays.filter {
            $0.id != display.id && controller.relationships[$0.id]?.mirrorsDisplayID == nil
          }
        ) { source in
          Button {
            Task { await controller.setMirror(source: source.id, for: display.id) }
          } label: {
            if relationship?.mirrorsDisplayID == source.id {
              Label("镜像 \(source.name)", systemImage: "checkmark")
            } else {
              Text("镜像 \(source.name)")
            }
          }
        }
      } label: {
        Label("镜像", systemImage: "rectangle.on.rectangle")
          .font(.caption)
      }
      .disabled(controller.isBusy || controller.displays.count < 2)
      Spacer()
      Button("断开") { Task { await controller.disconnect(display) } }
        .font(.caption)
        .disabled(controller.isBusy || !controller.connectionSupported)
        .help("暂时断开此显示器；至少保留一台活动显示器")
    }
  }

  @ViewBuilder
  private func brightnessControl(_ display: DisplayInfo) -> some View {
    let status = controller.brightnessByDisplay[display.id]
    HStack {
      Image(systemName: "sun.min")
        .foregroundStyle(.secondary)
      Slider(
        value: Binding(
          get: { controller.brightnessDrafts[display.id] ?? status?.percent ?? 50 },
          set: { controller.brightnessDrafts[display.id] = $0 }
        ),
        in: 0...100,
        onEditingChanged: { editing in
          controller.brightnessEditingChanged(for: display.id, editing: editing)
        }
      )
      .disabled(
        status?.isAdjustable != true || controller.busyDisplays.contains(display.id)
          || controller.isBusy)
      Image(systemName: "sun.max")
        .foregroundStyle(.secondary)
      Text(status?.percent.map { "\(Int($0.rounded()))%" } ?? "—")
        .font(.caption.monospacedDigit())
        .frame(width: 38, alignment: .trailing)
    }
    .help(status?.unavailableReason ?? "调节显示器亮度")
  }

  @ViewBuilder
  private func modeControls(_ display: DisplayInfo) -> some View {
    let modes = controller.modesByDisplay[display.id] ?? []
    let current = modes.first(where: \.isCurrent)
    let key = current?.resolutionKey
    let resolutions = DisplayModeCatalog.groupedResolutions(modes)
    HStack {
      Menu {
        ForEach(resolutions, id: \.self) { resolution in
          let options = DisplayModeCatalog.refreshChoices(for: resolution, in: modes)
          if let mode = preferredMode(options, current: current) {
            Button {
              Task { await controller.setMode(mode, for: display.id) }
            } label: {
              if resolution == key {
                Label(resolutionLabel(resolution), systemImage: "checkmark")
              } else {
                Text(resolutionLabel(resolution))
              }
            }
          }
        }
      } label: {
        Label(key.map(resolutionLabel) ?? "分辨率", systemImage: "rectangle.expand.vertical")
          .font(.caption)
      }
      .disabled(resolutions.isEmpty || controller.isBusy)

      Spacer()

      Menu {
        if let key {
          ForEach(distinctRefreshChoices(for: key, in: modes)) { mode in
            Button {
              Task { await controller.setMode(mode, for: display.id) }
            } label: {
              if mode.isCurrent {
                Label(refreshLabel(mode), systemImage: "checkmark")
              } else {
                Text(refreshLabel(mode))
              }
            }
          }
        }
      } label: {
        Label(current.map(refreshLabel) ?? "刷新率", systemImage: "arrow.clockwise")
          .font(.caption)
      }
      .disabled(key == nil || controller.isBusy)
    }
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

  private func resolutionLabel(_ key: ResolutionKey) -> String {
    "\(key.width)×\(key.height)\(key.isHiDPI ? " HiDPI" : "")"
  }

  private func refreshLabel(_ mode: DisplayModeOption) -> String {
    String(format: "%.2f Hz", mode.refreshRateHz)
  }

  private func dimensions(_ size: CGSize) -> String {
    "\(Int(size.width))×\(Int(size.height))"
  }
}
