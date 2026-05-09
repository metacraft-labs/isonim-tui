## Timeline HTML report — M25 time-travel snapshot.
##
## Given a `Recording`, produce a single self-contained HTML file that
## visualises every captured frame as an SVG thumbnail. Clicking a
## thumbnail in a browser reveals the full ScreenBuffer state plus a
## text diff against the previous frame.
##
## Charter compliance: the report is golden-comparable. Tests strip
## the timestamp before comparing against a stored golden under
## `tests/snapshots/<name>/`.

import std/[strutils, times]

import ../../cells
import ../recording_types
import ./svg as svgMod
import ./plaintext

export recording_types

const cellWidth = 8
const cellHeight = 16

proc thumbnailSvg(buf: ScreenBuffer; scale: float = 0.25): string =
  ## Tiny preview — the same SVG the per-frame snapshot would produce,
  ## scaled down via the SVG `viewBox`. Stable across runs because the
  ## underlying encoder is deterministic.
  let inner = svgMod.encodeSvg(buf)
  let totalW = buf.cols * cellWidth
  let totalH = buf.rowsCount * cellHeight
  let thumbW = int(totalW.float * scale)
  let thumbH = int(totalH.float * scale)
  var lines = inner.splitLines()
  if lines.len >= 2 and lines[1].startsWith("<svg"):
    lines[1] = "<svg xmlns=\"http://www.w3.org/2000/svg\" " &
      "width=\"" & $thumbW & "\" height=\"" & $thumbH & "\" " &
      "viewBox=\"0 0 " & $totalW & " " & $totalH & "\" " &
      "font-family=\"monospace\" font-size=\"" & $cellHeight & "\">"
  lines.join("\n")

proc plaintextDump(buf: ScreenBuffer): string =
  encodePlaintext(buf)

proc lineDiff(prev, cur: string): string =
  let pl = prev.splitLines()
  let cl = cur.splitLines()
  let n = max(pl.len, cl.len)
  var diffs: seq[string] = @[]
  for i in 0 ..< n:
    let p = if i < pl.len: pl[i] else: ""
    let c = if i < cl.len: cl[i] else: ""
    if p == c:
      diffs.add "  " & p
    else:
      if p.len > 0: diffs.add "- " & p
      if c.len > 0: diffs.add "+ " & c
  diffs.join("\n")

proc xmlEscape(s: string): string =
  result = ""
  for ch in s:
    case ch
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&apos;"
    else: result.add ch

proc encodeTimelineHtml*(recording: Recording;
                         includeTimestamp: bool = true): string =
  ## Build the HTML report. Each frame becomes:
  ##   * A clickable `<details>` element with an inline SVG thumbnail.
  ##   * A `<pre>` block with the frame's plaintext dump.
  ##   * A `<pre>` block with the line-diff against the previous frame.
  ##
  ## The output is a single self-contained string — no external CSS,
  ## JS, or fonts. Tests compare the timestamp-stripped variant.
  var lines: seq[string] = @[]
  lines.add "<!DOCTYPE html>"
  lines.add "<html><head><meta charset=\"utf-8\">"
  lines.add "<title>isonim-tui timeline</title>"
  lines.add "<style>"
  lines.add "body{font-family:monospace;padding:1em;}"
  lines.add ".frame{border:1px solid #ccc;margin-bottom:1em;padding:0.5em;}"
  lines.add ".frame summary{cursor:pointer;}"
  lines.add ".frame .thumb{display:inline-block;vertical-align:top;margin-right:1em;}"
  lines.add ".frame .meta{display:inline-block;vertical-align:top;}"
  lines.add "pre{background:#f0f0f0;padding:0.5em;overflow:auto;max-height:300px;}"
  lines.add ".diff-add{background:#e6ffe6;}"
  lines.add ".diff-del{background:#ffe6e6;}"
  lines.add "</style></head><body>"
  lines.add "<h1>isonim-tui timeline report</h1>"
  if includeTimestamp:
    lines.add "<p>generated: " & $now() & "</p>"
  lines.add "<p>frames: " & $recording.frames.len &
    " — events: " & $recording.events.len &
    " — dimensions: " & $recording.cols & "x" & $recording.rows & "</p>"
  var prevDump = ""
  for i, frame in recording.frames:
    let label =
      if frame.seqNumber == 0: "frame " & $i & " (initial)"
      else: "frame " & $i & " (event #" & $frame.seqNumber & ")"
    let dump = plaintextDump(frame.buffer)
    let diff = if i == 0: "(initial frame)" else: lineDiff(prevDump, dump)
    lines.add "<details class=\"frame\" open>"
    lines.add "<summary>" & xmlEscape(label) & "</summary>"
    lines.add "<div class=\"thumb\">" & thumbnailSvg(frame.buffer) & "</div>"
    lines.add "<div class=\"meta\">"
    lines.add "<h3>state</h3>"
    lines.add "<pre>" & xmlEscape(dump) & "</pre>"
    lines.add "<h3>diff vs previous</h3>"
    lines.add "<pre>" & xmlEscape(diff) & "</pre>"
    lines.add "</div>"
    lines.add "</details>"
    prevDump = dump
  lines.add "</body></html>"
  lines.join("\n") & "\n"

proc stripDynamic*(html: string): string =
  ## Remove the timestamp paragraph so two timeline reports built from
  ## the same recording at different times produce identical output.
  ## Used by `test_timeline_html_diffable`.
  let lines = html.splitLines()
  var keep: seq[string] = @[]
  for line in lines:
    if line.startsWith("<p>generated:"):
      continue
    keep.add line
  keep.join("\n")
