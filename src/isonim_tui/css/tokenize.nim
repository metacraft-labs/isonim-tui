## isonim_tui/css/tokenize.nim
##
## Tokenizer for IsoNim's TCSS (Textual-flavoured CSS).
##
## Port subset of `textual/css/tokenize.py` + `tokenizer.py`. Produces a
## stream of `Token` values with line/column location info. Handles the
## load-bearing token classes used by widgets.tcss across the Textual
## corpus:
##
##   - selectors: `#id`, `.class`, `Type`, `*`, `:pseudo`, `>`, `,`
##   - declaration name + value
##   - scalars: `100`, `50%`, `1fr`, `auto`, durations (`200ms`)
##   - colors: `#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`, `rgb(...)`,
##     named tokens like `red`, ANSI `ansi_red`
##   - variable refs: `$primary`
##   - strings, comments, !important
##
## We use a hand-rolled state machine (no regex) to keep the tokenizer
## allocation-light and easy to reason about. The state machine mirrors
## Textual's `TCSSTokenizerState`: root scope -> selector continue ->
## declaration -> value, with `{` / `}` driving transitions.
##
## Charter: every test in this repo runs the real tokenizer; no mocks.

## (No external imports needed; the tokenizer is self-contained.)

# ----------------------------------------------------------------------------
# Token types
# ----------------------------------------------------------------------------

type
  TokenKind* = enum
    ## Lexical token classes. Mirrors the `name=` keys in Textual's
    ## `Expect` regex sets but as a typed enum (charter: no string
    ## fall-through for the supported token classes).
    tkEof
    tkWhitespace
    tkCommentLine        ## `# ...` to end of line
    tkCommentStart       ## `/*`
    tkCommentEnd         ## `*/`
    tkSelectorStartId          ## `#id` at the root scope
    tkSelectorStartClass       ## `.class` at the root scope
    tkSelectorStartUniversal   ## `*` at the root scope
    tkSelectorStartType        ## `Type` at the root scope (CapitalCamel)
    tkSelectorId               ## `#id` after a selector
    tkSelectorClass            ## `.class` after a selector
    tkSelectorUniversal        ## `*` after a selector
    tkSelectorType             ## `Type` after a selector
    tkPseudoClass              ## `:pseudo` (e.g. `:focus`)
    tkCombinatorChild          ## `>`
    tkNewSelector              ## `,` (separator between selector groups)
    tkDeclarationSetStart      ## `{`
    tkDeclarationSetEnd        ## `}`
    tkDeclarationName          ## `prop:` (the `:` is consumed)
    tkDeclarationEnd           ## `;`
    tkScalar                   ## `100%`, `1fr`, `50w`, `50h`
    tkDuration                 ## `200ms`, `0.5s`
    tkNumber                   ## `123`, `-1.5`
    tkColorHex                 ## `#abc`, `#aabbcc`, `#aabbccdd`
    tkColorFunc                ## `rgb(...)` / `rgba(...)` / `hsl(...)` (raw)
    tkToken                    ## bare identifier (e.g. `red`, `auto`, `bold`)
    tkString                   ## `"..."`
    tkVariableName             ## `$name:` (declaration of a variable)
    tkVariableRef              ## `$name`
    tkComma                    ## `,` inside a declaration value
    tkImportant                ## `!important`
    tkAtRule                   ## `@media`, `@dark`, `@light`
    tkOpenParen                ## `(` (for media query sections; rarely used)
    tkCloseParen               ## `)`
    tkUnknown                  ## fallback / error token

  Token* = object
    ## A lexical token with location info. Value type — copyable, no
    ## ref aliasing. `line` and `col` are 1-indexed (matches Textual's
    ## `Token.start`).
    kind*: TokenKind
    value*: string
    line*: int
    col*: int
    adjacentToPrev*: bool  ## true if the previous token's end touched
                           ## this token's start (no whitespace/comment
                           ## in between). Used by the parser to fold
                           ## compound selectors like `Button.primary`.

  TokenizeError* = object of CatchableError
    ## Raised by `tokenizeStrict` when a lexical error is encountered.
    ## In recovery mode, errors emit a `tkUnknown` and the tokenizer
    ## advances by one character.
    line*: int
    col*: int

# ----------------------------------------------------------------------------
# Tokenizer state
# ----------------------------------------------------------------------------

