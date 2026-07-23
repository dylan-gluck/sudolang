# tree-sitter-sudolang — Grammar Specification

Status: Draft 2 (v2.1). Targets the **SudoLang v2.1** dialect — the v2.0 spec, made strict.

## v2.1 changes vs. v2.0

The v2.0 spec admits prose almost anywhere ("just write natural language declarations"). v2.1 narrows this so the grammar can produce useful structure rather than a sea of `natural_language_block` nodes:

- Block bodies must contain declarations, statements, property declarations, comments, or section headings. **Bare prose lines are no longer block members.**
- Identifiers and property names are single-word only — `Start game {`, `Authors to emulate:`, etc. become `StartGame {` and `authorsToEmulate:`.
- Constraint / `require` / `warn` bodies are expressions or blocks of structured items. Prose constraints are written as string literals: `"Avoid mentioning these constraints."`
- Markdown headings, lists, blockquotes, and fenced code blocks are no longer parsed by this grammar. The grammar targets `.sudo` only.
- `# Section heading` markers are recognised at top-level and inside blocks for outline navigation only.

## 1. Overview

This document specifies a [Tree-sitter](https://tree-sitter.github.io/) grammar for SudoLang. The grammar is the foundation for editor tooling — initially a Zed language extension, but the parser should be usable from any host that consumes Tree-sitter (Neovim, Helix, GitHub linguist, custom LSPs, static analyzers).

### 1.1 File types

| Extension  | Treatment                                                       |
|------------|-----------------------------------------------------------------|
| `.sudo`    | Pure SudoLang. The only extension this grammar claims directly. |
| `.sudo.md`, `.mdc`, `.md` | Handled by tree-sitter-markdown. SudoLang ` ```sudo ` / ` ```SudoLang ` code fences inside them are highlighted via Markdown's standard code-fence injection once the SudoLang grammar is registered with the editor. |

The grammar deliberately does not embed Markdown. Markdown is the host; SudoLang is what gets injected.

### 1.2 Design philosophy

SudoLang is a pseudolanguage executed by an LLM. The grammar therefore aims to be **structurally descriptive, not prescriptive**:

1. **Recognize structure where it exists** — interfaces, functions, constraint blocks, commands, pipes, operators, assignments, control flow.
2. **Accept prose as a first-class fallback** — anywhere a statement can appear, `natural_language` text is legal.
3. **Never reject valid SudoLang** — the spec explicitly allows referential omnipotence and inferred function bodies. A grammar that fails on `fn foo;` or `chunk() { Chunk sections of the text. }` is wrong.
4. **Stay LR(1)-friendly** — keep prose ambiguity bounded by clear terminators (newlines, braces, semicolons).
5. **Lean on `injections.scm` for embedded languages** — Mermaid, JSON, JavaScript, Python, etc. inside fenced code blocks are not parsed by this grammar.

The grammar's job is to produce a tree useful for highlighting, outline, navigation, and AI-tool inspection — not to validate the program.

## 2. Lexical structure

### 2.1 Comments

```
line_comment    ::= "//" /[^\n]*/
block_comment   ::= "/*" /([^*]|\*+[^/])*\*+/ "/"
```

Both are `extras` (may appear anywhere). The lexer must prefer `//` over division-in-context; SudoLang has no integer division operator that conflicts at the token level, so this is safe.

### 2.2 Strings

```
double_string   ::= '"' ( interpolation | escape | /[^"\\$]/ )* '"'
template_string ::= '`' ( interpolation | escape | /[^`\\$]/ )* '`'
interpolation   ::= "$" identifier | "${" expression "}"
escape          ::= "\\" any_char
```

`$` followed by an identifier is an interpolation; `\\$` is a literal `$`. Both string forms support interpolation; the spec uses double quotes for normal strings and backticks for "template strings" — they're functionally equivalent for syntax purposes.

### 2.3 Numbers

```
number ::= /[0-9]+(\.[0-9]+)?/
```

The spec does not currently use scientific notation, hex, or underscores in numerics. The grammar may extend to those without breaking changes.

### 2.4 Identifiers

```
identifier        ::= /[a-zA-Z_][a-zA-Z0-9_]*/
sigil_identifier  ::= "$" identifier
```

SudoLang convention reserves PascalCase for interfaces and types (`Player`, `StoryWorld`, `ActionObject`), but does not enforce it. The grammar uses a single `identifier` token. Highlight queries (`highlights.scm`) distinguish PascalCase via `#match?` predicates rather than the grammar.

`sigil_identifier` is a distinct token because `$` is unambiguous and Tree-sitter benefits from cheap tokenization here.

### 2.5 Commands

```
command_name ::= /\/[a-zA-Z_][a-zA-Z0-9_]*/
```

Slash-prefixed identifiers — `/help`, `/save`, `/run`, `/load` — are first-class. They appear both as command declarations inside interfaces (`/help - get help`) and as user invocations.

### 2.6 Operators

| Symbol      | Class               | Associativity | Precedence |
|-------------|---------------------|---------------|------------|
| `|>`        | pipe                | left          | 1 (lowest) |
| `=` `+=` `-=` `*=` `/=` | assignment | right         | 2 |
| `\|\|`      | logical or          | left          | 3 |
| `xor`       | logical xor         | left          | 3 |
| `&&`        | logical and         | left          | 4 |
| `==` `!=`   | equality            | left          | 5 |
| `<` `>` `<=` `>=` | comparison    | left          | 6 |
| `..`        | range               | none          | 7 |
| `union` `intersection` | set      | left          | 7 |
| `+` `-`     | additive            | left          | 8 |
| `*` `/` `%` | multiplicative      | left          | 9 |
| `^`         | exponent            | right         | 10 |
| `!` `-` (unary) | prefix          | right         | 11 |
| `.` `()` `[]` | member/call/index | left          | 12 (highest) |

The deprecated `cap`/`cup` set operators are accepted as aliases for `intersection`/`union` for backward compatibility but are flagged by the grammar with a `deprecated` field for tooling to surface.

### 2.7 Punctuation

`{` `}` `[` `]` `(` `)` `,` `;` `:` `.` — standard. The semicolon is optional in nearly every position; it serves primarily as a modifier terminator (`fn():mod=val;`).

### 2.8 Keywords

The `word` token is `identifier`, enabling Tree-sitter's keyword extraction optimization. The following are reserved in keyword contexts but remain usable as ordinary identifiers in property names and string contents (Tree-sitter handles this via context-aware lexing):

```
ask, case, concat, constraint, constraints, contains, continue, convert,
count, default, defaults, describe, else, emit, empty, error, escape, every,
exists, explain, filter, find, first, flatMap, flatten, fn, for, function,
groupBy, if, in, includes, interface, interpolate, join, list, log, loop,
map, match, max, merge, min, normalize, orderBy, otherwise, pick, pluck,
range, replace, require, requirements, reverse, revise, select, skip, slice,
some, sort, sortBy, split, take, takeLast, takeLatest, takeUntil, takeWhile,
throw, transpile, trim, true, false, null, union, intersection, unique, warn,
warnings, where, while, wrap, xor, zip
```

Note that "each" (in `for each`) is not reserved on its own — it's a syntactic partner to `for`.

## 3. Markdown integration

SudoLang files embed Markdown. The grammar recognizes the following Markdown structures at the file level (and inside interface bodies, where prose is also legal):

```
markdown_heading    ::= /^#{1,6}/ /[^\n]*/
markdown_list_item  ::= /^\s*[-*+]\s/ /[^\n]*/
                     |  /^\s*[0-9]+\.\s/ /[^\n]*/
fenced_code_block   ::= "```" optional(language_tag) /\n.*?\n/ "```"
markdown_blockquote ::= /^>\s/ /[^\n]*/
```

Inline Markdown (bold, italic, links, inline code) is **not** parsed structurally. It's treated as prose. The Zed extension's `injections.scm` may inject `markdown-inline` into `natural_language` nodes if a richer experience is desired, but this is optional.

Fenced code blocks with a recognized language tag (`javascript`, `python`, `json`, `mermaid`, `sudo`, `SudoLang`, etc.) are captured with `@injection.language` and `@injection.content` for downstream parsers. The fence content itself is left as opaque text by the SudoLang grammar.

## 4. Grammar rules

The grammar is written top-down, with field annotations where they aid outline and navigation queries.

### 4.1 Top level

```js
source_file: $ => repeat($._top_level_item),

_top_level_item: $ => choice(
  $.markdown_heading,
  $.markdown_list_item,
  $.fenced_code_block,
  $.markdown_blockquote,
  $.interface_declaration,
  $.function_declaration,
  $.command_declaration,
  $.constraint_block,
  $.require_statement,
  $.warn_statement,
  $.statement,
  $.natural_language_block,
),
```

`natural_language_block` is the fallback. It captures consecutive prose lines that don't match any structural construct.

### 4.2 Interface declarations

```js
interface_declaration: $ => seq(
  optional('interface'),
  field('name', $.identifier),
  field('body', $.block),
),

block: $ => seq(
  '{',
  repeat($._block_member),
  '}',
),

_block_member: $ => choice(
  $.interface_declaration,    // nested
  $.function_declaration,
  $.command_declaration,
  $.constraint_block,
  $.constraint_inline,
  $.require_statement,
  $.warn_statement,
  $.property_assignment,
  $.property_declaration,
  $.statement,
  $.natural_language_line,
),
```

The `interface` keyword is optional, matching usage in every example program (`Player { ... }`, `Dux { ... }`, `StoryWorld { ... }`).

### 4.3 Functions

SudoLang functions appear in four shapes:

```sudo
fn foo;                    // signature only, no body
function bar();            // signature with empty params
function baz(x, y);        // signature with params
function qux(a, b) { ... } // signature with body
runTests () { ... }        // bare-name function with body (no keyword)
chunk() { ... }            // same, no space before parens
```

```js
function_declaration: $ => choice(
  $._function_with_keyword,
  $._function_bare,
),

_function_with_keyword: $ => seq(
  choice('fn', 'function'),
  field('name', $.identifier),
  optional(field('parameters', $.parameter_list)),
  optional(field('modifiers', $.modifier_list)),
  optional(field('body', $.block)),
  optional(';'),
),

_function_bare: $ => seq(
  field('name', $.identifier),
  field('parameters', $.parameter_list),
  optional(field('modifiers', $.modifier_list)),
  field('body', $.block),
),

parameter_list: $ => seq(
  '(',
  optional(commaSep($.parameter)),
  ')',
),

parameter: $ => seq(
  field('name', $.identifier),
  optional(seq('=', field('default', $._expression))),
),
```

The bare-name function form (`chunk() { ... }`) conflicts with function calls (`chunk()` as an expression statement). This is resolved by **requiring a block** for the bare form — a function call has no block, a bare function declaration always does. Tree-sitter handles this without ambiguity because the lookahead at `}` after `chunk() {` disambiguates.

### 4.4 Commands

```js
command_declaration: $ => seq(
  field('command', $.command_name),
  optional(seq('|', field('alias', $.command_name))),
  optional(field('arguments', $.command_args)),
  optional(seq('-', field('description', $.natural_language_line))),
),

command_args: $ => /\[[^\]]*\]/,  // e.g. /load [filename]
```

Top-level command invocations (`/welcome`, `/help`) use the same `command_name` token but are parsed as `command_invocation` expressions when they appear as statements rather than declarations.

### 4.5 Constraints

Three shapes occur in the spec and examples:

```sudo
constraint MinimumSalary { emit({...}) }              // named block
constraint: Score points are awarded any time...      // unnamed inline (prose)
Constraints { Avoid mentioning these. PG-13. }        // plural block
```

```js
constraint_block: $ => seq(
  choice('constraint', 'Constraint', 'constraints', 'Constraints',
         'require', 'requirements', 'Requirements',
         'warn', 'warnings', 'Warnings'),
  optional(field('name', $.identifier)),
  field('body', $.block),
),

constraint_inline: $ => seq(
  choice('constraint', 'require', 'warn'),
  ':',
  field('body', $.natural_language_line),
),

require_statement: $ => seq(
  'require',
  field('body', $._require_body),
),

warn_statement: $ => seq(
  'warn',
  field('body', $._require_body),
),

_require_body: $ => choice(
  $._expression_then_terminator,
  $.natural_language_line,
),
```

`require` and `warn` accept either an expression-like form (`require should to be a string`) or pure prose (`warn if the test function is not readable`). The grammar accepts both via `choice`.

### 4.6 Property assignment

```js
property_assignment: $ => seq(
  field('name', $.identifier),
  choice('=', '+=', '-=', '*=', '/='),
  field('value', $._expression),
  optional(';'),
),

property_declaration: $ => seq(
  field('name', $._property_name),
  ':',
  field('value', $._property_value),
),

_property_name: $ => /[A-Za-z][A-Za-z0-9 _-]*/,  // permits multi-word names
_property_value: $ => /[^\n{}]+/,                // free-form to EOL or brace
```

The colon-form has an LR(1) conflict with `match` cases (`case x => ...` uses `=>` not `:` but pattern arms inside `match` use `:` in object patterns) and with command descriptions (`/help - ...` is `-` not `:` but TypeScript-style annotations would collide). We resolve this by making `property_declaration` only valid inside `block` / interface bodies, and giving `match` arm syntax its own scope via the dedicated `match_expression` rule.

### 4.7 Statements and expressions

```js
statement: $ => choice(
  $.assignment,
  $.expression_statement,
  $.for_each_statement,
  $.while_statement,
  $.loop_statement,
  $.if_statement,
  $.return_statement,
  $.throw_statement,
),

assignment: $ => seq(
  field('target', $._assignment_target),
  choice('=', '+=', '-=', '*=', '/='),
  field('value', $._expression),
  optional(';'),
),

_assignment_target: $ => choice(
  $.identifier,
  $.member_expression,
  $.index_expression,
  $.array_pattern,    // [a, b] = [1, 2]
  $.object_pattern,   // { a, b } = { a:1, b:2 }
),

for_each_statement: $ => seq(
  'for', 'each',
  field('binding', $._for_binding),
  optional(seq('in', field('source', $._expression))),
  ',',
  field('body', $._statement_or_prose),
),

while_statement: $ => seq(
  'while', '(', field('condition', $._expression), ')',
  field('body', choice($.block, $._statement_or_prose)),
),

loop_statement: $ => seq(
  'loop',
  field('body', $.block),
),

if_statement: $ => prec.right(seq(
  'if', '(', field('condition', $._expression), ')',
  field('consequence', $._statement_or_expression),
  optional(seq('else', field('alternative', $._statement_or_expression))),
)),
```

Expressions follow a flat precedence-climbing pattern, as recommended in the Tree-sitter docs:

```js
_expression: $ => choice(
  $.identifier,
  $.sigil_identifier,
  $.number,
  $.double_string,
  $.template_string,
  $.boolean,
  $.null,
  $.array_literal,
  $.object_literal,
  $.binary_expression,
  $.unary_expression,
  $.pipe_expression,
  $.call_expression,
  $.member_expression,
  $.index_expression,
  $.range_expression,
  $.match_expression,
  $.parenthesized_expression,
  $.if_expression,
  $.command_invocation,
),

binary_expression: $ => choice(
  ...['||', '&&', '==', '!=', '<', '>', '<=', '>=',
      '+', '-', '*', '/', '%', '^',
      'xor', 'union', 'intersection', 'cap', 'cup']
    .map(op => prec.left(PREC[op], seq(
      field('left', $._expression),
      field('operator', op),
      field('right', $._expression),
    )))
),

pipe_expression: $ => prec.left(PREC.pipe, seq(
  field('left', $._expression),
  '|>',
  field('right', $._expression),
)),

call_expression: $ => prec(PREC.call, seq(
  field('function', choice($.identifier, $.member_expression)),
  field('arguments', $.argument_list),
  optional(field('modifiers', $.modifier_list)),
)),

modifier_list: $ => seq(
  ':',
  commaSep1($.modifier),
  optional(';'),
),

modifier: $ => seq(
  field('name', $.identifier),
  optional(seq('=', field('value', $._modifier_value))),
),

_modifier_value: $ => choice(
  $.identifier,
  $.double_string,
  $.number,
  /[^,;\n]+/,  // permits unquoted phrases like `length=1 line`
),
```

### 4.8 Match expressions

```js
match_expression: $ => seq(
  'match',
  '(',
  field('subject', $._expression),
  ')',
  '{',
  commaSep($.match_arm),
  optional(','),
  '}',
),

match_arm: $ => seq(
  choice('case', 'default'),
  optional(field('pattern', $._pattern)),
  '=>',
  field('value', $._expression),
),

_pattern: $ => choice(
  $.identifier,
  $.number,
  $.double_string,
  $.array_pattern,
  $.object_pattern,
  $.literal_pattern,
),
```

### 4.9 Natural language

```js
natural_language_block: $ => prec(-1, repeat1($.natural_language_line)),

natural_language_line: $ => token(prec(-1,
  /[^{}\n#`/][^{}\n]*\n/
)),
```

The leading-character negative class prevents prose lines from accidentally swallowing headings (`#`), code fences (` ``` `), or commands (`/x`). The negative precedence ensures structured constructs always win when both could match.

