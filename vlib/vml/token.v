// Copyright (c) 2019-2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

// Module vml parses VML, the declarative markup language of the ui2 UI library.
// It contains only the grammar: the lexer, the AST, documents with local
// components and named styles, and `import` resolution. It has no dependency
// on the V compiler, so the compiler's `$vml(...)` lowering and a runtime
// interpreter parse exactly the same language. Widget knowledge (tags,
// properties, style helpers) is supplied by the host through `ParseConfig`.
module vml

// Location is a 1-based source position. `path` is empty for in-memory sources.
pub struct Location {
pub:
	path   string
	line   int = 1
	column int = 1
}

// TokenKind is the kind of a lexical VML token.
pub enum TokenKind {
	name
	string_
	number
	lbrace
	rbrace
	colon
	lpar
	rpar
	comma
	question
	plus
	minus
	mul
	div
	mod
	not
	eq
	assign
	declare
	increment
	decrement
	semicolon
	lsbr
	rsbr
	ne
	lt
	le
	gt
	ge
	and
	or
	eof
}

// Token is one lexical VML token. `line`/`column` are 1-based. For `.string_`
// tokens, `text` holds the decoded value and `string_locations` holds the source
// location of each decoded byte followed by the location of the closing quote,
// so positions inside interpolated `${...}` fragments map back to the file.
pub struct Token {
pub:
	kind             TokenKind
	text             string
	line             int
	column           int = 1
	string_locations []Location
}

struct Lexer {
	source string
mut:
	pos        int
	line       int = 1
	line_start int
}

fn (mut l Lexer) advance() u8 {
	c := l.source[l.pos]
	l.pos++
	if c == `\n` {
		l.line++
		l.line_start = l.pos
	}
	return c
}

fn (mut l Lexer) skip_space() {
	for l.pos < l.source.len {
		c := l.source[l.pos]
		if c in [` `, `\t`, `\r`, `\n`] {
			l.advance()
		} else if c == `/` && l.pos + 1 < l.source.len && l.source[l.pos + 1] == `/` {
			for l.pos < l.source.len && l.source[l.pos] != `\n` {
				l.pos++
			}
		} else {
			break
		}
	}
}

fn is_name_char(c u8) bool {
	return c.is_alnum() || c in [`_`, `.`, `#`]
}

fn (mut l Lexer) read_name() Token {
	start := l.pos
	line := l.line
	column := l.pos - l.line_start + 1
	for l.pos < l.source.len && is_name_char(l.source[l.pos]) {
		l.pos++
	}
	return Token{ kind: .name, text: l.source[start..l.pos], line: line, column: column }
}

fn (mut l Lexer) read_number() Token {
	start := l.pos
	line := l.line
	column := l.pos - l.line_start + 1
	mut dot := false
	for l.pos < l.source.len {
		c := l.source[l.pos]
		if c.is_digit() {
			l.pos++
		} else if c == `.` && !dot {
			dot = true
			l.pos++
		} else {
			break
		}
	}
	return Token{ kind: .number, text: l.source[start..l.pos], line: line, column: column }
}

fn (mut l Lexer) read_string() !Token {
	line := l.line
	column := l.pos - l.line_start + 1
	quote := l.advance()
	mut value := []u8{}
	mut locations := []Location{}
	for l.pos < l.source.len {
		location := Location{ line: l.line, column: l.pos - l.line_start + 1 }
		c := l.advance()
		if c == `\\` && l.pos < l.source.len {
			next := l.advance()
			match next {
				`n` { value << `\n` }
				`t` { value << `\t` }
				`\\` { value << `\\` }
				`"` { value << `"` }
				`'` { value << `'` }
				else { value << next }
			}
		} else if c == quote {
			locations << location
			return Token{ kind: .string_, text: value.bytestr(), line: line, column: column, string_locations: locations }
		} else {
			value << c
		}
		locations << location
	}
	return error('unterminated string at line ${line}')
}

