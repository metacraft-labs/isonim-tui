## datatable_app — a 1000-row DataTable. 'j' moves down, 'G' jumps to
## end (last row), 'g' jumps to top.

import isonim_tui
import ./app_runtime

proc generateRows(count: int): seq[RowData] =
  result = newSeqOfCap[RowData](count)
  for i in 0 ..< count:
    result.add RowData(cells: @[$i, "row#" & $i, $((i * 13) mod 997)])

when isMainModule:
  let rt = newAppRuntime(60, 16)
  var dt: DataTableWidget
  let cols = @[ColumnDef(key: "id", label: "id", width: 6),
               ColumnDef(key: "name", label: "name", width: 14),
               ColumnDef(key: "amt", label: "amt", width: 8)]
  let rows = generateRows(1000)

  proc rebuild() =
    rt.h.dispose()
    rt.h = newTerminalTestHarness(60, 16)
    rt.h.mount(proc(r: TerminalRenderer): TerminalNode =
      let root = r.createElement("div")
      dt = newDataTable(r, columns = cols, rows = rows,
                        viewportHeight = 12, border = bsRound)
      r.appendChild(root, dt.node)
      root)

  proc rebuildAndApply(action: proc(t: DataTableWidget)) =
    rebuild()
    action(dt)

  rebuild()
  rt.runEventLoop(proc(rt: AppRuntime; key: string) =
    if key == "q":
      rt.quit = true
      return
    if key == "G":
      rebuildAndApply(proc(t: DataTableWidget) = t.moveEnd())
    elif key == "j":
      dt.moveDown())
