# SudoLang Editor Tooling — Implementation Plan

Companion to `grammar-specification.md`. This document covers the engineering work required to deliver two artifacts:

1. **`tree-sitter-sudolang`** — a Tree-sitter parser for SudoLang.
2. **`zed-sudolang`** — a Zed editor extension that consumes that parser and provides syntax highlighting, outline, brackets, indentation, code injections, and text objects.

A future Phase 5 explores an optional SudoLang language server.

## 1. Objectives

| # | Objective | Verification |
|---|-----------|--------------|
| O1 | Parse every canonical SudoLang example with zero `ERROR` nodes | `tree-sitter parse` on the four `.sudo.md` files in this repo returns clean trees |
| O2 | Provide useful syntax highlighting in Zed for `.sudo`, `.sudo.md`, `.mdc` files | Side-by-side comparison against the existing TextMate grammar in `sudolang.tmLanguage.json` reaches feature parity, plus structural highlights TextMate can't express |
| O3 | Produce a navigable outline (interfaces, functions, commands) | Outline panel in Zed shows the structure of `ai-rpg.sudo.md` correctly |
| O4 | Support code injections for fenced blocks declaring `javascript`, `python`, `json`, `mermaid`, etc. | A `mermaid` block inside a `.sudo.md` file renders with Mermaid highlighting |
| O5 | Ship to the Zed extension registry | The extension is installable via Zed's extensions panel |

Non-goals for v1: a language server, semantic completion, LLM-backed diagnostics. These are tracked under Phase 5.

## 2. Repository structure

Two repositories, kept separate so the parser is reusable beyond Zed.

```
tree-sitter-sudolang/
├── grammar.js                  # the grammar definition
├── package.json                # npm metadata; "tree-sitter" field
├── Cargo.toml                  # rust crate metadata for downstream consumers
├── binding.gyp                 # native module build for Node
├── bindings/
│   ├── c/                      # C header
│   ├── node/                   # Node.js bindings
│   ├── rust/                   # Rust bindings
│   └── ...
├── src/                        # generated — tree-sitter generate output
│   ├── parser.c
│   ├── grammar.json
│   └── node-types.json
├── queries/                    # default queries; Zed overrides may shadow these
│   ├── highlights.scm
│   ├── injections.scm
│   ├── locals.scm
│   └── tags.scm                # for ctags/GitHub linguist
├── test/
│   └── corpus/                 # see grammar spec §8
├── examples/                   # canonical examples copied here for parse tests
└── docs/
    ├── grammar-specification.md
    └── implementation-plan.md

zed-sudolang/
├── extension.toml              # grammar + language server registration
├── languages/
│   └── sudolang/
│       ├── config.toml
│       ├── highlights.scm
│       ├── brackets.scm
│       ├── outline.scm
│       ├── indents.scm
│       ├── injections.scm
│       ├── overrides.scm
│       ├── textobjects.scm
│       └── runnables.scm
├── README.md
└── images/
    └── screenshot.png
```

The grammar repo is the upstream source of truth. The Zed extension pins a specific commit SHA of the grammar via `extension.toml`.

## 3. Phase 1 — Tree-sitter grammar

### 3.1 Setup (≈0.5 day)

- `tree-sitter init` to scaffold the project.
- Configure `package.json`, `Cargo.toml`, license (MIT, matching SudoLang).
- Set up CI on GitHub Actions: `tree-sitter generate`, `tree-sitter test`, `tree-sitter parse examples/*.sudo.md` on every PR.
- Add a pre-commit hook that runs `tree-sitter generate` and fails if `src/parser.c` is stale.

### 3.2 Skeleton grammar (≈1 day)

Implement the breadth-first skeleton:

- `source_file → repeat(_top_level_item)`
- `_top_level_item` as a `choice` over `interface_declaration`, `function_declaration`, `statement`, `natural_language_block`, and Markdown elements
- Minimal stubs for each, all returning `(identifier)` or a placeholder

Verify: a one-line SudoLang file parses; the tree contains the right top-level node.

### 3.3 Identifiers, literals, comments, strings (≈1 day)

- Implement `identifier`, `sigil_identifier`, `number`, `boolean`, `null`
- `line_comment`, `block_comment` — register as `extras`
- `double_string`, `template_string` with `string_interpolation` children
- Set `word: $ => $.identifier` for keyword extraction

Verify: parse `examples/strings.txt` test corpus.

