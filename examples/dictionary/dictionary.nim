## examples/dictionary/dictionary.nim — M27 demo: search-as-you-type
## dictionary with a hardcoded word list.
##
## Demonstrates:
##   * `Input` widget bound to a query signal
##   * Substring filtering against a static word list (no network)
##   * `ListView` rendering filtered matches
##
## The word list is intentionally small (~30 entries) so the demo
## binary stays self-contained and the snapshot is stable.

import std/strutils
import isonim_tui

# A hardcoded mini dictionary. Each entry is `(headword, gloss)`. The
# gloss is short so it fits inside the ListView label.
const WordList* = [
  ("aardvark",  "burrowing nocturnal mammal"),
  ("balloon",   "inflatable rubber bag"),
  ("cipher",    "encryption scheme"),
  ("delta",     "river mouth"),
  ("entropy",   "thermodynamic disorder"),
  ("forge",     "workshop with a hearth"),
  ("gauntlet",  "armoured glove"),
  ("harbour",   "sheltered body of water"),
  ("indigo",    "deep blue dye"),
  ("juniper",   "evergreen shrub"),
  ("kestrel",   "small falcon"),
  ("lantern",   "portable light"),
  ("meridian",  "great circle of longitude"),
  ("nebula",    "interstellar cloud"),
  ("orchid",    "flowering plant"),
  ("pyramid",   "polyhedral structure"),
  ("quasar",    "luminous active galactic nucleus"),
  ("relic",     "object from the past"),
  ("solstice",  "longest or shortest day"),
  ("tempest",   "violent storm"),
  ("umbra",     "fully shadowed region"),
  ("voyage",    "long journey"),
  ("wasabi",    "japanese horseradish"),
  ("xylem",     "water-conducting plant tissue"),
  ("yarrow",    "perennial herb"),
  ("zenith",    "highest point"),
  ("aurora",    "polar light display"),
  ("basalt",    "volcanic rock"),
  ("citadel",   "fortified place"),
  ("dahlia",    "tuberous flowering plant")]

# ----------------------------------------------------------------------------
# ViewModel
# ----------------------------------------------------------------------------

type
  DictionaryVM* = ref object
    query*: string
    results*: seq[tuple[word, gloss: string]]

proc newDictionaryVM*(): DictionaryVM =
  result = DictionaryVM(query: "", results: @[])
  for entry in WordList:
    result.results.add (word: entry[0], gloss: entry[1])

proc setQuery*(vm: DictionaryVM; q: string) =
  vm.query = q
  let lower = q.toLowerAscii
  vm.results = @[]
  for entry in WordList:
    if lower.len == 0 or entry[0].toLowerAscii.contains(lower) or
       entry[1].toLowerAscii.contains(lower):
      vm.results.add (word: entry[0], gloss: entry[1])

# ----------------------------------------------------------------------------
# Composition
# ----------------------------------------------------------------------------

proc buildResultsList(r: TerminalRenderer; vm: DictionaryVM;
                      width, height: int): ListViewWidget =
  var items: seq[ListItem] = @[]
  for i, entry in vm.results:
    items.add ListItem(id: "row" & $i,
                       label: entry.word & " — " & entry.gloss)
  if items.len == 0:
    items.add ListItem(id: "empty", label: "(no matches)")
  newListView(r, items = items, width = width,
              viewportHeight = height, border = bsRound)

proc buildDictionaryApp*(h: TerminalTestHarness; vm: DictionaryVM):
                        TerminalNode =
  let r = h.renderer
  let root = r.createElement("div")
  r.setAttribute(root, "class", "dictionary")

  # Search box.
  let inp = newInput(r, value = vm.query, placeholder = "Search…",
                     width = h.cols - 2, border = bsRound,
                     onChange = proc(s: string) = vm.setQuery(s))
  r.appendChild(root, inp.node)

  # Results list.
  let listH = max(3, h.rows - 4)
  let lv = buildResultsList(r, vm, h.cols - 2, listH)
  r.appendChild(root, lv.node)

  root

proc mountDictionary*(h: TerminalTestHarness): DictionaryVM =
  let vm = newDictionaryVM()
  h.mount(proc(r: TerminalRenderer): TerminalNode =
    discard r
    buildDictionaryApp(h, vm))
  vm

when isMainModule:
  let h = newTerminalTestHarness(60, 20)
  let vm = mountDictionary(h)
  echo "Dictionary mounted with ", vm.results.len, " entries."
  echo encodePlaintext(h.driver.buffer)
  h.dispose()
