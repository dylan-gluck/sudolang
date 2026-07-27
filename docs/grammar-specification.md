# tree-sitter-sudolang grammar specification

Status: current, and it matches the shipped grammar at version 0.3.2. The grammar targets the **SudoLang v2.2** dialect. Version 2.2 is a strict superset of v2.1, and v2.1 is the v2.0 specification made strict. Section [§4.10](#410-v22-additions) collects the v2.2 productions.

This document records what `grammar.js` does. When the two disagree, `grammar.js` wins, and this document is the bug.

## v2.1 changes against v2.0

The v2.0 specification admits prose almost anywhere. Version 2.1 narrows this, so the grammar can produce useful structure instead of a sea of prose nodes.

- A block body holds declarations, statements, property declarations, comments, or section headings. **A bare prose line is not a block member.**
- An identifier or a property name is one word. `Start game {` becomes `StartGame {`. `Authors to emulate:` becomes `authorsToEmulate:`.
- A `constraint`, `require`, or `warn` body is an expression or a block of structured items. Write a prose constraint as a string literal: `"Avoid mentioning these constraints."`
- This grammar does not parse markdown headings, lists, blockquotes, or fenced code blocks. It targets `.sudo` content.
- A `# Section heading` marker is legal at the top level and inside a block. It drives outline navigation and nothing else.

## 1. Overview

This document specifies a [Tree-sitter](https://tree-sitter.github.io/) grammar for SudoLang. The grammar carries the editor tooling. The first host is a Zed language extension. Any other Tree-sitter host can use the parser, such as Neovim, Helix, GitHub linguist, a custom LSP, or a static analyzer.

### 1.1 File types

| Extension                 | Treatment                                                                                                                                                       |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.sudo`                   | Pure SudoLang. This is the only extension the grammar claims.                                                                                                   |
| `.sudo.md`, `.md`, `.mdc` | tree-sitter-markdown handles the file. Standard code-fence injection highlights each ` ```sudo ` or ` ```SudoLang ` fence, once the editor registers this grammar. |

The grammar does not embed markdown. Markdown is the host, and SudoLang is the injected language. For the same reason, `queries/injections.scm` ships empty.

### 1.2 Design philosophy

An LLM runs a SudoLang program. The grammar is therefore **structurally descriptive, not prescriptive**:

1. **Recognize structure where structure exists.** This covers interfaces, functions, constraint blocks, commands, pipes, operators, assignments, and control flow.
2. **Keep prose in string literals and comments.** Version 2.1 removed the bare-prose fallback, because it swallowed the structure around it.
3. **Do not reject valid SudoLang.** The specification allows referential omnipotence and inferred function bodies. A grammar that fails on `fn foo;` or `chunk() { "Chunk sections of the text." }` is wrong.
4. **Stay LR(1)-friendly.** No external scanner. Braces, newlines, and semicolons bound the ambiguity.
5. **Leave embedded languages to the host.** The host grammar injects Mermaid, JSON, JavaScript, and Python. This grammar does not parse them.

The job of the grammar is a tree that serves highlighting, outline, navigation, and tool inspection. The job is not to validate the program.

## 2. Lexical structure

### 2.1 Comments

```
line_comment    ::= "//" /[^\n]*/
block_comment   ::= "/*" /[^*]*\*+([^/*][^*]*\*+)*/ "/"
```

Both are `extras`, so both are legal anywhere. Both carry precedence 20, so the lexer prefers `//` over division.

### 2.2 Strings

```
double_string       ::= '"' ( interpolation | escape | fragment )* '"'
template_string     ::= '`' ( interpolation | escape | fragment )* '`'
triple_quoted_block ::= '"""' body '"""'
interpolation       ::= "$" identifier | "${" expression "}"
escape              ::= "\" any_char_except_newline
```

A `$` followed by an identifier is an interpolation. A `\$` is a literal `$`. Both single-line string forms take interpolation. The specification uses double quotes for a normal string and backticks for a template string, and the two are equivalent to the parser.

A triple-quoted block holds multi-line prose. It has no interpolation, and the formatter never touches the body.

### 2.3 Numbers

```
number ::= /\$\d{1,3}(,\d{3})+(\.\d+)?/    // $1,000,000
         | /\$\d+(\.\d+)?/                  // $42.50
         | /\d{1,3}(,\d{3})+(\.\d+)?/       // 1,000,000
         | /\d+\.\d+/                       // 3.14
         | /\d+/                            // 42
```

A number carries an optional `$` prefix and optional comma groups. The grammar has no scientific notation, no hexadecimal, and no underscore separators. It can gain them without a breaking change.

### 2.4 Identifiers

```
identifier           ::= /[a-zA-Z_][a-zA-Z0-9_]*/
qualified_identifier ::= identifier ("::" identifier)+
sigil_identifier     ::= "$" identifier
                       | "@" identifier ("/" identifier)*
```

SudoLang convention keeps PascalCase for an interface or a type, such as `Player`, `StoryWorld`, or `ActionObject`. The grammar does not enforce the convention, and it uses one `identifier` token. The highlight queries in `highlights.scm` separate PascalCase with a `#match?` predicate.

The `sigil_identifier` token is separate because `$` and `@` are unambiguous, and cheap tokenization helps here. The `@` form also carries a path, such as `@paralleldrive/cuid2`. A decorator name reuses this token.

The pipe placeholder `_` parses as a plain `identifier`. See [§4.10](#410-v22-additions).

### 2.5 Commands

```
command_name ::= /\/[a-zA-Z_][a-zA-Z0-9_-]*/
command_args ::= /\[[^\]\n]*\]/
```

A slash-prefixed identifier such as `/help`, `/save`, `/run`, or `/load` is a language construct, not prose. It appears as a command declaration inside an interface (`/help - get help`) and as a user invocation.

### 2.6 Operators

| Symbol                  | Class                  | Associativity | Precedence   |
| ----------------------- | ---------------------- | ------------- | ------------ |
| `\|>`                   | pipe                   | left          | 1 (lowest)   |
| `=` `+=` `-=` `*=` `/=` | assignment             | right         | 2            |
| `=>`                    | arrow                  | right         | 2            |
| `\|\|` `??` `xor`       | logical or, nullish    | left          | 3            |
| `&&`                    | logical and            | left          | 4            |
| `==` `!=`               | equality               | left          | 5            |
| `<` `>` `<=` `>=`       | comparison             | left          | 6            |
| `..`                    | range                  | left          | 7            |
| `union` `intersection`  | set                    | left          | 7            |
| `+` `-`                 | additive               | left          | 8            |
| `*` `/` `%`             | multiplicative         | left          | 9            |
| `^`                     | exponent               | right         | 10           |
| `!` `-` (unary)         | prefix                 | right         | 11           |
| `()`                    | call                   | left          | 12           |
| `:`                     | modifier list          | right         | 13           |
| `.` `?.` `[]`           | member and index       | left          | 14           |
| `::`                    | capability namespace   | right         | 15 (highest) |

The `->` guard arrow is not an expression operator. It joins a condition to a consequence in statement position. See [§4.10](#410-v22-additions).

The deprecated `cap` and `cup` set operators are not in the grammar. Use `union` and `intersection`.

### 2.7 Punctuation

The grammar uses `{` `}` `[` `]` `(` `)` `,` `;` `:` `.` in the standard way. A semicolon is optional almost everywhere. Its two jobs are to end a modifier list (`fn():mod=val;`) and to end a statement before a line that starts with `[` or `(`. See the ASI note in [§4.10](#410-v22-additions).

### 2.8 Keywords

The `word` token is `identifier`, which turns on the keyword-extraction optimization in Tree-sitter. The grammar reserves the following words in keyword position. Context-aware lexing keeps them usable as an ordinary property name or inside a string.

```
case, catch, constraint, Constraint, constraints, Constraints, default,
each, else, fn, for, function, if, in, interface, intersection, loop,
match, null, require, return, throw, true, false, try, union, warn,
while, xor
```

The word `each` is not reserved on its own. It is the syntactic partner of `for`.

The names `Requirements`, `Options`, `Lint`, and `State` are **not** keywords. They collide with ordinary prose, so they stay identifiers and parse as an interface declaration.

## 3. Markdown integration

The grammar does not parse markdown. A markdown file goes through tree-sitter-markdown, and the standard code-fence injection puts each ` ```sudo ` or ` ```SudoLang ` fence body through this grammar.

The language server models the same split. It treats each fence as a virtual document, and it maps every position back to the host file. All fences of one document share one symbol table. The server skips a ` ```sudo-next ` fence, which holds proposal syntax.

Inside `.sudo` content, one markdown-like form survives: the `# Section heading` marker. It is an outline anchor, and it carries no other meaning.

```
section_heading ::= /#{1,6}/ /[ \t][^\n]*/
```

## 4. Grammar rules

The grammar reads top-down. It carries field annotations where an outline or navigation query needs them.

### 4.1 Top level

```js
source_file: $ => repeat($._top_level_item),

_top_level_item: $ => choice(
  $.section_heading,
  $.interface_declaration,
  $.function_declaration,
  $.command_declaration,
  $.constraint_block,
  $.constraint_inline,
  $.require_statement,
  $.warn_statement,
  $.command_invocation_statement,
  $._statement,
),
```

There is no prose fallback. Prose goes in a string literal or a comment.

### 4.2 Interface declarations

```js
interface_declaration: $ => seq(
  repeat(field('decorator', $.decorator)),
  optional('interface'),
  field('name', $.identifier),
  field('body', $.block),
),

block: $ => seq('{', repeat($._block_member), '}'),

_block_member: $ => choice(
  $.section_heading,
  $.interface_declaration,    // nested
  $.function_declaration,
  $.command_declaration,
  $.constraint_block,
  $.constraint_inline,
  $.require_statement,
  $.warn_statement,
  $.property_declaration,
  $.command_invocation_statement,
  $._statement,
),
```

The `interface` keyword is optional, which matches every example program: `Player { ... }`, `Dux { ... }`, `StoryWorld { ... }`.

### 4.3 Functions

A SudoLang function takes one of these shapes:

```sudo
fn foo;                        // signature only, no body
function bar();                // signature with empty params
function baz(x, y);            // signature with params
function qux(a, b) { qux(a) }  // signature with body
runTests () { "run them" }     // bare-name function with body (no keyword)
chunk() { "chunk the text" }   // same, no space before parens
```

```js
function_declaration: $ => choice($._function_with_keyword, $._function_bare),

_function_with_keyword: $ => prec.right(seq(
  repeat(field('decorator', $.decorator)),
  choice('fn', 'function'),
  field('name', $.identifier),
  optional(field('parameters', $.parameter_list)),
  optional(field('modifiers', $.modifier_list)),
  optional(field('body', $.block)),
  optional(';'),
)),

_function_bare: $ => seq(
  repeat(field('decorator', $.decorator)),
  field('name', $.identifier),
  field('parameters', $.parameter_list),
  optional(field('modifiers', $.modifier_list)),
  field('body', $.block),
),

parameter: $ => choice(
  seq(field('name', $.identifier), optional('?'),
      optional(seq('=', field('default', $._expression)))),
  seq(field('pattern', $.object_pattern),
      optional(seq('=', field('default', $._expression)))),
  seq(field('pattern', $.array_pattern),
      optional(seq('=', field('default', $._expression)))),
),
```

The bare-name form (`chunk() { ... }`) collides with a call used as an expression statement (`chunk()`). The **required block** breaks the tie. A call has no block, and a bare function declaration always has one. A parameter also takes `?` for optional, a default value, or a destructuring pattern.

### 4.4 Commands

```js
command_declaration: $ => prec.right(2, seq(
  field('command', $.command_name),
  optional(seq('|', field('alias', $._command_alias))),
  optional(field('arguments', $.command_args)),
  optional(seq(
    alias($._command_dash, $.command_dash),
    field('description', alias($._line_text, $.command_description)),
  )),
)),

command_invocation: $ => prec.right(2, seq(
  field('command', $.command_name),
  optional(field('arguments', $.argument_list)),
)),
```

A top-level invocation such as `/welcome` or `/help` uses the same `command_name` token. It parses as `command_invocation_statement` in statement position, and as `command_declaration` when a dash description or an alias follows.

### 4.5 Constraints

Three shapes appear in the specification and the examples:

```sudo
constraint MinimumSalary { emit(violation) }       // named block
constraint: "The goal scores a point."             // inline
Constraints { "Avoid mentioning these." "PG-13." } // plural block
```

```js
constraint_block: $ => prec.right(seq(
  field('keyword', alias($._constraint_keyword, $.constraint_keyword)),
  optional(field('name', $.identifier)),
  optional(':'),
  field('body', $.block),
)),

_constraint_keyword: $ => choice(
  'constraint', 'Constraint', 'constraints', 'Constraints',
),

constraint_inline: $ => prec(2, seq(
  field('keyword', alias(choice('constraint', 'Constraint'), $.constraint_keyword)),
  ':',
  field('body', $._expression),
)),

require_statement: $ => prec.right(seq(
  'require', field('body', choice($._expression, $.block)), optional(';'),
)),

warn_statement: $ => prec.right(seq(
  'warn', field('body', choice($._expression, $.block)), optional(';'),
)),
```

Only the four `constraint` spellings are keywords. `Requirements`, `Warnings`, `Options`, and `Lint` parse as interface declarations, because those words also read as prose.

A `require` or a `warn` takes an expression (`require age > 13`) or a block. Write a prose rule as a string: `warn "name should be defined"`.

### 4.6 Property declarations

```js
property_declaration: $ => prec.right(seq(
  field('name', $.identifier),
  ':',
  field('value', choice($._expression, $.block)),
  optional(';'),
)),
```

A property name is one identifier. The value is an expression or a block, which is what makes `State { ... }` and `Config: { theme: "dark" }` both work.

The assignment form (`name = "default"`) is an ordinary `assignment` node in block position. There is no separate `property_assignment` rule.

The colon form conflicts with `object_property_named` and with `object_pattern_pair`. The `conflicts` array declares each pair, and the surrounding rule decides.

### 4.7 Statements and expressions

```js
_statement: $ => choice(
  $.expression_statement,
  $.assignment,
  $.guard_statement,
  $.for_each_statement,
  $.while_statement,
  $.loop_statement,
  $.if_statement,
  $.return_statement,
  $.throw_statement,
  $.try_statement,
),

_assignment_target: $ => choice(
  $.identifier,
  $.member_expression,
  $.index_expression,
  $.array_pattern,    // [a, b] = [1, 2]
  $.object_pattern,   // { a, b } = { a: 1, b: 2 }
),

for_each_statement: $ => prec.right(seq(
  repeat(field('decorator', $.decorator)),
  'for', 'each',
  field('binding', $._for_binding),
  optional(seq('in', field('source', $._expression))),
  optional(','),
  field('body', $._statement_or_block),
)),
```

The grammar accepts `try` and `catch` so that a JavaScript-literate draft still parses. The 2.2 proposal defers `try`/`catch` as a language feature. Prefer a `require` gate and `@retry`.

Expressions use flat precedence climbing, as the Tree-sitter documentation recommends:

```js
_expression: $ => choice(
  $.identifier, $.qualified_identifier, $.sigil_identifier,
  $.number, $.double_string, $.template_string, $.triple_quoted_block,
  $.boolean, $.null,
  $.array_literal, $.object_literal,
  $.binary_expression, $.unary_expression, $.pipe_expression,
  $.modified_expression, $.call_expression, $.member_expression,
  $.index_expression, $.range_expression, $.match_expression,
  $.parenthesized_expression, $.if_expression, $.command_invocation,
  $.arrow_function,
),

member_expression: $ => prec.left(PREC.member, seq(
  field('object', $._expression),
  field('operator', choice('.', '?.')),
  field('property', $.identifier),
)),

modified_expression: $ => prec.right(PREC.modifier, seq(
  field('expression', $._expression),
  field('modifiers', $.modifier_list),
)),

modifier_list: $ => prec.right(seq(':', commaSep1($.modifier), optional(';'))),

modifier: $ => prec.right(seq(
  field('name', $.identifier),
  optional(seq('=', field('value', $._modifier_value))),
)),
```

A modifier list attaches to any expression through `modified_expression`, not only to a call. A modifier value is an identifier, a string, a number, or a boolean. An unquoted phrase is not legal, so write `format="json"`, not `format=json output`.

### 4.8 Match expressions

```js
match_expression: $ => seq(
  'match', '(', field('subject', $._expression), ')',
  '{',
  optional(seq($.match_arm, repeat(seq(',', $.match_arm)),
                optional(','), optional(';'))),
  '}',
),

match_arm: $ => seq(
  choice(seq('case', field('pattern', $._match_pattern)), 'default'),
  '=>',
  field('value', choice($._expression, $.block)),
),
```

A `default` arm carries no pattern. A `case` arm always does. An arm value is an expression or a block.

### 4.9 Patterns

```js
_pattern: $ => choice(
  $.identifier, $.sigil_identifier, $.number,
  $.double_string, $.template_string, $.boolean, $.null,
  $.array_pattern, $.object_pattern,
),

array_pattern:  $ => seq('[', optional(commaSep1(choice($._pattern, $.rest_pattern))),
                         optional(','), ']'),
object_pattern: $ => seq('{', optional(commaSep1(choice(
                           $.object_pattern_pair,
                           $.object_pattern_shorthand,
                           $.rest_pattern))),
                         optional(','), '}'),
rest_pattern:   $ => seq('...', field('binding',
                    choice($.identifier, $.array_pattern, $.object_pattern))),
```

Patterns serve destructuring assignment, a function parameter, a `for each` binding, and a match arm. A shorthand takes `?` and a default, the same way a parameter does.

### 4.10 v2.2 additions

Version 2.2 is a strict superset of v2.1, so every rule above is unchanged. The productions below are additive. Each new token is illegal in v2.1, which covers `::`, `->`, `?.`, `??`, `...`, and the decorator position. No existing program changes meaning.

**Qualified identifiers (`::`).** A capability namespace such as `mcp::linear`, `git::`, or `fs::` uses `::` between plain identifiers. It is legal wherever an `identifier` heads a member expression or a call. The `.` operator stays structural member access on the result.

```js
qualified_identifier: $ => prec.right(PREC.qualified, seq(
  field('namespace', $.identifier),
  repeat1(seq('::', field('name', $.identifier))),
)),
```

**Named arguments.** A call-site label, legal only inside an argument list. `argument_list` takes a `named_argument` next to a plain expression, an object property, and a spread element.

```js
named_argument: $ => seq(
  field('name', $.identifier),
  '=',
  field('value', $._expression),
),
```

Assignment-as-expression is already illegal in argument position. The `[$.parameter, $.named_argument]` conflict entry covers the remaining ambiguity.

**Guard statements.** The form is `condition -> statement`, in statement position only. It does not chain and it has no `else`. The consequence is a statement, a block, a `require`, or a `warn`. The `->` token is new, and `=>` stays the match-arm and lambda arrow.

```js
guard_statement: $ => prec.right(seq(
  field('condition', $._expression),
  '->',
  field('consequence', choice(
    $._statement_or_block,
    $.require_statement,
    $.warn_statement,
  )),
)),
```

**Decorators.** A decorator is `@name` with an optional argument list, stacked before a declaration or a loop. It reuses the `@` form of the `sigil_identifier` token. An unknown decorator name is legal, and the interpreter infers the metadata.

```js
decorator: $ => prec.dynamic(1, prec.right(seq(
  field('name', alias($.sigil_identifier, $.decorator_name)),
  optional(field('arguments', $.argument_list)),
))),
```

A `repeat($.decorator)` opens `interface_declaration`, both function forms, `for_each_statement`, `while_statement`, and `loop_statement`.

**Optional chaining and nullish default.** The `?.` operator is a member-access operator that short-circuits on a null or absent value. The `??` operator is binary, on the same precedence tier as `||`.

**Spread and rest.** A `spread_element` (`...expr`) appears in an array literal, an object literal, and an argument list. A `rest_pattern` (`...target`) appears in an array pattern and an object pattern.

```js
spread_element: $ => seq('...', field('argument', $._expression)),
rest_pattern:   $ => seq('...', field('binding',
                    choice($.identifier, $.array_pattern, $.object_pattern))),
```

**Pipe placeholder.** The `_` token parses as a plain `identifier` everywhere. The grammar does **not** special-case it. The LSP restricts `_` to a pipe stage and reports a warning outside one. This keeps the parser LR(1)-clean and avoids a grammar-wide scoped rule.

**Formalized v2.1 features.** These forms were already in `grammar.js`. Version 2.2 documents them as language:

- triple-quoted `"""` blocks
- `@scope/path` resource sigils
- comma-grouped and money numerics: `1,000,000` and `$100,000`
- optional parameters: `arg?`
- trailing commas
- `throw` and `return` statements

**Gotcha: a statement that starts with `[`.** SudoLang has the same automatic-semicolon-insertion hazard as JavaScript. Put a statement that starts with `[` or `(` right after an expression statement, and the parser reads an index or a call across the newline. For example, `compute()` on one line and `[a] = b` on the next parse as `compute()[a] = b`. The grammar inserts no semicolon. End the previous statement with `;`, or reorder so that the bracket-leading statement does not follow a bare expression.

## 5. Conflict resolution

A permissive grammar produces LR(1) conflicts, and the `conflicts` field declares each one. The main groups are:

| Conflict group                                         | Resolution                                                                                  |
| ------------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `object_literal` against `object_pattern` and `block`   | `{ a, b }` is a literal, a pattern, or a block until the parser sees what follows it.        |
| `array_literal` against `array_pattern`                 | Same shape on both sides of `=`. The assignment target position decides.                     |
| `property_declaration` against `object_property_named`  | Both use `:`. The surrounding rule decides.                                                  |
| `parameter` against `named_argument`                    | Both are `name = value`. A parameter list declares, and an argument list invokes.            |
| `command_declaration` against `command_invocation`      | A dash description or an alias makes it a declaration.                                       |
| `interface_declaration` against `_expression`           | `Name {` is an interface. A bare `Name` is an expression.                                    |
| `decorator` against `_expression`                       | `@name` is a sigil identifier in expression position and a decorator name before a declaration. |

The grammar declares `conflicts`, `precedences` through the `PREC` table, and `supertypes`. Together they keep the parser table small enough to reason about.

## 6. External scanner

The grammar has **no external scanner**, and it needs none. Regex tokens and context-aware lexing cover every structural element, including the triple-quoted block. Keeping the grammar scanner-free keeps the wasm build small and the npm package portable.

## 7. Node types and fields

The grammar exposes 86 named node types. `src/node-types.json` holds the full list. The externally interesting ones are:

- `source_file`
- `section_heading`, with fields `marker` and `text`
- `interface_declaration`, with fields `decorator`, `name`, and `body`
- `function_declaration`, with fields `decorator`, `name`, `parameters`, `modifiers`, and `body`
- `parameter_list`, `parameter`
- `command_declaration`, with fields `command`, `alias`, `arguments`, and `description`
- `command_invocation`, `command_invocation_statement`
- `constraint_block`, with fields `keyword`, `name`, and `body`
- `constraint_inline`, with fields `keyword` and `body`
- `require_statement`, `warn_statement`, with field `body`
- `property_declaration`, with fields `name` and `value`
- `block`
- `assignment`, with fields `target`, `operator`, and `value`
- `expression_statement`, `guard_statement`, `return_statement`, `throw_statement`, `try_statement`
- `for_each_statement`, with fields `binding`, `source`, and `body`
- `while_statement`, `loop_statement`, `if_statement`, `if_expression`
- `match_expression`, `match_arm`
- `binary_expression`, with fields `left`, `operator`, and `right`
- `unary_expression`, `pipe_expression`, `modified_expression`, `arrow_function`
- `call_expression`, with fields `function` and `arguments`
- `member_expression`, `index_expression`, `range_expression`, `parenthesized_expression`
- `argument_list`, `named_argument`, `modifier_list`, `modifier`
- `array_literal`, `object_literal`, `object_property`, `object_property_named`, `object_property_computed`, `object_property_shorthand`
- `array_pattern`, `object_pattern`, `object_pattern_pair`, `object_pattern_shorthand`, `rest_pattern`, `parenthesized_pattern`
- `spread_element`
- `identifier`, `qualified_identifier`, `sigil_identifier`, `command_name`, `command_args`
- `decorator`, with fields `name` and `arguments`, plus `decorator_name`
- `number`, `boolean`, `null`
- `double_string`, `template_string`, `triple_quoted_block`, `string_fragment`, `string_interpolation`, `escape_sequence`
- `line_comment`, `block_comment`

The grammar declares `supertypes` for `_top_level_item`, `_block_member`, `_expression`, `_statement`, and `_pattern`. This hides the intermediate nodes from the tree and keeps them queryable.

## 8. Test corpus

The tests live in `test/corpus/` as `.txt` files in the standard Tree-sitter test format. The current corpus holds 56 parses across 13 files:

| File             | Covers                                                             |
| ---------------- | ------------------------------------------------------------------ |
| `interfaces.txt` | bare, keyword-prefixed, and nested interfaces                      |
| `functions.txt`  | every function shape, with and without modifiers and bodies        |
| `constraints.txt`| `constraint` and `Constraints` blocks, inline form, `require`, `warn` |
| `commands.txt`   | declarations with a description, an alias, and arguments. Invocations |
| `expressions.txt`| operator precedence, associativity, pipes, member access, calls    |
| `strings.txt`    | interpolation, escapes, template strings, triple-quoted blocks     |
| `headings.txt`   | `# Section heading` markers at the top level and inside a block     |
| `qualified.txt`  | `::` capability paths, in a call and in a pipe chain               |
| `guards.txt`     | `condition -> statement`, with each consequence form               |
| `decorators.txt` | stacked decorators, before a declaration and before a loop         |
| `optional.txt`   | `?.` chains and `??` defaults                                      |
| `spread.txt`     | spread in a literal and a call. Rest in an array and object pattern |
| `placeholder.txt`| `_` parsing as a plain identifier                                  |

Beyond the corpus, `scripts/parse-examples.sh` runs every file in `examples/`. It parses each `.sudo` file whole, and it extracts and parses each ` ```sudo ` fence from each `.md` and `.sudo.md` file. Zero `ERROR` and zero `MISSING` nodes is the release gate. These examples are the binding contract, because they are what people write.

## 9. Open questions

1. **Multi-line property values.** Version 2.1 requires one identifier for a property name and an expression for the value. A wrapped prose value therefore goes in a triple-quoted block. This looks settled.
2. **Scientific and hexadecimal numerics.** No example needs them. Adding them later is not a breaking change.
3. **`try` and `catch`.** The grammar accepts both, and the 2.2 proposal defers both. Either promote them in a later version, or drop the rule once guards and `@retry` prove enough in the field.
4. **Namespace-aware tags.** `tags.scm` captures a qualified path in a call. A separate capture for the namespace segment could help ctags hosts, and it needs a host that reads it first.
5. **Placeholder scoping.** The `_` placeholder is a lint in the LSP, not a grammar rule. If misuse turns out to be common, a scoped grammar rule is the alternative, at the cost of LR(1) cleanliness.