### 3.4 Expressions and operators (≈1.5 days)

- Define `PREC` constants matching the operator table in spec §2.6
- Implement `binary_expression`, `unary_expression`, `pipe_expression` with proper precedence
- Implement `call_expression`, `member_expression`, `index_expression`, `range_expression`, `parenthesized_expression`
- Implement `array_literal`, `object_literal`
- Add `modifier_list` and `modifier` for call modifiers (`fn():length=short;`)

Verify: `expressions.txt` corpus passes; operator precedence trees match expectations.

### 3.5 Interfaces, functions, blocks (≈1 day)

- Implement `interface_declaration` with optional `interface` keyword
- Implement all five `function_declaration` shapes
- Implement `block` and `_block_member`
- Add fields per spec §7

Verify: `interfaces.txt`, `functions.txt` corpora pass.

### 3.6 Constraints, requires, warns (≈1 day)

- Implement `constraint_block`, `constraint_inline`, `require_statement`, `warn_statement`
- Allow prose bodies (`require ModuleName should be a string.`)

Verify: `constraints.txt` corpus passes.

### 3.7 Control flow and pattern matching (≈1 day)

- `for_each_statement`, `while_statement`, `loop_statement`
- `if_statement` and `if_expression` (statement form vs expression form per spec §2.4)
- `match_expression`, `match_arm`, patterns including object/array destructuring
- `return_statement`, `throw_statement`

Verify: `match.txt` corpus passes; pattern destructuring trees correct.

### 3.8 Commands (≈0.5 day)

- `command_name` token (`/foo`)
- `command_declaration` (with optional alias, args, description)
- `command_invocation` at statement position

Verify: `commands.txt` corpus passes.

### 3.9 Markdown integration (≈1 day)

- `markdown_heading` with level field
- `markdown_list_item`, `markdown_blockquote`
- `fenced_code_block` with `language` and `content` fields
- Ensure Markdown elements coexist with SudoLang at top level and inside blocks

Verify: `markdown.txt` corpus passes.

### 3.10 Natural language fallback (≈1 day)

- `natural_language_line` token with negative precedence
- `natural_language_block` as a sequence of lines
- Confirm prose appearing inside interface bodies and at top level doesn't break structural parsing

Verify: `prose.txt` corpus passes.

### 3.11 Real-world validation and tuning (≈1–2 days)

- Run `tree-sitter parse` on every canonical example
- Iterate on the grammar until each produces zero `ERROR` and zero `MISSING` nodes
- Resolve any remaining conflicts via `prec`, `prec.left`, `prec.right`, or explicit `conflicts` declarations
- Profile parser size (`tree-sitter generate --report`); investigate if `parser.c` exceeds ~2MB

Verify: O1 met.

### 3.12 Default queries (≈1 day)

Ship reasonable defaults in `queries/` so non-Zed consumers get value out of the box. The Zed extension can override these:

- `highlights.scm` — keyword, type (PascalCase identifier), function, string, number, operator captures
- `injections.scm` — fenced code blocks routed to their declared language
- `tags.scm` — for ctags / GitHub language detection
- `locals.scm` — scope tracking for `let`/`fn` (limited utility in SudoLang but useful for LSP later)

## 4. Phase 2 — Zed extension

### 4.1 Scaffolding (≈0.5 day)

- `extension.toml` registering the grammar and the `Sudolang` language
- `languages/sudolang/config.toml` with `name`, `grammar`, `path_suffixes = ["sudo", "sudo.md", "mdc"]`, `line_comments = ["// "]`
- README with installation instructions and screenshots

### 4.2 Syntax highlighting (≈1 day)

`highlights.scm` for Zed. Map captures to Zed's standard list (per Zed extension docs):

```scheme
; Keywords
[
  "fn" "function" "interface" "constraint" "constraints" "require"
  "requirements" "warn" "warnings" "match" "case" "default" "if" "else"
  "for" "each" "in" "while" "loop" "return" "throw"
] @keyword

; Types: PascalCase identifiers
((identifier) @type
  (#match? @type "^[A-Z][a-zA-Z0-9_]*$"))

; Functions: identifiers in function position
(function_declaration name: (identifier) @function)
(call_expression function: (identifier) @function.call)

; Commands
(command_name) @keyword.special  ; or @function depending on context

; Operators
[ "|>" "&&" "||" "==" "!=" "<=" ">=" "+" "-" "*" "/" "%" "^" "=" "+=" "-=" "*=" "/=" ] @operator

; Strings, numbers, booleans
(double_string) @string
(template_string) @string
(string_interpolation) @string.special.symbol
(number) @number
(boolean) @constant.builtin
(null) @constant.builtin

; Comments
(line_comment) @comment
(block_comment) @comment

; Markdown
(markdown_heading) @title
(fenced_code_block) @text.literal

; Variables
(sigil_identifier) @variable
(identifier) @variable        ; fallback for non-PascalCase
```

