import Foundation

// Accessed only inside the scheduler transaction, then after both workers finish.
private final class CommandOrder { var values: [Int] = [] }

@main enum DDCRequestSchedulerTests {
  static func main() {
    var clock: TimeInterval = 10
    var commands: [TimeInterval] = []
    let scheduler = DDCRequestScheduler(now: { clock }, sleep: { clock += $0 })
    for _ in 0..<4 {
      precondition(
        scheduler.perform {
          commands.append(clock)
          return 0
        } == 0)
    }
    for gap in zip(commands.dropFirst(), commands).map({ $0 - $1 }) {
      precondition(gap >= 0.0799, "Every I2C call needs a settling interval")
    }

    let failure: Int32 = -123
    precondition(scheduler.perform { failure } == failure)
    let failedAt = clock
    for _ in 0..<20 {
      clock += 0.1
      precondition(scheduler.perform { fatalError("Command sent during cooldown") } == failure)
    }
    clock = failedAt + 5
    precondition(scheduler.perform { 0 } == 0, "Queued callers must not extend cooldown")
    precondition(scheduler.perform { 0 } == 0, "Success clears the transport failure")

    // Slow kernel calls need their spacing measured from completion, not submission.
    precondition(
      scheduler.perform {
        clock += 4
        return 0
      } == 0)
    let finishedAt = clock
    precondition(
      scheduler.perform {
        precondition(clock >= finishedAt + 0.0799)
        return 0
      } == 0)

    // A whole brightness transaction excludes another control's I2C commands.
    let concurrent = DDCRequestScheduler(sleep: { _ in })
    let entered = DispatchSemaphore(value: 0)
    let contender = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let order = CommandOrder()
    DispatchQueue.global().async {
      concurrent.transaction {
        _ = concurrent.perform {
          order.values.append(1)
          return 0
        }
        entered.signal()
        precondition(contender.wait(timeout: .now() + 2) == .success)
        _ = concurrent.perform {
          order.values.append(2)
          return 0
        }
      }
      finished.signal()
    }
    precondition(entered.wait(timeout: .now() + 2) == .success)
    contender.signal()
    _ = concurrent.perform {
      order.values.append(3)
      return 0
    }
    precondition(finished.wait(timeout: .now() + 2) == .success)
    precondition(order.values == [1, 2, 3])
    print(
      "DDC scheduler: pacing, cooldown, recovery, slow calls, transaction isolation passed (no hardware)"
    )
  }
}
