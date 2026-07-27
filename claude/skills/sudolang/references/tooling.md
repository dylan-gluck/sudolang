# SudoLang tooling

## File-type strategy

| Extension                 | Treatment                                                                                                                        |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `.sudo`                   | Pure SudoLang. This is the only extension the grammar claims.                                                                    |
| `.md`, `.sudo.md`, `.mdc` | Markdown is the host. SudoLang lives in a ` ```sudo `, ` ```sudolang `, or ` ```SudoLang ` fence, injected by tree-sitter-markdown. |

The grammar does not embed markdown. To validate markdown-hosted SudoLang, extract the fences. See `scripts/validate.sh`.

**Markdown with fences is the preferred authoring form**, in a `.md` or `.sudo.md` file. A pure `.sudo` file suits a program that needs no prose. The LSP, the `validate.sh` gate, and CI all check a `.md` or `.sudo.md` file by extracting and parsing each ` ```sudo ` fence.

## tree-sitter-sudolang (grammar)

The grammar lives at `~/Workspace/sudolang/tree-sitter-sudolang`. The version is **0.3.2**, and it targets the **SudoLang v2.2** dialect, a strict superset of v2.1. The grammar is the single source of truth for what parses. When `docs/grammar-specification.md` disagrees with `grammar.js`, trust `grammar.js`.

```sh
cd ~/Workspace/sudolang/tree-sitter-sudolang
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

| Capability  | Behavior                                                                                                                            |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Diagnostics | ERROR and MISSING nodes, malformed modifiers, broken `${}` interpolations, and the 2.2 placeholder-misuse lint                       |
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

## Validation from an agent or a script

Use `scripts/validate.sh`, in this skill, as the one entry point. It handles a `.sudo` file and a markdown fence, it reports the offset of each fence, and it exits non-zero on any failure. It needs only the `tree-sitter` CLI and a grammar checkout. Set `SUDOLANG_GRAMMAR_DIR` to override the default location.