Acceptance: visual diff against the TextMate grammar's output on the four example files shows comparable or better coverage.

### 4.3 Brackets, indents, overrides (≈0.5 day)

- `brackets.scm` — `{}`, `[]`, `()`, `""`, ` `` `
- `indents.scm` — indent after `{` and `[`, dedent before matching close
- `overrides.scm` — strings and comments as scopes so `word_characters` and auto-closing behavior shift appropriately

### 4.4 Outline (≈0.5 day)

`outline.scm`:

```scheme
(interface_declaration
  name: (identifier) @name) @item

(function_declaration
  name: (identifier) @name) @item

(constraint_block
  name: (identifier)? @name) @item

(command_declaration
  command: (command_name) @name) @item

(markdown_heading
  text: (_) @name) @item
```

Acceptance: opening `ai-rpg.sudo.md` shows `StoryWorld`, `Inventory`, `Player`, etc. as outline entries with their methods nested correctly.

### 4.5 Injections (≈0.5 day)

`injections.scm` routes fenced code blocks to their declared language:

```scheme
(fenced_code_block
  language: (_) @injection.language
  content: (_) @injection.content)
```

Plus a redirect from `sudo` / `SudoLang` language tags to the same `sudolang` grammar (self-injection for nested examples).

### 4.6 Text objects (≈0.5 day)

`textobjects.scm` for Vim-mode users:

```scheme
(function_declaration body: (block) @function.inside) @function.around
(interface_declaration body: (block) @class.inside) @class.around
(line_comment)+ @comment.around
(block_comment) @comment.around
```

### 4.7 Runnable detection (optional, ≈0.5 day)

`runnables.scm` to surface "Run" affordances for `describe`/`assert` (Riteway) and `transpile` calls:

```scheme
(call_expression
  function: (identifier) @_name
  (#eq? @_name "describe")) @run
```

This is best-effort — the run action surfaces a button but its handler is the user's responsibility (typically copying the code to an LLM).

### 4.8 Local install testing (≈0.5 day)

- `zed: install dev extension` pointed at the local checkout
- Open each example file, verify highlighting, outline, brackets, indentation
- Toggle comments with `cmd-/` to confirm `line_comments` works
- File-icon and language picker show "SudoLang"

## 5. Phase 3 — Publishing

### 5.1 Tree-sitter parser

- Tag `v0.1.0` in `tree-sitter-sudolang`
- Publish to crates.io as `tree-sitter-sudolang`
- Publish to npm as `tree-sitter-sudolang`
- Submit to the Tree-sitter parser list (`tree-sitter/tree-sitter-...` org or community list)

### 5.2 Zed extension

