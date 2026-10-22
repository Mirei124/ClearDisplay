import CoreGraphics
import SwiftUI

struct DisplayArrangementView: View {
  @ObservedObject var controller: DisplayController
  @Binding var arrangementExpanded: Bool
  @Binding var primaryListExpanded: Bool
  let onArrangementExpanded: () -> Void
  let onPrimaryExpanded: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var origins: [CGDirectDisplayID: CGPoint] = [:]
  @State private var primaryID: CGDirectDisplayID = 0
  @State private var pendingOffsets: [CGDirectDisplayID: CGPoint]?
  @State private var draggingID: CGDirectDisplayID?
  @State private var dragStartOrigin: CGPoint?
  @State private var dragScale: CGFloat?
  @State private var dragBounds: CGRect?
  @State private var verticalGuide: CGFloat?
  @State private var horizontalGuide: CGFloat?

  private var items: [DisplayLayoutItem] { controller.layout }
  private var hasChanges: Bool {
    items.contains { origins[$0.id] != $0.origin }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Button(action: toggleArrangement) {
            HStack(spacing: 8) {
              Text("排列显示器").font(.subheadline.weight(.semibold))
              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          if arrangementExpanded {
            Button("重置") { reset() }
              .disabled(!hasChanges || controller.isBusy)
            Button("应用排列") {
              Task { await controller.applyLayout(origins: origins, primaryID: primaryID) }
            }
            .disabled(!hasChanges || controller.isBusy)
          }
          Button(action: toggleArrangement) {
            Image(systemName: arrangementExpanded ? "chevron.down" : "chevron.right")
              .font(.caption2)
              .frame(width: 20, height: 20)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        if arrangementExpanded {
          arrangementContent
            .padding(.horizontal, 9)
            .padding(.bottom, 9)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
        }
      }
      .background(
        arrangementExpanded ? Color.white : Color.secondary.opacity(0.1),
        in: RoundedRectangle(cornerRadius: 8)
      )
      .environment(\.colorScheme, arrangementExpanded ? .light : colorScheme)
      primarySelector
    }
    .onAppear(perform: reset)
    .onChange(of: controller.layout) { _, updated in
      if let pendingOffsets {
        origins = Dictionary(
          uniqueKeysWithValues: updated.map { item in
            let offset = pendingOffsets[item.id] ?? .zero
            return (item.id, CGPoint(x: item.origin.x + offset.x, y: item.origin.y + offset.y))
          })
        primaryID = updated.first(where: \.isMain)?.id ?? 0
      } else {
        reset()
      }
    }
  }

  private func toggleArrangement() {
    withAnimation(.easeInOut(duration: 0.18)) {
      arrangementExpanded.toggle()
      if arrangementExpanded { onArrangementExpanded() }
    }
  }

  @ViewBuilder
  private var arrangementContent: some View {
    if items.count < 2 {
      Text("连接两台或更多扩展显示器后可调整排列。")
        .font(.caption).foregroundStyle(.secondary)
    } else if items.contains(where: { controller.relationships[$0.id]?.mirrorsDisplayID != nil }) {
      Text("请先结束镜像，再调整排列。")
        .font(.caption).foregroundStyle(.secondary)
    } else {
      GeometryReader { geometry in
        let bounds = dragBounds ?? layoutBounds
        let scale = min(
          (geometry.size.width - 24) / max(bounds.width, 1),
          (geometry.size.height - 24) / max(bounds.height, 1))
        ZStack(alignment: .topLeading) {
          if let verticalGuide {
            Rectangle()
              .fill(Color.accentColor.opacity(0.7))
              .frame(width: 1, height: geometry.size.height)
              .offset(x: (verticalGuide - bounds.minX) * scale + 12)
              .allowsHitTesting(false)
          }
          if let horizontalGuide {
            Rectangle()
              .fill(Color.accentColor.opacity(0.7))
              .frame(width: geometry.size.width, height: 1)
              .offset(y: (horizontalGuide - bounds.minY) * scale + 12)
              .allowsHitTesting(false)
          }
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
                      dragBounds = bounds
                    }
                    guard draggingID == item.id, !controller.isBusy else { return }
                    let start = dragStartOrigin ?? item.origin
                    let initialScale = dragScale ?? scale
                    let proposed = CGPoint(
                      x: start.x + (value.translation.width / initialScale).rounded(),
                      y: start.y + (value.translation.height / initialScale).rounded())
                    let snapped = snap(item: item, proposed: proposed, scale: initialScale)
                    origins[item.id] = snapped.origin
                    verticalGuide = snapped.verticalGuide
                    horizontalGuide = snapped.horizontalGuide
                  }
                  .onEnded { _ in
                    draggingID = nil
                    dragStartOrigin = nil
                    dragScale = nil
                    dragBounds = nil
                    verticalGuide = nil
                    horizontalGuide = nil
                  })
          }
        }
      }
      .frame(height: 130)
      .accessibilityLabel("拖动显示器方块以排列")
    }
  }

  private var primarySelector: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button {
        withAnimation(.easeInOut(duration: 0.18)) {
          primaryListExpanded.toggle()
          if primaryListExpanded { onPrimaryExpanded() }
        }
      } label: {
        HStack {
          Text("主显示器").font(.caption.weight(.semibold))
          Spacer()
          Text(displayName(for: primaryID))
            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
          Image(systemName: primaryListExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2)
        }
        .padding(9)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if primaryListExpanded {
        ForEach(items) { item in
          Button {
            selectPrimary(item.id)
          } label: {
            HStack {
              Text(displayName(for: item.id))
              Spacer()
              if item.id == primaryID {
                Image(systemName: "checkmark").foregroundStyle(.secondary)
              }
            }
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 9)
          .padding(.vertical, 3)
          .disabled(controller.isBusy)
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
      }
    }
    .background(
      primaryListExpanded ? Color.white : Color.secondary.opacity(0.1),
      in: RoundedRectangle(cornerRadius: 8)
    )
    .environment(\.colorScheme, primaryListExpanded ? .light : colorScheme)
  }

  private func displayName(for id: CGDirectDisplayID) -> String {
    controller.displays.first(where: { $0.id == id })?.name ?? "显示器 \(id)"
  }

  private func selectPrimary(_ id: CGDirectDisplayID) {
    withAnimation(.easeInOut(duration: 0.18)) { primaryListExpanded = false }
    guard id != items.first(where: \.isMain)?.id, !controller.isBusy else { return }
    pendingOffsets = Dictionary(
      uniqueKeysWithValues: items.map { item in
        let draft = origins[item.id] ?? item.origin
        return (item.id, CGPoint(x: draft.x - item.origin.x, y: draft.y - item.origin.y))
      })
    primaryID = id
    let systemOrigins = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.origin) })
    Task {
      await controller.applyLayout(origins: systemOrigins, primaryID: id)
      if controller.layout.first(where: \.isMain)?.id != id {
        primaryID = controller.layout.first(where: \.isMain)?.id ?? 0
      }
      pendingOffsets = nil
    }
  }

  private var layoutBounds: CGRect {
    items.reduce(CGRect.null) { partial, item in
      partial.union(CGRect(origin: origins[item.id] ?? item.origin, size: item.size))
    }
  }

  private func snap(item: DisplayLayoutItem, proposed: CGPoint, scale: CGFloat)
    -> (origin: CGPoint, verticalGuide: CGFloat?, horizontalGuide: CGFloat?)
  {
    let moving = CGRect(origin: proposed, size: item.size)
    let threshold = 8 / max(scale, 0.001)
    var xMatch: (distance: CGFloat, offset: CGFloat, guide: CGFloat)?
    var yMatch: (distance: CGFloat, offset: CGFloat, guide: CGFloat)?
    for other in items where other.id != item.id {
      let target = CGRect(origin: origins[other.id] ?? other.origin, size: other.size)
      if moving.maxY >= target.minY - threshold && moving.minY <= target.maxY + threshold {
        for (source, destination) in [
          (moving.minX, target.minX), (moving.midX, target.midX),
          (moving.maxX, target.maxX), (moving.minX, target.maxX),
          (moving.maxX, target.minX),
        ] {
          let distance = abs(destination - source)
          if distance <= threshold && distance < (xMatch?.distance ?? .infinity) {
            xMatch = (distance, destination - source, destination)
          }
        }
      }
      if moving.maxX >= target.minX - threshold && moving.minX <= target.maxX + threshold {
        for (source, destination) in [
          (moving.minY, target.minY), (moving.midY, target.midY),
          (moving.maxY, target.maxY), (moving.minY, target.maxY),
          (moving.maxY, target.minY),
        ] {
          let distance = abs(destination - source)
          if distance <= threshold && distance < (yMatch?.distance ?? .infinity) {
            yMatch = (distance, destination - source, destination)
          }
        }
      }
    }
    return (
      CGPoint(x: proposed.x + (xMatch?.offset ?? 0), y: proposed.y + (yMatch?.offset ?? 0)),
      xMatch?.guide, yMatch?.guide
    )
  }

  private func reset() {
    pendingOffsets = nil
    primaryListExpanded = false
    dragBounds = nil
    verticalGuide = nil
    horizontalGuide = nil
    origins = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.origin) })
    primaryID = items.first(where: \.isMain)?.id ?? 0
  }
}
