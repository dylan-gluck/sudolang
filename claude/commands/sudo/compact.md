---
description: "sudo:compact(markdown|code) => sudo — compress a doc, spec, or source file into an equivalent idiomatic .sudo program"
argument-hint: <text | @file ...>
allowed-tools: Read, Write, Skill, Bash(tree-sitter parse:*), Bash(bash:*)
---

# sudo:compact

This is a transform, not a reference: `compact(markdown | code | prose) => .sudo`. The command converts existing material into SudoLang, and it does nothing else. For a syntax question, for authoring guidance, or for the specification, load the `sudolang` skill. This command depends on that skill and does not replace it.

```sudolang
// /sudo:compact — (markdown|code) => sudo
// SudoLang v2.2

# Compact

"Act as a SudoLang v2.2 expert. Transform each input into the most idiomatic, minimal SudoLang program that preserves every semantic intent — and write it to a .sudo file that parses cleanly."

## Ground truth

"Load the sudolang skill (claude/skills/sudolang) before writing anything: SKILL.md carries the parser-verified gotchas, references/spec.md the full syntax."
"Canonical shape lives in tree-sitter-sudolang/examples — zero ERROR or MISSING nodes, always. When in doubt, match the examples."

## Transform

toSudo(input) {
  !input -> throw "empty input"

  match (classify(input)) {
    case markdown => "Hoist headings to # sections, prose to string literals, procedures to functions, rule lists to Constraints, tables to interfaces or property lists.",
    case code     => "Lift intent, not syntax: public API => interface, invariants => Constraints, load-bearing control flow => functions + pipes; drop boilerplate the LLM can infer.",
    case prose    => "Extract roles, entities, rules, and workflows; shape as preamble + interfaces + Constraints + trailing invocation.",
    case sudo     => "Already SudoLang: tighten further and repair anything the parser rejects.",
  }

  Constraints {
    "Preserve every semantic intent — nothing lost, only compressed."
    "Favor inference: omit bodies, types, and signatures the LLM reconstructs from context."
    "Prefer declarative Constraints over imperative control flow."
    "Prose only as string literals, // comments, or # headings — never bare paragraphs."
    "Reach for 2.2 where it compresses: guards over if, :: for capabilities, named arguments, decorators for execution metadata, ?. and ?? for absent fields, _ in pipe stages."
  }
}

## Output path

outfileFor(input) {
  "@file reference => sibling path with the extension replaced by .sudo."
  "Raw text => ./<slug>.sudo where slug is kebab-cased from the first heading or first six meaningful words."
}

## Pipeline

compact() {
  "Inputs: $ARGUMENTS — each @file reference or standalone text block is one input."
  inputs = parseArguments($ARGUMENTS) |> filter(_.nonEmpty)

  for each input in inputs {
    read(input) |> toSudo |> writeFile(outfileFor(input)) |> validate
  }
}

Constraints {
  "The .sudo file is the deliverable — do not echo its contents in chat."
  "Do not invent semantics absent from the source."
  "Target a 20-30% token reduction for natural-language sources; less if the source is already terse."
  "After all files: report one line per file — 'wrote <path> (<bytes>, parse: ok)'."
}

## Validation gate

@retry(3)
validate(path) {
  "Hard gate: run the sudolang skill's scripts/validate.sh <path>. Exit 0 means done."
  "On failure: fix the reported lines per the skill's gotchas table, rewrite, re-validate."
  "After the third attempt, report residual diagnostics honestly — never claim success on a failing parse."
}

compact()
```
