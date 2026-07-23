# SudoLang v2.1 — Syntax Reference

Condensed from `docs/cheatsheet.md`, `docs/user-guide.md`, and (authoritatively)
`tree-sitter-sudolang/grammar.js`. Everything here parses clean.

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
x = 42
x += 1
[a, b] = [1, 2]
{ name, age } = user
obj.prop = 5
arr[0] = "first"
```

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

## Program skeleton

```sudo
// One-line purpose comment
// SudoLang v2.1

# ProgramName

"Role description: who the LLM acts as, expertise, tone."

interface SharedShape { ... }

stepOne() { "What this step accomplishes." }
stepTwo() { result = stepOne() |> refine }

ProgramName {
  State { ... }
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
