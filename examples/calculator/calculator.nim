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

import std/strutils
import isonim_tui

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
# Layer-1 leaves (TUI specific)
# ----------------------------------------------------------------------------

proc renderDisplay(r: TerminalRenderer; parent: TerminalNode;
                   vm: CalculatorVM; width: int) =
  let body = align(vm.display, width - 4, ' ')
  let s = newStatic(r, body, width = width - 4, height = 1,
                    border = bsRound)
  r.appendChild(parent, s.node)

proc keyButton(r: TerminalRenderer; parent: TerminalNode;
               label: string; vm: CalculatorVM) =
  let onClick = proc() =
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
  let b = newButton(r, label, width = 6, onClick = onClick)
  r.appendChild(parent, b.node)

proc renderKeypadRow(r: TerminalRenderer; parent: TerminalNode;
                     labels: openArray[string]; vm: CalculatorVM) =
  let row = r.createElement("div")
  r.setAttribute(row, "class", "keypad-row")
  for lbl in labels: keyButton(r, row, lbl, vm)
  r.appendChild(parent, row)

# ----------------------------------------------------------------------------
# Composition root
# ----------------------------------------------------------------------------

proc buildCalculatorApp*(h: TerminalTestHarness; vm: CalculatorVM):
                        TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  r.setAttribute(root, "class", "calculator")

  renderDisplay(r, root, vm, h.cols)

  renderKeypadRow(r, root, ["7", "8", "9", "/"], vm)
  renderKeypadRow(r, root, ["4", "5", "6", "*"], vm)
  renderKeypadRow(r, root, ["1", "2", "3", "-"], vm)
  renderKeypadRow(r, root, ["0", "C", "=", "+"], vm)

  root

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
