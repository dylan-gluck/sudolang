# SudoLang v2.2 cheatsheet

A quick reference for the SudoLang pseudolanguage. Pin it next to your editor. Version 2.2 is a strict superset of v2.1. The [SudoLang 2.2](#sudolang-22) section lists the new syntax.

---

## Comments

```sudo
// line comment
/* block comment */
```

## Variables and assignment

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
"""
long prose block, no interpolation
"""
```

## Numbers and math

```
+  -  *  /  %  ^           arithmetic (^ = exponent)
union  intersection        set operations
1..5                       range (inclusive)
1,000,000   $100,000       comma groups and money
```

## Comparison and logic

```
==  !=  <  >  <=  >=       comparison
&&  ||  xor  !             logic
??                         nullish default
```

## Conditionals

```sudo
status = if (age >= 18) "adult" else "minor"

if (cond) { a() } else { b() }
```

## Pattern matching

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
function add(x, y) { return x + y }    // full definition
chunk() { "Chunk the text." }          // bare-name + body
f = x => x + 1                         // arrow function
function draft(role, budget?) { }      // optional parameter
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

Blocks nest:

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

## Requirements and warnings

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

## Inferred functions

These work without a definition. The AI infers them:

```
ask  explain  log  list  emit  run  transpile(lang)
convert  wrap  escape  concat  sort  filter  map
join  split  trim  reverse  unique  flatten  merge
```

---

## SudoLang 2.2

New syntax over v2.1. Version 2.2 is a strict superset, so every v2.1 program still parses:

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

The documented decorators are `@agent(name)`, `@retry(n)`, `@timeout(seconds)`, `@parallel`, `@memo`, and `@blocking(user)`. An unknown decorator is legal, and the interpreter infers it.

**ASI gotcha.** Put a statement that starts with `[` or `(` right after an expression statement. The parser then reads an index or a call across the newline. End the previous line with `;`, or put the `[`-leading statement first.

### Token-economy idioms

Prefer the 2.2 form. It states the same intent in fewer tokens:

| Instead of                                 | Write                       |
| ------------------------------------------ | --------------------------- |
| `if (gaps) askUser(gaps)`                  | `gaps -> askUser(gaps)`     |
| `f({ branch: b, base: d })`                | `f(branch = b, base = d)`   |
| `if (exists(x.p)) x.p else "none"`         | `x?.p ?? "none"`            |
| `filter(x => x.state == "open")`           | `filter(_.state == "open")` |
| `"Run gather as a general subagent."`      | `@agent(general)`           |
| `"Use the linear MCP to fetch the issue."` | `mcp::linear.getIssue(id)`  |

---

## Program skeleton

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

## Operator precedence, high to low

```
::               capability namespace
.  ?.  []        member / optional member / index
:                modifier list
()               call
!  - (unary)     prefix
^                exponent
*  /  %          multiplicative
+  -             additive
..               range
union  intersection
<  >  <=  >=     comparison
==  !=           equality
&&               AND
||  ??  xor      OR / nullish default / XOR
=  +=  -=  *=    assignment
=>               arrow
|>               pipe
```

The `->` guard arrow is not an expression operator. It joins a condition to a consequence in statement position.

---

## Strict rules

| Rule                         | Example                               |
| ---------------------------- | ------------------------------------- |
| Single-word identifiers      | `StartGame`, not `Start Game`         |
| Prose as string literals     | `"Avoid X."`, not bare `Avoid X.`     |
| `interface` keyword optional | `Player { }` is `interface Player { }` |
| Semicolons optional          | They end a modifier list: `fn():mod=val;` |

---

## Style cheat codes

- Favor natural language over code.
- Infer a function body. Declare the name to document it.
- Keep a constraint declarative. State *what*, not *how*.
- Use `interface`. Never use `class`.
- Prefer composition over inheritance.
- Stay short.

---

_SudoLang v2.2 · [User guide](user-guide.md) · [2.2 proposal](proposals/sudolang-2.2.md) · [Grammar](grammar-specification.md)_
