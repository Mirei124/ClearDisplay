import Foundation

/// Shared by all VCP controls: serialize complete exchanges, pace every I2C call,
/// and let a failed transport rest instead of draining queued requests into it.
final class DDCRequestScheduler {
  private let lock = NSRecursiveLock()
  private let now: () -> TimeInterval
  private let sleep: (TimeInterval) -> Void
  private var nextCommand: TimeInterval = 0
  private var retryAfter: TimeInterval = 0
  private var transportError: Int32?

  init(
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) {
    self.now = now
    self.sleep = sleep
  }

  func transaction<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  func perform(_ command: () -> Int32) -> Int32 {
    transaction {
      if let transportError, now() < retryAfter { return transportError }
      let delay = nextCommand - now()
      if delay > 0 { sleep(delay) }
      let result = command()
      // Include a settling interval after both Set VCP and Get VCP exchanges.
      nextCommand = now() + 0.08
      if result != 0 {
        transportError = result
        retryAfter = now() + 5
      } else {
        transportError = nil
      }
      return result
    }
  }
}
