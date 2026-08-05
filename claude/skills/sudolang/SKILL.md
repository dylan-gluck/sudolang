---
name: sudolang
description: >-
  Reference and commands for SudoLang, the LLM-interpreted pseudolanguage
  (v2.2 dialect). Invoke as `/sudolang [command]`: `lint <file> [--fix]`
  checks a file and repairs it, `compact <input>` compresses a doc, spec, or
  source file into SudoLang. With no command it is the syntax reference. Use
  it for .md or .sudo.md files that carry ```sudo fences, which is the
  preferred authoring form, for pure .sudo files, and for any SudoLang syntax
  question.
---

# SudoLang v2.2

An LLM **interprets** a SudoLang program. Nothing compiles it. This workspace owns the specification. Version 2.1 made v2.0 strict, so that the tree-sitter grammar, the LSP, and the Zed extension can parse it. Version 2.2 is a **strict superset** of v2.1, so every valid v2.1 program still parses.

The semantics do not change: structure where structure exists, prose as string literals, and inference everywhere else. The [New in 2.2](#new-in-22) section covers `::`, named arguments, `->`, decorators, `?.` and `??`, `...`, and `_`.

**Authoring format.** Write SudoLang in markdown with ` ```sudo ` code fences. Use a plain `.md` file, or use `.sudo.md` to mark the file as SudoLang content. The prose explains, and the fences carry the program. A pure `.sudo` file still works, and it suits a program that needs no prose. The tools extract and check each ` ```sudo ` fence in a `.md` or `.sudo.md` file.

## Commands

Invoke this skill as `/sudolang [command] [options]`. Read the command file, then follow it. The command file is the specification for that command. This page is the shared ground truth that each one depends on.

| Command   | Invocation                              | File                 |
| --------- | --------------------------------------- | -------------------- |
| `lint`    | `/sudolang lint <file>... [--fix]`      | `commands/lint.md`   |
| `compact` | `/sudolang compact <text \| @file>...`  | `commands/compact.md` |

With no command, this skill is the reference. Answer from the sections below, and load `references/spec.md` when the question needs the full syntax.

## Workspace map

| Path (under `~/Workspace/sudolang/`) | What                                                                       |
| ------------------------------------ | -------------------------------------------------------------------------- |
| `tree-sitter-sudolang/`              | Grammar (`grammar.js`), queries, and the **canonical examples** in `examples/` |
| `sudolang-lsp/`                      | The Rust LSP. The `sudolang-lsp` binary lands in `~/.cargo/bin`             |
| `zed-sudolang/`                      | The Zed editor extension                                                   |
| `docs/`                              | `cheatsheet.md`, `user-guide.md`, `grammar-specification.md`, `proposals/`  |

Ground truth is `tree-sitter-sudolang/examples/`. It holds `sudolang`, `riteway`, `autodux`, `ai-rpg`, `vector-search`, and `issue-to-pr` as `.sudo` files, plus `showcase-2.2.sudo.md` for the literate form. Every one parses with zero ERROR and zero MISSING nodes. Match their shape. When the specification prose and `grammar.js` disagree, the grammar wins.

## Core rules (v2.1 strict)

1. An identifier is one word: `StartGame`, not `Start Game`. PascalCase for an interface and camelCase for a function or property are convention, not enforcement.
2. Prose is code, but only in a legal position. Use a `"double-quoted string line"`, a `// comment`, or a `# Section heading` at the top level or in a block. Never write a bare English paragraph. A `.sudo` file has no markdown bold, no lists, and no tables.
3. Markdown hosts SudoLang through ` ```sudo ` fence injection. That is the preferred authoring form, in a `.md` or `.sudo.md` file. The grammar itself claims only `.sudo`.
4. Favor inference. Declare a function name without a body when the name says enough. Prefer a declarative `Constraints { "..." }` block over imperative control flow.
5. Follow the program skeleton. The order is a preamble comment, a `# Title`, a role string, the interfaces and functions, a `Constraints` block, the `/commands`, then a trailing invocation as the entry point.

## Parser-verified gotchas

These constructs look like SudoLang and go wrong. The fix is in the right column.