// tokenize splits VML source into tokens ending with one `.eof` token.
// `//` comments and whitespace are skipped.
pub fn tokenize(source string) ![]Token {
	mut lexer := Lexer{ source: source }
	mut tokens := []Token{}
	for {
		lexer.skip_space()
		if lexer.pos >= source.len {
			tokens << Token{ kind: .eof, text: '', line: lexer.line, column: lexer.pos - lexer.line_start + 1 }
			return tokens
		}
		line := lexer.line
		column := lexer.pos - lexer.line_start + 1
		c := source[lexer.pos]
		match c {
			`{` { tokens << Token{ kind: .lbrace, text: '{', line: line, column: column } }
			`}` { tokens << Token{ kind: .rbrace, text: '}', line: line, column: column } }
			`:` {
				if lexer.pos + 1 < source.len && source[lexer.pos + 1] == `=` {
					lexer.pos++
					tokens << Token{ kind: .declare, text: ':=', line: line, column: column }
				} else {
					tokens << Token{ kind: .colon, text: ':', line: line, column: column }
				}
			}
			`;` { tokens << Token{ kind: .semicolon, text: ';', line: line, column: column } }
			`[` { tokens << Token{ kind: .lsbr, text: '[', line: line, column: column } }
			`]` { tokens << Token{ kind: .rsbr, text: ']', line: line, column: column } }
			`(` { tokens << Token{ kind: .lpar, text: '(', line: line, column: column } }
			`)` { tokens << Token{ kind: .rpar, text: ')', line: line, column: column } }
			`,` { tokens << Token{ kind: .comma, text: ',', line: line, column: column } }
			`?` { tokens << Token{ kind: .question, text: '?', line: line, column: column } }
			`+` {
				if lexer.pos + 1 < source.len && source[lexer.pos + 1] == `+` {
					lexer.pos++
					tokens << Token{ kind: .increment, text: '++', line: line, column: column }
				} else {
					tokens << Token{ kind: .plus, text: '+', line: line, column: column }
				}
			}
			`-` {
				if lexer.pos + 1 < source.len && source[lexer.pos + 1] == `-` {
					lexer.pos++
					tokens << Token{ kind: .decrement, text: '--', line: line, column: column }
				} else {
					tokens << Token{ kind: .minus, text: '-', line: line, column: column }
				}
			}
			`*` { tokens << Token{ kind: .mul, text: '*', line: line, column: column } }
			`/` { tokens << Token{ kind: .div, text: '/', line: line, column: column } }
			`%` { tokens << Token{ kind: .mod, text: '%', line: line, column: column } }
			`!` {
				lexer.pos++
				if lexer.pos < source.len && source[lexer.pos] == `=` {
					tokens << Token{ kind: .ne, text: '!=', line: line, column: column }
				} else {
					tokens << Token{ kind: .not, text: '!', line: line, column: column }
					continue
				}
			}
			`=` {
				lexer.pos++
				if lexer.pos >= source.len || source[lexer.pos] != `=` {
					tokens << Token{ kind: .assign, text: '=', line: line, column: column }
					continue
				}
				tokens << Token{ kind: .eq, text: '==', line: line, column: column }
			}
			`<` {
				lexer.pos++
				if lexer.pos < source.len && source[lexer.pos] == `=` {
					tokens << Token{ kind: .le, text: '<=', line: line, column: column }
				} else {
					tokens << Token{ kind: .lt, text: '<', line: line, column: column }
					continue
				}
			}
			`>` {
				lexer.pos++
				if lexer.pos < source.len && source[lexer.pos] == `=` {
					tokens << Token{ kind: .ge, text: '>=', line: line, column: column }
				} else {
					tokens << Token{ kind: .gt, text: '>', line: line, column: column }
					continue
				}
			}
			`&` {
				lexer.pos++
				if lexer.pos >= source.len || source[lexer.pos] != `&` {
					return error('expected `&&` at line ${line}')
				}
				tokens << Token{ kind: .and, text: '&&', line: line, column: column }
			}
			`|` {
				lexer.pos++
				if lexer.pos >= source.len || source[lexer.pos] != `|` {
					return error('expected `||` at line ${line}')
				}
				tokens << Token{ kind: .or, text: '||', line: line, column: column }
			}
			`"`, `'` {
				tokens << lexer.read_string()!
				continue
			}
			else {
				if c.is_digit() {
					tokens << lexer.read_number()
					continue
				}
				if is_name_char(c) {
					tokens << lexer.read_name()
					continue
				}
				return error('unexpected character `${[c].bytestr()}` at line ${line}')
			}
		}
		lexer.pos++
	}
	return tokens
}
