# SudoLang v2.2 user guide

SudoLang is a pseudolanguage for instructing large language models. It has no compiler and no runtime. The model reads the program and acts as the interpreter. The language mixes natural language with a small set of programming constructs: interfaces, constraints, functions, pattern matching, and pipes.

This guide covers SudoLang v2.2. Version 2.2 is a strict superset of v2.1, so every valid v2.1 program stays valid. Section 20 collects the v2.2 additions.

A model does not need this specification to read a SudoLang program. The specification exists so that tools can read one.

---

## Table of contents

1. [Getting started](#1-getting-started)
2. [File structure](#2-file-structure)
3. [Comments](#3-comments)
4. [Variables and assignments](#4-variables-and-assignments)
5. [Strings and interpolation](#5-strings-and-interpolation)
6. [Numbers and math](#6-numbers-and-math)
7. [Conditionals](#7-conditionals)
8. [Pattern matching](#8-pattern-matching)
9. [Functions](#9-functions)
10. [Interfaces](#10-interfaces)
11. [Constraints, requirements, and warnings](#11-constraints-requirements-and-warnings)
12. [Commands](#12-commands)
13. [Loops](#13-loops)
14. [Pipes and composition](#14-pipes-and-composition)
15. [Modifiers](#15-modifiers)
16. [Destructuring](#16-destructuring)
17. [Ranges](#17-ranges)
18. [Referential omnipotence](#18-referential-omnipotence)
19. [Style guide](#19-style-guide)
20. [SudoLang 2.2 syntax](#20-sudolang-22-syntax)
21. [v2.1 changes from v2.0](#21-v21-changes-from-v20)
22. [Full example: AI RPG](#22-full-example-ai-rpg)

---

## 1. Getting started

### What SudoLang is for

- **AI-first programs**: chatbots, study tools, game engines, and productivity agents.
- **AI-driven development**: use `transpile()` to generate production code in any language.
- **Structured prompting**: state a complex instruction in 20 to 30 percent fewer tokens than prose.
- **Specification documents**: declare system architecture, constraints, and behavior.

### Your first program

```sudo
// greeting.sudo

Greeter {
  name: "World"
  /greet - say hello to the user by name
}

/greet
```

Paste this program into any LLM chat. The model answers with something like *"Hello, World!"*, and it reads `/greet` as a command to run.

### File types and the authoring convention

SudoLang has two authoring shapes. Markdown with fences is the preferred default.

| Extension  | Use                                                                                                                    |
| ---------- | ---------------------------------------------------------------------------------------------------------------------- |
| `.md`      | **Preferred.** Markdown prose with SudoLang in ` ```sudo ` fenced code blocks. The prose explains, and the fences carry the program. |
| `.sudo.md` | The same shape, with an extension that marks the file as SudoLang content.                                             |
| `.sudo`    | Pure SudoLang, for a program that needs no prose.                                                                      |

The tools extract and check each ` ```sudo ` fence in a `.md` or `.sudo.md` file. This covers the LSP, the `check.sh` gate, and CI. A fenced program gets the same checks as a pure `.sudo` file. Use whichever shape fits. Use markdown when the prose earns its place next to the code.

---

## 2. File structure

Most SudoLang programs follow this pattern:

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

A `# Heading` marker drives outline navigation. Use it at the top level and inside a block.

---

## 3. Comments

```sudo
// Line comment — extends to end of line

/* Block comment —
   can span multiple lines */
```

**The AI does not ignore comments.** In SudoLang, the documentation is code. Use a comment to guide behavior, to state intent, and to supply context.

---

## 4. Variables and assignments

```sudo
counter = 0        // Assign
counter += 1       // Increment
total -= n         // Decrement
price *= n         // Multiply-assign
share /= n         // Divide-assign
```

The assignment operators are `=`, `+=`, `-=`, `*=`, and `/=`.

An assignment target is an identifier, a member expression (`obj.prop`), an index expression (`arr[0]`), or a destructuring pattern.

---

## 5. Strings and interpolation

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

Both string forms accept `$identifier` and `${expression}` interpolation. To write a literal dollar sign, escape it with `\$`.

---

## 6. Numbers and math

```sudo
area = base * height / 2
exp = 2 ^ 8           // Exponent
remainder = total % chunkSize
```

### Operators by precedence, highest to lowest

|  Precedence | Operators                | Description                     |
| :---------: | ------------------------ | ------------------------------- |
|     12      | `.` `()` `[]`            | Member access, call, index      |
|     11      | `!` `-` (unary)          | Prefix NOT, negation            |
|     10      | `^`                      | Exponent (right-associative)    |
|      9      | `*` `/` `%`              | Multiply, divide, remainder     |
|      8      | `+` `-`                  | Add, subtract                   |
|      7      | `..`                     | Range                           |
|      7      | `union` `intersection`   | Set operations                  |
|      6      | `<` `>` `<=` `>=`        | Comparison                      |
|      5      | `==` `!=`                | Equality                        |
|      4      | `&&`                     | Logical AND                     |
|      3      | `\|\|` `xor` `??`        | Logical OR, XOR, nullish default |
|      2      | `=` `+=` `-=` `*=` `/=`  | Assignment (right-associative)  |
|      1      | `\|>`                    | Pipe (lowest)                   |

> **Note:** SudoLang deprecates the `cap` and `cup` operators. Use `union` and `intersection`.

---

## 7. Conditionals

A conditional expression produces a value, so you can assign it:

```sudo
status = if (age >= 18) "adult" else "minor"
access = if (age >= 18 && isMember) "granted" else "denied"
```

The same form takes blocks:

```sudo
if (score > 100) {
  awardBonus()
} else {
  encouragePlayer()
}
```

---

## 8. Pattern matching

Use `match` for semantic pattern matching with destructuring:

```sudo
result = match (value) {
  case { type: "circle", radius } => "Circle with radius: $radius",
  case { type: "rectangle", width, height } => "Rectangle ${width}x${height}",
  case { type: "triangle", base, height } => "Triangle base $base height $height",
  default => "Unknown shape",
}
```

A pattern matches an object shape, an array shape, a literal value, or an identifier. The AI also does **semantic pattern matching**, where it infers the condition:

```sudo
match (post) {
  case "contains harmful content" => explain(contentPolicy),
  case "is spam" => flag(),
  default => publish(),
}
```

---

## 9. Functions

SudoLang functions run from a fully inferred signature to a complete definition.

### Inferred functions, signature only

```sudo
fn foo                     // Keyword + name, no parens
function bar               // Alternate keyword
function baz(x, y)         // With parameters
```

The AI **infers the function body** from the name, the parameters, and the context. This is a core SudoLang feature. You do not spell out obvious behavior.

### Functions with bodies

```sudo
function withBody(x, y) {
  return x + y
}
```

### Bare-name functions, no keyword

```sudo
chunk() {
  "Chunk sections of the text and create an index."
}
```

When a function has a block body, the `fn` or `function` keyword is optional.

### Arrow functions

```sudo
f = x => x + 1
g = (a, b) => a + b
```

### Natural language function bodies

A function body holds prose constraints and instructions, and the AI reads them:

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

An interface declares structure and behavior. It is the main organizational unit in SudoLang. The `interface` keyword is **optional**.

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

A property takes one of two forms:

```sudo
Account {
  name = "default"     // Assignment form — sets a default value
  role: "admin"        // Declaration form — colon-separated key:value
  health               // Bare property — type and value inferred
}
```

### Conventions

- **PascalCase** for an interface or type name: `Player`, `StoryWorld`, `ActionObject`.
- **camelCase** for a property or function: `minimumSalary`, `greet()`.
- Single-word identifiers: `StartGame`, not `Start Game`.

---

## 11. Constraints, requirements, and warnings

A constraint declares a rule that the AI keeps to for the whole run. Constraints carry most of the language.

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

### Requirements, which throw on a violation

A requirement states a hard rule. A violation throws an error:

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

### Warnings, which are soft rules

A warning works like a requirement, but it does not throw:

```sudo
warn "name should be defined."
warn "given should be a string when defined."
```

### Best practices

- **Be declarative.** State *what* you want, not *how* to do it.
- **Keep a constraint short.** A few clear rules beat a wall of text.
- **Use `require` for a hard rule**, such as input validation or an invariant.
- **Use `warn` for soft guidance**, such as a style hint.
- **Use a `Constraints {}` block** for a behavioral rule that the AI follows without comment.

---

## 12. Commands

A command declares a chat interface for your program. Command names start with a slash.

### Declaring commands

```sudo
StudyBot {
  /l | learn [topic] - set the topic and provide a brief introduction
  /v | vocab - list essential terms with definitions
  /f | flashcards - play the flashcard game
  /help - explain how to use StudyBot
}
```

The syntax is `/name | alias [arguments] - description`.

- The pipe `|` separates the full command from a short alias.
- Square brackets `[args]` mark the arguments.
- The dash `-` comes before the description.

### Invoking commands

```sudo
/welcome       // At top level — kicks off the program
/help          // User types this in the chat
```

### Common inferred commands

These work without a definition, because the AI infers them:

```
ask       explain   run       log       convert   emit
wrap      escape    continue  instruct  list      revise
transpile(targetLang, source)
```

---

## 13. Loops

### For-each

```sudo
for each number in numbers, log(number)
```

Commas separate the variable, the source, and the action.

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

## 14. Pipes and composition

The pipe operator `|>` passes the value on the left as the first argument to the expression on the right:

```sudo
f = x => x + 1
g = x => x * 2
h = f |> g
h(20)  // 42
```

Chain pipes to compose several steps:

```sudo
results = extrapolateQuery(text) |> forEach(search) |> surroundingContext()
```

```sudo
options = listRandomOptions(7)
  |> scoreByEngagement
  |> takeTop(3)
```

```sudo
Dux |> transpile(JavaScript)
```

---

## 15. Modifiers

A modifier tunes the response of a call. Modifiers follow the call, after a colon:

```sudo
explain(historyOfFrance):length=short, detail=simple;
```

```sudo
log(formatResults()):format="Markdown, no outer code block wrapper"
```

```sudo
welcome():length=1, format=line
```

The syntax is `functionCall():modifier=value, modifier=value;`. The semicolon ends the modifier list.

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

Destructuring also works in a function parameter and in a match pattern.

---

## 17. Ranges

The range operator `..` builds an inclusive range:

```sudo
1..3    // 1, 2, 3
1..10   // 1 through 10
```

Use a range in options, in loops, and anywhere a sequence fits:

```sudo
Options {
  depth: 1..10
  verbosity: 1..5
}
```

---

## 18. Referential omnipotence

You do **not** define every function. The AI infers the behavior from the context:

```sudo
function greet(name);

greet("Echo")  // "Hello, Echo"
```

This reaches as far as the model does:

- **Inference**: read the intent and produce a fitting response.
- **Natural language processing**: parse and write human text.
- **Code generation**: produce working code in any language.
- **Knowledge access**: use the training data of the model.
- **Problem solving**: reason through a multi-step problem.

---

## 19. Style guide

1. **Favor natural language.** Write prose where prose is clearer than code.
2. **Lean into inference.** Infer a function body when the name says enough. Declare a named function without a body to record that it exists.
3. **Minimize code.** Keep structural code to flow control and composition.
4. **Stay short and readable.** This applies to the prose and to the code.
5. **Favor composition over inheritance.** Use interfaces and factories, not `class` or `extends`.
6. **Use constraints declaratively.** State *what*, not *how*.

### Linting rules

- A bug, a spelling error, or a grammar error: throw and fix it.
- A code smell: warn and explain it.
- `new`, `extends`, and `class`: prohibit them and suggest an alternative.
- Prefer inference and natural language, unless the code is shorter.

---

## 20. SudoLang 2.2 syntax

Version 2.2 is a **strict superset** of v2.1. Every valid v2.1 program is a valid 2.2 program. The additions close the gaps that fluent authors kept reaching for: capability calls, call-site labels, guards, and execution metadata. Version 2.2 also documents several features that the grammar already accepted.

### Qualified capability names (`::`)

The `::` operator addresses a **capability namespace**, such as a tool, an MCP server, an agent, or an external system. The `.` operator stays structural member access on a value.

```sudo
issue = mcp::linear.getIssue(ISSUE_ID)
git::worktree.add({ branch: issue.branchName })
summary = fs::read(path) |> ai::summarize
```

The split tells the interpreter which of two things to do. For `mcp::linear`, `git::`, and `fs::`, it resolves the name against the environment. For `.parent` and `.title`, it reads the name off a value. In an agent context this maps onto tool namespaces, which makes SudoLang an orchestration surface without a module system. The `::` operator joins plain identifiers, and `.` does member access on the result.

### Named arguments

Label an argument at the call site:

```sudo
git::worktree.add(branch = issue.branchName, base = "origin/development")
```

A call-site label is documentation that binds. It removes argument-order ambiguity, which matters when the interpreter infers the body. A named argument is legal only inside an argument list.

### Guards (`->`)

A guard runs its consequence only when the condition holds. Read `->` as "then":

```sudo
!issue -> throw "ISSUE_ID did not resolve"
gaps -> askUser(gaps)
count > MAX -> warn "truncating to $MAX"
```

The form `condition -> statement` works in statement position only. It does not chain and it has no `else`. The consequence is a statement, a block, a `require`, or a `warn`. For anything richer, use `if`.

A match arm keeps `=>`, which means "map to value". A guard uses `->`, which means "do this consequence". The split is deliberate.

### Decorators

A decorator attaches execution metadata to a declaration. It states who runs the unit, how the interpreter handles a failure, and whether the unit runs concurrently.

```sudo
@agent(general)
gatherContext() { "Explore the codebase; return a Task." }

@retry(3) @timeout(120)
validate() { "Typecheck, lint, test; fix until green." }

@parallel
for each dimension in reviews { review(dimension) }
```

Decorators stack. They answer "how should this run", so the body stays about "what it does". A decorator goes before an interface declaration, before a function declaration in either form, or before a `for each`, `while`, or `loop` statement.

| Decorator           | Meaning                             |
| ------------------- | ----------------------------------- |
| `@agent(name)`      | Run as the named subagent           |
| `@retry(n)`         | Retry up to n times on failure      |
| `@timeout(seconds)` | Bound the run time                  |
| `@parallel`         | Run iterations or branches together |
| `@memo`             | Memoize the result                  |
| `@blocking(user)`   | Pause for user interaction          |

An unknown decorator is legal, and the interpreter infers it. The table above lists the documented vocabulary, not every legal name.

### Optional chaining and nullish default (`?.`, `??`)

As in JavaScript, `?.` short-circuits on a null or absent value, and `??` supplies a default:

```sudo
parent = issue?.parent?.title ?? "none"
```

The `??` operator sits at the same precedence tier as `||`. Together the two operators collapse the most common data-shape hazard in an LLM pipeline, an absent field, into one line.

### Spread and rest (`...`)

Use spread in a literal or a call, and rest in a pattern, the same way JavaScript does:

```sudo
[first, ...rest] = queue
{ id, ...extras } = record
config = { ...defaults, theme: "dark" }
run(...steps)
```

Spread merges or collects a sequence. Rest captures everything else when you destructure.

### Pipe placeholder (`_`)

Inside a pipe stage, `_` is the piped value. It drops the lambda head when exactly one subject flows through:

```sudo
open = issues |> filter(_.state == "open") |> map(_.title) |> take(5)
```

The placeholder means something only inside a pipe stage. The LSP flags `_` anywhere else.

### Formalized features

The grammar already accepted these forms. Version 2.2 promotes them to documented language.

- **Triple-quoted prose blocks**: `"""..."""` holds long prose or an example across lines. It has no interpolation, and the formatter leaves the body alone.
- **Resource sigils**: `@scope/path` names an external resource. A decorator (`@name`) builds on the same `@` sigil.
- **Comma-grouped and money numerics**: `1,000,000` and `$100,000` parse as numbers.
- **Optional parameters**: `arg?` marks a parameter optional, next to a default (`arg = value`).
- **Trailing commas**: legal in an array, an object, an argument list, and a parameter list.
- **`throw` and `return` statements**: `throw "issue not found"` and `return value`.

### Gotcha: a statement that starts with `[`

SudoLang has the same automatic-semicolon-insertion hazard as JavaScript. Put a statement that starts with `[` or `(` right after an expression statement, and the parser reads an index or a call across the newline. The next block is wrong on purpose, so it is not a `sudo` fence:

```
result = compute()
[first, ...rest] = queue     // parsed as compute()[first, ...] — wrong
```

End the previous statement with `;`. You can also reorder, so that the `[`-leading statement does not follow a bare expression:

```sudo
result = compute();
[first, ...rest] = queue
```

---

## 21. v2.1 changes from v2.0

Version 2.1 is the v2.0 specification, made **strict** for parser tooling. To upgrade a v2.0 program, apply these changes:

| Change                    | v2.0                    | v2.1                                             |
| ------------------------- | ----------------------- | ------------------------------------------------ |
| **Bare prose in blocks**  | Legal anywhere          | Must be a string literal or a structured item    |
| **Multi-word identifiers**| `Start game {`          | `StartGame {` (single-word, camelCase, PascalCase) |
| **Prose constraints**     | Bare text               | String literals: `"Avoid mentioning these."`     |
| **Markdown**              | The grammar parses it   | The host grammar injects it instead              |
| **Section headings**      | Full Markdown headings  | `# Heading` markers, for outline navigation only |

The meaning does not change. Version 2.1 gives the structure a shape that tools can parse, such as tree-sitter, the LSP, and an editor extension. It keeps everything that made v2.0 expressive.

---

## 22. Full example: AI RPG

This program uses interfaces, constraints, commands, pipes, loops, and natural language bodies together:

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

  add(item, quantity = 1) {
    item.weight > player.strength * 2 -> throw "the item is too heavy to lift"
    items = { ...items, [item.name]: { ...item, quantity } }
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

Quests {
  activeQuests

  next() {
    return activeQuests |> filter(_.available) |> sortBy(_.priority) |> take(1)
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

## Further reading

- [SudoLang 2.2 proposal](proposals/sudolang-2.2.md): the design record for the v2.2 additions.
- [Grammar specification](grammar-specification.md): the tree-sitter grammar in detail.
- [Cheatsheet](cheatsheet.md): the one-page reference.
- [Examples](../tree-sitter-sudolang/examples/): runnable `.sudo` and `.sudo.md` programs.
- [SudoLang: A Powerful Pseudocode Programming Language for LLMs](https://medium.com/javascript-scene/sudolang-a-powerful-pseudocode-programming-language-for-llms-d64d42aa719b): the article this workspace started from.
