```sudo
# SudoLang workspace

// Three packages, one design-doc set, all under github.com/dylan-gluck/.
// docs/ is workspace-only, not part of any package.

Packages {
  tree-sitter-sudolang  // parser — grammar.js + scanner.c, v0.1.1
  sudolang-lsp          // LSP — tower-lsp + tree-sitter, v0.1.0
  zed-sudolang          // Zed extension — Rust cdylib, v0.1.2
}

# Status

Done {
  parser: "26/26 corpus tests; 5 canonical examples parse with zero ERROR/MISSING"
  lsp:    "13/13 tests; diagnostics + deterministic formatter; idempotent on canonical examples"
  zed:    "8 .scm queries; Rust extension resolves sudolang-lsp from $PATH"
}

Pending {
  install-test: "zed: install dev extension — visual verification of highlight / outline / brackets / comment-toggle"
  registry:     "Submit zed-sudolang to the Zed extensions registry"
}

warn "Claude is blocked from writing to ~/Library/Application Support/Zed/ — Phase 2.8 install-test must be run by the user."

# LSP

Formatter {
  strategy: "Re-indent each line by the count of `block` ancestors at its first non-ws byte"

  Constraints {
    "Never reorder tokens; never split or join lines"
    "Skip interior of block_comment / triple_quoted_block / double_string / template_string"
    "Refuse when tree has any ERROR/MISSING node — block ranges would be unreliable"
  }
}

Wiring {
  binary: "No bundling — Zed registry forbids it. Extension resolves via worktree.which() from $PATH"
  future: "Download-on-demand from GitHub Releases would require prebuilt artifacts per release"
  abi:    "Parser ABI 15 → tree-sitter crate >= 0.25 (0.24 fails set_language with LanguageError { version: 15 })"
}

# Parser

Scanner {
  role:   "Resolves the prose-vs-structure ambiguity the grammar alone can't"
  emits:  ["natural_language_line", "multiword_heading", "multiword_property_name", "list_marker"]
  leads:  ["fn", "function", "interface", "if", "for", "match", "require", "warn", "constraint"]

  Constraints {
    "Multi-word names recognised only when followed by `{` or `:`; else fall back to prose"
    "Prose detection scans the line for top-level `=` / `+=`; bails to the lexer if found — assignments win without precedence tricks"
    "List markers must start at column 0 (lexer->get_column) — `a + b * c` mustn't tokenise `+` as a bullet"
    "property_value uses token.immediate + leading-space regex — prevents cross-blank-line matches"
    "( -starting lines stay with the default lexer; treating them as prose broke `chunk() {}` and arrow fns"
  }
}

warn "Capitalised constraint variants (Constraints, Requirements, Options, Lint, State) are NOT grammar keywords — they collide with English prose. Use lowercase `constraint` / `constraints` only."

warn "grammar.js TS errors (`Cannot find name 'seq'`, etc.) are noise — missing @types/tree-sitter-cli, no effect on generation."
```

# Build

```bash
# tree-sitter-sudolang/
tree-sitter generate && tree-sitter test
tree-sitter build --wasm

# sudolang-lsp/
cargo test && cargo build --release
cargo run --release --example format_canonical    # formatter diff vs canonical examples

# zed-sudolang/
cargo build --release --target wasm32-wasip1
```
