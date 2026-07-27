# SudoLang v2.2 syntax reference

Condensed from `docs/cheatsheet.md`, `docs/user-guide.md`, and `tree-sitter-sudolang/grammar.js`. The grammar is the authority. Everything here parses clean. Version 2.2 is a strict superset of v2.1, so the v2.1 constructs below are unchanged. The [SudoLang 2.2 additions](#sudolang-22-additions) section holds the new syntax.

## Comments and prose

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

## Strings and interpolation

```sudo
"Hello, $name"           // identifier interpolation
"Total: ${a + b}"        // expression interpolation
"Literal \$42"           // escaped dollar
`backtick template ${x}` // equivalent semantics
```

## Operators, high to low precedence

```
::                        capability namespace (2.2)
.  ?.  []                 member / optional member / index
:mod=val;                 modifier list (binds to the expression)
()                        call
!  - (unary)              prefix
^                         exponent (right-assoc)
*  /  %                   multiplicative
+  -                      additive
..                        range (1..10 inclusive)
union  intersection       set ops
<  >  <=  >=              comparison
==  !=                    equality
&&                        AND
||  ??  xor               OR / nullish default (2.2) / XOR
=  +=  -=  *=  /=         assignment (right-assoc)
=>                        arrow (lambda, match arm)
|>                        pipe (lowest)
```

The `->` guard arrow is not an expression operator. It joins a condition to a consequence in statement position. The deprecated `cap` and `cup` aliases are not in the grammar.

## Variables, destructuring, assignment

```sudo
[a, b] = [1, 2]
{ name, age } = user
x = 42
x += 1
obj.prop = 5
arr[0] = "first"
```

Lead with the destructuring targets, so the `[`-line does not read as an index on a previous expression. See the ASI gotcha under [SudoLang 2.2 additions](#sudolang-22-additions).

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
f = x => x + 1                           // arrow function, expression body
g = x => { log(x) }                      // arrow function, block body
withDefaults(a = 1, b?) { log(a, b) }    // defaults and optional params
pick({ name, age }) { name }             // destructuring params
```

- The bare-name form needs a block. That is what separates it from a call. `chunk()` alone is a call. `chunk() { ... }` is a declaration.
- `return` and `throw` are statements: `throw "issue not found"`.

## Modifiers

A modifier tunes an expression. It follows a colon, and a semicolon ends the list.

```sudo
explain(topic):length=short, detail=simple;
log(results):format="json"
```

A modifier value is an identifier, a string, a number, or a boolean. Quote a phrase: write `format="json output"`, not `format=json output`.

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

Prefer composition over inheritance. `class`, `extends`, and `new` are lint-prohibited. A `new Task { }` line parses, and it parses wrong. It becomes a bare `new` expression plus an interface declaration.

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

Error handling is constraint-first. The grammar accepts `try` and `catch` for tolerance, and it binds the catch variable without parentheses (`catch e { }`). Version 2.2 defers `try` and `catch` as language. Prefer a declarative failure policy such as "On unrecoverable failure: stop and report, never proceed", a `require` gate on each step, and `@retry(n)` for the recoverable half.

Only the four `constraint` spellings are keywords: `constraint`, `Constraint`, `constraints`, and `Constraints`. `Requirements`, `Options`, `Lint`, and `State` are not keywords. They parse as interface declarations.

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

An undeclared function is legal, and the interpreter infers it from the name and the context. The common inferred library is:

```
ask log list emit run explain transpile(lang) convert wrap escape
concat sort sortBy filter map find groupBy join split trim reverse
unique flatten merge pick pluck zip take takeLast skip slice count min max
```

## SudoLang 2.2 additions

Version 2.2 is a strict superset of v2.1, so everything above still parses. The new syntax is:

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

- **`::`** addresses a capability namespace, such as a tool, an MCP server, or an agent. The `.` operator stays structural member access on a value. Both chain: `mcp::linear.getIssue(id)`.
- **Named arguments** are call-site labels. They are legal only inside an argument list.
- **Guards** (`->`) run the consequence only when the condition holds. They work in statement position only, with no chains and no `else`. For anything richer, use `if`. A match arm keeps `=>`, and the split between `->` and `=>` is deliberate.
- **Decorators** attach execution metadata. They stack, and they go before an interface declaration, a function declaration in either form, and a `for each`, `while`, or `loop` statement. The documented vocabulary is `@agent(name)`, `@retry(n)`, `@timeout(seconds)`, `@parallel`, `@memo`, and `@blocking(user)`. An unknown decorator is legal, and the interpreter infers it.
- **`?.`** short-circuits on a null or absent value. **`??`** supplies a default, at the same precedence tier as `||`.
- **`...`** spreads in a literal and a call, and it gathers as rest in an array or object pattern.
- **`_`** is the piped value inside a pipe stage. It parses as a plain identifier everywhere, and it means something only in a pipe. The LSP flags misuse.

**ASI gotcha.** Put a statement that starts with `[` or `(` right after an expression statement. The parser then reads an index or a call across the newline. End the previous statement with `;`, or put the bracket-leading statement first.

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

## v2.0 to v2.1 strict differences

| v2.0 allowed                          | v2.1 requires                                          |
| ------------------------------------- | ------------------------------------------------------ |
| Bare prose anywhere                   | String literals, comments, or `#` headings only        |
| Multi-word identifiers (`Start game`) | One word (`StartGame`)                                 |
| Bare prose constraints                | `"String literal"` constraints                         |
| Inline markdown (bold, lists, tables) | Not parsed. Use a prose string or a host markdown fence |
| Parsed markdown headings              | `#` heading markers, for the outline only              |
