# SudoLang workspace

// Superproject with three package submodules, all under github.com/dylan-gluck/.
// docs/ and claude/ are workspace-only, not part of any package.
// Versions are LOCKSTEP: one release = same version across all three packages.

```sudo
Packages {
  "tree-sitter-sudolang"  // parser — grammar.js only, no external scanner, v0.3.2
  "sudolang-lsp"          // LSP — tower-lsp + tree-sitter, markdown virtual docs, v0.3.2
  "zed-sudolang"          // Zed extension — Rust cdylib, v0.3.2
}
```

# Dialect

````sudo
// SudoLang v2.2 (docs/proposals/sudolang-2.2.md) — strict superset of v2.1.

Features {
  qualified:  "mcp::linear.getIssue(id) — :: is capability namespace, . is member access"
  namedArgs:  "f(branch = x, base = y)"
  guards:     "condition -> statement (statement position only, no else)"
  decorators: "@agent(g) @retry(3) before interface/fn declarations and loops"
  optional:   "?. member access, ?? nullish default"
  spread:     "... in literals, calls, patterns"
  placeholder: "_ in pipe stages; parses as plain identifier, LSP lints misuse"
}

FileTypes {
  preferred: ".md with ```sudo fences (or .sudo.md to signal content)"
  pure:      ".sudo — whole-file programs, no prose"
  note:      "```sudo-next fences are proposal-only; every tool skips them"
}
````

# Status

```sudo
Done {
  parser: "56/56 corpus tests; 7 examples (.sudo + .sudo.md) zero ERROR/MISSING; release CI"
  lsp:    "46/46 tests; markdown fences as virtual documents; 2.2 hovers/completions/lints"
  zed:    "grammar rev pinned to 0.3.2; LSP attaches to Markdown; Cargo.lock committed"
  docs:   "all docs + examples on 2.2; prose in ASD-STE100 (skill:ste-writing); every
           sudo fence in docs/ and claude/ passes validate.sh"
}

Released {
  registries: "v0.3.1 live: crates.io (grammar + lsp), npm (grammar; 0.3.0 is broken — Node
               binding never compiled — deprecate it if not done), GH releases with wasm + binaries"
  next:       "0.3.2 prepared locally: manifests, parser regen, CHANGELOGs — not yet tagged/pushed"
  auth:       "OIDC trusted publishing configured on crates.io (both crates) and npm — CI
               publishes with NO token secrets; new packages still need one manual first publish"
  registry:   "zed-industries/extensions PR #6961 submitted (sudolang @ 0.3.1) — awaiting merge"
}

Pending {
  installTest: "zed: install dev extension — visual verification (user-run; see warn below)"
  push:        "0.3.2 is committed in all three submodules + workspace; push + tag is user-run
                (docs/release.md steps 1-3), then the registry PR bump"
}

warn "Claude is blocked from writing to ~/Library/Application Support/Zed/ — dev-extension install tests must be run by the user."
```

# Release

```sudo
// Goal: roll out one version across all packages, automated with checks.

Process {
  preflight: "./scripts/release-preflight.sh — versions aligned, trees clean, all tests, rev pins"
  runbook:   "docs/release.md — ordered: grammar → lsp → zed → registry PR"
  order:     "grammar publishes first; lsp's dep is { path, version } and cargo publish strips
              the path to resolve crates.io; zed pins the pushed grammar rev"
}
```

# LSP

````sudo
Formatter {
  strategy: "Re-indent each line by the count of `block` ancestors at its first non-ws byte"

  Constraints {
    "Never reorder tokens; never split or join lines"
    "Skip interior of block_comment / triple_quoted_block / double_string / template_string"
    "Pure .sudo: refuse when tree has any ERROR/MISSING node"
    "Markdown: format each clean ```sudo fence in place; skip broken fences; never touch prose"
  }
}

Markdown {
  model: "Document = Vec<Block>; pure file is one block at line 0; fence mapping is line-offset only"
  scope: "Fences of one document share a symbol table — completion/hover/definition see all fences"
}

Wiring {
  binary: "No bundling — Zed registry forbids it. Extension resolves via worktree.which() from $PATH"
  dep:    "lsp → grammar is a path dep (../tree-sitter-sudolang) + version; CI checks out siblings"
  abi:    "Parser ABI 15 → tree-sitter crate >= 0.25 (0.24 fails set_language with LanguageError { version: 15 })"
}
````

# Gotchas

```sudo
warn "ASI hazard (as in JS): a statement starting with `[` or `(` after an expression
      statement parses as index/call across the newline — end the previous statement
      with `;` or reorder."

warn "Capitalised `Constraint` / `Constraints` ARE grammar keywords; Requirements /
      Options / Lint / State are NOT — they collide with prose and stay identifiers."

warn "The grammar ACCEPTS try/catch (binding without parens: `catch e { }`) and block-body
      lambdas — the 2.2 proposal defers try/catch as language; prefer require + @retry."

warn "Formatter treats only `block` as indent-bearing, so multi-line object/array literals
      and pipe continuations get flattened to their statement depth. Known, documented."

warn "grammar.js TS errors (`Cannot find name 'seq'`, etc.) are noise — missing @types/tree-sitter-cli, no effect on generation."
```

# Build

```bash
# workspace
./scripts/release-preflight.sh                    # full cross-package gate

# tree-sitter-sudolang/
tree-sitter generate && tree-sitter test
./scripts/parse-examples.sh                       # .sudo whole + fences from .md/.sudo.md
tree-sitter build --wasm

# sudolang-lsp/   (needs ../tree-sitter-sudolang checked out)
cargo test && cargo build --release
cargo run --release --example format_canonical
cargo run --release --example diag_dump -- <file.md>   # LSP diagnostics for any doc

# docs prose + fences
python3 ~/.claude/skills/ste-writing/scripts/lint.py --descriptive docs/*.md
bash claude/skills/sudolang/scripts/validate.sh docs/*.md claude/**/*.md

# zed-sudolang/
cargo build --release --target wasm32-wasip1
```
