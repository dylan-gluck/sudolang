---
name: sudolang
description: >-
  Authoritative reference for writing, editing, reviewing, or validating
  SudoLang — the LLM-interpreted pseudolanguage (v2.1 dialect). Use whenever
  working with .sudo files, ```sudo fences in markdown, SudoLang syntax
  questions, or when another command (e.g. sudo:compact) needs the spec,
  gotchas, or the validation gate.
---

# SudoLang v2.1

SudoLang is a pseudolanguage **interpreted by LLMs**, not compiled. We own the
spec: v2.1 is v2.0 made strict so tooling (tree-sitter grammar, LSP, Zed
extension) can parse it. Semantics are unchanged — structure where structure
exists, prose as string literals, inference everywhere else.

## Workspace map

| Path (under `~/Workspace/sudolang/`) | What |
|---|---|
| `tree-sitter-sudolang/` | Grammar (`grammar.js`), queries, **canonical examples** in `examples/*.sudo` |
| `sudolang-lsp/` | Rust LSP (`sudolang-lsp` binary in `~/.cargo/bin`) |
| `zed-sudolang/` | Zed editor extension |
| `docs/` | `cheatsheet.md`, `user-guide.md`, `grammar-specification.md`, `proposals/` |
| `docs/reference/` | **NOT canonical** — pre-2.1 samples that do not parse |

Ground truth is `tree-sitter-sudolang/examples/` (sudolang, riteway, autodux,
ai-rpg, vector-search) — they parse with zero ERROR/MISSING nodes. Match their
shape. When spec prose and `grammar.js` disagree, the grammar wins.

## Core rules (v2.1 strict)

1. Identifiers are single-word (`StartGame`, not `Start Game`). PascalCase for
   interfaces, camelCase for functions/properties — convention, not enforced.
2. Prose is code, but only in legal positions: `"double-quoted string lines"`,
   `// comments`, or `# Section headings` (top-level/block only). **Never bare
   English paragraphs** — no markdown bold/lists/tables in `.sudo`.
3. Markdown files host SudoLang via ` ```sudo ` fences (injection); the grammar
   itself only claims `.sudo`.
4. Favor inference: declare function names without bodies when the name says it
   all; prefer declarative `Constraints { "..." }` over imperative control flow.
5. Program skeleton: preamble comment + `# Title` + role string → interfaces /
   functions → `Constraints` → `/commands` → trailing invocation (the "main").

## Parser-verified gotchas

These constructs LOOK like SudoLang but **fail the grammar** — with the fix:

| Fails | Use instead |
|---|---|
| `try { } catch (e) { }` | `require "..."` guards + a `Constraints` block stating the failure policy |
| `ns::member` | Dot paths: `linear.getIssue(id)` |
| `cond -> throw(x)` | `if (cond) throw x` or `require "..."` |
| Named args `f(base = x)` | Object literal: `f({ base: x })` |
| `new Task { }` | Interface declaration + plain assignment (`new` is lint-prohibited) |
| Spread `[...xs]`, `f(...xs)` | Name the collection; let the LLM infer merging |
| Lambda with block body `x => { }` | Named bare function `name() { }` or expression lambda `x => expr` |

Legal but under-documented (in the grammar, use freely): `throw`/`return`
statements, `"""triple-quoted blocks"""` for long prose, `@name/sub-path`
sigils, money/comma numerics (`$100,000`), optional params (`arg?`), trailing
commas.

## Validation gate (hard requirement)

A `.sudo` file or ` ```sudo ` fence is not done until the parser accepts it:

```sh
scripts/validate.sh <file.sudo | file.md> [more files...]
```

- `.sudo` → parsed directly; `.md` → every ` ```sudo `/` ```sudolang ` fence is
  extracted and parsed individually with fence line offsets reported.
- Exit 0 = clean. On failure it prints ERROR/MISSING node ranges — fix the
  offending lines per the rules above and re-run. Up to 3 attempts, then report
  residual diagnostics honestly; never claim success on a failing parse.
- Override the grammar location with `SUDOLANG_GRAMMAR_DIR` if the workspace
  isn't at `~/Workspace/sudolang`.

## Deeper reference

- `references/spec.md` — full syntax reference: every construct with examples,
  operator precedence, strict-mode diffs from v2.0.
- `references/tooling.md` — LSP capabilities and editor setup, grammar
  build/test commands, formatter behavior, fence-injection details.
- `docs/user-guide.md` — long-form guide; `docs/proposals/` — language RFCs.
