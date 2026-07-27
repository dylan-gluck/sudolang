# SudoLang 2.2: expressiveness, shorthand, and the capability layer

Status: **accepted and shipped**. Grammar 0.3.0 landed the productions, and 0.3.2 is the current release. Target: SudoLang v2.2, a strict superset of v2.1.
Author: Dylan Navajas Gluck · 2026-07-23

This document is the design record. For the language as it stands, read the [user guide](../user-guide.md) and the [grammar specification](../grammar-specification.md).

---

## §1 Motivation

Version 2.1 made the language parseable. The cost was a grammar that rejects constructs fluent authors write by instinct. The field evidence comes from one real agent-workflow command, written on 2026-07-23. Six constructs appeared in the first draft, and the grammar rejected all six.

| Written instinctively              | v2.1 verdict | Author's intent                        |
| ---------------------------------- | ------------ | -------------------------------------- |
| `mcp::linear.get(id)`              | ERROR        | address a _capability_, not a property |
| `git.config(base = x, branch = y)` | ERROR        | label arguments at the call site       |
| `!issue -> throw(reason)`          | ERROR        | guard: "if this, then that"            |
| `try { } catch (e) { }`            | ERROR        | scoped failure policy                  |
| `new Task { ... }`                 | ERROR        | construct a typed value                |
| `[...requirements]`                | ERROR        | collect or merge a sequence            |

Two of the six, `new` and `try`/`catch`, have better idiomatic answers that v2.1 already supplies. The rewrite proved it, and §5 records the result. The other four are real expressiveness gaps. The author reached for semantics that the language had no syntax for. Version 2.2 closes those gaps. It also formalizes the latent features that live in `grammar.js` but not in the specification.

## §2 Design principles

**P1. LLM-first.** Syntax sharpens the interpretation of the model. It does not compile. A feature earns its place by the intent it disambiguates.

**P2. Every token must earn its place.** New syntax must compress intent. It must cost fewer tokens than the v2.1 workaround for the same meaning, or it does not ship. Section §4 measures this.

**P3. Parseable without heroics.** The grammar stays LR(1)-friendly, with no external scanner. Every canonical example keeps parsing with zero ERROR and zero MISSING nodes.

**P4. JS-gradient.** When an author guesses syntax, the guess is JavaScript. Prefer the form a JS-literate author writes correctly on the first try.

**P5. Additive only.** Every valid 2.1 program is a valid 2.2 program.

## §3 Proposals

### §3.1 Qualified names: the capability layer (`::`)

```sudo
issue = mcp::linear.getIssue(ISSUE_ID)
git::worktree.add({ branch: issue.branchName })
result = fs::read(path) |> ai::summarize
```

**Semantics.** The `::` operator addresses a _capability namespace_: a tool, an MCP server, an agent, or an external system. The `.` operator stays structural member access on a value. The split tells the LLM which of two things to do. Either resolve the name against the environment, or read the name off a value. In an agent context this maps one-to-one onto tool namespaces such as `mcp::linear`, `git::`, and `fs::`. SudoLang becomes an orchestration surface without a module system.

**Grammar.** `qualified_identifier ::= identifier ("::" identifier)+`. It is legal wherever `identifier` heads a member expression or a call. There is no conflict, because `::` is always an error today. Highlight it as `@namespace`.

**Tooling.** LSP completion offers each namespace the document uses. Hover resolves the capability. `tags.scm` captures a qualified path in a call.

**v2.1 workaround.** A flat dot-path such as `linear.getIssue`. This loses the capability-against-value distinction that authors keep trying to express.

### §3.2 Named arguments

```sudo
git::worktree.add(branch = issue.branchName, base = "origin/development")
```

**Semantics.** A call-site label, symmetric with a parameter default. The form `f(a = 1)` declares, and `f(a = 2)` invokes. For an LLM interpreter, a label at the call site is _documentation that binds_. It removes argument-order ambiguity, which is a real failure mode when the interpreter infers the body.

**Grammar.** `argument ::= expression | identifier "=" expression`. There is one conflict with assignment-as-expression inside an argument list. Precedence resolves it, because assignment is already illegal in argument position.

**v2.1 workaround.** An object-literal argument: `f({ branch: x, base: y })`. This costs two extra tokens. It also changes the shape of the callee from two parameters to one object, which matters when the LLM infers the implementation.

### §3.3 Consequence arrow (guards)

```sudo
!issue -> throw "ISSUE_ID did not resolve"
gaps -> askUser(gaps)
count > MAX -> warn "truncating to $MAX"
```

