# SudoLang v2.2 — Syntax Reference

Condensed from `docs/cheatsheet.md`, `docs/user-guide.md`, and (authoritatively)
`tree-sitter-sudolang/grammar.js`. Everything here parses clean. v2.2 is a strict
superset of v2.1 — the v2.1 constructs below are unchanged; the additions are
under [SudoLang 2.2 additions](#sudolang-22-additions).

## Comments & prose

```sudo
// line comment
/* block comment */
# Section heading        — outline anchor; top-level or block position only
"Prose lines are string literals — the canonical place for natural language."
"""
Triple-quoted blocks hold long prose or examples.
Multi-line, no interpolation, body left untouched by the formatter.
"""
```

## Literals

```sudo
n = 42
f = 3.14
big = 1,000,000          // comma-grouped numerics parse
pay = $100,000           // money literals parse as numbers
ok = true; nothing = null
list = [1, 2, 3,]        // trailing commas legal
obj = { name: "x", nested: { a: 1 }, shorthand }
sig = $name              // $ sigil identifier
ref = @scope/path-name   // @ sigil with /-separated path segments
```

## Strings & interpolation

```sudo
"Hello, $name"           // identifier interpolation
"Total: ${a + b}"        // expression interpolation
"Literal \$42"           // escaped dollar
`backtick template ${x}` // equivalent semantics
```

## Operators (high → low precedence)

```
.  ()  []                 member / call / index
:mod=val;                 modifier list (binds to the call)
!  - (unary)              prefix
^                         exponent (right-assoc)
*  /  %                   multiplicative
+  -                      additive
..                        range (1..10 inclusive)
union  intersection       set ops (cap/cup deprecated aliases)
<  >  <=  >=              comparison
==  !=                    equality
&&                        AND
||  xor                   OR
=  +=  -=  *=  /=         assignment (right-assoc)
|>                        pipe (lowest)
```

## Variables, destructuring, assignment

```sudo
[a, b] = [1, 2]
{ name, age } = user
x = 42
x += 1
obj.prop = 5
arr[0] = "first"
```

(Destructuring targets lead so the `[`-line isn't read as indexing a prior
expression — see the ASI gotcha under [SudoLang 2.2 additions](#sudolang-22-additions).)

## Conditionals

```sudo
status = if (age >= 18) "adult" else "minor"   // expression form
if (cond) { a() } else { b() }                 // statement form, block bodies
if (cond) doThing()                            // single-statement consequence
```

## Pattern matching

```sudo
result = match (value) {
  case { type: "circle", radius } => "r=$radius",
  case [first, second]            => "pair",
  case 42                         => "the answer",
  default                         => "unknown",
}
```

## Functions

```sudo
fn inferred                              // signature only — body inferred
function greet(name);                    // keyword + params, no body
function add(x, y) { return x + y }      // full definition
chunk() { "Chunk the text." }            // bare-name + block (block REQUIRED)
f = x => x + 1                           // arrow function (expression body only)
withDefaults(a = 1, b?) { log(a, b) }    // defaults and optional params
pick({ name, age }) { name }             // destructuring params
```

- The bare-name form requires a block — that's what disambiguates it from a
  call. `chunk()` alone is a call; `chunk() { ... }` is a declaration.
- `return` and `throw` are statements: `throw "issue not found"`.

## Modifiers

Post-fix tuning on calls/signatures; semicolon terminates the list:

```sudo
explain(topic):length=short, detail=simple;
log(results):format="json"
```

## Interfaces

```sudo
Player {                    // `interface` keyword optional
  name: "Hero"              // property declaration (colon form)
  score = 0                 // property assignment (equals form)
  health                    // bare property — type/value inferred
  items: { [item]: { name, weight } }   // computed-key shape

  attack(target) {
    "Calculate and apply damage."
  }

  State { Config { theme: "dark" } }    // nesting composes state
}
```

Composition over inheritance. `class`, `extends`, `new` are lint-prohibited.

## Constraints, require, warn

```sudo
Constraints {                      // declarative rules — the idiomatic core
  "Rule as prose string, one per line."
  "Say what, not how."
}
constraint MinSalary { emit(violation) }    // named block
constraint: "Inline prose rule."            // inline form
require "users must be over 13"             // hard gate — throw on violation
warn "name should be defined"               // soft guidance
```

Error handling is constraint-first: there is no try/catch. State the failure
policy declaratively ("On unrecoverable failure: stop and report — never
proceed") and gate steps with `require`.

## Commands

```sudo
/help - show help                    // declaration: name - description
/l | learn [topic] - learn a topic   // alias + [args]
/start                               // invocation (also the program "main")
```

## Loops

```sudo
for each item in items, process(item)    // comma + single statement
for each item in items { process(item) } // block body
while (running) { tick() }
loop { poll() }                          // infinite
```

## Pipes

```sudo
data |> transform |> format |> log       // value threading
h = f |> g                               // function composition; h(20)
results = query() |> filter(relevant) |> take(5)
```

## Referential omnipotence

Undeclared functions are legal and inferred from name + context. Common
inferred stdlib: `ask log list emit run explain transpile(lang) convert wrap
escape concat sort sortBy filter map find groupBy join split trim reverse
unique flatten merge pick pluck zip take takeLast skip slice count min max`.

## SudoLang 2.2 additions

Strict superset of v2.1 — all of the above still parses. New syntax:

```sudo
mcp::linear.getIssue(id)          // :: — capability namespace; . stays member access
git::worktree.add(branch = x, base = y)   // named arguments (argument lists only)
!issue -> throw "not found"       // guard: condition -> statement (stmt position only)
gaps -> askUser(gaps)             // consequence: statement, block, require, or warn

@agent(general)                   // decorator — execution metadata on a declaration
gather() { "explore the codebase" }

@retry(3) @timeout(120)           // decorators stack; also before for each / while / loop
validate() { "typecheck, lint, test" }

[first, ...rest] = queue          // rest in patterns
{ id, ...extras } = record        // rest in object patterns
parent = issue?.parent?.title ?? "none"   // optional chaining + nullish default
config = { ...defaults, theme: "dark" }   // spread in literals
run(...steps)                     // spread in calls
open = issues |> filter(_.state == "open") |> map(_.title)   // _ = piped value
```

- **`::`** addresses a capability namespace (tools, MCP servers, agents); `.`
  remains structural member access on values. Both chain: `mcp::linear.getIssue(id)`.
- **Named arguments** are call-site labels, legal only inside argument lists.
- **Guards** (`->`) run the consequence iff the condition holds — statement
  position only, no chains, no `else` (reach for `if` for anything richer). Match
  arms keep `=>`; the `->` vs `=>` split is intentional.
- **Decorators** attach execution metadata; they stack and precede interface /
  function (keyword and bare) declarations and `for each` / `while` / `loop`.
  Vocabulary: `@agent(name)`, `@retry(n)`, `@timeout(seconds)`, `@parallel`,
  `@memo`, `@blocking(user)`. Unknown decorators are legal and inferred.
- **`?.`** short-circuits on null/absent; **`??`** supplies a default (same
  precedence tier as `||`).
- **`...`** spreads in literals and calls, and gathers as rest in array/object
  patterns.
- **`_`** is the piped value inside a pipe stage — it parses as a plain
  identifier everywhere, but is only meaningful in a pipe; the LSP flags misuse.

**ASI gotcha.** As in JavaScript, a statement starting with `[` (or `(`) right
after an expression statement is parsed as indexing/calling the previous line
across the newline. Terminate the prior statement with `;`, or put the
bracket-leading statement first.

## Program skeleton

```sudo
// One-line purpose comment
// SudoLang v2.2

# ProgramName

"Role description: who the LLM acts as, expertise, tone."

interface SharedShape { field }

stepOne() { "What this step accomplishes." }
stepTwo() { result = stepOne() |> refine }

ProgramName {
  State { ready = false }
  Constraints { "Global rules." }
  /go - run the pipeline
}

stepOne() |> stepTwo    // or: /go
```

## v2.0 → v2.1 strict diffs

| v2.0 allowed | v2.1 requires |
|---|---|
| Bare prose anywhere | String literals / comments / `#` headings only |
| Multi-word identifiers (`Start game`) | Single-word (`StartGame`) |
| Bare prose constraints | `"String literal"` constraints |
| Inline markdown (bold, lists, tables) | Not parsed — prose strings or host-markdown fences |
| Markdown headings parsed | `#` heading markers, outline-only |
