# Wide-range brightness dragging — 2026-11-17

Environment: macOS 27.2.1, one active Q27B30 external display, display ID 2 in this session. Original hardware brightness was independently read as 100%. No other display controls were changed.

## Reproduction

The installed application was tested through its real menu bar popup. A mouse gesture swept approximately 10–100% twice over about 1.1 seconds, then released at 20% or 100%. Repeated gestures used a roughly 0.1-second pause plus accessibility inspection between releases.

- Small-range 90–100% tests had passed earlier and did not reproduce the problem.
- Two isolated wide-range gestures passed. A following rapid sequence failed on its second release: `The monitor did not return a valid DDC/CI brightness value.` The slider was disabled, but an independent probe read 26%. Hardware brightness was restored and independently verified at 100%.
- The first candidate removed redundant reads, serialized the entire brightness exchange, and spaced I2C calls by 80 ms, but still streamed writes during a drag. Six rapid gestures passed; a second sequence of five reproduced persistent `0xE0114101`. Restoration was blocked while DDC was unavailable. The user reconnected HDMI; the next read returned 94%, and the original 100% was restored and verified before further testing.

These observations establish a repeatable interaction and transport failure, not a decoded monitor/driver root cause. The first candidate was rejected despite its initial passing round.

## Final behavior

- External brightness drafts stay local while the mouse is down. Releasing schedules only the latest target after 250 ms without another submission. Resuming a drag discards the queued target. Built-in brightness retains live updates.
- A repeated, already verified value does not produce another Set VCP command.
- A single fresh channel/maximum read is used for each external brightness operation. Its read/write/readback transaction excludes other controls' I2C calls. All VCP calls are paced by the shared scheduler, measured from command completion.
- Driver errors block actual I2C calls for five seconds across controls. Invalid replies have bounded retries. A failed brightness operation drops queued targets and performs one delayed read-only recovery check; a valid read re-enables the slider at the measured value. The original error remains visible until the next adjustment.
- Background brightness and color reads are coalesced by display identity. Worker tokens prevent canceled workers from publishing over their replacements.

## Tests

The release-only candidate was exercised in the actual Debug menu bar popup. Holding the mouse down with the draft at 20% left the independently read hardware brightness at 100%; releasing applied 20%. A further six rapid wide-range gestures passed and independently read back 20%. A subsequent release to 100% restored the original value.

After adding the resettable 250 ms submission deadline and slider help text, the final build passed another six rapid wide-range gestures. Four additional gestures, each allowed to settle, independently read back 20%, 100%, 20%, and 100%. No popup error was observed during these final ten gestures. At the end, no `DCPAVServiceProxyUserClient` entries were present, and original brightness was verified at 100%.

`./format.sh`, `./check.sh`, and `git diff --check` passed. The tested Debug app was left running; the installed application was not overwritten. The pre-existing Info.plist version change was preserved.

`DDCRequestSchedulerTests.swift` uses fake time and commands to cover inter-command spacing, failure cooldown, queued callers not extending cooldown, recovery after the deadline, spacing after a slow call, and transaction isolation across competing threads. It sends no hardware commands and runs in `check.sh` alongside the existing simulated recovery tests.

This is a single-monitor reproduction and regression check. It does not establish reliability for every monitor, cable, dock, or macOS version. A transport already stuck in the driver/monitor may still require reconnection; the application cannot guarantee software recovery.
