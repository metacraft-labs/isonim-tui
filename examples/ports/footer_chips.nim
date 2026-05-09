## examples/ports/footer_chips.nim — Nim port (M23 Batch-3).
##
## Mirrors Textual's footer-chip snapshot apps: a `Footer` widget with
## several keyboard-binding entries rendered as chips along the bottom
## of the screen.

import isonim_tui

proc buildFooterChipsApp*(h: TerminalTestHarness): TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  let footer = newFooter(r,
    bindings = [
      FooterBinding(key: "q", description: "Quit"),
      FooterBinding(key: "s", description: "Save"),
      FooterBinding(key: "o", description: "Open"),
      FooterBinding(key: "?", description: "Help")],
    width = h.cols)
  r.appendChild(root, footer.node)
  root
