import AppKit

/// A lid-open wake does not necessarily produce a display topology callback.
@MainActor
final class DisplayWakeObserver {
  private let center: NotificationCenter
  private var tokens: [NSObjectProtocol] = []

  init(
    center: NotificationCenter = NSWorkspace.shared.notificationCenter,
    onWake: @escaping @MainActor () -> Void
  ) {
    self.center = center
    for name in [
      NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
      NSWorkspace.sessionDidBecomeActiveNotification,
    ] {
      tokens.append(
        center.addObserver(forName: name, object: nil, queue: .main) { _ in
          MainActor.assumeIsolated { onWake() }
        })
    }
  }

  deinit {
    for token in tokens { center.removeObserver(token) }
  }
}
