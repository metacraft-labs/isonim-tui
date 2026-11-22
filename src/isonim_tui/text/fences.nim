## Width fences — where a terminal may draw a cell at a width the layout
## did not count, the next cell is placed by an absolute move instead of by
## the terminal's own advance.
##
## A terminal's width table is not the program's: an ambiguous-width
## character may be one cell or two, a character newer than the terminal's
## Unicode tables may be zero, one or two, a text-default pictograph may be
## drawn wide, and a joined emoji sequence is one glyph on a terminal that
## clusters graphemes and two or more on one that does not. When the
## application could not MEASURE the answer for one of these, a wrong guess
## would shift every later cell of the row. Following such a cell with
## `CSI <col> G` (cursor horizontal absolute, to the column the layout
## expects next) bounds the damage to that one cell's drawing — about four
## bytes per fenced cell. ASCII and the common ranges never take a fence.
##
## What is uncertain is the APPLICATION'S knowledge (`WidthFences`), passed
## in by whoever measured the terminal; the zero value fences nothing.

import std/unicode

import ../cells
import ./width

type
  WidthFences* = object
    ## Which width questions are unanswered for this terminal.
    ambiguousUnknown*: bool
      ## East Asian Width `A` characters: one cell or two is not known.
    unicode13Unknown*: bool
      ## The terminal's tables are not known to cover Unicode 13 and later.
    pictographsUnknown*: bool
      ## Text-default pictographs: whether they are drawn wide is not known.
    noClusters*: bool
      ## The terminal is not known to cluster graphemes (ZWJ / VS16
      ## sequences may be drawn as their parts).

func fencesAnything*(f: WidthFences): bool =
  f.ambiguousUnknown or f.unicode13Unknown or f.pictographsUnknown or
    f.noClusters

const
  Unicode13Blocks = [
    # Blocks opened by Unicode 13.0 – 16.0, and the pictograph block whose
    # emoji those versions added. Coarse on purpose: a fence where none was
    # needed costs four bytes; a missing one shifts a row.
    (0x10580'i32, 0x105FF'i32),   # Vithkuqi (14), Todhri (16)
    (0x10D40'i32, 0x10D8F'i32),   # Garay (16)
    (0x10E80'i32, 0x10EBF'i32),   # Yezidi (13)
    (0x10EC0'i32, 0x10EFF'i32),   # Arabic Extended-C (15)
    (0x10F70'i32, 0x10FFF'i32),   # Old Uyghur (14), Chorasmian (13), Elymaic
    (0x11380'i32, 0x113FF'i32),   # Tulu-Tigalari (16)
    (0x11900'i32, 0x1195F'i32),   # Dives Akuru (13)
    (0x11AB0'i32, 0x11ABF'i32),   # Unified Canadian Aboriginal Ext-A (14)
    (0x11B00'i32, 0x11B5F'i32),   # Devanagari Extended-A (15)
    (0x11F00'i32, 0x11F5F'i32),   # Kawi (15)
    (0x13460'i32, 0x143FF'i32),   # Egyptian Hieroglyphs Ext-A (16)
    (0x16100'i32, 0x1613F'i32),   # Gurung Khema (16)
    (0x16D40'i32, 0x16D7F'i32),   # Kirat Rai (16)
    (0x18B00'i32, 0x18D8F'i32),   # Khitan (13), Tangut Supplement (13)
    (0x1AFF0'i32, 0x1AFFF'i32),   # Kana Extended-B (14)
    (0x1CC00'i32, 0x1CEBF'i32),   # Symbols for Legacy Computing Supplement (16)
    (0x1CF00'i32, 0x1CFCF'i32),   # Znamenny Musical Notation (14)
    (0x1DF00'i32, 0x1DFFF'i32),   # Latin Extended-G (14)
    (0x1E030'i32, 0x1E08F'i32),   # Cyrillic Extended-D (15)
    (0x1E290'i32, 0x1E2BF'i32),   # Toto (14)
    (0x1E4D0'i32, 0x1E4FF'i32),   # Nag Mundari (15)
    (0x1E5D0'i32, 0x1E5FF'i32),   # Ol Onal (16)
    (0x1E7E0'i32, 0x1E7FF'i32),   # Ethiopic Extended-B (14)
    (0x1FA70'i32, 0x1FAFF'i32),   # Symbols and Pictographs Extended-A
    (0x1FB00'i32, 0x1FBFF'i32),   # Symbols for Legacy Computing (13)
    (0x2EBF0'i32, 0x2EE5F'i32),   # CJK Extension I (15.1)
    (0x30000'i32, 0x323AF'i32)]   # CJK Extensions G (13) and H (15)

func isUnicode13OrLater*(cp: int32): bool =
  ## A code point in a block Unicode 13 or later opened (see the table).
  for (lo, hi) in Unicode13Blocks:
    if cp >= lo and cp <= hi:
      return true
  false

func isBoxOrBlock(cp: int32): bool {.inline.} =
  ## Box drawing and block elements: the chrome an application draws from a
  ## width-safe table of its own, never fenced (a border is a run of them).
  cp >= 0x2500 and cp <= 0x259F

func needsFence*(c: Cell; f: WidthFences): bool =
  ## Whether the cell after `c` must be placed by an absolute move.
  if c.width == 0 or c.rune.int32 < 0x80:
    return false
  let cp = c.rune.int32
  if f.ambiguousUnknown and eawClass(cp) == eawAmbiguous and
     not isBoxOrBlock(cp):
    return true
  if f.unicode13Unknown and isUnicode13OrLater(cp):
    return true
  if f.pictographsUnknown and isExtendedPictographic(cp) and
     eawClass(cp) != eawWide:
    return true
  if f.noClusters and c.extra.len > 0:
    for r in runes(c.extra):
      if int32(r) == ZeroWidthJoiner or int32(r) == VariationSelector16:
        return true
  false

func fenceAfter*(col: int; c: Cell): string =
  ## `CSI <n> G` to the column after `c` drawn at the 0-based `col`.
  "\x1b[" & $(col + max(1, int(c.width)) + 1) & "G"
