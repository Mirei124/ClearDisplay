import CoreGraphics
import SwiftUI

struct DisplayArrangementView: View {
  @ObservedObject var controller: DisplayController
  @State private var origins: [CGDirectDisplayID: CGPoint] = [:]
  @State private var primaryID: CGDirectDisplayID = 0
  @State private var draggingID: CGDirectDisplayID?
  @State private var dragStartOrigin: CGPoint?
  @State private var dragScale: CGFloat?

  private var items: [DisplayLayoutItem] { controller.layout }
  private var hasChanges: Bool {
    primaryID != items.first(where: \.isMain)?.id
      || items.contains {
        origins[$0.id] != $0.origin
      }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("排列显示器").font(.subheadline.weight(.semibold))
        Spacer()
        Button("重置") { reset() }
          .disabled(!hasChanges || controller.isBusy)
      }
      if items.count < 2 {
        Text("连接两台或更多扩展显示器后可调整排列。")
          .font(.caption).foregroundStyle(.secondary)
      } else if items.contains(where: { controller.relationships[$0.id]?.mirrorsDisplayID != nil })
      {
        Text("请先结束镜像，再调整排列。")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        GeometryReader { geometry in
          let bounds = layoutBounds
          let scale = min(
            (geometry.size.width - 24) / max(bounds.width, 1),
            (geometry.size.height - 24) / max(bounds.height, 1))
          ZStack(alignment: .topLeading) {
            ForEach(items) { item in
              let origin = origins[item.id] ?? item.origin
              let name = controller.displays.first(where: { $0.id == item.id })?.name ?? "显示器"
              RoundedRectangle(cornerRadius: 6)
                .fill(
                  item.id == primaryID
                    ? Color.accentColor.opacity(0.23) : Color.secondary.opacity(0.16)
                )
                .overlay {
                  VStack(spacing: 2) {
                    Text(name).lineLimit(1)
                    if item.id == primaryID { Text("主显示器").font(.caption2) }
                  }
                  .font(.caption)
                  .padding(4)
                }
                .overlay(
                  RoundedRectangle(cornerRadius: 6).strokeBorder(
                    item.id == primaryID ? Color.accentColor : Color.secondary)
                )
                .frame(
                  width: max(item.size.width * scale, 42), height: max(item.size.height * scale, 28)
                )
                .position(
                  x: (origin.x - bounds.minX + item.size.width / 2) * scale + 12,
                  y: (origin.y - bounds.minY + item.size.height / 2) * scale + 12
                )
                .gesture(
                  DragGesture(minimumDistance: 2)
                    .onChanged { value in
                      if draggingID == nil {
                        draggingID = item.id
                        dragStartOrigin = origins[item.id] ?? item.origin
                        dragScale = scale
                      }
                      guard draggingID == item.id, !controller.isBusy else { return }
                      let start = dragStartOrigin ?? item.origin
                      let initialScale = dragScale ?? scale
                      origins[item.id] = CGPoint(
                        x: start.x + (value.translation.width / initialScale).rounded(),
                        y: start.y + (value.translation.height / initialScale).rounded())
                    }
                    .onEnded { _ in
                      draggingID = nil
                      dragStartOrigin = nil
                      dragScale = nil
                    })
            }
          }
        }
        .frame(height: 130)
        .accessibilityLabel("拖动显示器方块以排列")
        HStack {
          Text("主显示器").font(.caption)
          Picker("主显示器", selection: $primaryID) {
            ForEach(items) { item in
              Text(controller.displays.first(where: { $0.id == item.id })?.name ?? "显示器 \(item.id)")
                .tag(item.id)
            }
          }
          .labelsHidden()
          Spacer()
          Button("应用排列") {
            Task { await controller.applyLayout(origins: origins, primaryID: primaryID) }
          }
          .disabled(!hasChanges || controller.isBusy)
        }
      }
    }
    .onAppear(perform: reset)
    .onChange(of: controller.layout) { _, _ in reset() }
  }

  private var layoutBounds: CGRect {
    items.reduce(CGRect.null) { partial, item in
      partial.union(CGRect(origin: origins[item.id] ?? item.origin, size: item.size))
    }
  }

  private func reset() {
    origins = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.origin) })
    primaryID = items.first(where: \.isMain)?.id ?? 0
  }
}
