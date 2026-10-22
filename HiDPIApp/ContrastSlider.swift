import SwiftUI

/// A compact slider with a visible filled track in both system appearances.
struct ContrastSlider: View {
  let title: String
  @Binding var value: Double
  let range: ClosedRange<Double>
  let step: Double
  let onEditingChanged: (Bool) -> Void

  @State private var isDragging = false

  private let thumbSize: CGFloat = 16

  var body: some View {
    GeometryReader { geometry in
      let travel = max(geometry.size.width - thumbSize, 1)
      let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
        .clamped(to: 0...1)

      ZStack(alignment: .leading) {
        Capsule()
          .fill(Color.primary.opacity(0.36))
          .frame(height: 6)
          .padding(.horizontal, thumbSize / 2)
        Capsule()
          .fill(Color.accentColor)
          .frame(width: travel * fraction, height: 6)
          .offset(x: thumbSize / 2)
        Circle()
          .fill(.white)
          .overlay(Circle().strokeBorder(Color.black.opacity(0.3), lineWidth: 1))
          .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
          .frame(width: thumbSize, height: thumbSize)
          .offset(x: travel * fraction)
      }
      .frame(height: geometry.size.height)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { drag in
            if !isDragging {
              isDragging = true
              onEditingChanged(true)
            }
            let fraction = min(max((drag.location.x - thumbSize / 2) / travel, 0), 1)
            setValue(range.lowerBound + Double(fraction) * (range.upperBound - range.lowerBound))
          }
          .onEnded { _ in
            isDragging = false
            onEditingChanged(false)
          }
      )
    }
    .frame(height: 22)
    .opacity(isEnabled ? 1 : 0.5)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(String(format: "%.2f", value))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment: setValue(value + step)
      case .decrement: setValue(value - step)
      @unknown default: break
      }
    }
  }

  @Environment(\.isEnabled) private var isEnabled

  private func setValue(_ proposed: Double) {
    let clamped = min(max(proposed, range.lowerBound), range.upperBound)
    let stepped = range.lowerBound + ((clamped - range.lowerBound) / step).rounded() * step
    value = min(max(stepped, range.lowerBound), range.upperBound)
  }
}

extension CGFloat {
  fileprivate func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}
