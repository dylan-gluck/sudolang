---
name: sudolang
description: >-
  Authoritative reference for writing, editing, reviewing, or validating
  SudoLang — the LLM-interpreted pseudolanguage (v2.2 dialect). Use whenever
  working with .md/.sudo.md files carrying ```sudo fences (the preferred
  authoring form) or pure .sudo files, SudoLang syntax questions, or when
  another command (e.g. sudo:compact) needs the spec, gotchas, or the
  validation gate.
---

# SudoLang v2.2

SudoLang is a pseudolanguage **interpreted by LLMs**, not compiled. We own the
spec: v2.1 made v2.0 strict so tooling (tree-sitter grammar, LSP, Zed
extension) can parse it, and **v2.2 is a strict superset of v2.1** — every valid
v2.1 program still parses. Semantics are unchanged — structure where structure
exists, prose as string literals, inference everywhere else. The v2.2 additions
(`::`, named args, `->`, decorators, `?.`/`??`, `...`, `_`) are covered under
[New in 2.2](#new-in-22-previously-errors-now-legal).

**Authoring format:** the preferred, default form is **Markdown with ` ```sudo `
code fences** — plain `.md`, or `.sudo.md` to signal SudoLang content. Prose
explains; the fences carry the program. Pure `.sudo` files remain supported for
programs that need no surrounding prose. Tooling extracts and validates each
` ```sudo ` fence in `.md` / `.sudo.md` files.

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
3. Markdown hosts SudoLang via ` ```sudo ` fences (injection) — the preferred
   authoring form (`.md` / `.sudo.md`); the grammar itself only claims `.sudo`.
4. Favor inference: declare function names without bodies when the name says it
   all; prefer declarative `Constraints { "..." }` over imperative control flow.
5. Program skeleton: preamble comment + `# Title` + role string → interfaces /
   functions → `Constraints` → `/commands` → trailing invocation (the "main").

## Parser-verified gotchas

These constructs LOOK like SudoLang but **fail the grammar** — with the fix:

| Fails | Use instead |
|---|---|
| `try { } catch (e) { }` | `require "..."` guards + a `Constraints` block stating the failure policy; `@retry(n)` covers the recoverable half |
| `new Task { }` | Interface declaration + plain assignment (`new` / `class` / `extends` are lint-prohibited) |
| Lambda with block body `x => { }` | Named bare function `name() { }`, or expression lambda `x => expr` |
| A statement starting with `[` (or `(`) right after an expression statement | ASI hazard: the `[`/`(` is read as indexing/calling the previous line. End the prior statement with `;`, or put the bracket-leading statement first |

### New in 2.2 (previously errors, now legal)

The strict superset landed these — write them directly instead of the v2.1 workaround:

| Construct | Example |
|---|---|
| Qualified capability names `::` | `mcp::linear.getIssue(id)` — `::` is the capability namespace, `.` stays member access |
| Named arguments | `f(branch = x, base = y)` (argument lists only) |
| Guards `->` | `!issue -> throw "not found"` (statement position only; no chains / `else`) |
| Decorators | `@agent(general)`, stacked `@retry(3) @timeout(120)`, before decls / `for each` / `while` / `loop` |
| Optional chaining / nullish | `issue?.parent?.title ?? "none"` (`??` sits at the `\|\|` tier) |
| Spread / rest `...` | `{ ...defaults }`, `f(...xs)`, `[first, ...rest] = xs`, `{ id, ...extras } = record` |
| Pipe placeholder `_` | `issues \|> filter(_.state == "open")` — only inside a pipe stage; the LSP flags misuse |

Decorator vocabulary: `@agent(name)` `@retry(n)` `@timeout(seconds)` `@parallel`
`@memo` `@blocking(user)`; unknown decorators are legal and inferred.

Now documented as language (2.2): `throw` / `return` statements,
`"""triple-quoted blocks"""` for long prose, `@scope/path` resource sigils,
money / comma numerics (`$100,000`, `1,000,000`), optional params (`arg?`),
trailing commas.

## Validation gate (hard requirement)

A `.sudo` file or ` ```sudo ` fence is not done until the parser accepts it:

```sh
scripts/validate.sh <file.sudo | file.md | file.sudo.md> [more files...]
```

- `.sudo` → parsed whole; `.md` / `.sudo.md` → every ` ```sudo ` / ` ```sudolang `
  / ` ```SudoLang ` fence is extracted and parsed individually with fence line
  offsets reported. ` ```sudo-next ` fences are skipped (reserved for proposals).
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