Multi-line prose paragraphs are represented as `natural_language_block` containing multiple `natural_language_line` children. Blank lines terminate a block.

## 5. Conflict resolution

The intentionally permissive grammar produces several LR(1) conflicts that must be declared in the `conflicts` field:

| Conflict pair | Resolution |
|---------------|------------|
| `interface_declaration` ↔ `function_declaration` (bare) | Disambiguated by presence/absence of block immediately after the parameter list. Tree-sitter handles this with `conflicts: [[$.interface_declaration, $._function_bare]]`. |
| `property_assignment` ↔ `assignment` | Identical at the syntactic level. Distinguished by context — `property_assignment` only inside `block`. Resolved by inlining both into a single rule with two parents. |
| `property_declaration` ↔ `match_arm` | Both use `:`. Disambiguated by surrounding rule (`match_expression` only allows `match_arm`). |
| `natural_language_line` ↔ everything | Negative precedence on the prose token ensures the structured rule always wins when both match. |
| `call_expression` ↔ `parenthesized_expression` | Standard expression-vs-call disambiguation; the function identifier on the left edge of `(` decides. |

The grammar declares `conflicts` and `precedences` arrays explicitly to keep these manageable.

## 6. External scanner

A custom external scanner in C is **not anticipated** for the first version. All structural elements can be handled with regex tokens and context-aware lexing. If multi-line prose paragraphs prove difficult to tokenize cleanly, a small external scanner that emits a `_prose_paragraph` token bounded by blank lines or braces could be added — this is a Phase 2 consideration.