**Semantics.** The form `condition -> statement` runs the consequence only when the condition holds. Read it as "then". It works in statement position only. It does not chain, and it has no `else`. For anything richer, use `if`. This is the guard idiom that every rule engine and every prompt author reaches for.

**Grammar.** `guard_statement ::= expression "->" statement`. The `->` token is new, and it collides with nothing. The `=>` token stays the lambda and match-arm arrow. A match arm keeps `=>` on purpose. The visual split between "map to value" and "do consequence" is deliberate.

**v2.1 workaround.** `if (cond) statement`. This costs three more tokens, and it buries the rule-like character of the guard inside control flow.

### §3.4 Decorators

```sudo
@agent(general)
gatherContext() { "Explore the codebase; return a Task." }

@retry(3) @timeout(120)
validate() { "Typecheck, lint, test; fix until green." }

@parallel
for each dimension in reviews { review(dimension) }
```

**Semantics.** A decorator is declaration metadata that the interpreter honors as _execution semantics_. It states who runs the unit (`@agent`), how the interpreter handles failure (`@retry`), the concurrency (`@parallel`), the memoization (`@memo`), and the interactivity (`@blocking(user)`). A decorator answers "how should this run", so the body stays about "what it does". That split is what keeps a SudoLang program short. An unknown decorator is legal, and the interpreter infers it. Referential omnipotence reaches metadata too.

**Grammar.** The `@` sigil already lexes, because `sigil_identifier` accepts `@name/sub-path`. Add `decorator ::= "@" identifier optional(argument_list)`, and `repeat($.decorator)` before an interface declaration, a function declaration, a command declaration, and a loop statement. Highlight it as `@attribute`.

**v2.1 workaround.** A modifier list such as `fn():retry=3;`. A modifier tunes a call site, and it cannot annotate a declaration. Prose such as "run this as a subagent" costs an order of magnitude more tokens.

### §3.5 Optional chaining and nullish default

```sudo
parent = issue?.parent?.title ?? "none"
```

**Semantics and grammar.** These work as they do in JavaScript. The `?.` operator short-circuits on a null or absent value, and `??` supplies the default. Both are small additions to the expression grammar. A `?` after a parameter name already exists, so the grammar already carries the token family.

**v2.1 workaround.** `if (exists(issue.parent)) ... else ...`. This is a fivefold token cost for the most common data-shape hazard in an LLM pipeline, an absent field.

### §3.6 Pipe placeholder

```sudo
open = issues |> filter(_.state == "open") |> map(_.title) |> take(5)
```

**Semantics.** Inside a pipe-stage call, `_` is the piped value. It removes the lambda head that the current form needs, and it keeps a pipeline point-free. It is illegal outside a pipe stage.

**Grammar.** `placeholder ::= "_"` as a primary expression, valid only on the right-hand side of a `pipe_expression`. The implementer chooses between a scoped rule and a grammar-wide accept with a lint. The shipped grammar takes the second path, and the LSP diagnoses misuse.

**v2.1 workaround.** `filter(x => x.state == "open")`. The lambda head is pure ceremony when exactly one subject flows through.

### §3.7 Spread and rest

