# Distribution — surface area & requirements

Audited 2026-07-23 against the submodule pins: tree-sitter-sudolang v0.1.1
(`241a4fb`), sudolang-lsp v0.2.0 (`24b291d`), zed-sudolang v0.1.3 (`de640fe`).
All three repos are clean, tagged at HEAD, and pushed to `origin/main`.

## Dependency chain

```
tree-sitter-sudolang ──git-tag dep (v0.1.1)──▶ sudolang-lsp ──binary on $PATH──▶ zed-sudolang
        └────────────grammar rev pin (241a4fb, wasm built by Zed)──────────────────────┘
```

The chain dictates the release order: the grammar crate must reach crates.io
before the LSP can, and the LSP needs a real install story before the Zed
extension is useful to anyone who didn't build it from source.

## Registry name availability (checked 2026-07-23)

| Registry  | Name                 | Status    |
|-----------|----------------------|-----------|
| crates.io | tree-sitter-sudolang | available |
| crates.io | sudolang-lsp         | available |
| npm       | tree-sitter-sudolang | available |
| PyPI      | tree-sitter-sudolang | available |
| Zed       | id `sudolang`        | not in zed-industries/extensions |

## tree-sitter-sudolang (v0.1.1)

**Surface area.** grammar.js (~20k) with generated `src/parser.c` committed;
the external scanner was removed in v0.1.1 (`externals: []`) — prose is now
handled structurally. Bindings: node (node-gyp-build + node-addon-api), rust
(root Cargo.toml, build.rs compiles parser.c via `cc`), c (header + pc.in).
No python/go/swift bindings. 4 query files ship (highlights, injections,
locals, tags). 7 corpus files under `test/corpus/`. CI matrix on
ubuntu+macos runs generate + test + example parse. Versions fully consistent
(package.json = tree-sitter.json = Cargo.toml = tag = 0.1.1).

**Verified.** `cargo package --list` includes `src/tree_sitter/*.h`, so the
published crate builds downstream. README is auto-included.

**Bugs found (fix before any publish):**

1. CI example gate is dead **and red**: the workflow globs `examples/*.sudo.md`
   but examples are `*.sudo` — the glob matches nothing and the literal path
   fails the job. Change to `examples/*.sudo`.
2. `npm test` is broken: `node --test bindings/node/*_test.js` matches no
   files. Point it at `tree-sitter test` (corpus) instead.
3. LICENSE is not in the crate package: Cargo `include` omits it. Add
   `"LICENSE"` to the include list. (SPDX `license = "MIT"` keeps the publish
   legal either way — this is a packaging-completeness fix.)
4. CHANGELOG 0.1.0 claims queries (indents/folds/brackets/outline/…) and a C
   scanner that no longer exist in the tree; `test/highlight/` is empty.

**Channels.**
- *crates.io* — primary; required to unblock sudolang-lsp. Ready after fix 3.
- *npm* — works from-source today (binding.gyp + committed parser.c);
  prebuildify is a devDep but nothing wires `prebuilds/` into publishing, so
  no prebuilt binaries ship. Acceptable for v0; wire prebuildify later.
- *PyPI* — not configured (no pyproject, no python binding,
  `tree-sitter.json` python=false). Skip unless demand appears.
- *Zed* — consumed by grammar `rev` pin; `241a4fb` is confirmed pushed, so
  the registry's from-source wasm build will succeed.

Nice-to-have: `.gitattributes` marking `src/parser.c` linguist-generated.

## sudolang-lsp (v0.2.0)

**Surface area.** tower-lsp 0.20 + tree-sitter 0.25 server: diagnostics,
deterministic formatter, hover, completion, goto-definition. Modules:
server, diagnostics, formatter, hover, completion, definition, symbols,
document; lib + `[[bin]] sudolang-lsp`. 25 integration tests across tests/
plus the `format_canonical` example. Cargo.lock committed. MIT LICENSE,
thorough README, metadata (description/keywords/categories/repo) complete.

**Hard blocker for crates.io:** the grammar is a git dependency —