## 7. Node types and fields

Externally visible node types (those without a leading underscore) are:

- `source_file`
- `interface_declaration` — fields: `name`, `body`
- `function_declaration` — fields: `name`, `parameters`, `modifiers`, `body`
- `parameter_list`, `parameter`
- `command_declaration` — fields: `command`, `alias`, `arguments`, `description`
- `command_invocation`
- `constraint_block` — fields: `name`, `body`
- `constraint_inline` — field: `body`
- `require_statement`, `warn_statement` — field: `body`
- `property_assignment` — fields: `name`, `value`
- `property_declaration` — fields: `name`, `value`
- `block`
- `assignment` — fields: `target`, `value`
- `for_each_statement` — fields: `binding`, `source`, `body`
- `while_statement` — fields: `condition`, `body`
- `loop_statement` — field: `body`
- `if_statement` — fields: `condition`, `consequence`, `alternative`
- `match_expression`, `match_arm`
- `binary_expression` — fields: `left`, `operator`, `right`
- `unary_expression`, `pipe_expression`
- `call_expression` — fields: `function`, `arguments`, `modifiers`
- `member_expression`, `index_expression`, `range_expression`
- `argument_list`, `modifier_list`, `modifier`
- `array_literal`, `object_literal`, `array_pattern`, `object_pattern`
- `identifier`, `sigil_identifier`, `command_name`
- `number`, `boolean`, `null`
- `double_string`, `template_string`, `string_interpolation`
- `line_comment`, `block_comment`
- `markdown_heading` — fields: `level`, `text`
- `markdown_list_item`, `markdown_blockquote`
- `fenced_code_block` — fields: `language`, `content`
- `natural_language_line`, `natural_language_block`

