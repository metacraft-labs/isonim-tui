## benchmarks/standard_app/app.nim — the 30-widget reference app.
##
## A single deterministic application used by every M24 benchmark so
## that all metrics share a workload. Built once via
## `buildStandardApp(h)`; benchmarks then drive it through the harness.
##
## Composition (per spec "Performance + responsiveness targets"):
##   * Header
##   * 1 DataTable (10 columns x 50 rows of stable synthetic data)
##   * 1 form (10 Input widgets)
##   * 3 Tabs widgets
##   * 1 Modal (closed, ready to open)
##   * Footer
##
## Total widget count is exactly 30. The composition is deterministic —
## the same `buildStandardApp` call twice produces byte-identical output
## because every random number is a stable function of the index.

import isonim_tui

type
  StandardAppHandles* = ref object
    ## Bundles the widget handles tests / benchmarks need to drive the
    ## app: focus targets, selection probe points, modal handle, etc.
    root*: TerminalNode
    header*: HeaderWidget
    table*: DataTableWidget
    inputs*: seq[InputWidget]
    tabs*: seq[TabsWidget]
    modal*: ModalWidget
    footer*: FooterWidget
    widgetCount*: int

const
  StandardWidth* = 100
  StandardHeight* = 40
  TableRows* = 50
  TableColumns* = 10
  FormFieldCount* = 10
  TabsCount* = 3

proc syntheticTableRows*(): seq[RowData] =
  result = @[]
  for i in 0 ..< TableRows:
    var cells: seq[string] = @[]
    for c in 0 ..< TableColumns:
      cells.add "r" & $i & "c" & $c
    result.add RowData(cells: cells)

proc syntheticTableColumns*(): seq[ColumnDef] =
  result = @[]
  for c in 0 ..< TableColumns:
    result.add ColumnDef(key: "c" & $c, label: "Col" & $c, width: 8)

proc buildStandardApp*(h: TerminalTestHarness): StandardAppHandles =
  ## Construct and mount the standard reference app in `h`.
  ## Returns handles every benchmark uses to drive interactions.
  let handles = StandardAppHandles(
    inputs: @[],
    tabs: @[],
    widgetCount: 0)
  let r = h.renderer

  h.mount(proc(rin: TerminalRenderer): TerminalNode =
    let root = rin.createElement("div")
    rin.setAttribute(root, "id", "standard-app")
    handles.root = root

    # Header (1 widget)
    let header = newHeader(rin, title = "IsoNim-TUI Bench",
                          subtitle = "M24 reference app",
                          width = StandardWidth)
    rin.appendChild(root, header.node)
    handles.header = header
    inc handles.widgetCount

    # DataTable (1 widget)
    let table = newDataTable(rin,
                             columns = syntheticTableColumns(),
                             rows = syntheticTableRows(),
                             viewportHeight = 20)
    rin.appendChild(root, table.node)
    handles.table = table
    inc handles.widgetCount

    # Form: 10 Input widgets
    let form = rin.createElement("div")
    rin.setAttribute(form, "data-widget", "form")
    rin.appendChild(root, form)
    inc handles.widgetCount      # the form container counts as one widget
    for i in 0 ..< FormFieldCount:
      let field = newInput(rin,
                           value = "field" & $i,
                           placeholder = "input " & $i,
                           width = 24)
      rin.appendChild(form, field.node)
      handles.inputs.add field
      inc handles.widgetCount

    # 3 Tabs widgets
    for t in 0 ..< TabsCount:
      let tabs = newTabs(rin,
                        tabs = [
                          Tab(id: "a", label: "Alpha"),
                          Tab(id: "b", label: "Beta"),
                          Tab(id: "g", label: "Gamma")],
                        activeIndex = 0,
                        width = StandardWidth)
      rin.appendChild(root, tabs.node)
      handles.tabs.add tabs
      inc handles.widgetCount

    # Footer (1 widget)
    let footer = newFooter(rin,
                          bindings = [
                            FooterBinding(key: "q", description: "Quit"),
                            FooterBinding(key: "enter", description: "Activate"),
                          ],
                          width = StandardWidth)
    rin.appendChild(root, footer.node)
    handles.footer = footer
    inc handles.widgetCount

    root)

  # Modal — built but not opened. Counts toward the 30-widget total.
  handles.modal = newModal(h, title = "Confirm", width = 30, height = 8)
  inc handles.widgetCount

  # We expect exactly 30 widgets:
  #   1 header + 1 table + 1 form + 10 inputs + 3 tabs + 1 footer + 1 modal +
  #   12 implicit fillers. Not all of these are real "Textual widgets" but
  #   the spec calls out a 30-widget composition; we add the implicit
  #   container nodes the form already provides. To make the count exactly
  #   match 30 and keep the workload deterministic, append 12 placeholder
  #   widgets (Static labels) to round out the total.
  while handles.widgetCount < 30:
    let s = newStatic(r, content = "filler#" & $handles.widgetCount,
                     width = 12, height = 1)
    r.appendChild(handles.root, s.node)
    inc handles.widgetCount

  h.flush()
  return handles
