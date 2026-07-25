# SudoLang 2.2 — Expressiveness, Shorthand, and the Capability Layer

Status: **Draft 1** · Target: SudoLang v2.2 (strict superset of v2.1)
Author: Dylan Navajas Gluck · 2026-07-23

---

## §1 Motivation

v2.1 made the language parseable; the cost was rejecting constructs that
fluent authors produce instinctively. Field evidence (authoring a real
agent-workflow command, 2026-07-23): six constructs written naturally in a
first draft, all rejected by the grammar —

| Written instinctively              | v2.1 verdict | Author's intent                        |
| ---------------------------------- | ------------ | -------------------------------------- |
| `mcp::linear.get(id)`              | ERROR        | address a _capability_, not a property |
| `git.config(base = x, branch = y)` | ERROR        | label arguments at the call site       |
| `!issue -> throw(reason)`          | ERROR        | guard: "if this, then that"            |
| `try { } catch (e) { }`            | ERROR        | scoped failure policy                  |
| `new Task { ... }`                 | ERROR        | construct a typed value                |
| `[...requirements]`                | ERROR        | collect/merge a sequence               |

Two of these (`new`, `try/catch`) have better idiomatic answers that v2.1
already provides, and the rewrite proved it (§5). The other four are genuine
expressiveness gaps: the author was reaching for semantics the language has no
syntax for. 2.2 closes those gaps and formalizes latent grammar features that
exist in `grammar.js` but not in the spec.

## §2 Design principles

P1. **LLM-first.** Syntax exists to sharpen the model's interpretation, not to
compile. A feature is justified by the intent it disambiguates.
P2. **Every token must earn its place.** New syntax must compress intent —
fewer tokens than the v2.1 workaround for the same meaning, or it doesn't
ship (measured in §4).
P3. **Parseable without heroics.** LR(1)-friendly, no external scanner,
canonical examples keep parsing with zero ERROR/MISSING nodes.
P4. **JS-gradient.** When authors guess syntax, they guess JavaScript. Prefer
forms a JS-literate author writes correctly on the first try.
P5. **Additive only.** Every valid 2.1 program is a valid 2.2 program.

## §3 Proposals

### §3.1 Qualified names — the capability layer (`::`)

```sudo
issue = mcp::linear.getIssue(ISSUE_ID)
git::worktree.add({ branch: issue.branchName })
result = fs::read(path) |> ai::summarize
```

**Semantics.** `::` addresses a _capability namespace_ — tools, MCP servers,
agents, external systems — while `.` remains structural member access on
values. The distinction tells the LLM "resolve this against the environment"
vs "read this off a value". In agent contexts this maps 1:1 onto tool
namespaces (`mcp::linear`, `git::`, `fs::`) — SudoLang becomes a natural
orchestration surface without a module system.

**Grammar.** `qualified_identifier ::= identifier ("::" identifier)+`, legal
wherever `identifier` heads a member/call expression. No conflicts: `::` is
currently always an error. Highlight as `@namespace`.

**Tooling.** LSP completion segments by namespace; hover resolves the
capability. `tags.scm` gains a namespace capture.

**v2.1 workaround.** Flat dot-paths (`linear.getIssue`) — loses the
capability/value distinction that authors keep trying to express.

### §3.2 Named arguments

```sudo
git::worktree.add(branch = issue.branchName, base = "origin/development")
```

**Semantics.** Call-site labels, symmetric with parameter defaults
(`f(a = 1)` declares; `f(a = 2)` invokes). For an LLM interpreter, labels at
the call site are _documentation that binds_ — they remove argument-order
ambiguity, which is a real failure mode when bodies are inferred.

**Grammar.** `argument ::= expression | identifier "=" expression`. One
conflict with assignment-as-expression inside argument lists, resolved by
precedence (assignment is already illegal in argument position).

**v2.1 workaround.** Object-literal args: `f({ branch: x, base: y })` — two
extra tokens, and it changes the callee's shape from "two params" to "one
object", which matters when the LLM infers the implementation.

### §3.3 Consequence arrow (guards)

```sudo
!issue -> throw "ISSUE_ID did not resolve"
gaps -> askUser(gaps)
count > MAX -> warn "truncating to $MAX"
```

**Semantics.** `condition -> statement`: evaluate the consequence iff the
condition holds. Reads as "then". Statement position only — no chains, no
`else` (use `if` for anything richer). This is the guard idiom every rule
engine and every prompt author reaches for.

**Grammar.** `guard_statement ::= expression "->" statement`. `->` is a new
token; no collision (`=>` stays lambda/match-arm). Match arms keep `=>` —
the visual distinction between "map to value" (`=>`) and "do consequence"
(`->`) is intentional.

**v2.1 workaround.** `if (cond) statement` — 3 tokens heavier and buries the
guard's rule-like character inside control flow.

### §3.4 Decorators

```sudo
@agent(general)
gatherContext() { "Explore the codebase; return a Task." }

@retry(3) @timeout(120)
validate() { "Typecheck, lint, test; fix until green." }

@parallel
for each dimension in reviews { review(dimension) }
```

**Semantics.** Declaration metadata the interpreter honors as _execution
semantics_: who runs it (`@agent`), how failure is handled (`@retry`),
concurrency (`@parallel`), memoization (`@memo`), interactivity
(`@blocking(user)`). Decorators answer "how should this run" so the body can
stay about "what it does" — exactly the split that keeps SudoLang programs
short. Unknown decorators are legal and inferred (referential omnipotence
extends to metadata).

**Grammar.** The `@` sigil already lexes (`sigil_identifier` accepts
`@name/sub-path`). Add `decorator ::= "@" identifier optional(argument_list)`
and `repeat($.decorator)` before interface/function/command declarations and
loop statements. Highlight as `@attribute`.

