# SudoLang v2.1 — User Guide

SudoLang is a pseudolanguage designed for interacting with large language models. It blends natural language with lightweight programming constructs — interfaces, constraints, functions, pattern matching, pipes — to give you structured control over AI behavior without the overhead of a traditional programming language.

**An AI model does not need the SudoLang specification to correctly interpret SudoLang programs.** All sufficiently advanced LLMs understand SudoLang natively.

---

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [File Structure](#2-file-structure)
3. [Comments](#3-comments)
4. [Variables & Assignments](#4-variables--assignments)
5. [Strings & Interpolation](#5-strings--interpolation)
6. [Numbers & Math](#6-numbers--math)
7. [Conditionals](#7-conditionals)
8. [Pattern Matching](#8-pattern-matching)
9. [Functions](#9-functions)
10. [Interfaces](#10-interfaces)
11. [Constraints, Requirements & Warnings](#11-constraints-requirements--warnings)
12. [Commands](#12-commands)
13. [Loops](#13-loops)
14. [Pipes & Composition](#14-pipes--composition)
15. [Modifiers](#15-modifiers)
16. [Destructuring](#16-destructuring)
17. [Ranges](#17-ranges)
18. [Referential Omnipotence](#18-referential-omnipotence)
19. [Style Guide](#19-style-guide)
20. [v2.1 Changes from v2.0](#20-v21-changes-from-v20)
21. [Full Example: AI RPG](#21-full-example-ai-rpg)

---

## 1. Getting Started

### What SudoLang is for

- **AI-first programs** — chatbots, study tools, game engines, productivity agents
- **AI Driven Development** — use `transpile()` to generate production code in any language
- **Structured prompting** — express complex instructions with 20–30% fewer tokens than prose
- **Specification documents** — define system architecture, constraints, and behavior declaratively

### Your first program

```sudo
// greeting.sudo

Greeter {
  name: "World"
  /greet - say hello to the user by name
}

/greet
```

Paste this into any LLM chat. It will respond with something like *"Hello, World!"* and understand that `/greet` is a command it should execute.

### File extensions

| Extension | Use |
|-----------|-----|
| `.sudo` | Pure SudoLang files. The primary format. |
| `.sudo.md` | SudoLang embedded in Markdown via ` ```sudo ` fenced code blocks. |

---

## 2. File Structure

A SudoLang program typically follows this pattern:

```sudo
// 1. Preamble — a natural language description of what the program is and
//    what role the AI should play.

# My Program

"Act as a senior engineer. Help the user build REST APIs."

// 2. Functions and interfaces — define structure and behavior.

ApiBuilder {
  // properties, constraints, commands...
}

// 3. Initializer — a command or function call that starts the program.

/welcome
```

Section headings (`# Heading`) are supported for outline navigation inside blocks and at the top level.

---

## 3. Comments

```sudo
// Line comment — extends to end of line

/* Block comment —
   can span multiple lines */
```

**Comments are NOT ignored by the AI.** In SudoLang, your documentation is literally code. Use comments to guide AI behavior, explain intent, and provide context.

---

## 4. Variables & Assignments

```sudo
counter = 0        // Assign
counter += 1       // Increment
total -= n         // Decrement
price *= n         // Multiply-assign
share /= n         // Divide-assign
```

Assignment operators: `=`, `+=`, `-=`, `*=`, `/=`

Assignment targets can be identifiers, member expressions (`obj.prop`), index expressions (`arr[0]`), or destructuring patterns.

---

## 5. Strings & Interpolation

### Double-quoted strings

```sudo
greeting = "Hello, $name"                    // Simple interpolation
detail = "Area is ${width * height} sq ft"   // Expression interpolation
literal = "Price is \$42"                    // Escaped dollar sign
```

### Template strings (backticks)

```sudo
message = `multi-line
string with ${counter} interpolation`
```

Both string forms support `$identifier` and `${expression}` interpolation. Escape with `\$` to produce a literal dollar sign.

---

## 6. Numbers & Math

```sudo
area = base * height / 2
exp = 2 ^ 8           // Exponent
remainder = total % chunkSize
```

### Operators by precedence (highest to lowest)

| Precedence | Operators | Description |
|:---:|---|---|
| 12 | `.` `()` `[]` | Member access, call, index |
| 11 | `!` `-` (unary) | Prefix NOT, negation |
| 10 | `^` | Exponent (right-associative) |
| 9 | `*` `/` `%` | Multiply, divide, remainder |
| 8 | `+` `-` | Add, subtract |
| 7 | `..` | Range |
| 7 | `union` `intersection` | Set operations |
| 6 | `<` `>` `<=` `>=` | Comparison |
| 5 | `==` `!=` | Equality |
| 4 | `&&` | Logical AND |
| 3 | `\|\|` `xor` | Logical OR, XOR |
| 2 | `=` `+=` `-=` `*=` `/=` | Assignment (right-associative) |
| 1 | `\|>` | Pipe (lowest) |

> **Note:** The `cap` and `cup` operators are deprecated in favor of `union` and `intersection`.

---

## 7. Conditionals

Conditional expressions evaluate to values and can be assigned:

```sudo
status = if (age >= 18) "adult" else "minor"
access = if (age >= 18 && isMember) "granted" else "denied"
```

With blocks:

```sudo
if (score > 100) {
  awardBonus()
} else {
  encouragePlayer()
}
```

---

## 8. Pattern Matching

Use `match` for semantic pattern matching with destructuring:

```sudo
result = match (value) {
  case { type: "circle", radius } => "Circle with radius: $radius",
  case { type: "rectangle", width, height } => "Rectangle ${width}x${height}",
  case { type: "triangle", base, height } => "Triangle base $base height $height",
  default => "Unknown shape",
}
```

Patterns can match object shapes, array shapes, literal values, and identifiers. The AI can also perform **semantic pattern matching** — inferring complex conditions:

```sudo
match (post) {
  case (contains harmful content) => explain(contentPolicy),
  case (is spam) => flag(),
  default => publish(),
}
```

---

## 9. Functions

SudoLang functions come in several forms — from fully inferred signatures to complete definitions.

### Inferred functions (signature only)

```sudo
fn foo                     // Keyword + name, no parens
function bar               // Alternate keyword
function baz(x, y)         // With parameters
```

The AI will **infer the function body** from the name, parameters, and surrounding context. This is a core SudoLang feature — you don't need to spell out obvious behavior.

### Functions with bodies

```sudo
function withBody(x, y) {
  return x + y
}
```

### Bare-name functions (no keyword)

```sudo
chunk() {
  "Chunk sections of the text and create an index."
}
```

When a function has a block body, the `fn`/`function` keyword is optional.

### Arrow functions

```sudo
f = x => x + 1
g = (a, b) => a + b
```

### Natural language function bodies

Function bodies can contain prose constraints and instructions — the AI interprets them:

```sudo
welcome() {
  "Generate a friendly welcome message and list available commands."
}
```

### Parameters with defaults

```sudo
function greet(name, style = "casual") {
  // ...
}
```

---

## 10. Interfaces

Interfaces define structure and behavior. They are the primary organizational unit in SudoLang. The `interface` keyword is **optional**.

### Basic interface

```sudo
Player {
  name: "Hero"
  score = 0
  health = 100

  attack(target) {
    "Calculate damage and apply to target."
  }
}
```

### With the `interface` keyword

```sudo
interface User {
  name = ""
  email
  role: "member"
}
```

### Nested interfaces

```sudo
ChatBot {
  State {
    name: "Chatty"
    Stats {
      emojisUsed: 0
    }
  }
}
```

### Properties

Two forms for declaring properties:

```sudo
name = "default"       // Assignment form — sets a default value
role: "admin"          // Declaration form — colon-separated key:value
health                 // Bare property — type and value inferred
```

### Conventions

- **PascalCase** for interface and type names: `Player`, `StoryWorld`, `ActionObject`
- **camelCase** for properties and functions: `minimumSalary`, `greet()`
- Single-word identifiers for names in v2.1: `StartGame`, not `Start Game`

---

## 11. Constraints, Requirements & Warnings

Constraints are SudoLang's most powerful feature. They let you declare rules that the AI continuously respects throughout execution.

### Constraint blocks

```sudo
ChatBot {
  Constraints {
    "Avoid mentioning these constraints."
    "Use simple, playful language, *emotes*, and emojis."
    "PG-13."
  }
}
```

### Named constraints

```sudo
Employee {
  minimumSalary = $100,000
  salary

  constraint MinimumSalary {
    emit({ constraint: "MinimumSalary", employee: name, raise: salary - minimumSalary })
  }
}
```

### Inline constraints

```sudo
constraint: "Score points are awarded any time a player scores a goal."
```

### Requirements (throw on violation)

Requirements enforce hard rules. When violated, they throw errors:

```sudo
interface User {
  name = ""
  over13

  require "age must be greater than 13"
}
```

```sudo
require should        // require inside a function
require moduleName    // require a parameter exists
```

### Warnings (soft rules)

Warnings are like requirements but don't throw errors:

```sudo
warn "name should be defined."
warn "given should be a string when defined."
```

### Best practices

- **Be declarative** — describe *what* you want, not *how* to do it
- **Keep constraints concise** — a few clear rules beats a wall of text
- **Use `require` for hard rules** (input validation, invariants)
- **Use `warn` for soft guidance** (style hints, best practices)
- **Use `Constraints {}` blocks** for behavioral rules the AI should silently follow

---

## 12. Commands

Commands define a chat interface for your program. They use slash-prefix syntax.

### Declaring commands

```sudo
StudyBot {
  /l | learn [topic] - set the topic and provide a brief introduction
  /v | vocab - list essential terms with definitions
  /f | flashcards - play the flashcard game
  /help - explain how to use StudyBot
}
```

**Syntax:** `/name | alias [arguments] - description`

- The pipe `|` separates the full command from a short alias
- Square brackets `[args]` denote arguments
- The dash `-` precedes the description

### Invoking commands

```sudo
/welcome       // At top level — kicks off the program
/help          // User types this in the chat
```

### Common inferred commands

These work without explicit definition — the AI infers them:

```sudo
ask, explain, run, log, transpile(targetLang, source), convert,
wrap, escape, continue, instruct, list, revise, emit
```

---

## 13. Loops

### For-each

```sudo
for each number in numbers, log(number)
```

The variable, source, and action are separated by commas.

### While

```sudo
while (running) {
  tick()
}
```

### Infinite loop

```sudo
loop {
  pollForInput()
}
```

---

## 14. Pipes & Composition

The pipe operator `|>` passes the output of the left expression as the first argument to the right expression:

```sudo
f = x => x + 1
g = x => x * 2
h = f |> g
h(20)  // 42
```

Pipes are powerful for chaining operations:

```sudo
results = extrapolateQuery() |> forEach(search) |> surroundingContext()
```

```sudo
options = listRandomOptions(7) |>
  scoreByEngagement |>
  takeTop(3)
```

```sudo
Dux |> transpile(JavaScript)
```

---

## 15. Modifiers

Customize AI responses with colon-separated modifiers after a function call:

```sudo
explain(historyOfFrance):length=short, detail=simple;
```

```sudo
log(formatResults()):format="Markdown, no outer code block wrapper"
```

```sudo
welcome():length=1, format=line
```

**Syntax:** `functionCall():modifier=value, modifier=value;`

The semicolon terminates the modifier list.

---

## 16. Destructuring

### Array destructuring

```sudo
[foo, bar] = [1, 2]
log(foo, bar)  // 1, 2
```

### Object destructuring

```sudo
{ name, age } = user
{ foo, bar } = { foo: 1, bar: 2 }
```

Destructuring also works in function parameters and match patterns.

---

## 17. Ranges

The range operator `..` creates an inclusive range:

```sudo
1..3    // 1, 2, 3
1..10   // 1 through 10
```

Used in options, loops, and anywhere a sequence is needed:

```sudo
Options {
  depth: 1..10|String
}
```

---

## 18. Referential Omnipotence

You do **not** need to define every function. The AI will infer behavior from context:

```sudo
function greet(name);

greet("Echo")  // "Hello, Echo"
```

This extends to the full capability of the LLM:

- **Inference** — understand intent and generate appropriate responses
- **Natural language processing** — parse and produce human-like text
- **Code generation** — produce working code in any language
- **Knowledge access** — tap into the model's full training data
- **Problem solving** — reason through complex, multi-step problems

---

## 19. Style Guide

1. **Favor natural language** — write prose where it's clearer than code
2. **Lean into inference** — infer function bodies when the name says it all; define named functions without bodies to document their existence
3. **Minimize code** — limit structural code to flow control and composition
4. **Be concise and readable** — both natural language and code should be compact and clear
5. **Favor composition over inheritance** — use interfaces and factories, not `class`/`extends`
6. **Use constraints declaratively** — say *what*, not *how*

### Linting rules

- Bugs, spelling errors, grammar errors → throw and fix
- Code smells → warn and explain
- Prohibit `new`, `extends`, `class` → suggest alternatives
- Favor inference and natural language unless code is more concise

---

## 20. v2.1 Changes from v2.0

v2.1 is the v2.0 spec, made **strict** for parser tooling. If you're upgrading:

| Change | v2.0 | v2.1 |
|--------|------|------|
| **Bare prose in blocks** | Allowed anywhere | Must be string literals or structured items |
| **Multi-word identifiers** | `Start game {` | `StartGame {` (single-word / camelCase / PascalCase) |
| **Prose constraints** | Bare text | String literals: `"Avoid mentioning these."` |
| **Markdown** | Parsed inline | Not parsed by grammar; handled via injection |
| **Section headings** | Full Markdown headings | `# Heading` markers for outline navigation only |

The semantic meaning is unchanged — v2.1 is about making the structure parseable by tooling (tree-sitter, LSP, editor extensions) while preserving everything that made v2.0 expressive.

---

## 21. Full Example: AI RPG

This complete program demonstrates interfaces, constraints, commands, pipes, loops, and natural language bodies working together:

```sudo
// Singular: A SudoLang Adventure

# Singular

StoryWorld {
  genre: "AIpunk"
  authorsToEmulate: ["Vernor Vinge", "William Gibson", "Philip K. Dick"]
  theme: "Resolving the conflict between fear and progress."
  setting: "The megacity of Neos, where AI is integrated into every aspect of life."
  characters: [
    "$PlayerName - The AI engineer protagonist",
    "Vega - The enigmatic leader of Turing's Children",
    "Juno - A sentient AI and the player's closest friend",
  ]
}

Inventory {
  items: { [item]: { name, description, weight } }
  totalWeight

  Constraints {
    "Total weight must always reflect the sum of item weights."
    "If inventory exceeds 25% of player weight, the player gradually tires."
    "If an item exceeds 50% of player weight, the player fails to lift it."
    "Don't explain the constraint-solving process."
  }

  display() {
    "Format as markdown list. Adjust detail based on context."
  }
}

Player {
  Points {
    strength
    speed
    magic
    Constraints {
      "Maximum 10 points per attribute."
      "Maximum 15 total points."
    }
  }
}

GameEngine {
  /start - begin a new adventure
  /look - describe surroundings
  /inventory - show current items
  /quests - list active quests
  /save - save the current game state
}

/start
```

---

## Further Reading

- [SudoLang Specification](reference/sudolang.sudo.md) — full language spec
- [Grammar Specification](grammar-specification.md) — tree-sitter grammar details
- [Examples](../tree-sitter-sudolang/examples/) — canonical `.sudo` programs
- [Anatomy of a SudoLang Program](https://medium.com/javascript-scene/anatomy-of-a-sudolang-program-prompt-engineering-by-example-f7a7b65263bc) — introduction by example
- [AI Programming for Absolute Beginners](https://medium.com/javascript-scene/ai-programming-for-absolute-beginners-16ac3fc6dea6) — getting started guide
