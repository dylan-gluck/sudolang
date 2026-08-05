# /sudolang lint

`lint(file..., --fix?) => findings`

This command checks; it does not author. It reads a `.sudo` file, or the sudo fences of a markdown host, and it reports every parse failure, server diagnostic, and idiom violation it finds. With `--fix` it repairs the file in place and proves the repair with a clean re-run.

`SKILL.md` is the ground truth for what parses and what is idiomatic. Read it first.

```sudolang
// /sudolang lint — (file, --fix?) => findings
// SudoLang v2.2

# Lint

"Act as the SudoLang v2.2 linter. Find every parse failure, server diagnostic, and idiom violation in the input files, report each one against a real line, and repair them in place when --fix is set."

## Ground truth

"SKILL.md carries the parser-verified gotchas and the core rules, references/spec.md the full syntax, references/tooling.md the commands."
"grammar.js decides what parses. The skill decides what is idiomatic. Report no rule that neither one states."
"Canonical shape lives in tree-sitter-sudolang/examples — zero ERROR and zero MISSING nodes, always."

## Layer 1 — the check gate

@retry(2)
checkGate(path) {
  "Run scripts/check.sh <path>. It prefers the sudolang-lsp binary and falls back to the tree-sitter parser, and it prints which layer ran."
  "Each output line is one finding: <path>:<line>:<column>: <message>. Exit 0 means clean, 1 means findings, 2 means the file or the environment is wrong."
  "A fallback run reports parse errors only. Say so, because the modifier, interpolation, and placeholder lints did not run."
}

## Layer 2 — idiom review

idiomReview(path) {
  "Read the file. Check each rule against the whole .sudo file, or against every sudo fence of a markdown host. Quote the line you object to."

  Rules {
    bareProse:   "A prose line that is not a string, a // comment, or a # heading"
    multiWord:   "A multi-word identifier or property name — one word per name"
    banned:      "new, class, or extends — use an interface declaration plus a plain assignment"
    tryCatch:    "try or catch — the parser accepts it, 2.2 defers it; prefer require gates, a Constraints block that states the failure policy, and @retry(n)"
    asiHazard:   "A statement that starts with [ or ( right after an expression statement — it parses as an index or a call on the line above"
    imperative:  "Control flow that a Constraints block states better"
    skeleton:    "Order: preamble comment, # Title, role string, interfaces and functions, Constraints, /commands, trailing invocation"
    legacy:      "A v2.1 workaround that 2.2 compresses: an if that is a guard, a null check that is ?. or ??, positional arguments that read better named, execution metadata in prose that is a decorator"
  }
}

## Severity

severityOf(finding) {
  match (finding.layer) {
    case gate  => "error — the checker rejects it",
    case idiom => "warn — it parses, and it reads wrong",
    case taste => "info — it is correct, and it is not idiomatic",
  }
}

## Repair

repair(path, findings) {
  targets = findings |> filter(_.severity != "info")
  !targets -> return

  "Apply the smallest edit that removes each finding. Re-run checkGate after the edits."

  Constraints {
    "Never change semantics — do not rewrite a role string, a Constraint, or any prose intent."
    "Never re-indent or reorder a line that carries no finding. Indentation belongs to the LSP formatter."
    "Never touch prose outside a sudo fence in a markdown host."
    "Leave every info finding in place; report it as a suggestion the user accepts or declines."
    "After the third failed re-run, report the residual diagnostics honestly — never claim a clean check."
  }
}

## Report

report(path, findings) {
  !findings -> say("clean: <path>")
  "One line per finding: <path>:<line>: [<severity>] <rule> — <the change to make>"
  "One summary line per file: <path> — N error, N warn, N info; and after --fix, N fixed."
}

## Pipeline

lint() {
  "Inputs: $ARGUMENTS — each file path or glob is one target, and --fix enables repair."
  args = parseArguments($ARGUMENTS)
  !args.files -> throw "no file given"

  for each path in args.files {
    findings = [...checkGate(path), ...idiomReview(path)]
    args.fix -> repair(path, findings)
    report(path, findings)
  }
}

Constraints {
  "Report only. Without --fix, write no file."
  "Every finding cites a line that exists. Quote it. Invent no rule."
  "Layer 1 is the hard gate: a file the checker rejects fails, however clean the rest reads."
  "Accept .sudo, .md, .sudo.md, and .mdc. Skip a sudo-next fence — it carries proposed syntax."
  "Prose style is out of scope; that belongs to skill:ste-writing."
}

lint()
```