```toml
tree-sitter-sudolang = { git = "https://github.com/dylan-gluck/tree-sitter-sudolang", tag = "v0.1.1" }
```

crates.io rejects crates with git deps. Sequence: publish the grammar crate,
switch this to `tree-sitter-sudolang = "0.1"`, bump to 0.2.1, publish.
(It is a git dep, not a `../` path dep, so standalone clones already build —
good for binary CI.)

**No CI of any kind.** No test workflow, no release workflow. Needed:

1. Test CI (ubuntu + macos; needs a C toolchain for the grammar's `cc` build —
   present by default on GitHub runners).
2. Release workflow producing prebuilt binaries on GitHub Releases
   (cargo-dist is the low-effort option: mac arm64/x64, linux x64, windows).
   This is also the prerequisite for the Zed extension's future
   download-on-demand path; today users must `cargo install`.

**Install story after publishing:** `cargo install sudolang-lsp` (replaces the
current `cargo install --git … --tag v0.2.0` in the README), plus GitHub
Release binaries. Homebrew tap optional later.

## zed-sudolang (v0.1.3)

**Surface area.** Rust cdylib on zed_extension_api 0.6.0, compiled to wasm by
the registry. 16 tracked files: extension.toml, languages/sudolang/config.toml
+ 8 `.scm` queries (brackets, highlights, indents, injections, outline,
overrides, runnables, textobjects — richer than the grammar repo's 4), MIT
LICENSE, README, CHANGELOG. `src/lib.rs` resolves `sudolang-lsp` via
`worktree.which()` with a helpful install error — no bundled binaries, which
is what the registry requires. Grammar pinned to `241a4fb` (= v0.1.1 tag,
pushed). extension.toml has every field the registry requires, including
`description`. Versions consistent: extension.toml = Cargo.toml = tag v0.1.3.

**One blocker:** `Cargo.lock` is gitignored and untracked. Zed's registry
build expects it committed. Remove it from .gitignore, commit it, cut v0.1.4.

Cosmetic: LICENSE says "Dylan Gluck", authors say "Dylan Navajas Gluck".

**Submission process** (zed-industries/extensions PR):
1. `git submodule add https://github.com/dylan-gluck/zed-sudolang.git extensions/sudolang`
   (HTTPS required; submodule commit must be on a branch, not detached).
2. Add entry to their `extensions.toml` with `submodule` + `version` matching
   extension.toml.
3. `pnpm sort-extensions`, open PR.
Updates later = PR bumping the submodule commit + version.

## Release order (critical path)

1. **Grammar fixes** — CI glob, npm test script, LICENSE in Cargo include,
   CHANGELOG accuracy → tag v0.1.2 → `cargo publish`. Optionally `npm publish`.
2. **LSP** — switch grammar dep to crates.io version, add test + release CI
   (prebuilt binaries) → tag v0.2.1 → `cargo publish`. Update README install.
3. **Zed extension** — commit Cargo.lock → tag v0.1.4 → user runs the Phase
   2.8 dev-extension install test (Claude cannot write to Zed's app support
   dir) → submit registry PR.
4. Later: extension download-on-demand from GitHub Releases (removes the
   $PATH requirement); npm prebuilds; PyPI binding if wanted.

## Workspace notes

- Superproject: `main` at the initial commit; submodules pinned at release
  tags; `.gitmodules` uses HTTPS (local checkouts still push over SSH — do
  not run `git submodule sync`, it would overwrite the SSH remotes). No
  remote yet — create e.g. `github.com/dylan-gluck/sudolang` and push.
- CLAUDE.md corrections needed (not applied — flagged for review):
  - Versions: lsp is v0.2.0 (hover/completion/goto-definition shipped,
    25 tests, not 13), zed is v0.1.3.
  - "parser — grammar.js + scanner.c": scanner.c was removed in v0.1.1; the
    entire `Scanner {}` block describes the pre-0.1.1 design. Keep as
    history or delete, but it no longer matches the tree.