type
  TokenizerScope = enum
    ## State the tokenizer is in. Drives which characters are valid.
    tsRoot          ## top of file: expect selectors, variable defs, at-rules
    tsSelector      ## inside a selector list (after the start)
    tsDeclaration   ## inside a `{ ... }` block, expecting a property name
    tsValue         ## inside a property value, until `;` or `}`
    tsVariableValue ## inside `$name: value\n`

  Tokenizer = object
    code: string
    pos: int
    line: int
    col: int
    scope: TokenizerScope
    nestLevel: int
    recover: bool
    tokens: seq[Token]
    sawWhitespace: bool   ## set when whitespace/comments were skipped
                          ## since the last emitted token; consumed when
                          ## the next token is emitted.

# ----------------------------------------------------------------------------
# Character predicates (avoid `in {...}` allocations on hot paths)
# ----------------------------------------------------------------------------

proc isIdentStart(c: char): bool {.inline.} =
  c == '_' or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

proc isIdentCont(c: char): bool {.inline.} =
  c == '_' or c == '-' or
    (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or
    (c >= '0' and c <= '9')

proc isUpperIdentStart(c: char): bool {.inline.} =
  c == '_' or (c >= 'A' and c <= 'Z')

proc isHex(c: char): bool {.inline.} =
  (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')

proc isDigit(c: char): bool {.inline.} =
  c >= '0' and c <= '9'

# ----------------------------------------------------------------------------
# Tokenizer primitives
# ----------------------------------------------------------------------------

proc peek(t: Tokenizer; off = 0): char {.inline.} =
  if t.pos + off < t.code.len: t.code[t.pos + off] else: '\0'

proc advance(t: var Tokenizer; n = 1) =
  for _ in 0 ..< n:
    if t.pos >= t.code.len: return
    if t.code[t.pos] == '\n':
      inc t.line
      t.col = 1
    else:
      inc t.col
    inc t.pos

proc emit(t: var Tokenizer; kind: TokenKind; value: string;
          line: int; col: int) {.inline.} =
  let adj = (t.tokens.len > 0) and (not t.sawWhitespace)
  t.tokens.add(Token(kind: kind, value: value, line: line, col: col,
                     adjacentToPrev: adj))
  t.sawWhitespace = false

proc raiseTokenError(t: Tokenizer; msg: string) =
  var e = newException(TokenizeError, msg & " at " & $t.line & ":" & $t.col)
  e.line = t.line
  e.col = t.col
  raise e

# ----------------------------------------------------------------------------
# Lexers for individual token shapes
# ----------------------------------------------------------------------------

proc readIdent(t: var Tokenizer): string =
  ## Read an identifier matching `[a-zA-Z_-][a-zA-Z0-9_-]*`. Allows
  ## leading `-` for properties like `-disabled`.
  let start = t.pos
  if t.pos < t.code.len and (isIdentStart(t.code[t.pos]) or t.code[t.pos] == '-'):
    advance(t)
    while t.pos < t.code.len and isIdentCont(t.code[t.pos]):
      advance(t)
  result = t.code[start ..< t.pos]

proc readHexColor(t: var Tokenizer): string =
  ## Read `#abc` / `#abcd` / `#abcdef` / `#abcdef00`. The leading `#`
  ## is consumed by the caller before this function runs.
  let start = t.pos
  while t.pos < t.code.len and isHex(t.code[t.pos]):
    advance(t)
  result = t.code[start ..< t.pos]

proc readString(t: var Tokenizer): string =
  ## Read a `"..."` string literal. The result includes the surrounding
  ## quotes (mirrors Textual's STRING capture).
  let start = t.pos
  if t.pos < t.code.len and t.code[t.pos] == '"':
    advance(t)
    while t.pos < t.code.len and t.code[t.pos] != '"':
      if t.code[t.pos] == '\\' and t.pos + 1 < t.code.len:
        advance(t, 2)
      else:
        advance(t)
    if t.pos < t.code.len: advance(t)  # closing quote
  result = t.code[start ..< t.pos]

proc skipWhitespaceAndComments(t: var Tokenizer) =
  while t.pos < t.code.len:
    let c = t.code[t.pos]
    if c == ' ' or c == '\t' or c == '\n' or c == '\r':
      advance(t)
      t.sawWhitespace = true
    elif c == '/' and t.pos + 1 < t.code.len and t.code[t.pos + 1] == '*':
      # Block comment: skip until '*/'
      advance(t, 2)
      while t.pos < t.code.len:
        if t.code[t.pos] == '*' and t.pos + 1 < t.code.len and
           t.code[t.pos + 1] == '/':
          advance(t, 2); break
        advance(t)
      t.sawWhitespace = true
    elif c == '#' and t.pos + 1 < t.code.len and t.code[t.pos + 1] == ' ':
      # Line comment: `# ` to end of line. (Textual-specific: requires the
      # space to disambiguate from `#id` selectors.)
      while t.pos < t.code.len and t.code[t.pos] != '\n':
        advance(t)
      t.sawWhitespace = true
    else:
      break

# ----------------------------------------------------------------------------
# Number / unit recognition
# ----------------------------------------------------------------------------

proc tryReadScalarOrNumber(t: var Tokenizer; firstLine, firstCol: int): bool =
  ## Try to read a number (with optional unit). Returns true if a token
  ## was emitted.
  let start = t.pos
  # Optional leading minus
  if t.pos < t.code.len and t.code[t.pos] == '-' and
     t.pos + 1 < t.code.len and isDigit(t.code[t.pos + 1]):
    advance(t)
  if t.pos >= t.code.len or not isDigit(t.code[t.pos]):
    t.pos = start
    return false
  while t.pos < t.code.len and isDigit(t.code[t.pos]):
    advance(t)
  if t.pos < t.code.len and t.code[t.pos] == '.':
    advance(t)
    while t.pos < t.code.len and isDigit(t.code[t.pos]):
      advance(t)
  let numEnd = t.pos
  let numText = t.code[start ..< numEnd]

  # Now check for a unit
  if t.pos < t.code.len:
    let c = t.code[t.pos]
    if c == '%':
      advance(t)
      emit(t, tkScalar, numText & "%", firstLine, firstCol)
      return true
    elif c == 'f' and t.pos + 1 < t.code.len and t.code[t.pos + 1] == 'r':
      advance(t, 2)
      emit(t, tkScalar, numText & "fr", firstLine, firstCol)
      return true
    elif c == 'w' and (t.pos + 1 >= t.code.len or
                       not isIdentCont(t.code[t.pos + 1])):
      advance(t)
      emit(t, tkScalar, numText & "w", firstLine, firstCol)
      return true
    elif c == 'h' and (t.pos + 1 >= t.code.len or
                       not isIdentCont(t.code[t.pos + 1])):
      advance(t)
      emit(t, tkScalar, numText & "h", firstLine, firstCol)
      return true
    elif c == 'v' and t.pos + 1 < t.code.len and
         (t.code[t.pos + 1] == 'w' or t.code[t.pos + 1] == 'h'):
      advance(t, 2)
      emit(t, tkScalar, numText, firstLine, firstCol)
      # actually re-emit with unit
      t.tokens[^1].value = numText & "v" & t.code[t.pos - 1]
      return true
    elif c == 'm' and t.pos + 1 < t.code.len and t.code[t.pos + 1] == 's':
      advance(t, 2)
      emit(t, tkDuration, numText & "ms", firstLine, firstCol)
      return true
    elif c == 's' and (t.pos + 1 >= t.code.len or
                       not isIdentCont(t.code[t.pos + 1])):
      advance(t)
      emit(t, tkDuration, numText & "s", firstLine, firstCol)
      return true

  emit(t, tkNumber, numText, firstLine, firstCol)
  return true

# ----------------------------------------------------------------------------
# Scope-specific lexers
# ----------------------------------------------------------------------------

proc lexRoot(t: var Tokenizer) =
  let line = t.line
  let col = t.col
  let c = peek(t)
  case c
  of '#':
    # Could be `#id` or `#rgb` color (but only at value scope). At root
    # this is always `#id` selector start.
    advance(t)
    let id = readIdent(t)
    if id.len == 0:
      raiseTokenError(t, "expected identifier after `#`")
    emit(t, tkSelectorStartId, id, line, col)
    t.scope = tsSelector
  of '.':
    advance(t)
    let id = readIdent(t)
    if id.len == 0:
      raiseTokenError(t, "expected identifier after `.`")
    emit(t, tkSelectorStartClass, id, line, col)
    t.scope = tsSelector
  of '*':
    advance(t)
    emit(t, tkSelectorStartUniversal, "*", line, col)
    t.scope = tsSelector
  of ':':
    # Bare `:focus` at root scope — interpret as `*:focus`. We emit a
    # synthetic universal start so the parser sees a selector to attach
    # the pseudo-class to.
    emit(t, tkSelectorStartUniversal, "*", line, col)
    t.scope = tsSelector
    # Don't advance — re-process the `:` in tsSelector scope.
  of '$':
    advance(t)
    let name = readIdent(t)
    if name.len == 0:
      raiseTokenError(t, "expected identifier after `$`")
    if peek(t) == ':':
      advance(t)
      emit(t, tkVariableName, name, line, col)
      t.scope = tsVariableValue
    else:
      # treat as variable reference at root (rare)
      emit(t, tkVariableRef, name, line, col)
  of '@':
    advance(t)
    let name = readIdent(t)
    emit(t, tkAtRule, name, line, col)
    t.scope = tsSelector  # at-rules look like selectors until '{'
  of '}':
    advance(t)
    emit(t, tkDeclarationSetEnd, "}", line, col)
    if t.nestLevel > 0:
      dec t.nestLevel
    t.scope = if t.nestLevel > 0: tsDeclaration else: tsRoot
  of '\0':
    discard
  else:
    if isUpperIdentStart(c):
      let id = readIdent(t)
      emit(t, tkSelectorStartType, id, line, col)
      t.scope = tsSelector
    else:
      if t.recover:
        advance(t)
        emit(t, tkUnknown, $c, line, col)
      else:
        raiseTokenError(t, "unexpected character '" & $c & "' at root scope")

proc lexSelector(t: var Tokenizer) =
  let line = t.line
  let col = t.col
  let c = peek(t)
  case c
  of '#':
    advance(t)
    let id = readIdent(t)
    emit(t, tkSelectorId, id, line, col)
  of '.':
    advance(t)
    let id = readIdent(t)
    emit(t, tkSelectorClass, id, line, col)
  of '*':
    advance(t)
    emit(t, tkSelectorUniversal, "*", line, col)
  of ':':
    advance(t)
    let id = readIdent(t)
    emit(t, tkPseudoClass, id, line, col)
  of '>':
    advance(t)
    emit(t, tkCombinatorChild, ">", line, col)
  of ',':
    advance(t)
    emit(t, tkNewSelector, ",", line, col)
  of '{':
    advance(t)
    emit(t, tkDeclarationSetStart, "{", line, col)
    inc t.nestLevel
    t.scope = tsDeclaration
  of '}':
    advance(t)
    emit(t, tkDeclarationSetEnd, "}", line, col)
    if t.nestLevel > 0: dec t.nestLevel
    t.scope = if t.nestLevel > 0: tsDeclaration else: tsRoot
  of '&':
    # Nested-CSS reference; for our subset, treat as a no-op (ignore).
    advance(t)
  of '\0':
    discard
  else:
    if isUpperIdentStart(c):
      let id = readIdent(t)
      emit(t, tkSelectorType, id, line, col)
    elif isIdentStart(c) or c == '_' or c == '-':
      # Lowercase ident in selector continue: rare, treat as type.
      let id = readIdent(t)
      emit(t, tkSelectorType, id, line, col)
    else:
      if t.recover:
        advance(t)
        emit(t, tkUnknown, $c, line, col)
      else:
        raiseTokenError(t, "unexpected '" & $c & "' in selector")

proc lexDeclaration(t: var Tokenizer) =
  let line = t.line
  let col = t.col
  let c = peek(t)
  case c
  of '}':
    advance(t)
    emit(t, tkDeclarationSetEnd, "}", line, col)
    if t.nestLevel > 0: dec t.nestLevel
    t.scope = if t.nestLevel > 0: tsDeclaration else: tsRoot
  of '\0':
    discard
  else:
    # Could be a nested selector (ID/class/type) or a declaration name.
    # Nested selector starts with '#', '.', '*', or uppercase ident.
    if c == '#' or c == '.' or c == '*':
      lexSelector(t)
      return
    if isUpperIdentStart(c) and c != '_':
      let id = readIdent(t)
      emit(t, tkSelectorStartType, id, line, col)
      t.scope = tsSelector
      return
    if c == '&':
      advance(t)
      t.scope = tsSelector
      return
    if isIdentStart(c) or c == '-':
      let name = readIdent(t)
      if name.len == 0:
        raiseTokenError(t, "expected declaration name")
      if peek(t) == ':':
        advance(t)
        emit(t, tkDeclarationName, name, line, col)
        t.scope = tsValue
      else:
        if t.recover:
          emit(t, tkUnknown, name, line, col)
        else:
          raiseTokenError(t, "expected `:` after declaration name '" & name & "'")
    else:
      if t.recover:
        advance(t)
        emit(t, tkUnknown, $c, line, col)
      else:
        raiseTokenError(t, "unexpected '" & $c & "' in declaration")

proc lexValue(t: var Tokenizer) =
  let line = t.line
  let col = t.col
  let c = peek(t)
  case c
  of ';':
    advance(t)
    emit(t, tkDeclarationEnd, ";", line, col)
    t.scope = tsDeclaration
  of '}':
    advance(t)
    emit(t, tkDeclarationSetEnd, "}", line, col)
    if t.nestLevel > 0: dec t.nestLevel
    t.scope = if t.nestLevel > 0: tsDeclaration else: tsRoot
  of ',':
    advance(t)
    emit(t, tkComma, ",", line, col)
  of '!':
    if t.pos + 9 < t.code.len and
       t.code[t.pos ..< t.pos + 10] == "!important":
      advance(t, 10)
      emit(t, tkImportant, "!important", line, col)
    else:
      if t.recover:
        advance(t)
        emit(t, tkUnknown, "!", line, col)
      else:
        raiseTokenError(t, "expected `!important`")
  of '#':
    advance(t)
    let hex = readHexColor(t)
    if hex.len in {3, 4, 6, 8}:
      emit(t, tkColorHex, "#" & hex, line, col)
    else:
      emit(t, tkUnknown, "#" & hex, line, col)
  of '"':
    let s = readString(t)
    emit(t, tkString, s, line, col)
  of '$':
    advance(t)
    let name = readIdent(t)
    emit(t, tkVariableRef, name, line, col)
  of '(':
    advance(t)
    emit(t, tkOpenParen, "(", line, col)
  of ')':
    advance(t)
    emit(t, tkCloseParen, ")", line, col)
  of '\0':
    discard
  else:
    # Numeric (with possible scalar/duration unit) or token.
    if isDigit(c) or (c == '-' and t.pos + 1 < t.code.len and
                      isDigit(t.code[t.pos + 1])):
      discard tryReadScalarOrNumber(t, line, col)
    elif isIdentStart(c) or c == '-':
      # Could be `rgb(`, `rgba(`, `hsl(...)`, or a bare token.
      let id = readIdent(t)
      if peek(t) == '(' and (id == "rgb" or id == "rgba" or
                              id == "hsl" or id == "hsla"):
        # Capture whole call as one ColorFunc token for the parser to
        # split. (Mirrors Textual's regex which captures `rgb(...)` as a
        # single COLOR token.)
        let funcStart = line
        let funcCol = col
        advance(t)  # consume '('
        var depth = 1
        let valStart = t.pos
        while t.pos < t.code.len and depth > 0:
          if t.code[t.pos] == '(': inc depth
          elif t.code[t.pos] == ')': dec depth
          if depth > 0: advance(t)
        let argText = t.code[valStart ..< t.pos]
        if t.pos < t.code.len: advance(t)  # consume ')'
        emit(t, tkColorFunc, id & "(" & argText & ")", funcStart, funcCol)
      else:
        emit(t, tkToken, id, line, col)
    else:
      if t.recover:
        advance(t)
        emit(t, tkUnknown, $c, line, col)
      else:
        raiseTokenError(t, "unexpected '" & $c & "' in value")

proc lexVariableValue(t: var Tokenizer) =
  ## Variable values run until end-of-line or `;`. We re-use the value
  ## lexer but stop on newlines.
  if peek(t) == '\n' or peek(t) == ';':
    if peek(t) == ';':
      let line = t.line
      let col = t.col
      advance(t)
      emit(t, tkDeclarationEnd, ";", line, col)
    else:
      advance(t)
    t.scope = tsRoot
  else:
    lexValue(t)

# ----------------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------------

proc tokenizeImpl(code: string; recover: bool): seq[Token] =
  ## Tokenize a CSS source string.
  ## If `recover` is true, lexical errors emit `tkUnknown` instead of
  ## raising; this matches `test_error_recovery`'s expectation that
  ## downstream rules continue to be parsed past a malformed token.
  var t = Tokenizer(code: code, pos: 0, line: 1, col: 1,
                    scope: tsRoot, recover: recover)
  while t.pos < t.code.len:
    skipWhitespaceAndComments(t)
    if t.pos >= t.code.len: break
    case t.scope
    of tsRoot: lexRoot(t)
    of tsSelector: lexSelector(t)
    of tsDeclaration: lexDeclaration(t)
    of tsValue: lexValue(t)
    of tsVariableValue: lexVariableValue(t)
  emit(t, tkEof, "", t.line, t.col)
  result = t.tokens

proc tokenize*(code: string): seq[Token] =
  ## Strict tokenization. Raises `TokenizeError` on lexical errors.
  tokenizeImpl(code, recover = false)

proc tokenizeRecover*(code: string): seq[Token] =
  ## Recovery-mode tokenization. Lexical errors emit `tkUnknown`.
  tokenizeImpl(code, recover = true)

proc `$`*(tok: Token): string =
  result = $tok.kind & "(" & tok.value & ")@" & $tok.line & ":" & $tok.col
