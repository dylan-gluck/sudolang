# Release runbook — coordinated cross-package rollout

One release = one version across all three packages (lockstep, currently
**0.3.0**). The dependency chain fixes the order:

```
tree-sitter-sudolang ──crates.io dep──▶ sudolang-lsp ──binary on $PATH──▶ zed-sudolang
        └──────────────grammar rev pin (built by Zed from GitHub)──────────────┘
```

## One-time setup

Publishing is authenticated by **OIDC trusted publishing** — CI exchanges
a GitHub Actions identity token for a short-lived registry token. No
token secrets exist anywhere. Configure once, in each registry's web UI:

- **crates.io** (per crate, Settings → Trusted Publishing → GitHub):
  - `tree-sitter-sudolang`: owner `dylan-gluck`, repo
    `tree-sitter-sudolang`, workflow `release.yml`, no environment
  - `sudolang-lsp`: owner `dylan-gluck`, repo `sudolang-lsp`,
    workflow `release.yml`, no environment
- **npmjs.com** (package `tree-sitter-sudolang` → Settings → Trusted
  Publisher): GitHub Actions, org `dylan-gluck`, repo
  `tree-sitter-sudolang`, workflow `release.yml`, allowed action
  `npm publish`. Provenance is generated automatically.
- The zed-sudolang registry PR (step 4) is manual the first time; later
  versions are a submodule bump in the same PR flow.

## 0. Preflight

```sh
./scripts/release-preflight.sh
```

Verifies lockstep versions, clean trees, current generated parser,
corpus + examples + LSP tests, extension wasm build, and that the Zed
grammar-rev pin matches the grammar HEAD. Fix anything it flags before
proceeding.

## 1. Grammar (tree-sitter-sudolang)

```sh
cd tree-sitter-sudolang
git push origin main
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

The tag triggers `release.yml`: test matrix → version check →
`cargo publish` + `npm publish` + GitHub Release (wasm artifact).
**Wait for the crates.io publish to succeed before step 2** — the LSP
publish resolves the grammar from crates.io.

## 2. Language server (sudolang-lsp)

```sh
cd sudolang-lsp
git push origin main
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

The tag triggers: test matrix → version check → `cargo publish` +
prebuilt binaries (mac arm64/x64, linux x64/arm64, windows x64) attached
to a GitHub Release. After this, `cargo install sudolang-lsp` works.

## 3. Zed extension (zed-sudolang)

Preflight already confirmed `extension.toml`'s grammar `rev` equals the
pushed grammar commit.

```sh
cd zed-sudolang
git push origin main
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

Then the human check Claude can't do: in Zed run
**`zed: install dev extension`**, pick the checkout, and verify
highlighting / outline / brackets / comment-toggle on `.sudo` files and
`sudo` fences in `.md` — plus LSP diagnostics + format-on-save in both.

## 4. Registry submission (first release) / update (later releases)

```sh
git clone https://github.com/zed-industries/extensions
cd extensions
git submodule add https://github.com/dylan-gluck/zed-sudolang.git extensions/sudolang
# pin the submodule to the tagged commit, on a branch (not detached):
git -C extensions/sudolang checkout main
# add to extensions.toml:
#   [sudolang]
#   submodule = "extensions/sudolang"
#   version = "X.Y.Z"
pnpm sort-extensions
# open the PR
```

Updates: PR bumping the submodule commit and the `version` field to
match the new `extension.toml`.

## 5. Workspace

```sh
git add tree-sitter-sudolang sudolang-lsp zed-sudolang
git commit -m "Release vX.Y.Z: bump submodule pins"
git push
```

## Next version

Bump ALL of these to the same version, in one commit per repo:
`package.json`, `tree-sitter.json` (metadata), grammar `Cargo.toml`;
LSP `Cargo.toml` (package **and** the `tree-sitter-sudolang` dep
version); `extension.toml` + zed `Cargo.toml`. Update each CHANGELOG.
Re-pin the zed grammar `rev` after the grammar commit exists, then run
the preflight.