- Update `extension.toml` to pin the released grammar SHA
- Tag `v0.1.0` in `zed-sudolang`
- Submit to the Zed extension registry per [Zed's submission guidelines](https://zed.dev/docs/extensions/developing-extensions.html)

## 6. Phase 4 — Maintenance and parity

After v0.1.0:

- Track SudoLang spec changes in `sudolang.sudo.md`; any new keyword, operator, or construct should land in the grammar within one release cycle
- Re-run the corpus when example programs in `paralleldrive/sudolang` evolve
- Cut a 0.2 release if any breaking change is required (e.g. node renames)

## 7. Phase 5 — Language server

A proper LSP for SudoLang has two plausible directions:

### 7.1 Structural LSP (no LLM) — shipped in v0.1.0

Released as [`sudolang-lsp`](https://github.com/dylan-gluck/sudolang-lsp) v0.1.0. Rust crate built on `tower-lsp` and `tree-sitter-sudolang`. The Zed extension registers it under `[language_servers.sudolang-lsp]` in `extension.toml`; its Rust code (`zed-sudolang/src/lib.rs`) returns the binary path from `worktree.which("sudolang-lsp")`.

Shipped capabilities:

- **`textDocument/publishDiagnostics`** — syntax errors, missing tokens, malformed modifier lists (`:foo=bar;`), broken `${}` interpolations.
- **`textDocument/formatting`** — deterministic, AST-driven re-indenter. Walks `block` ancestors per line, strips trailing whitespace, collapses 2+ blank lines, ensures a single terminal newline. Never reorders tokens, never splits or joins lines, never touches the interior of `block_comment` / `triple_quoted_block` / `double_string` / `template_string`. Declines to run when the document has parse errors.

Deferred to a follow-up release (no LLM required):

- Document symbols (from the outline tree)
- Hover for keyword documentation
- Go-to-definition for interfaces and functions defined in the same file
- Richer formatting (alignment of `Constraints` blocks, etc.)

### 7.2 LLM-backed LSP

Adds:
- Completions backed by an LLM that has seen the rest of the file as context
- "Run constraint check" — sends the program plus a constraint snippet to an LLM and reports violations as diagnostics
- "Suggest function body" code action for `fn foo;` placeholders

This is significantly more work and raises API-key, network, and privacy considerations. Defer until structural LSP is stable.

Neither is required for v1.

## 8. Acceptance criteria

The v1 release is done when **all** of the following hold:

1. `tree-sitter parse` on each of the four canonical examples produces zero `ERROR` and zero `MISSING` nodes.
2. The full test corpus described in spec §8 passes via `tree-sitter test`.
3. `zed-sudolang` installed locally provides syntax highlighting, outline, bracket matching, comment toggling, and language detection for `.sudo`, `.sudo.md`, and `.mdc` files.
4. Mermaid blocks inside a `.sudo.md` file render with Mermaid highlighting via injection.
5. Both repos have green CI on Linux and macOS.
6. The Zed extension passes `zed: check extensions` validation.
7. README files in both repos document installation and the supported feature matrix.

## 9. Tooling and conventions

- **Language**: grammar in JavaScript per Tree-sitter convention; Zed extension's Rust code only if a language server is added (Phase 5).
- **License**: MIT, matching SudoLang.
- **Node version**: pinned via `.nvmrc` to current LTS.
- **Rust toolchain**: `rust-toolchain.toml` pinned to stable for reproducibility.
- **Lint**: `eslint` on `grammar.js`, plus `tree-sitter generate --report` checked into CI to catch grammar regressions.
- **Versioning**: SemVer. Node-type renames are breaking changes.

## 10. Risks and mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Natural language fallback over-claims, swallowing structural constructs | Medium | Negative precedence on `natural_language_line`; first-character negative classes; comprehensive `prose.txt` corpus |
| LR(1) conflicts proliferate as the grammar grows | Medium | Keep `conflicts` declarations minimal; favor precedence-driven resolution; review with each new rule |
| `.sudo.md` files don't play nice with Zed's existing Markdown handler | Low | `config.toml` registers `.sudo.md` explicitly; Zed associates the longest-matching `path_suffixes` to the right language |
| Spec evolves faster than the grammar tracks | Medium | Subscribe to SudoLang releases; pin canonical examples as integration tests; cut grammar releases tied to SudoLang version |
| Parser size grows unmanageably (large `parser.c`) | Low | Inline rarely-used rules; consider `inline` field for prose helpers; monitor parser size in CI |
| TextMate grammar users expect feature parity from day one | Medium | Document the highlighting capture map in README; explicitly note features that differ |

## 11. Time estimate

Roughly 10–14 engineering days for Phase 1 and Phase 2 combined, plus 2–3 days for publishing and documentation. Phase 5 is a separate effort estimated at 5–10 days for the structural LSP, considerably more for the LLM variant.

## 12. References

- `grammar-specification.md` — this plan's companion
- [Tree-sitter — Writing the Grammar](https://tree-sitter.github.io/tree-sitter/creating-parsers/3-writing-the-grammar.html)
- [Tree-sitter — Grammar DSL](https://tree-sitter.github.io/tree-sitter/creating-parsers/2-the-grammar-dsl.html)
- [Zed — Language Extensions](https://zed.dev/docs/extensions/languages)
- [SudoLang spec (`sudolang.sudo.md`)](../sudolang.sudo.md) and example programs in this project
- [Existing TextMate grammar (`sudolang.tmLanguage.json`)](../sudolang.tmLanguage.json) — useful reference for token-level highlighting expectations