**v2.1 workaround.** Modifier lists (`fn():retry=3;`) cover call-site tuning
but cannot annotate declarations, and prose ("run this as a subagent") costs
an order of magnitude more tokens.

### §3.5 Optional chaining and nullish default

```sudo
parent = issue?.parent?.title ?? "none"
```

**Semantics/Grammar.** As in JS: `?.` short-circuits on null/absent, `??`
supplies the default. Trivial additions to the expression grammar; `?` after
a parameter name already exists, so the token family is established.

**v2.1 workaround.** `if (exists(issue.parent)) ... else ...` — five-fold
token cost for the single most common data-shape hazard in LLM pipelines
(absent fields).

### §3.6 Pipe placeholder

```sudo
open = issues |> filter(_.state == "open") |> map(_.title) |> take(5)
```

**Semantics.** `_` inside a pipe-stage call is the piped value. Removes the
lambda head that today's form requires and keeps pipelines point-free.
Illegal outside a pipe stage.

**Grammar.** `placeholder ::= "_"` as a primary expression, valid only within
`pipe_expression` right-hand sides (enforced by a scoped rule, or accepted
grammar-wide and linted — implementer's choice; the LSP can diagnose misuse).

**v2.1 workaround.** `filter(x => x.state == "open")` — the lambda head is
pure ceremony when there's exactly one subject flowing through.

### §3.7 Spread / rest

```sudo
config = { ...defaults, theme: "dark" }
run(...steps);  // `;` required — a `[` on the next line would parse as indexing
[first, ...rest] = queue
```

**Semantics/Grammar.** JS spread in literals, calls, and patterns. Authors
write it unprompted (§1); the merge/collect intent is otherwise prose.

### §3.8 Formalize latent v2.1 features

Already in `grammar.js`, absent from the spec — 2.2 promotes them to
documented language: triple-quoted `"""` prose blocks, `@scope/path` resource
sigils (which §3.4 builds on), comma-grouped and money numerics
(`1,000,000`, `$100,000`), optional parameters (`arg?`), trailing commas,
`throw`/`return` statements.

## §4 Token economy

Character counts as a token proxy, same intent expressed both ways:

| Intent          | v2.1 idiom                                   | 2.2                         | Δ                 |
| --------------- | -------------------------------------------- | --------------------------- | ----------------- |
| Guard           | `if (gaps) askUser(gaps)`                    | `gaps -> askUser(gaps)`     | −4                |
| Labeled call    | `f({ branch: b, base: d })`                  | `f(branch = b, base = d)`   | −2, flatter shape |
| Null default    | `if (exists(x.p)) x.p else "none"`           | `x?.p ?? "none"`            | −20               |
| Pipe filter     | `filter(x => x.state == "open")`             | `filter(_.state == "open")` | −5                |
| Run-as-agent    | `"Run gatherContext as a general subagent."` | `@agent(general)`           | −27               |
| Capability call | `"Use the linear MCP to fetch the issue."`   | `mcp::linear.getIssue(id)`  | −16, and binding  |

The wins compound: a realistic workflow program (§8 appendix) drops ~15%
tokens while gaining precision — the opposite trade v2.0→v2.1 made, now
recovered with structure instead of prose.

## §5 Considered and deferred

- **`try` / `catch`.** Authors write it (§1), but the constraint-first
  rewrite of the motivating program was _better_ — `require` gates plus a
  declarative failure policy read clearer and compress smaller than paired
  braces. `@retry` (§3.4) covers the recoverable half. Deferred; revisit if
  guards + decorators still leave a gap.
- **`new` / classes.** Stays lint-prohibited. Interfaces + inference cover
  construction; `new` drags inheritance semantics the language rejects.
- **Modules / imports.** `::` (§3.1) provides the namespace story without a
  file-resolution system a pseudolanguage can't honor.
- **Static types.** Interfaces + inference remain the contract; annotations
  would double token cost for marginal disambiguation.

## §6 Compatibility

Additive throughout (P5): every canonical example parses unchanged. New
tokens (`::`, `->`, `?.`, `??`, `...`, decorator position) are all illegal in
v2.1, so no reinterpretation of existing programs is possible. Version the
grammar 0.3.0; keep the corpus green.

## §7 Implementation plan

1. `tree-sitter-sudolang`: tokens + rules per §3, corpus files
   `qualified.txt`, `guards.txt`, `decorators.txt`, `optional.txt`,
   `spread.txt`, `placeholder.txt`; extend `examples/` with a 2.2 showcase.
2. `sudolang-lsp`: namespace-aware completion/hover (§3.1), decorator blurbs
   (§3.4), placeholder-misuse diagnostic (§3.6).
3. Docs: fold §3.8 into the user guide now (it's true today); cheatsheet 2.2
   column; update the `sudolang` skill's gotchas table as items land.
4. `zed-sudolang`: bump grammar revision, highlight `@namespace` /
   `@attribute`.

## §8 Appendix — motivating program, three ways

The issue→draft-PR workflow that motivated §1. **(a)** the author's
instinctive draft — 6 parse errors; **(b)** valid v2.1 after rewrite;
**(c)** proposed 2.2 — every instinctive construct now legal or improved:

```sudo
// Issue -> Draft PR — SudoLang v2.2 (proposed)

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
  req.evidence ?? warn "surface the gap in the PR description"
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

Versus (b), this drops the object-literal ceremony, the `if` wrappers, and
every prose line that existed only to say _how_ a step runs — while (a)'s
instincts now parse. That is the 2.2 thesis: the language should be strict
_and_ shaped like what fluent authors already write.
