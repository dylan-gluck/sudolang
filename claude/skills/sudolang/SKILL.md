---
name: sudolang
description: >-
  Reference for writing, editing, reviewing, or validating SudoLang, the
  LLM-interpreted pseudolanguage (v2.2 dialect). Use it for .md or .sudo.md
  files that carry ```sudo fences, which is the preferred authoring form, and
  for pure .sudo files. Use it for a SudoLang syntax question, and when another
  command such as sudo:compact needs the spec, the gotchas, or the validation
  gate.
---

# SudoLang v2.2

An LLM **interprets** a SudoLang program. Nothing compiles it. This workspace owns the specification. Version 2.1 made v2.0 strict, so that the tree-sitter grammar, the LSP, and the Zed extension can parse it. Version 2.2 is a **strict superset** of v2.1, so every valid v2.1 program still parses.

The semantics do not change: structure where structure exists, prose as string literals, and inference everywhere else. The [New in 2.2](#new-in-22) section covers `::`, named arguments, `->`, decorators, `?.` and `??`, `...`, and `_`.

**Authoring format.** Write SudoLang in markdown with ` ```sudo ` code fences. Use a plain `.md` file, or use `.sudo.md` to mark the file as SudoLang content. The prose explains, and the fences carry the program. A pure `.sudo` file still works, and it suits a program that needs no prose. The tools extract and check each ` ```sudo ` fence in a `.md` or `.sudo.md` file.

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

## Validation gate

A `.sudo` file or a ` ```sudo ` fence is not done until the parser accepts it.

```sh
scripts/validate.sh <file.sudo | file.md | file.sudo.md> [more files...]
```

- The script parses a `.sudo` file whole. For a `.md` or `.sudo.md` file, it extracts every ` ```sudo `, ` ```sudolang `, and ` ```SudoLang ` fence, and it parses each one on its own with the fence line offset. It skips a ` ```sudo-next ` fence, which is reserved for a proposal.
- Exit 0 means clean. On a failure, the script prints the ERROR and MISSING node ranges. Fix the lines per the rules above and run it again. Take up to three attempts, then report the remaining diagnostics honestly. Never claim success on a failing parse.
- Set `SUDOLANG_GRAMMAR_DIR` to override the grammar location, if the workspace is not at `~/Workspace/sudolang`.

## Deeper reference

- `references/spec.md`: the full syntax reference, with every construct, an example, the operator precedence, and the strict-mode differences from v2.0.
- `references/tooling.md`: the LSP capabilities, the editor setup, the grammar build and test commands, the formatter behavior, and the fence-injection details.
- `docs/user-guide.md`: the long-form guide. `docs/proposals/`: the language RFCs.
