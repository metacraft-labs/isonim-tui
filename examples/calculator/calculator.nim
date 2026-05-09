## examples/calculator/calculator.nim — M27 demo: a touch-grid
## calculator with full keyboard.
##
## Demonstrates:
##   * `Static` for the display strip
##   * `Button` rows for a 4x5 keypad
##   * Pure ViewModel for arithmetic state (renderer-agnostic)
##   * `TerminalTestHarness` mounting via `buildCalculatorApp`
##
## The arithmetic surface is intentionally minimal — integer arithmetic
## with `+ - * /` plus `=` and `c` (clear). Decimal points and
## negative-number entry are out of scope; the goal is a snapshot-
## stable demo, not a Replacement Calculator.
##
## DM-M1: composition root uses the `ui(r):` DSL — see
## `docs/dsl-pattern.md`. Structural divs use `tdiv(class=...)`,
## widgets compose via the `w*` wrappers in
## `isonim_tui/dsl/widget_blocks`.

import std/strutils
import isonim_tui
import isonim_tui/dsl/widget_blocks
import isonim/dsl/ui

# ----------------------------------------------------------------------------
# ViewModel
# ----------------------------------------------------------------------------

type
  Op* = enum opNone, opAdd, opSub, opMul, opDiv

  CalculatorVM* = ref object
    display*: string  ## Currently typed number (or a result).
    accumulator*: int
    pendingOp*: Op
    fresh*: bool      ## True when the next digit should clear `display`.

proc newCalculatorVM*(): CalculatorVM =
  CalculatorVM(display: "0", accumulator: 0, pendingOp: opNone, fresh: true)

proc digit*(vm: CalculatorVM; d: int) =
  if vm.fresh:
    vm.display = $d
    vm.fresh = false
  else:
    if vm.display == "0": vm.display = $d
    else: vm.display.add $d

proc applyPending(vm: CalculatorVM; rhs: int): int =
  case vm.pendingOp
  of opNone, opAdd: vm.accumulator + rhs
  of opSub:         vm.accumulator - rhs
  of opMul:         vm.accumulator * rhs
  of opDiv:
    if rhs == 0: 0
    else: vm.accumulator div rhs

proc setOp*(vm: CalculatorVM; op: Op) =
  let rhs = try: parseInt(vm.display) except ValueError: 0
  if vm.pendingOp == opNone:
    vm.accumulator = rhs
  else:
    vm.accumulator = vm.applyPending(rhs)
  vm.pendingOp = op
  vm.fresh = true
  vm.display = $vm.accumulator

proc equals*(vm: CalculatorVM) =
  if vm.pendingOp == opNone: return
  let rhs = try: parseInt(vm.display) except ValueError: 0
  vm.accumulator = vm.applyPending(rhs)
  vm.pendingOp = opNone
  vm.display = $vm.accumulator
  vm.fresh = true

proc clear*(vm: CalculatorVM) =
  vm.display = "0"
  vm.accumulator = 0
  vm.pendingOp = opNone
  vm.fresh = true

# ----------------------------------------------------------------------------
# Per-key handler factory
# ----------------------------------------------------------------------------

proc makeKeyHandler(label: string; vm: CalculatorVM): proc() =
  ## Build the click handler for one keypad button. Defined out of
  ## line so each iteration of the keypad-row `for` loop captures its
  ## own `label` value rather than aliasing the loop variable.
  result = proc() =
    case label
    of "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
      vm.digit(parseInt(label))
    of "+": vm.setOp(opAdd)
    of "-": vm.setOp(opSub)
    of "*": vm.setOp(opMul)
    of "/": vm.setOp(opDiv)
    of "=": vm.equals()
    of "C": vm.clear()
    else: discard

# ----------------------------------------------------------------------------
# Composition root
# ----------------------------------------------------------------------------

proc buildCalculatorApp*(h: TerminalTestHarness; vm: CalculatorVM):
                        TerminalNode =
  let r = h.renderer
  let dispWidth = h.cols - 4
  let displayBody = align(vm.display, dispWidth, ' ')
  const keypadRows = [
    ["7", "8", "9", "/"],
    ["4", "5", "6", "*"],
    ["1", "2", "3", "-"],
    ["0", "C", "=", "+"]]

  result = ui(r):
    tdiv(class = "calculator"):
      wStatic(r, displayBody, dispWidth, 1, bsRound)
      for row in keypadRows:
        tdiv(class = "keypad-row"):
          for label in row:
            wButton(r, label, 6, makeKeyHandler(label, vm))

proc mountCalculator*(h: TerminalTestHarness): CalculatorVM =
  let vm = newCalculatorVM()
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildCalculatorApp(h, vm))
  vm

# ----------------------------------------------------------------------------
# Standalone entry point
# ----------------------------------------------------------------------------

when isMainModule:
  let h = newTerminalTestHarness(40, 18)
  let vm = mountCalculator(h)
  echo "Calculator mounted (", h.cols, "x", h.rows, ")."
  echo "Display: ", vm.display
  echo encodePlaintext(h.driver.buffer)
  h.dispose()