| Problem                                                              | Use instead                                                                                                                     |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| A statement that starts with `[` or `(` right after an expression statement | ASI hazard. The parser reads the `[` or `(` as an index or a call on the previous line. End the previous statement with `;`, or put the bracket-leading statement first. |
| `new Task { }`                                                        | This parses, and it parses wrong. It becomes a bare `new` expression plus an interface declaration. Use an interface declaration and a plain assignment. `new`, `class`, and `extends` are lint-prohibited. |
| `catch (e) { }`                                                       | The grammar binds the catch variable without parentheses: `catch e { }`. Better, drop `try` entirely. Version 2.2 defers it. Use `require` gates plus a `Constraints` block that states the failure policy, and `@retry(n)` for the recoverable half. |
| A bare prose line in a block                                          | Wrap it in a string: `"Say what, not how."`                                                                                     |
| A multi-word property name                                            | Use one identifier: `authorsToEmulate:`, not `Authors to emulate:`                                                              |

A lambda with a block body (`x => { log(x) }`) is legal. Earlier drafts of this skill said otherwise.

## New in 2.2

The strict superset landed these. Write them directly instead of the v2.1 workaround.

| Construct                       | Example                                                                                       |
| ------------------------------- | --------------------------------------------------------------------------------------------- |
| Qualified capability names `::` | `mcp::linear.getIssue(id)`. The `::` operator is the capability namespace, and `.` stays member access |
| Named arguments                 | `f(branch = x, base = y)`, in an argument list only                                           |
| Guards `->`                     | `!issue -> throw "not found"`, in statement position only, with no chains and no `else`        |
| Decorators                      | `@agent(general)`, stacked as `@retry(3) @timeout(120)`, before a declaration or `for each`, `while`, `loop` |
| Optional chaining and nullish   | `issue?.parent?.title ?? "none"`. The `??` operator sits at the `\|\|` tier                    |
| Spread and rest `...`           | `{ ...defaults }`, `f(...xs)`, `[first, ...rest] = xs`, `{ id, ...extras } = record`          |
| Pipe placeholder `_`            | `issues \|> filter(_.state == "open")`, inside a pipe stage only. The LSP flags misuse         |

The documented decorators are `@agent(name)`, `@retry(n)`, `@timeout(seconds)`, `@parallel`, `@memo`, and `@blocking(user)`. An unknown decorator is legal, and the interpreter infers it.

Version 2.2 also documents these as language: `throw` and `return` statements, `"""triple-quoted blocks"""` for long prose, `@scope/path` resource sigils, money and comma numerics (`$100,000`, `1,000,000`), optional parameters (`arg?`), and trailing commas.

## Check gate

A `.sudo` file or a ` ```sudo ` fence is not done until the checker accepts it.

```sh
scripts/check.sh <file.sudo | file.md | file.sudo.md | file.mdc> [more files...]
```

- The script runs the best layer the machine has. It prefers `sudolang-lsp check`, which reports every diagnostic the language server publishes: syntax errors, missing tokens, malformed modifier lists, broken string interpolations, and pipe-placeholder misuse. That binary is the only dependency — no workspace, no grammar checkout, and no build step. Install it with `cargo install sudolang-lsp`.
- Without the binary the script falls back to `scripts/validate.sh`, which parses with the `tree-sitter` CLI against a grammar checkout and reports parse errors only. It prints which layer ran.
- Either layer parses a `.sudo` file whole. For a markdown host it checks each ` ```sudo `, ` ```sudolang `, and ` ```SudoLang ` fence on its own, at host line numbers. It skips a ` ```sudo-next ` fence, which is reserved for a proposal.
- Exit 0 means clean, 1 means findings, and 2 means a usage or environment error. Fix the reported lines per the rules above and run it again. Take up to three attempts, then report the remaining diagnostics honestly. Never claim success on a failing check.
- Set `SUDOLANG_CHECK` to `lsp` or `treesitter` to force a layer. Set `SUDOLANG_GRAMMAR_DIR` to point the fallback at a grammar checkout outside `~/Workspace/sudolang`.

## Deeper reference

- `commands/`: the command specifications, one file per command.
- `references/spec.md`: the full syntax reference, with every construct, an example, the operator precedence, and the strict-mode differences from v2.0.
- `references/tooling.md`: the LSP capabilities, the editor setup, the grammar build and test commands, the formatter behavior, and the fence-injection details.
- `docs/user-guide.md`: the long-form guide. `docs/proposals/`: the language RFCs.
