# Release runbook: coordinated cross-package rollout

One release is one version across all three packages. The packages stay in lockstep. The current version is **0.3.2**.

The dependency chain fixes the order:

```
tree-sitter-sudolang ──crates.io dep──▶ sudolang-lsp ──binary on $PATH──▶ zed-sudolang
        └──────────────grammar rev pin (built by Zed from GitHub)──────────────┘
```

## One-time setup

**OIDC trusted publishing** authenticates each publish. CI exchanges a GitHub Actions identity token for a short-lived registry token. No token secrets exist anywhere. Configure this one time, in the web UI of each registry.

1. On crates.io, open **Settings > Trusted Publishing > GitHub** for each crate.
   - For `tree-sitter-sudolang`, set owner `dylan-gluck`, repo `tree-sitter-sudolang`, workflow `release.yml`, and no environment.
   - For `sudolang-lsp`, set owner `dylan-gluck`, repo `sudolang-lsp`, workflow `release.yml`, and no environment.
2. On npmjs.com, open **Settings > Trusted Publisher** for the `tree-sitter-sudolang` package. Set GitHub Actions, org `dylan-gluck`, repo `tree-sitter-sudolang`, workflow `release.yml`, and allowed action `npm publish`. Provenance follows automatically.
3. Submit the zed-sudolang registry PR by hand the first time. A later version is a submodule bump in the same PR flow.

## 0. Preflight

```sh
./scripts/release-preflight.sh
```

The script checks all of this:

- the lockstep versions across the three packages
- the clean working trees
- the generated parser against the committed `src/`
- the grammar corpus and the examples
- the LSP test suite
- the extension wasm build
- the Zed grammar-rev pin against the grammar HEAD

Fix everything the script reports before you go on.

## 1. Grammar (tree-sitter-sudolang)

```sh
cd tree-sitter-sudolang
git push origin main
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

The tag starts `release.yml`. The workflow runs the test matrix, checks the version, then runs `cargo publish`, `npm publish`, and a GitHub Release with the wasm artifact.

**Wait for the crates.io publish to succeed before step 2.** The LSP publish resolves the grammar from crates.io.

## 2. Language server (sudolang-lsp)

```sh
cd sudolang-lsp
git push origin main
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

The tag starts the test matrix and the version check. The workflow then runs `cargo publish` and attaches prebuilt binaries to a GitHub Release. The binaries cover macOS arm64 and x64, Linux x64 and arm64, and Windows x64. After this step, `cargo install sudolang-lsp` works.

## 3. Zed extension (zed-sudolang)

The preflight already confirmed that the grammar `rev` in `extension.toml` equals the pushed grammar commit.

```sh
cd zed-sudolang
git push origin main
git tag -a vX.Y.Z -m "vX.Y.Z"
git push origin vX.Y.Z
```

Then do the visual check, which Claude cannot do. Claude has no write access to the Zed support directory.

1. In Zed, run **`zed: install dev extension`**.
2. Pick this checkout.
3. Open a `.sudo` file. Check the highlighting, the outline, the brackets, and the comment toggle.
4. Open a `.md` file with `sudo` fences. Check the same four items.
5. Check the LSP diagnostics and format-on-save in both files.

## 4. Registry submission

Submit the first release by hand. A later release is an update to the same entry.

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

For an update, open a PR that bumps the submodule commit and the `version` field. The `version` field must match the new `extension.toml`.

## 5. Workspace

```sh
git add tree-sitter-sudolang sudolang-lsp zed-sudolang
git commit -m "Release vX.Y.Z: bump submodule pins"
git push
```

## Next version

Bump every field below to the same version, in one commit per repository.

- Grammar: `package.json`, the `metadata` block in `tree-sitter.json`, and `Cargo.toml`.
- LSP: `Cargo.toml`, both the package version and the `tree-sitter-sudolang` dependency version.
- Zed: `extension.toml` and `Cargo.toml`.

Then do the rest in order:

1. Update each CHANGELOG.
2. Run `tree-sitter generate` and commit the result. The generated `src/parser.c` embeds the version, so the parser changes on every bump.
3. Re-pin the Zed grammar `rev`, after the grammar commit exists.
4. Run the preflight.
