#!/usr/bin/env bash
# check.sh — the SudoLang check gate. This is the one entry point for an
# agent, a command, or a CI job.
#
#   check.sh <file.sudo | file.md | file.sudo.md | file.mdc> [more files...]
#
# It runs the best layer that the machine has:
#
#   1. `sudolang-lsp check` (preferred). Every diagnostic the language
#      server publishes: syntax errors, missing tokens, malformed modifier
#      lists, broken string interpolations, and pipe-placeholder misuse.
#      It needs only the installed binary — no workspace checkout, no
#      grammar checkout, and no cargo build. Install it with
#      `cargo install sudolang-lsp`.
#   2. `validate.sh` (fallback). It parses with the tree-sitter CLI
#      against a grammar checkout, and it reports parse errors only.
#
# Both layers read a pure .sudo file whole, and both read a markdown host
# one sudo fence at a time, at host line numbers.
#
# Exit codes: 0 = clean, 1 = findings, 2 = usage / environment error.
# Env:
#   SUDOLANG_CHECK        auto (default) | lsp | treesitter — force a layer
#   SUDOLANG_GRAMMAR_DIR  grammar checkout, for the fallback layer only

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${SUDOLANG_CHECK:-auto}"

if [ "$#" -lt 1 ]; then
  cat >&2 <<'USAGE'
usage: check.sh <file.sudo | file.md | file.sudo.md | file.mdc> [more files...]

  Reports every diagnostic in each file. Exit 0 = clean, 1 = findings,
  2 = usage or environment error.

  SUDOLANG_CHECK=lsp         require the sudolang-lsp binary
  SUDOLANG_CHECK=treesitter  require the tree-sitter fallback
USAGE
  exit 2
fi

have_lsp() { command -v sudolang-lsp >/dev/null 2>&1; }

run_lsp() {
  echo "-- layer: sudolang-lsp check (server diagnostics)" >&2
  sudolang-lsp check "$@"
}

run_treesitter() {
  echo "-- layer: tree-sitter parse (parse errors only; install sudolang-lsp for the full lint set)" >&2
  bash "$HERE/validate.sh" "$@"
}

case "$MODE" in
  lsp)
    if ! have_lsp; then
      echo "error: SUDOLANG_CHECK=lsp, but sudolang-lsp is not on PATH" >&2
      echo "       install it with: cargo install sudolang-lsp" >&2
      exit 2
    fi
    run_lsp "$@"
    ;;
  treesitter)
    run_treesitter "$@"
    ;;
  auto)
    if have_lsp; then
      run_lsp "$@"
    else
      run_treesitter "$@"
    fi
    ;;
  *)
    echo "error: SUDOLANG_CHECK must be auto, lsp, or treesitter (got '$MODE')" >&2
    exit 2
    ;;
esac
