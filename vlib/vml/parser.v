module vml

// ParseConfig lets the host add widget-specific validation and replace file IO
// without changing the grammar. Every hook is optional.
@[params]
pub struct ParseConfig {
pub:
	// validate_style checks one resolved named style declaration (the list after
	// named references were inlined). `owner` is the document root or component
	// that declares the style. It runs while the document is parsed, in
	// declaration order.
	validate_style ?fn (owner &Node, style &Expr) !
	// validate_document checks a document parsed by `parse_file`, after its imports
	// were expanded. `imported` is true for a document reached through `import`.
	// Imported documents are validated before the importing document.
	validate_document ?fn (root &Node, imported bool) !
	// read_file reads a VML document. The default is `os.read_file`.
	read_file ?fn (path string) !string
	// is_file reports whether an import candidate exists. The default is `os.is_file`.
	is_file ?fn (path string) bool
}

// Parser is a recursive-descent parser over the tokens of one VML document.
// `file` prefixes positioned diagnostics; it is empty for in-memory sources.
pub struct Parser {
pub:
	file   string
	tokens []Token
	config ParseConfig
mut:
	pos int
}

// new_parser returns a parser for `tokens` (from `tokenize`).
pub fn new_parser(tokens []Token, file string, config ParseConfig) Parser {
	return Parser{ tokens: tokens, file: file, config: config }
}

// parse_source parses an in-memory document: optional leading `style` and
// `component` declarations followed by one root element, or a document made only
// of component declarations (the last one is the root). Local components are
// expanded and named styles resolved. `Node.source` stays empty.
pub fn parse_source(source string, config ParseConfig) !&Node {
	tokens := tokenize(source)!
	mut parser := Parser{ tokens: tokens, config: config }
	root := parser.parse_document()!
	parser.take(.eof)!
	return root
}

// at returns the current token, or `.eof` past the end.
pub fn (p &Parser) at() Token {
	return if p.pos < p.tokens.len {
		p.tokens[p.pos]
	} else {
		Token{ kind: .eof, text: '', line: 0, column: 1 }
	}
}

// take consumes the current token, which must be of `kind`.
pub fn (mut p Parser) take(kind TokenKind) !Token {
	token := p.at()
	if token.kind != kind {
		return error('${p.file}:${token.line}:${token.column}: expected ${kind}, got ${token.kind} (`${token.text}`)')
	}
	p.pos++
	return token
}

// parse_node parses one element: `Tag`, `Tag(name: value, ...)`, optionally followed
// by `{ children }`. `id` must be a quoted name; `on_*` arguments are handlers.
pub fn (mut p Parser) parse_node() !&Node {
	tag := p.take(.name)!
	mut node := &Node{ tag: tag.text, line: tag.line, column: tag.column }
	if p.at().kind == .lpar {
		p.pos++
		for p.at().kind != .rpar {
			name := p.take(.name)!
			if node.properties.any(it.name == name.text) {
				return error('duplicate VML argument `${name.text}` at line ${name.line}:${name.column}')
			}
			p.take(.colon)!
			expr := if name.text.starts_with('on_') {
				p.parse_handler()!
			} else {
				p.parse_expression()!
			}
			if name.text.starts_with('on_') && expr.kind !in [.path, .call, .assignment, .block] {
				return error('callback `${name.text}` requires a typed function reference or an action at line ${name.line}:${name.column}')
			}
			if name.text == 'id' {
				if expr.kind != .literal || !expr.quoted {
					return error('id must be a quoted local name at line ${name.line}:${name.column}')
				}
				node.id = expr.value
			}
			node.properties << Property{ name: name.text, line: name.line, column: name.column, expr: expr }
			if p.at().kind != .comma { break }
			p.pos++
		}
		p.take(.rpar)!
	}
	if p.at().kind == .lbrace {
		p.pos++
		for p.at().kind !in [.rbrace, .eof] {
			if p.at().text in ['property', 'computed', 'state', 'style'] || (p.pos + 1 < p.tokens.len && p.tokens[p.pos + 1].kind == .colon) {
				return error('${p.file}:${p.at().line}:${p.at().column}: element arguments use `Name(name: value)`; state/computed belong to the component body')
			}
			node.children << p.parse_node()!
		}
		p.take(.rbrace)!
	}
	return node
}