```sudo
config = { ...defaults, theme: "dark" }
run(...steps);  // `;` required — a `[` on the next line would parse as indexing
[first, ...rest] = queue
```

**Semantics and grammar.** JavaScript spread in a literal, a call, and a pattern. Authors write it without prompting, as §1 shows. Without it, the merge-or-collect intent falls back to prose.

### §3.8 Formalize latent v2.1 features

These forms are already in `grammar.js` and absent from the specification. Version 2.2 promotes them to documented language:

- triple-quoted `"""` prose blocks
- `@scope/path` resource sigils, which §3.4 builds on
- comma-grouped and money numerics: `1,000,000` and `$100,000`
- optional parameters: `arg?`
- trailing commas
- `throw` and `return` statements

## §4 Token economy

The table uses a character count as a token proxy. Each row states the same intent both ways.

| Intent          | v2.1 idiom                                   | 2.2                         | Delta             |
| --------------- | -------------------------------------------- | --------------------------- | ----------------- |
| Guard           | `if (gaps) askUser(gaps)`                    | `gaps -> askUser(gaps)`     | −4                |
| Labeled call    | `f({ branch: b, base: d })`                  | `f(branch = b, base = d)`   | −2, flatter shape |
| Null default    | `if (exists(x.p)) x.p else "none"`           | `x?.p ?? "none"`            | −20               |
| Pipe filter     | `filter(x => x.state == "open")`             | `filter(_.state == "open")` | −5                |
| Run-as-agent    | `"Run gatherContext as a general subagent."` | `@agent(general)`           | −27               |
| Capability call | `"Use the linear MCP to fetch the issue."`   | `mcp::linear.getIssue(id)`  | −16, and binding  |

The wins compound. The realistic workflow program in §8 drops about 15 percent of its tokens and gains precision. This reverses the trade that v2.0 made for v2.1, and it recovers the loss with structure instead of prose.

## §5 Considered and deferred

**`try` and `catch`.** Authors write both, as §1 shows. The constraint-first rewrite of the motivating program was _better_. A `require` gate plus a declarative failure policy reads clearer and compresses smaller than paired braces. The `@retry` decorator in §3.4 covers the recoverable half.

Deferred. Revisit if guards and decorators still leave a gap. The shipped grammar accepts `try` and `catch` for tolerance, so a JavaScript-literate draft still parses.

**`new` and classes.** These stay lint-prohibited. Interfaces and inference cover construction. The `new` keyword drags inheritance semantics that the language rejects.

**Modules and imports.** The `::` operator in §3.1 supplies the namespace story. It does so without a file-resolution system that a pseudolanguage cannot honor.

**Static types.** Interfaces and inference stay the contract. Annotations would double the token cost for marginal disambiguation.

## §6 Compatibility

Every change is additive, per P5. Every canonical example parses unchanged. Each new token is illegal in v2.1, which covers `::`, `->`, `?.`, `??`, `...`, and the decorator position. No existing program can change meaning. The grammar carried this work in version 0.3.0, and the corpus stayed green.

## §7 Implementation plan

All four steps landed in the 0.3.x line.

1. `tree-sitter-sudolang`: the tokens and rules from §3, with corpus files `qualified.txt`, `guards.txt`, `decorators.txt`, `optional.txt`, `spread.txt`, and `placeholder.txt`. The `examples/` directory gained a 2.2 showcase.
2. `sudolang-lsp`: namespace-aware completion and hover for §3.1, decorator blurbs and decorator completion for §3.4, and the placeholder-misuse diagnostic for §3.6.
3. Docs: §3.8 folded into the user guide, a 2.2 section in the cheatsheet, and an updated gotchas table in the `sudolang` skill.
4. `zed-sudolang`: the grammar revision bumped, with `@namespace` and `@attribute` highlighting.

## §8 Appendix: the motivating program

This is the issue-to-draft-PR workflow that motivated §1. The author's instinctive draft produced six parse errors. A rewrite made it valid v2.1. The version below is 2.2, where every instinctive construct is now legal or better.

```sudo
// Issue -> Draft PR — SudoLang v2.2

fetchIssue() {
  issue = mcp::linear.getIssue(ISSUE_ID)
  !issue -> throw "ISSUE_ID did not resolve"
}

createWorktree() {
  git::fetch(origin)
  git::worktree.add(branch = issue.branchName, base = "origin/development")
}

@agent(general)
gatherContext() {
  task = clarify(issue, CONTEXT) |> explore(memory, cwd, git::log) |> deduceRequirements
}

planImplementation() {
  plan = task.requirements |> design |> simplify
  "Every step traces to a requirement; drop steps that satisfy none."
}

@blocking(user)
clarificationGate() {
  gaps = task.requirements |> filter(_.ambiguous || _.conflicting || _.unachievable)
  gaps -> askUser(gaps)
}

implement() {
  for each step in plan { applyChanges(step) |> commit }
}

@retry(3)
validate() {
  "Typecheck, lint, test; fix and re-run until green."
  for each req in task.requirements, collectEvidence(req)
  evidence = req?.evidence ?? warn "surface the gap in the PR description"
}

draftPR() {
  git::push(origin, issue.branchName)
  pr = gh::pr.createDraft(base = "development", title, description)
  report(pr.url)
}

Constraints {
  "On unrecoverable failure: stop and report progress — never open the PR anyway."
}

fetchIssue() |> createWorktree |> gatherContext |> planImplementation
  |> clarificationGate |> implement |> validate |> draftPR
```

Against the valid v2.1 rewrite, this version drops the object-literal ceremony and the `if` wrappers. It also drops every prose line that existed only to say _how_ a step runs. The instincts in the first draft now parse.

That is the 2.2 thesis. The language should be strict _and_ shaped like what fluent authors already write.
