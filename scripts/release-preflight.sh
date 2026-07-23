#!/usr/bin/env bash
# Coordinated-release preflight for the SudoLang workspace.
#
# Verifies, across tree-sitter-sudolang / sudolang-lsp / zed-sudolang:
#   1. every version field carries the SAME version (lockstep releases)
#   2. all three working trees are clean
#   3. grammar: generated parser is current, corpus green, examples parse
#      (.sudo whole, ```sudo fences extracted from .md/.sudo.md)
#   4. lsp: full test suite green
#   5. zed: extension wasm builds; pinned grammar rev == grammar HEAD;
#      Cargo.lock is tracked
#
# Exits non-zero on the first failure. Run from anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
pass() { printf '  ok: %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; exit 1; }

GRAMMAR=tree-sitter-sudolang
LSP=sudolang-lsp
ZED=zed-sudolang

bold "1/5 version lockstep"
v_pkg=$(node -p "require('./$GRAMMAR/package.json').version")
v_ts=$(node -p "require('./$GRAMMAR/tree-sitter.json').metadata.version")
v_gcargo=$(grep -m1 '^version = ' $GRAMMAR/Cargo.toml | cut -d'"' -f2)
v_lsp=$(grep -m1 '^version = ' $LSP/Cargo.toml | cut -d'"' -f2)
v_ldep=$(grep -m1 'tree-sitter-sudolang = ' $LSP/Cargo.toml | sed 's/.*version = "\([^"]*\)".*/\1/')
v_ext=$(grep -m1 '^version = ' $ZED/extension.toml | cut -d'"' -f2)
v_zcargo=$(grep -m1 '^version = ' $ZED/Cargo.toml | cut -d'"' -f2)
echo "  grammar: pkg=$v_pkg tree-sitter.json=$v_ts cargo=$v_gcargo"
echo "  lsp:     cargo=$v_lsp grammar-dep=$v_ldep"
echo "  zed:     extension=$v_ext cargo=$v_zcargo"
for v in "$v_ts" "$v_gcargo" "$v_lsp" "$v_ldep" "$v_ext" "$v_zcargo"; do
  [ "$v" = "$v_pkg" ] || fail "version mismatch: $v != $v_pkg"
done
pass "all packages at $v_pkg"

bold "2/5 clean working trees"
for repo in $GRAMMAR $LSP $ZED; do
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    fail "$repo has uncommitted changes"
  fi
  pass "$repo clean"
done

bold "3/5 grammar: generate + corpus + examples"
(cd $GRAMMAR && tree-sitter generate)
if [ -n "$(git -C $GRAMMAR status --porcelain src/)" ]; then
  fail "generated parser differs from committed src/ — run tree-sitter generate and commit"
fi
pass "committed parser is current"
(cd $GRAMMAR && tree-sitter test >/dev/null) || fail "corpus tests"
pass "corpus green"
(cd $GRAMMAR && ./scripts/parse-examples.sh >/dev/null) || fail "example parse"
pass "examples parse (.sudo + fences)"

bold "4/5 lsp: tests"
(cd $LSP && cargo test --quiet >/dev/null 2>&1) || fail "cargo test in $LSP"
pass "lsp tests green"

bold "5/5 zed: wasm build + pins"
(cd $ZED && cargo build --release --target wasm32-wasip1 >/dev/null 2>&1) \
  || fail "zed extension wasm build"
pass "extension compiles (wasm32-wasip1)"
git -C $ZED ls-files --error-unmatch Cargo.lock >/dev/null 2>&1 \
  || fail "zed Cargo.lock is not tracked (registry requires it)"
pass "Cargo.lock tracked"
pinned=$(grep -m1 '^rev = ' $ZED/extension.toml | cut -d'"' -f2)
head=$(git -C $GRAMMAR rev-parse HEAD)
[ "$pinned" = "$head" ] || fail "zed grammar rev ($pinned) != grammar HEAD ($head)"
pass "zed grammar rev matches grammar HEAD"
if remote_head=$(git -C $GRAMMAR ls-remote origin -h refs/heads/main 2>/dev/null | cut -f1); then
  if [ "$remote_head" = "$head" ]; then
    pass "grammar HEAD is pushed to origin/main"
  else
    echo "  WARN: grammar HEAD not on origin/main yet — push before building the Zed extension or submitting to the registry"
  fi
else
  echo "  WARN: could not reach origin to verify the grammar rev is pushed"
fi

bold "preflight passed — release order: grammar → lsp → zed (docs/release.md)"