// parse_handler parses an event handler: a `{ a; b }` block or one assignment/expression.
pub fn (mut p Parser) parse_handler() !&Expr {
	if p.at().kind == .lbrace {
		token := p.take(.lbrace)!
		mut statements := []&Expr{}
		for p.at().kind !in [.rbrace, .eof] {
			statements << p.parse_assignment()!
			if p.at().kind == .semicolon { p.pos++ }
		}
		p.take(.rbrace)!
		return &Expr{ kind: .block, line: token.line, column: token.column, args: statements }
	}
	return p.parse_assignment()
}

fn (mut p Parser) parse_assignment() !&Expr {
	left := p.parse_expression()!
	if p.at().kind in [.assign, .increment, .decrement] && left.kind == .path && left.value.contains('.')
		&& (!left.value.starts_with('app.') || left.value.count('.') != 1) {
		return error('assignment target `${left.value}` is read-only at line ${left.line}, column ${left.column}')
	}
	if p.at().kind in [.increment, .decrement] {
		op := p.at()
		p.pos++
		return &Expr{
			kind:   .assignment
			line:   op.line
			column: op.column
			left:   left
			right:  &Expr{
				kind:  .binary
				value: if op.kind == .increment {
					'+'
				} else {
					'-'
				}
				left:  left
				right: &Expr{ kind: .literal, value: '1' }
			}
		}
	}
	if p.at().kind != .assign { return left }
	op := p.take(.assign)!
	return &Expr{ kind: .assignment, line: op.line, column: op.column, left: left, right: p.parse_expression()! }
}

// parse_expression parses a full expression (conditional, logic, comparison,
// arithmetic, unary, calls, paths, literals, arrays and interpolated strings).
pub fn (mut p Parser) parse_expression() !&Expr {
	return p.parse_conditional()
}

fn (mut p Parser) parse_conditional() !&Expr {
	condition := p.parse_or()!
	if p.at().kind != .question {
		return condition
	}
	line := p.take(.question)!.line
	when_true := p.parse_expression()!
	p.take(.colon)!
	return &Expr{
		kind:  .conditional
		line:  line
		left:  condition
		right: when_true
		third: p.parse_expression()!
	}
}

fn (mut p Parser) parse_or() !&Expr {
	mut left := p.parse_and()!
	for p.at().kind == .or {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_and()!
		}
	}
	return left
}

fn (mut p Parser) parse_and() !&Expr {
	mut left := p.parse_equality()!
	for p.at().kind == .and {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_equality()!
		}
	}
	return left
}

fn (mut p Parser) parse_equality() !&Expr {
	mut left := p.parse_comparison()!
	for p.at().kind in [.eq, .ne] {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_comparison()!
		}
	}
	return left
}

fn (mut p Parser) parse_comparison() !&Expr {
	mut left := p.parse_term()!
	for p.at().kind in [.lt, .le, .gt, .ge] {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_term()!
		}
	}
	return left
}

fn (mut p Parser) parse_term() !&Expr {
	mut left := p.parse_factor()!
	for p.at().kind in [.plus, .minus] {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_factor()!
		}
	}
	return left
}

fn (mut p Parser) parse_factor() !&Expr {
	mut left := p.parse_unary()!
	for p.at().kind in [.mul, .div, .mod] {
		op := p.at()
		p.pos++
		left = &Expr{
			kind:   .binary
			value:  op.text
			line:   op.line
			column: op.column
			left:   left
			right:  p.parse_unary()!
		}
	}
	return left
}

fn (mut p Parser) parse_unary() !&Expr {
	if p.at().kind in [.not, .minus] {
		op := p.at()
		p.pos++
		return &Expr{ kind: .unary, value: op.text, line: op.line, column: op.column, left: p.parse_unary()! }
	}
	return p.parse_primary()
}

