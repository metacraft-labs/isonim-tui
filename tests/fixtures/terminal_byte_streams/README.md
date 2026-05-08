# Terminal byte-stream corpus

This directory holds *recorded* byte streams from real terminal
emulators, paired with golden event sequences. M4's
`test_parser_byte_parity_*` tests load these fixtures, feed each
`.bin` file through the production parser, and compare the resulting
event stream against the matching `.txt` golden.

## Status

**M4 ships an inline corpus** (covered by the test files in
`tests/test_input_*_corpus.nim` directly) rather than a populated
fixtures directory. The reasons:

1. The CI host runs in a single environment; recording across xterm,
   Kitty, Alacritty, iTerm2, WezTerm, Windows Terminal, and the Linux
   console requires either a multi-host matrix or an emulator pool —
   neither is available today.
2. Real-terminal fixtures committed without provenance (which terminal
   produced them, with which keymap, on which OS) are worse than no
   fixtures: a regression test against a synthetic "iTerm2-like"
   stream would lock in our *guess* of how iTerm2 behaves rather than
   actual iTerm2 behaviour.
3. The byte-level surface that matters in practice — SGR-1006 mouse,
   bracketed paste, focus events, in-band resize, Kitty extended
   keyboard, partial-CSI reassembly — is universal across terminals
   that implement it. The inline corpus exercises every code path the
   parser knows about.

## Growing the corpus

Use `tools/record_terminal_bytes.nim` to record a new fixture against
a real terminal:

```sh
# Inside the terminal you want to capture (xterm, kitty, etc.)
nim r tools/record_terminal_bytes.nim --label=kitty
# Press the keys / mouse actions you want recorded; Ctrl+D ends.
```

Each invocation creates two files in this directory:

* `<label>-<timestamp>.bin` — raw bytes received on the input FD.
* `<label>-<timestamp>.txt` — human-readable transcript with one
  parsed event per line. Edit by hand to author the golden if you
  recorded a noisy session.

When the corpus has at least one fixture per major terminal, M4 will
add `test_parser_byte_parity_*` tests that load each `.bin`, feed it
through the parser, and assert the typed-event stream matches the
`.txt` golden.

## Deferred

* Cross-terminal recording across xterm, Kitty, Alacritty, iTerm2,
  WezTerm, Windows Terminal, and the Linux console — see notes
  above; depends on a multi-host CI configuration not yet available.
* `test_parser_byte_parity_with_textual` — would require a Python
  harness running Textual's `_xterm_parser.py` over the same
  fixtures and comparing event-by-event. Deferred until the corpus
  has enough population to make the comparison meaningful.
