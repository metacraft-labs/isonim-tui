## Drive the demo's real async VM and platform event loop to a settled state.
## FakeDb is the demo's production backing service, not a replacement introduced
## by these tests. No clock or renderer is mocked.
import std/[monotimes, times, os]
import nim_everywhere/async_compat
import isonim/core/signals
import task_app/core/vm

proc settleTaskApp*(vm: TaskAppVM) =
  let deadline = getMonoTime() + initDuration(seconds = 5)
  while vm.pendingOps.val > 0 or vm.tasks.loading:
    doAssert getMonoTime() < deadline, "task-app async operations did not settle"
    drainPlatformCallbacks()
    sleep(1)
  doAssert vm.lastError.val.isNone, "task-app write failed"
