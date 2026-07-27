# SudoLang

SudoLang is a pseudolanguage for instructing LLMs — a fake language with
no rules, no compiler, and no runtime. The model is the interpreter. It
earns its keep because intelligence is compression: an interface, a
constraint block, and a few guards state intent that prose circles for
paragraphs.

This workspace formalizes that fake language just enough to hang real
tooling on it: a dialect specification, a tree-sitter grammar, a language
server, and a Zed extension. In practice that mostly means editor support —
syntax highlighting, lints, and formatting for `sudo` code fences in
markdown. The packages release in lockstep, one version across all three
(currently **v0.3.1**, SudoLang **v2.2**).

## Packages

| Package                                                                     | What it is                                                                     | Install                                                                                                   |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| [tree-sitter-sudolang](https://github.com/dylan-gluck/tree-sitter-sudolang) | Parser (tree-sitter grammar)                                                   | `npm install tree-sitter-sudolang` · Cargo: `tree-sitter-sudolang = "0.3.1"`                              |
| [sudolang-lsp](https://github.com/dylan-gluck/sudolang-lsp)                 | Language server (diagnostics, formatting, hover, completion, go-to-definition) | `cargo install sudolang-lsp` or [prebuilt binaries](https://github.com/dylan-gluck/sudolang-lsp/releases) |
| [zed-sudolang](https://github.com/dylan-gluck/zed-sudolang)                 | Zed extension (highlighting, outline, LSP wiring)                              | Zed → `zed: extensions` → search **SudoLang**                                                             |

The Zed extension resolves `sudolang-lsp` from `$PATH`; install the server
once and both `.sudo` files and markdown fences get diagnostics, hover,
and formatting.

## Authoring format

The preferred format is **markdown with `sudo` code fences** — plain `.md`,
or `.sudo.md` to signal SudoLang content. Prose stays prose; programs live
in fences; the tooling diagnoses, formats, and navigates the fences in
place, and all fences of one document share a symbol table. Pure `.sudo`
files hold whole-file programs with no surrounding prose.

## The dialect

```sudo
# Issue triage — SudoLang 2.2

interface TriageAgent {
  queue: [Issue]

  Constraints {
    "Escalate anything critical before touching the rest of the queue."
  }

  @retry(3)
  fn triage(issue) {
    labels = issue?.labels ?? []
    issue.priority == "critical" -> escalate(issue)
    mcp::linear.updateIssue(id = issue.id, labels = [...labels, "triaged"])
  }

  fn drain() {
    [next, ...rest] = queue
    next |> triage(_) |> log
    queue = rest
  }
}
```

New in **v2.2** (a strict superset of v2.1):

- **Qualified capability names** — `mcp::linear.getIssue(id)`: `::` names a
  capability namespace, `.` is member access.
- **Named arguments** — `f(branch = x, base = y)`.
- **Guard statements** — `condition -> statement`, in statement position.
- **Decorators** — `@agent(g)`, `@retry(3)` before interfaces, functions,
  and loops.
- **Optional chaining & nullish default** — `issue?.labels ?? []`.
- **Spread / rest** — `...` in literals, calls, and patterns.
- **Pipe placeholder** — `_` marks the piped value's slot in a stage.

Full details: the [language spec proposal](docs/proposals/sudolang-2.2.md),
the [user guide](docs/user-guide.md), the [cheatsheet](docs/cheatsheet.md),
and the [grammar specification](docs/grammar-specification.md). Runnable
examples live in
[`tree-sitter-sudolang/examples/`](https://github.com/dylan-gluck/tree-sitter-sudolang/tree/main/examples)
— see `issue-to-pr.sudo` (pure) and `showcase-2.2.sudo.md` (literate).

## Workspace layout

```
tree-sitter-sudolang/   # submodule — parser: grammar.js, corpus, queries, examples
sudolang-lsp/           # submodule — server: tower-lsp + tree-sitter, markdown virtual docs
zed-sudolang/           # submodule — extension: Rust cdylib, queries, LSP wiring
docs/                   # workspace-only: guides, spec, proposals, release runbook
scripts/                # release-preflight.sh — cross-package release gate
```

Packages are git submodules with their own repos and registries; releases
are coordinated here. Clone with:

```sh
git clone --recurse-submodules <this-repo>
```

## Development

````sh
./scripts/release-preflight.sh              # full cross-package gate

# parser
cd tree-sitter-sudolang
tree-sitter generate && tree-sitter test
./scripts/parse-examples.sh                 # .sudo whole + ```sudo fences from .md

# language server (needs ../tree-sitter-sudolang as a sibling — path dep)
cd sudolang-lsp
cargo test

# zed extension
cd zed-sudolang
cargo build --release --target wasm32-wasip1
````

Releases are tag-driven and lockstep — see [docs/release.md](docs/release.md)
for the ordered runbook (grammar → LSP → Zed → registry).

## Origin

SudoLang comes from Eric Elliott's article
[SudoLang: A Powerful Pseudocode Programming Language for LLMs](https://medium.com/javascript-scene/sudolang-a-powerful-pseudocode-programming-language-for-llms-d64d42aa719b).
This workspace is an independent formalization of the idea, built for
tooling.

## License

MIT, across all packages.
