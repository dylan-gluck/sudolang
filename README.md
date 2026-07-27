# SudoLang

SudoLang is a pseudolanguage for instructing LLMs. It has no compiler and no runtime. The model reads the program and acts as the interpreter.

The value is compression. An interface, a constraint block, and a few guards state an intent that takes paragraphs of prose to write.

This workspace defines the language well enough to build tools for it: a dialect specification, a tree-sitter grammar, a language server, and a Zed extension. The result is editor support. You get syntax highlighting, lints, and formatting for `sudo` code fences in markdown. The three packages release in lockstep at one version. The current version is **0.3.1**, and it targets SudoLang **v2.2**.

## Packages

| Package                                                                     | What it is                                                                     | Install                                                                                                   |
| --------------------------------------------------------------------------- | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------- |
| [tree-sitter-sudolang](https://github.com/dylan-gluck/tree-sitter-sudolang) | Parser (tree-sitter grammar)                                                   | `npm install tree-sitter-sudolang` · Cargo: `tree-sitter-sudolang = "0.3.1"`                              |
| [sudolang-lsp](https://github.com/dylan-gluck/sudolang-lsp)                 | Language server (diagnostics, formatting, hover, completion, go-to-definition) | `cargo install sudolang-lsp` or [prebuilt binaries](https://github.com/dylan-gluck/sudolang-lsp/releases) |
| [zed-sudolang](https://github.com/dylan-gluck/zed-sudolang)                 | Zed extension (highlighting, outline, LSP wiring)                              | Zed → `zed: extensions` → search **SudoLang**                                                             |

The Zed extension finds `sudolang-lsp` on `$PATH`. Install the server one time. Both `.sudo` files and markdown fences then get diagnostics, hover, and formatting.

## Authoring format

Write SudoLang in markdown with `sudo` code fences. Use a plain `.md` file, or use `.sudo.md` to mark the file as SudoLang content. Programs go in the fences, and the prose around them stays prose. The tools diagnose, format, and navigate each fence in place. All fences in one document share a symbol table. A pure `.sudo` file holds one whole program and no prose.

## The dialect

```sudo
# Issue triage: SudoLang 2.2

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

Version **2.2** is a strict superset of 2.1. It adds:

- **Qualified capability names**: `mcp::linear.getIssue(id)`. The `::` operator names a capability namespace. The `.` operator is member access.
- **Named arguments**: `f(branch = x, base = y)`.
- **Guard statements**: `condition -> statement`, in statement position.
- **Decorators**: `@agent(g)` and `@retry(3)` before interfaces, functions, and loops.
- **Optional chaining and nullish default**: `issue?.labels ?? []`.
- **Spread and rest**: `...` in literals, calls, and patterns.
- **Pipe placeholder**: `_` marks the slot for the piped value in a stage.

For the full details, read the [language spec proposal](docs/proposals/sudolang-2.2.md), the [user guide](docs/user-guide.md), the [cheatsheet](docs/cheatsheet.md), and the [grammar specification](docs/grammar-specification.md). Runnable examples live in [`tree-sitter-sudolang/examples/`](https://github.com/dylan-gluck/tree-sitter-sudolang/tree/main/examples). Read `issue-to-pr.sudo` for the pure form and `showcase-2.2.sudo.md` for the literate form.

## Workspace layout

```
tree-sitter-sudolang/   # submodule. Parser: grammar.js, corpus, queries, examples
sudolang-lsp/           # submodule. Server: tower-lsp + tree-sitter, markdown virtual docs
zed-sudolang/           # submodule. Extension: Rust cdylib, queries, LSP wiring
docs/                   # workspace only: guides, spec, proposals, release runbook
scripts/                # release-preflight.sh, the cross-package release gate
```

Each package is a git submodule with its own repository and registry. This repository coordinates the releases. Clone with:

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

# language server (needs ../tree-sitter-sudolang as a sibling, a path dep)
cd sudolang-lsp
cargo test

# zed extension
cd zed-sudolang
cargo build --release --target wasm32-wasip1
````

Releases use tags and stay in lockstep. See [docs/release.md](docs/release.md) for the ordered runbook: grammar, then LSP, then Zed, then the registry.

## Origin

SudoLang comes from Eric Elliott's article [SudoLang: A Powerful Pseudocode Programming Language for LLMs](https://medium.com/javascript-scene/sudolang-a-powerful-pseudocode-programming-language-for-llms-d64d42aa719b). This workspace formalizes that idea independently, to support tooling.

## License

MIT, across all packages.
