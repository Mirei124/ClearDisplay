import AppKit
import SwiftUI

struct MenuHeightKey: PreferenceKey {
  static var defaultValue: [String: CGFloat] = [:]

  static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
    value.merge(nextValue(), uniquingKeysWith: { _, new in new })
  }
}

extension View {
  func measureMenuHeight(_ name: String) -> some View {
    background {
      GeometryReader { geometry in
        Color.clear.preference(key: MenuHeightKey.self, value: [name: geometry.size.height])
      }
    }
  }
}

/// Keeps the AppKit host in step with the measured SwiftUI root, including MenuBarExtra.
struct MenuWindowSizing: NSViewRepresentable {
  let height: CGFloat
  let availableHeight: (CGFloat) -> Void

  func makeNSView(context: Context) -> SizingView { SizingView() }

  func updateNSView(_ view: SizingView, context: Context) {
    view.targetHeight = height
    view.availableHeight = availableHeight
    view.scheduleUpdate()
  }

  final class SizingView: NSView {
    var targetHeight: CGFloat = 0
    var availableHeight: ((CGFloat) -> Void)?
    private var pending = false
    private var observers: [NSObjectProtocol] = []
    private var lastAvailableHeight: CGFloat?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      observers.forEach(NotificationCenter.default.removeObserver)
      observers.removeAll()
      lastAvailableHeight = nil
      if let window {
        for name in [NSWindow.didChangeScreenNotification, NSWindow.didBecomeKeyNotification] {
          observers.append(
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
              [weak self] _ in self?.scheduleUpdate()
            })
        }
        observers.append(
          NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
          ) { [weak self] _ in self?.scheduleUpdate() })
      }
      scheduleUpdate()
    }

    deinit {
      observers.forEach(NotificationCenter.default.removeObserver)
    }

    func scheduleUpdate() {
      guard !pending else { return }
      pending = true
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        self.pending = false
        self.resizeWindow()
      }
    }

    private func resizeWindow() {
      guard let window, let screen = window.screen else { return }
      let visible = screen.visibleFrame.insetBy(dx: 0, dy: 8)
      let decoration = window.frame.height - window.contentRect(forFrameRect: window.frame).height
      let maximum = max(1, visible.height - decoration)
      if lastAvailableHeight != maximum {
        lastAvailableHeight = maximum
        availableHeight?(maximum)
      }
      guard targetHeight > 0 else { return }
      let size = NSSize(width: 390, height: min(ceil(targetHeight), maximum))
      var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
      frame.origin.x = window.frame.minX
      frame.origin.y = min(window.frame.maxY, visible.maxY) - frame.height
      frame.origin.y = max(visible.minY, frame.origin.y)
      guard
        abs(window.frame.height - frame.height) > 0.5
          || abs(window.frame.width - frame.width) > 0.5
          || abs(window.frame.minY - frame.minY) > 0.5
      else { return }
      window.setFrame(frame, display: true, animate: false)
    }
  }
}