fn (mut p Parser) parse_primary() !&Expr {
	token := p.at()
	match token.kind {
		.string_ {
			p.pos++
			mut expr := parse_interpolation(token)!
			expr.column = token.column
			return expr
		}
		.name, .number {
			p.pos++
			if p.at().kind == .lpar {
				p.pos++
				mut args := []&Expr{}
				if p.at().kind != .rpar {
					for {
						args << p.parse_expression()!
						if p.at().kind != .comma {
							break
						}
						p.pos++
					}
				}
				p.take(.rpar)!
				fallible := p.at().kind == .not
				if fallible { p.pos++ }
				return &Expr{ fallible: fallible, kind: .call, value: token.text, line: token.line, column: token.column, args: args }
			}
			return &Expr{
				kind:   if token.kind == .number || token.text in ['true', 'false'] {
					ExprKind.literal
				} else {
					ExprKind.path
				}
				value:  token.text
				line:   token.line
				column: token.column
			}
		}
		.lsbr {
			p.pos++
			mut values := []&Expr{}
			for p.at().kind != .rsbr {
				values << p.parse_expression()!
				if p.at().kind != .comma { break }
				p.pos++
			}
			p.take(.rsbr)!
			return &Expr{ kind: .array, args: values, line: token.line, column: token.column }
		}
		.lpar {
			p.pos++
			expr := p.parse_expression()!
			p.take(.rpar)!
			return expr
		}
		else {
			return error('expected expression, got ${token.kind} (`${token.text}`) at line ${token.line}')
		}
	}
}

fn interpolation_end(value string, start int) ?int {
	mut quote := u8(0)
	mut escaped := false
	mut nested_braces := 0
	for i := start; i < value.len; i++ {
		ch := value[i]
		if quote != 0 {
			if escaped {
				escaped = false
			} else if ch == `\\` {
				escaped = true
			} else if ch == quote {
				quote = 0
			}
			continue
		}
		if ch == `"` || ch == `'` {
			quote = ch
		} else if ch == `{` {
			nested_braces++
		} else if ch == `}` {
			if nested_braces == 0 {
				return i
			}
			nested_braces--
		}
	}
	return none
}

fn parse_interpolation(token Token) !&Expr {
	value := token.text
	line := token.line
	if !value.contains(r'${') {
		return &Expr{ kind: .literal, value: value, line: line, quoted: true }
	}
	mut parts := []InterpolationPart{}
	mut cursor := 0
	for cursor < value.len {
		start_relative := value[cursor..].index(r'${') or {
			parts << InterpolationPart{ text: value[cursor..] }
			break
		}
		start := cursor + start_relative
		if start > cursor {
			parts << InterpolationPart{ text: value[cursor..start] }
		}
		end := interpolation_end(value, start + 2) or {
			return error('unterminated interpolation at line ${line}')
		}
		fragment := value[start + 2..end]
		mut tokens := tokenize(fragment) or {
			return error('${token.line}:${token.column}: invalid interpolation: ${err}')
		}
		mut line_starts := [0]
		for offset, ch in fragment {
			if ch == `\n` { line_starts << offset + 1 }
		}
		// Decoded escapes can introduce newlines that do not exist in the file.
		// Map fragment tokens back to the original string bytes, including nested
		// strings, before parsing their expressions.
		for index, part_token in tokens {
			location := token.string_locations[start + 2 + line_starts[part_token.line - 1] + part_token.column - 1]
			mut nested_locations := []Location{cap: part_token.string_locations.len}
			for nested in part_token.string_locations {
				nested_locations << token.string_locations[start + 2 + line_starts[nested.line - 1] + nested.column - 1]
			}
			tokens[index] = Token{ ...part_token, line: location.line, column: location.column, string_locations: nested_locations }
		}
		mut parser := Parser{ tokens: tokens }
		parts << InterpolationPart{ expr: parser.parse_expression()! }
		parser.take(.eof) or { return error('invalid interpolation at line ${line}: ${err}') }
		cursor = end + 1
	}
	return &Expr{ kind: .interpolation, line: line, parts: parts }
}
