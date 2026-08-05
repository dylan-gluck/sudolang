# SudoLang tooling

## File-type strategy

| Extension                 | Treatment                                                                                                                        |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `.sudo`                   | Pure SudoLang. This is the only extension the grammar claims.                                                                    |
| `.md`, `.sudo.md`, `.mdc` | Markdown is the host. SudoLang lives in a ` ```sudo `, ` ```sudolang `, or ` ```SudoLang ` fence, injected by tree-sitter-markdown. |

The grammar does not embed markdown. To check markdown-hosted SudoLang, extract the fences. See `scripts/check.sh`.

**Markdown with fences is the preferred authoring form**, in a `.md` or `.sudo.md` file. A pure `.sudo` file suits a program that needs no prose. The LSP, the `check.sh` gate, and CI all check a `.md` or `.sudo.md` file by extracting and parsing each ` ```sudo ` fence.

## tree-sitter-sudolang (grammar)

The grammar lives at `~/Workspace/sudolang/tree-sitter-sudolang`. The version is **0.3.3**, and it targets the **SudoLang v2.2** dialect, a strict superset of v2.1. The grammar is the single source of truth for what parses. When `docs/grammar-specification.md` disagrees with `grammar.js`, trust `grammar.js`.

Use the CLI that `package.json` pins, as CI does: run `npm ci`, then call `node_modules/.bin/tree-sitter`. A globally installed CLI of a different version rewrites the runtime headers and thousands of parser lines, and CI fails on the diff. The parser embeds the package version as metadata, so a version bump changes one line of `src/parser.c`.

```sh
cd ~/Workspace/sudolang/tree-sitter-sudolang
npm ci                          # install the pinned tree-sitter CLI
tree-sitter generate            # regenerate parser after grammar.js edits
tree-sitter test                # run test/corpus/*.txt
tree-sitter parse file.sudo     # parse; --quiet for exit-code-only
tree-sitter highlight file.sudo # check queries/highlights.scm
./scripts/parse-examples.sh     # .sudo whole + fences from .md / .sudo.md
```

- npm globals install the `tree-sitter` CLI, at `~/.npm-global/bin`.
- The queries are `highlights.scm`, `injections.scm`, `locals.scm`, and `tags.scm`. The `injections.scm` file ships empty on purpose, because injection into a `sudo` fence is the job of the host grammar.
- `test/corpus/` holds 56 parses across 13 files. It covers v2.1 and the v2.2 additions: `qualified.txt`, `guards.txt`, `decorators.txt`, `optional.txt`, `spread.txt`, and `placeholder.txt`.
- `examples/` holds the canonical programs: `sudolang`, `riteway`, `autodux`, `ai-rpg`, `vector-search`, and `issue-to-pr`. It also holds `showcase-2.2.sudo.md`, which demonstrates the markdown-first form.
- The corpus contract: every example in `examples/` must produce zero ERROR and zero MISSING nodes. A grammar change that breaks an example is wrong, unless the change revises the specification on purpose. See `docs/proposals/`.

## sudolang-lsp

The Rust language server builds on `tower-lsp` and the grammar. The binary is `sudolang-lsp`, in `~/.cargo/bin`. The Zed extension finds it on `$PATH`.

The binary has two modes. With no arguments it serves the LSP over stdio, which is what an editor does. With `check` it runs once and exits, which is what an agent or a CI job does:

```sh
sudolang-lsp check file.sudo notes.sudo.md   # findings, one per line
sudolang-lsp fmt file.sudo                   # formatted text to stdout
sudolang-lsp fmt --check docs/*.md           # what would change; exit 1 if any
sudolang-lsp fmt --write docs/*.md           # rewrite in place
sudolang-lsp --help                          # usage
```

`check` prints `<path>:<line>:<column>: <message>` at host line numbers, and it exits 0 for clean, 1 for findings, and 2 for a usage error or an unreadable file. `fmt --check` exits 1 when a file would change. Neither needs a workspace, a grammar checkout, or a build step, so both work in any repository that has the binary installed.

`fmt` declines a file that does not parse. Run `check` first, fix the findings, then format.

| Capability  | Behavior                                                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Diagnostics | ERROR and MISSING nodes, malformed modifiers, broken `${}` interpolations, and the 2.2 placeholder-misuse lint. The `check` subcommand prints the same set |
| Formatting  | A deterministic re-indent at two spaces per indent level. Blocks, object and array literals, patterns, argument and parameter lists, `match` braces, and multi-line pipe chains each add a level. It trims trailing space and collapses blank runs. It never reorders tokens. It refuses to format a pure `.sudo` file that has parse errors. |
| Hover       | Keyword, decorator, and capability blurbs. In-document declaration signatures, as `sudo` fences                                      |
| Completion  | Keywords, the 2.2 decorators, every named declaration in the document, and every capability namespace it uses. Triggers are `.` `/` `$` `:` `@` |
| Definition  | Same-document jumps, across every fence of one markdown document. SudoLang has no module system, so there is no cross-file jump.     |

```sh
# install / update
cargo install --path ~/Workspace/sudolang/sudolang-lsp
# test
cd ~/Workspace/sudolang/sudolang-lsp && cargo test
cargo run --release --example format_canonical
cargo run --release --example diag_dump -- path/to/file.md
```

## Zed extension

The extension lives at `~/Workspace/sudolang/zed-sudolang`. It registers the grammar and the LSP for `.sudo`, and it wires fence injection for markdown. To ship a grammar update, point the extension at a new tree-sitter-sudolang revision.

## Checking from an agent or a script

Use `scripts/check.sh`, in this skill, as the one entry point. It handles a `.sudo` file and a markdown fence, it reports host line numbers, and it exits non-zero on any finding.

It runs the best layer the machine has:

| Layer | Command | Needs | Reports |
| ----- | ------- | ----- | ------- |
| Preferred | `sudolang-lsp check` | the installed binary only | every server diagnostic |
| Fallback | `scripts/validate.sh` | the `tree-sitter` CLI and a grammar checkout | parse errors only |

The script prints which layer ran. A fallback run misses the modifier, interpolation, and placeholder lints, so say so when you report a clean result from it.

- `SUDOLANG_CHECK=lsp` or `SUDOLANG_CHECK=treesitter` forces a layer.
- `SUDOLANG_GRAMMAR_DIR` points the fallback at a grammar checkout outside `~/Workspace/sudolang`.
- Install the binary with `cargo install sudolang-lsp`. That is the one step that makes a symlinked copy of this skill work in an unrelated repository.