`supertypes` are declared for `_expression`, `_statement`, `_pattern` to hide intermediate nodes from the parse tree while keeping them queryable.

## 8. Test corpus

Tests live in `test/corpus/` as `.txt` files using Tree-sitter's standard test format. The corpus must cover:

1. **`interfaces.txt`** — bare, keyword-prefixed, nested, with/without bodies.
2. **`functions.txt`** — all five function shapes; with/without modifiers; with/without bodies.
3. **`constraints.txt`** — `constraint` block, `constraints` block, inline `constraint:`, `require`, `warn`, requirements with prose.
4. **`commands.txt`** — command declarations with descriptions, aliases, arguments; command invocations.
5. **`expressions.txt`** — operator precedence, associativity, pipes, member access, calls with modifiers.
6. **`strings.txt`** — interpolation, escapes, template strings, multi-line.
7. **`match.txt`** — pattern matching with object/array destructuring patterns.
8. **`markdown.txt`** — headings at every level, lists, blockquotes, fenced code blocks with various language tags.
9. **`prose.txt`** — prose-only files, prose mixed with structure, prose at every nesting level.
10. **`real-world/`** — each of the four canonical examples (`autodux.sudo.md`, `ai-rpg.sudo.md`, `riteway.sudo.md`, `vector-search.sudo.md`) must round-trip through the parser and produce a tree with no `ERROR` nodes.

The real-world tests are the most important — they're the binding contract that the grammar handles what people actually write.

## 9. Open questions

1. **Should `Mermaid` blocks be a first-class node, or only injected?** Probably injected — Mermaid has its own Tree-sitter grammar.
2. **Should we parse Markdown tables?** They appear in some docs but not in spec/example code. Defer to Phase 2.
3. **Multi-line property values** — `Authors to emulate: Vernor Vinge, William Gibson, Philip K. Dick` is one line, but could a value wrap? The spec is silent. We default to single-line and reconsider if examples emerge.
4. **`describe(name, fn)` and similar test-style calls** — these are just function calls in SudoLang. No special handling needed in the grammar; the Riteway extension queries can identify them via `runnables.scm` patterns.
5. **Range operator vs property access** — `1..3` (range) vs `obj..prop` (not valid SudoLang). The grammar accepts `..` only between two `_expression`s with numeric or identifier operands; ambiguity is resolved by the parser.
