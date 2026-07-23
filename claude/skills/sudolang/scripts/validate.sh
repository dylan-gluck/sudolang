#!/usr/bin/env bash
# validate.sh — parse-validate SudoLang sources against tree-sitter-sudolang.
#
#   validate.sh <file.sudo | file.md> [more files...]
#
# .sudo files are parsed directly. Markdown files have every ```sudo /
# ```sudolang / ```SudoLang fence extracted and parsed individually; failures
# are reported with the fence's starting line in the host file.
#
# Exit codes: 0 = all clean, 1 = parse failures, 2 = usage / environment error.
# Env: SUDOLANG_GRAMMAR_DIR — grammar checkout (default ~/Workspace/sudolang/tree-sitter-sudolang)

set -uo pipefail

GRAMMAR_DIR="${SUDOLANG_GRAMMAR_DIR:-$HOME/Workspace/sudolang/tree-sitter-sudolang}"

if [ "$#" -lt 1 ]; then
  echo "usage: validate.sh <file.sudo | file.md> [more files...]" >&2
  exit 2
fi
if ! command -v tree-sitter >/dev/null 2>&1; then
  echo "error: tree-sitter CLI not found on PATH" >&2
  exit 2
fi
if [ ! -f "$GRAMMAR_DIR/grammar.js" ]; then
  echo "error: grammar not found at $GRAMMAR_DIR (set SUDOLANG_GRAMMAR_DIR)" >&2
  exit 2
fi

TMPDIR_V="$(mktemp -d "${TMPDIR:-/tmp}/sudolang-validate.XXXXXX")"
trap 'rm -rf "$TMPDIR_V"' EXIT

FAILURES=0

# parse_one <sudo-file> <display-label> <line-offset>
# Runs tree-sitter parse; on failure prints ERROR/MISSING diagnostics with
# rows re-based against the host file via the offset (tree-sitter rows are
# 0-indexed; host lines are 1-indexed).
parse_one() {
  local src="$1" label="$2" offset="$3" out
  if out="$(cd "$GRAMMAR_DIR" && tree-sitter parse "$src" 2>&1)" \
     && ! printf '%s' "$out" | grep -qE '\(ERROR|\(MISSING'; then
    echo "ok   : $label"
    return 0
  fi
  echo "FAIL : $label"
  printf '%s\n' "$out" | grep -oE '\((ERROR|MISSING)[^)]*\)' | sort -u | while IFS= read -r diag; do
    local row line
    row="$(printf '%s' "$diag" | sed -nE 's/.*\[([0-9]+), .*/\1/p' | head -1)"
    if [ -n "$row" ]; then
      line=$((row + 1 + offset))
      echo "         line $line: $diag"
    else
      echo "         $diag"
    fi
  done
  return 1
}

for file in "$@"; do
  if [ ! -f "$file" ]; then
    echo "error: no such file: $file" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi
  abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"

  case "$file" in
    *.sudo)
      parse_one "$abs" "$file" 0 || FAILURES=$((FAILURES + 1))
      ;;
    *.md|*.mdc)
      # Extract each sudo fence into its own file, recording the line number
      # of the first line INSIDE the fence.
      fence_dir="$TMPDIR_V/$(basename "$file").fences"
      mkdir -p "$fence_dir"
      awk -v dir="$fence_dir" '
        BEGIN { n = 0 }
        { lower = tolower($0) }
        lower ~ /^[ \t]*```(sudo|sudolang)[ \t]*$/ && !in_fence { in_fence = 1; n += 1
          out = dir "/fence-" n ".sudo"
          print NR + 1 > (dir "/fence-" n ".line")
          next }
        lower ~ /^[ \t]*```[ \t]*$/ && in_fence { in_fence = 0; close(out); next }
        in_fence { print >> out }
        END {
          if (in_fence) print n > (dir "/unterminated")
          print n > (dir "/count")
        }
      ' "$abs"
      count="$(cat "$fence_dir/count")"
      if [ -f "$fence_dir/unterminated" ]; then
        echo "FAIL : $file [fence $(cat "$fence_dir/unterminated")] — fence never closed (missing \`\`\`)"
        FAILURES=$((FAILURES + 1))
      fi
      if [ "$count" -eq 0 ]; then
        echo "ok   : $file (no sudo fences found)"
        continue
      fi
      i=1
      while [ "$i" -le "$count" ]; do
        start="$(cat "$fence_dir/fence-$i.line")"
        # An opening fence with no content/close yields no .sudo file; flag it.
        if [ ! -f "$fence_dir/fence-$i.sudo" ]; then
          echo "FAIL : $file [fence $i @ line $start] — empty or unterminated fence"
          FAILURES=$((FAILURES + 1))
        else
          parse_one "$fence_dir/fence-$i.sudo" "$file [fence $i @ line $start]" "$((start - 1))" \
            || FAILURES=$((FAILURES + 1))
        fi
        i=$((i + 1))
      done
      ;;
    *)
      echo "error: unsupported extension (want .sudo, .md, .mdc): $file" >&2
      FAILURES=$((FAILURES + 1))
      ;;
  esac
done

if [ "$FAILURES" -gt 0 ]; then
  echo "-- $FAILURES failure(s)"
  exit 1
fi
exit 0
