# SudoLang v2.2 — Cheatsheet

Quick reference for the SudoLang pseudolanguage. Pin this next to your editor. v2.2 is a strict superset of v2.1 — see [SudoLang 2.2](#sudolang-22) for the new syntax.

---

## Comments

```sudo
// line comment
/* block comment */
```

## Variables & Assignment

```sudo
x = 42                     // assign
x += 1                     // also: -=  *=  /=
```

## Strings

```sudo
"Hello, $name"             // interpolation
"Total: ${a + b}"          // expression interpolation
"Price: \$42"              // escaped dollar sign
`template ${string}`       // backtick template strings
```

## Numbers & Math

```sudo
+  -  *  /  %  ^           // arithmetic (^ = exponent)
union  intersection         // set operations
1..5                        // range (inclusive)
```

## Comparison & Logic

```sudo
==  !=  <  >  <=  >=       // comparison
&&  ||  xor  !             // logic
```

## Conditionals

```sudo
status = if (age >= 18) "adult" else "minor"

if (cond) { a() } else { b() }
```

## Pattern Matching

```sudo
result = match (value) {
  case { type: "circle", radius } => "r=$radius",
  case 42                         => "the answer",
  default                         => "unknown",
}
```

## Functions

```sudo
fn inferred                            // inferred body
function greet(name)                   // signature only
function add(x, y) { return x + y }   // full definition
chunk() { "Chunk the text." }          // bare-name + body
f = x => x + 1                        // arrow function
```

## Interfaces

```sudo
Player {                    // interface keyword is optional
  name: "Hero"              // property declaration
  score = 0                 // property with default
  health                    // inferred property

  attack(target) {
    "Calculate and apply damage."
  }
}
```

Nesting is supported:

```sudo
App {
  State {
    Config { theme: "dark" }
  }
}
```

## Constraints

```sudo
Constraints {                                    // block
  "Rule one."
  "Rule two."
}

constraint MinSalary { emit(violation) }         // named
constraint: "Points awarded on goal."            // inline
```

## Requirements & Warnings

```sudo
require "users must be over 13"        // throws on violation
warn "name should be defined"          // soft guidance
```

## Commands

```sudo
/help - show help                      // declaration
/l | learn [topic] - learn a topic     // with alias + args
/start                                 // invocation
```

## Loops

```sudo
for each item in items, process(item)  // for-each
while (running) { tick() }             // while
loop { poll() }                        // infinite
```

## Pipes

```sudo
data |> transform |> format |> log

f = x => x + 1
g = x => x * 2
h = f |> g
h(20)  // 42
```

## Modifiers

```sudo
explain(topic):length=short, detail=simple;
log(results):format="json"
```

## Destructuring

```sudo
[a, b] = [1, 2]
{ name, age } = user
```

## Ranges

```sudo
1..10                       // inclusive range: 1,2,...,10
```

## Inferred Functions

These work without definition — the AI infers them:

```
ask  explain  log  list  emit  run  transpile(lang)
convert  wrap  escape  concat  sort  filter  map
join  split  trim  reverse  unique  flatten  merge
```

---

## SudoLang 2.2

New syntax over v2.1 (strict superset — every v2.1 program still parses):

```sudo
[first, ...rest] = queue                  // rest in patterns
issue = mcp::linear.getIssue(id)          // :: capability namespace (vs . member access)
f(branch = x, base = y)                   // named arguments at the call site
!issue -> throw "not found"               // guard: condition -> statement
parent = issue?.parent?.title ?? "none"   // optional chaining + nullish default
config = { ...defaults, theme: "dark" }   // spread in literals / calls
open = issues |> filter(_.state == "open") |> map(_.title)   // _ = piped value
@retry(3) @timeout(120)                   // decorators stack; precede fn / interface / loop
gather() { "explore the codebase" }
```

Decorator vocabulary: `@agent(name)` `@retry(n)` `@timeout(seconds)` `@parallel`
`@memo` `@blocking(user)`. Unknown decorators are legal and inferred.

**ASI gotcha:** a statement that starts with `[` or `(` right after an expression
statement is parsed as indexing / call across the newline. End the previous line
with `;` or put the `[`-leading statement first.

### Token-economy idioms

Prefer the 2.2 form — same intent, fewer tokens:

| Instead of                                 | Write                       |
| ------------------------------------------ | --------------------------- |
| `if (gaps) askUser(gaps)`                  | `gaps -> askUser(gaps)`     |
| `f({ branch: b, base: d })`                | `f(branch = b, base = d)`   |
| `if (exists(x.p)) x.p else "none"`         | `x?.p ?? "none"`            |
| `filter(x => x.state == "open")`           | `filter(_.state == "open")` |
| `"Run gather as a general subagent."`      | `@agent(general)`           |
| `"Use the linear MCP to fetch the issue."` | `mcp::linear.getIssue(id)`  |

---

## Program Skeleton

```sudo
// preamble
# MyApp
"Role description and expertise."

// structure
MyApp {
  State { /* ... */ }
  Constraints { /* ... */ }

  /cmd - description
}

// initializer
/start
```

---

## Operator Precedence (high → low)

```
.  ()  []        member / call / index
!  - (unary)     prefix
^                exponent
*  /  %          multiplicative
+  -             additive
..               range
union ∩          set ops
<  >  <=  >=     comparison
==  !=           equality
&&               AND
||  xor  ??      OR / nullish default (2.2)
=  +=  -=  *=    assignment
|>               pipe
```

---

## v2.1 Strict Rules

| Rule                         | Example                               |
| ---------------------------- | ------------------------------------- |
| Single-word identifiers      | `StartGame`, not `Start Game`         |
| Prose as string literals     | `"Avoid X."`, not bare `Avoid X.`     |
| `interface` keyword optional | `Player { }` ≡ `interface Player { }` |
| Semicolons optional          | Terminate modifiers: `fn():mod=val;`  |

---

## Style Cheat Codes

- Favor natural language over code
- Infer function bodies — define names for documentation
- Keep constraints declarative: _what_, not _how_
- Use `interface`, never `class`
- Composition over inheritance
- Concise > verbose, always

---

_SudoLang v2.2 · [Full User Guide](user-guide.md) · [Spec](reference/sudolang.sudo.md) · [Grammar](grammar-specification.md)_
