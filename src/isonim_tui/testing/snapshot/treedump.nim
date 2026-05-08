## Tree-dump snapshot encoder.
##
## A pretty-printed dump of the renderer's element tree (tag, id,
## classes, computed style, layout region). Sourced from
## `introspection.dumpTree` so the same string appears in
## `h.dumpTree()` results and in this snapshot file.

import ../../renderer
import ../../compositor
import ../introspection

proc encodeTreeDump*(comp: Compositor; root: TerminalNode): string =
  introspection.dumpTree(comp, root)
