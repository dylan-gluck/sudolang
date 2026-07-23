# SudoLang Tooling

## File-type strategy

| Extension | Treatment |
|---|---|
| `.sudo` | Pure SudoLang — the only extension the grammar claims directly |
| `.md`, `.sudo.md`, `.mdc` | Markdown is the host; SudoLang lives in ` ```sudo ` / ` ```sudolang ` / ` ```SudoLang ` fences and is injected via tree-sitter-markdown |

The grammar deliberately does not embed markdown. Validate markdown-hosted
SudoLang by extracting fences (see `scripts/validate.sh`).

## tree-sitter-sudolang (grammar)

Located at `~/Workspace/sudolang/tree-sitter-sudolang`. The grammar is the
single source of truth for what parses; `docs/grammar-specification.md` has
sections that predate the final grammar — trust `grammar.js`.

```sh
cd ~/Workspace/sudolang/tree-sitter-sudolang
tree-sitter generate            # regenerate parser after grammar.js edits
tree-sitter test                # run test/corpus/*.txt
tree-sitter parse file.sudo     # parse; --quiet for exit-code-only
tree-sitter highlight file.sudo # check queries/highlights.scm
```

- `tree-sitter` CLI is installed via npm globals (`~/.npm-global/bin`).
- Queries: `highlights.scm`, `injections.scm` (fenced code → other grammars,
  e.g. mermaid/json/js), `locals.scm`, `tags.scm`.
- Test corpus contract: every canonical example in `examples/` must produce
  zero ERROR/MISSING nodes. Grammar changes that break an example are wrong
  unless the spec is being intentionally revised (see `docs/proposals/`).

## sudolang-lsp

Rust language server (`tower-lsp` + the grammar). Binary: `sudolang-lsp` in
`~/.cargo/bin` (auto-discovered from `$PATH` by the Zed extension).

| Capability | Behavior |
|---|---|
| Diagnostics | ERROR/MISSING nodes, malformed modifiers, broken `${}` interpolations |
| Formatting | Deterministic re-indent (2 × block depth), trims trailing space, collapses blank runs; never reorders tokens; **declines to format files with parse errors** |
| Hover | Keyword blurbs; in-document declaration signatures as `sudo` fences |
| Completion | Keywords + every named declaration in the document; triggers `.` `/` `$` |
| Definition | Same-document jumps (no module system → no cross-file) |

```sh
# install / update
cargo install --path ~/Workspace/sudolang/sudolang-lsp
# test
cd ~/Workspace/sudolang/sudolang-lsp && cargo test
cargo run --release --example format_canonical
```

## Zed extension

`~/Workspace/sudolang/zed-sudolang` — registers the grammar + LSP for `.sudo`
and wires fence injection for markdown. Grammar updates ship by pointing the
extension at a new tree-sitter-sudolang revision.

## Validation from agents/scripts

Use `scripts/validate.sh` (in this skill) as the one entry point — it handles
both `.sudo` files and markdown fences, reports per-fence offsets, and exits
non-zero on any failure. It only needs the `tree-sitter` CLI and the grammar
checkout (`SUDOLANG_GRAMMAR_DIR` overrides the default location).
