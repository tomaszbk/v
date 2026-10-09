module parser

import os
import strings
import v.flat

enum VmlTokenKind {
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
	ne
	lt
	le
	gt
	ge
	and
	or
	eof
}

struct VmlToken {
	kind             VmlTokenKind
	text             string
	line             int
	column           int = 1
	string_locations []VmlLocation
}

struct VmlLexer {
	source string
mut:
	pos        int
	line       int = 1
	line_start int
}

fn (mut l VmlLexer) advance() u8 {
	c := l.source[l.pos]
	l.pos++
	if c == `\n` {
		l.line++
		l.line_start = l.pos
	}
	return c
}

fn (mut l VmlLexer) skip_space() {
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

fn vml_is_name_char(c u8) bool {
	return c.is_alnum() || c in [`_`, `.`, `#`]
}

fn (mut l VmlLexer) read_name() VmlToken {
	start := l.pos
	line := l.line
	column := l.pos - l.line_start + 1
	for l.pos < l.source.len && vml_is_name_char(l.source[l.pos]) {
		l.pos++
	}
	return VmlToken{ kind: .name, text: l.source[start..l.pos], line: line, column: column }
}

fn (mut l VmlLexer) read_number() VmlToken {
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
	return VmlToken{ kind: .number, text: l.source[start..l.pos], line: line, column: column }
}

fn (mut l VmlLexer) read_string() !VmlToken {
	line := l.line
	column := l.pos - l.line_start + 1
	quote := l.advance()
	mut value := []u8{}
	mut locations := []VmlLocation{}
	for l.pos < l.source.len {
		location := VmlLocation{ line: l.line, column: l.pos - l.line_start + 1 }
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
			return VmlToken{ kind: .string_, text: value.bytestr(), line: line, column: column, string_locations: locations }
		} else {
			value << c
		}
		locations << location
	}
	return error('unterminated string at line ${line}')
}

fn tokenize_vml(source string) ![]VmlToken {
	mut lexer := VmlLexer{ source: source }
	mut tokens := []VmlToken{}
	for {
		lexer.skip_space()
		if lexer.pos >= source.len {
			tokens << VmlToken{ kind: .eof, text: '', line: lexer.line, column: lexer.pos - lexer.line_start + 1 }
			return tokens
		}
		line := lexer.line
		column := lexer.pos - lexer.line_start + 1
		c := source[lexer.pos]
		match c {
			`{` { tokens << VmlToken{ kind: .lbrace, text: '{', line: line, column: column } }
			`}` { tokens << VmlToken{ kind: .rbrace, text: '}', line: line, column: column } }
			`:` { tokens << VmlToken{ kind: .colon, text: ':', line: line, column: column } }
			`(` { tokens << VmlToken{ kind: .lpar, text: '(', line: line, column: column } }
			`)` { tokens << VmlToken{ kind: .rpar, text: ')', line: line, column: column } }
			`,` { tokens << VmlToken{ kind: .comma, text: ',', line: line, column: column } }
			`?` { tokens << VmlToken{ kind: .question, text: '?', line: line, column: column } }
			`+` { tokens << VmlToken{ kind: .plus, text: '+', line: line, column: column } }
			`-` { tokens << VmlToken{ kind: .minus, text: '-', line: line, column: column } }
			`*` { tokens << VmlToken{ kind: .mul, text: '*', line: line, column: column } }
			`/` { tokens << VmlToken{ kind: .div, text: '/', line: line, column: column } }
			`%` { tokens << VmlToken{ kind: .mod, text: '%', line: line, column: column } }
			`!` {
				lexer.pos++
				if lexer.pos < source.len && source[lexer.pos] == `=` {
					tokens << VmlToken{ kind: .ne, text: '!=', line: line, column: column }
				} else {
					tokens << VmlToken{ kind: .not, text: '!', line: line, column: column }
					continue
				}
			}
			`=` {
				lexer.pos++
				if lexer.pos >= source.len || source[lexer.pos] != `=` {
					tokens << VmlToken{ kind: .assign, text: '=', line: line, column: column }
					continue
				}
				tokens << VmlToken{ kind: .eq, text: '==', line: line, column: column }
			}
			`<` {
				lexer.pos++
				if lexer.pos < source.len && source[lexer.pos] == `=` {
					tokens << VmlToken{ kind: .le, text: '<=', line: line, column: column }
				} else {
					tokens << VmlToken{ kind: .lt, text: '<', line: line, column: column }
					continue
				}
			}
			`>` {
				lexer.pos++
				if lexer.pos < source.len && source[lexer.pos] == `=` {
					tokens << VmlToken{ kind: .ge, text: '>=', line: line, column: column }
				} else {
					tokens << VmlToken{ kind: .gt, text: '>', line: line, column: column }
					continue
				}
			}
			`&` {
				lexer.pos++
				if lexer.pos >= source.len || source[lexer.pos] != `&` {
					return error('expected `&&` at line ${line}')
				}
				tokens << VmlToken{ kind: .and, text: '&&', line: line, column: column }
			}
			`|` {
				lexer.pos++
				if lexer.pos >= source.len || source[lexer.pos] != `|` {
					return error('expected `||` at line ${line}')
				}
				tokens << VmlToken{ kind: .or, text: '||', line: line, column: column }
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
				if vml_is_name_char(c) {
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

enum VmlExprKind {
	literal
	path
	call
	unary
	binary
	assignment
	conditional
	interpolation
}

struct VmlInterpolationPart {
	text string
	// A nil expression marks a literal-text part. V requires `unsafe` only to
	// declare that sentinel pointer default; interpolation logic checks it before use.
	expr &VmlExpr = unsafe { nil }
}

struct VmlExpr {
	kind  VmlExprKind
	value string
	line  int
mut:
	column int = 1
	source string
	// The tagged expression tree is recursive. Nil marks child links unused by
	// the current kind, and V requires `unsafe` only for those pointer defaults.
	left   &VmlExpr = unsafe { nil }
	right  &VmlExpr = unsafe { nil }
	third  &VmlExpr = unsafe { nil }
	args   []&VmlExpr
	parts  []VmlInterpolationPart
	quoted bool
}

struct VmlProperty {
	name          string
	declared_type string
	expr          &VmlExpr
}

struct VmlNode {
	tag    string
	line   int
	column int = 1
mut:
	source     string
	imported   bool
	import_id  bool
	id         string
	properties []VmlProperty
	children   []&VmlNode
}

struct VmlSourceParser {
	file   string
	tokens []VmlToken
mut:
	pos int
}

fn (p &VmlSourceParser) at() VmlToken {
	return if p.pos < p.tokens.len {
		p.tokens[p.pos]
	} else {
		VmlToken{ kind: .eof, text: '', line: 0, column: 1 }
	}
}

fn (mut p VmlSourceParser) take(kind VmlTokenKind) !VmlToken {
	token := p.at()
	if token.kind != kind {
		return error('${p.file}:${token.line}:${token.column}: expected ${kind}, got ${token.kind} (`${token.text}`)')
	}
	p.pos++
	return token
}

fn (mut p VmlSourceParser) parse_node() !&VmlNode {
	tag := p.take(.name)!
	p.take(.lbrace)!
	mut node := &VmlNode{ tag: tag.text, line: tag.line, column: tag.column }
	for p.at().kind !in [.rbrace, .eof] {
		if p.at().kind != .name {
			return error('unexpected token `${p.at().text}` at line ${p.at().line}')
		}
		if p.at().text == 'property' {
			p.pos++
			typ := p.take(.name)!
			name := p.take(.name)!
			if node.properties.any(it.name == name.text) {
				return error('duplicate VML property `${name.text}` at line ${name.line}:${name.column}')
			}
			p.take(.colon)!
			node.properties << VmlProperty{ name: name.text, declared_type: typ.text, expr: p.parse_expression()! }
		} else if p.pos + 1 < p.tokens.len && p.tokens[p.pos + 1].kind == .lbrace {
			node.children << p.parse_node()!
		} else if p.pos + 1 < p.tokens.len && p.tokens[p.pos + 1].kind == .colon {
			name := p.take(.name)!
			if node.properties.any(it.name == name.text) {
				return error('duplicate VML property `${name.text}` at line ${name.line}:${name.column}')
			}
			p.take(.colon)!
			expr := if vml_is_event(name.text) {
				p.parse_assignment()!
			} else {
				p.parse_expression()!
			}
			if name.text == 'id' {
				if expr.kind !in [.literal, .path] {
					return error('id must be a literal identifier at line ${name.line}')
				}
				node.id = expr.value
			}
			node.properties << VmlProperty{ name: name.text, expr: expr }
		} else {
			return error('unexpected token `${p.at().text}` at line ${p.at().line}')
		}
	}
	p.take(.rbrace)!
	return node
}

const vml_event_names = ['on_tap', 'on_change', 'on_active', 'on_submit', 'on_scroll', 'on_pointer_down',
	'on_pointer_drag', 'on_pointer_up', 'on_long_press', 'on_swipe_left', 'on_link']

fn vml_is_event(name string) bool {
	return name in vml_event_names
}

fn (mut p VmlSourceParser) parse_assignment() !&VmlExpr {
	left := p.parse_expression()!
	if p.at().kind != .assign { return left }
	op := p.take(.assign)!
	return &VmlExpr{ kind: .assignment, line: op.line, column: op.column, left: left, right: p.parse_expression()! }
}

fn (mut p VmlSourceParser) parse_expression() !&VmlExpr {
	return p.parse_conditional()
}

fn (mut p VmlSourceParser) parse_conditional() !&VmlExpr {
	condition := p.parse_or()!
	if p.at().kind != .question {
		return condition
	}
	line := p.take(.question)!.line
	when_true := p.parse_expression()!
	p.take(.colon)!
	return &VmlExpr{
		kind:  .conditional
		line:  line
		left:  condition
		right: when_true
		third: p.parse_expression()!
	}
}

fn (mut p VmlSourceParser) parse_or() !&VmlExpr {
	mut left := p.parse_and()!
	for p.at().kind == .or {
		op := p.at()
		p.pos++
		left = &VmlExpr{
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

fn (mut p VmlSourceParser) parse_and() !&VmlExpr {
	mut left := p.parse_equality()!
	for p.at().kind == .and {
		op := p.at()
		p.pos++
		left = &VmlExpr{
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

fn (mut p VmlSourceParser) parse_equality() !&VmlExpr {
	mut left := p.parse_comparison()!
	for p.at().kind in [.eq, .ne] {
		op := p.at()
		p.pos++
		left = &VmlExpr{
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

fn (mut p VmlSourceParser) parse_comparison() !&VmlExpr {
	mut left := p.parse_term()!
	for p.at().kind in [.lt, .le, .gt, .ge] {
		op := p.at()
		p.pos++
		left = &VmlExpr{
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

fn (mut p VmlSourceParser) parse_term() !&VmlExpr {
	mut left := p.parse_factor()!
	for p.at().kind in [.plus, .minus] {
		op := p.at()
		p.pos++
		left = &VmlExpr{
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

fn (mut p VmlSourceParser) parse_factor() !&VmlExpr {
	mut left := p.parse_unary()!
	for p.at().kind in [.mul, .div, .mod] {
		op := p.at()
		p.pos++
		left = &VmlExpr{
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

fn (mut p VmlSourceParser) parse_unary() !&VmlExpr {
	if p.at().kind in [.not, .minus] {
		op := p.at()
		p.pos++
		return &VmlExpr{ kind: .unary, value: op.text, line: op.line, column: op.column, left: p.parse_unary()! }
	}
	return p.parse_primary()
}

fn (mut p VmlSourceParser) parse_primary() !&VmlExpr {
	token := p.at()
	match token.kind {
		.string_ {
			p.pos++
			mut expr := parse_vml_interpolation(token)!
			expr.column = token.column
			return expr
		}
		.name, .number {
			p.pos++
			if p.at().kind == .lpar {
				p.pos++
				mut args := []&VmlExpr{}
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
				return &VmlExpr{ kind: .call, value: token.text, line: token.line, column: token.column, args: args }
			}
			return &VmlExpr{
				kind:   if token.kind == .number || token.text in ['true', 'false'] {
					VmlExprKind.literal
				} else {
					VmlExprKind.path
				}
				value:  token.text
				line:   token.line
				column: token.column
			}
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

fn vml_interpolation_end(value string, start int) ?int {
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

fn parse_vml_interpolation(token VmlToken) !&VmlExpr {
	value := token.text
	line := token.line
	if !value.contains(r'${') {
		return &VmlExpr{ kind: .literal, value: value, line: line, quoted: true }
	}
	mut parts := []VmlInterpolationPart{}
	mut cursor := 0
	for cursor < value.len {
		start_relative := value[cursor..].index(r'${') or {
			parts << VmlInterpolationPart{ text: value[cursor..] }
			break
		}
		start := cursor + start_relative
		if start > cursor {
			parts << VmlInterpolationPart{ text: value[cursor..start] }
		}
		end := vml_interpolation_end(value, start + 2) or {
			return error('unterminated interpolation at line ${line}')
		}
		fragment := value[start + 2..end]
		mut tokens := tokenize_vml(fragment) or {
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
			mut nested_locations := []VmlLocation{cap: part_token.string_locations.len}
			for nested in part_token.string_locations {
				nested_locations << token.string_locations[start + 2 + line_starts[nested.line - 1] + nested.column - 1]
			}
			tokens[index] = VmlToken{ ...part_token, line: location.line, column: location.column, string_locations: nested_locations }
		}
		mut parser := VmlSourceParser{ tokens: tokens }
		parts << VmlInterpolationPart{ expr: parser.parse_expression()! }
		parser.take(.eof) or { return error('invalid interpolation at line ${line}: ${err}') }
		cursor = end + 1
	}
	return &VmlExpr{ kind: .interpolation, line: line, parts: parts }
}

fn parse_vml_source(source string) !&VmlNode {
	tokens := tokenize_vml(source)!
	mut parser := VmlSourceParser{ tokens: tokens }
	root := parser.parse_node()!
	parser.take(.eof)!
	validate_compiled_vml_node(root)!
	return root
}

fn validate_compiled_vml_node(node &VmlNode) ! {
	if node.tag in ['TextField', 'TextArea', 'ScrollView'] {
		return error('${node.source}:${node.line}:${node.column}: removed widget `${node.tag}`; use TextInput or Scroll')
	}
	mut bindings := 0
	for property in node.properties {
		if property.name in ['hint_text', 'on_text_validate', 'editable', 'emit_change'] {
			return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: removed widget property `${property.name}`')
		}
		if property.name.starts_with('on_') && !vml_is_event(property.name) {
			return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: unsupported VML event `${property.name}`')
		}
		if property.name.starts_with('bind.') {
			bindings++
			bound_property := property.name.all_after('bind.')
			if bound_property !in ['text', 'checked', 'active', 'value'] {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: two-way binding is not supported for `${bound_property}`')
			}
			if property.expr.kind != .path || !property.expr.value.starts_with('app.')
				|| property.expr.value.count('.') != 1 {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: `${property.name}` must target a mutable top-level app field')
			}
		}
		if vml_is_event(property.name)
			&& property.expr.kind == .call {
			if !property.expr.value.starts_with('app.') || property.expr.value.count('.') != 1 {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: event handlers must call an app action')
			}
			if property.expr.args.len > 1 {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: app actions support at most one argument')
			}
		}
		if vml_is_event(property.name) && property.expr.kind == .assignment {
			left := property.expr.left
			if left.kind != .path || !left.value.starts_with('app.') || left.value.count('.') != 1 {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: event assignments must target a mutable top-level app field')
			}
		}
	}
	if bindings > 1 {
		return error('${node.source}:${node.line}:${node.column}: an element can only have one two-way binding')
	}
	if node.tag == 'Repeater' {
		for property in node.properties {
			if property.name !in ['model', 'key'] {
				return error('${property.expr.source}:${property.expr.line}:${property.expr.column}: unsupported `${property.name}` on Repeater')
			}
		}
		if vml_find_property(node, 'model') == none {
			return error('${node.source}:${node.line}:${node.column}: Repeater requires `model`')
		}
		if vml_find_property(node, 'key') == none {
			return error('${node.source}:${node.line}:${node.column}: Repeater requires a stable `key`')
		}
	}
	for child in node.children {
		validate_compiled_vml_node(child)!
	}
}

fn vml_expr_text(expr &VmlExpr) string {
	return match expr.kind {
		.literal, .path { expr.value }
		.call { expr.value + '(' + expr.args.map(vml_expr_text(it)).join(', ') + ')' }
		.unary { expr.value + vml_expr_text(expr.left) }
		.binary { '${vml_expr_text(expr.left)} ${expr.value} ${vml_expr_text(expr.right)}' }
		.assignment { '${vml_expr_text(expr.left)} = ${vml_expr_text(expr.right)}' }
		.conditional {
			'${vml_expr_text(expr.left)} ? ${vml_expr_text(expr.right)} : ${vml_expr_text(expr.third)}'
		}
		.interpolation {
			mut value := ''
			for part in expr.parts {
				value += if isnil(part.expr) {
					part.text
				} else {
					r'${' + vml_expr_text(part.expr) + '}'
				}
			}
			value
		}
	}
}

// parse_vml_template_expr compiles `$vml('file.vml')` into a direct ui2.Element builder.
fn (mut p Parser) parse_vml_template_expr(call_start int) flat.NodeId {
	p.next() // vml
	if p.tok != .lpar {
		p.record_diagnostic('expected `(` after `\$vml`', p.tok_pos)
		return p.add_val_id(5, '')
	}
	p.next()
	arg_id := p.expr(.lowest)
	arg := p.resolve_tmpl_path_arg(arg_id)
	for p.tok != .rpar && p.tok != .eof && p.tok != .semicolon {
		p.next()
	}
	if p.tok == .rpar {
		p.next()
	}
	if arg.len == 0 {
		p.record_diagnostic('`\$vml()` path must be a compile-time string', call_start)
		return p.add_val_id(5, '')
	}
	path := p.resolve_veb_template_path(false, arg)
	if !os.exists(path) {
		p.record_diagnostic('VML file `${path}` does not exist', call_start)
		return p.add_val_id(5, '')
	}
	root := parse_compiled_vml_file(path, '', []) or {
		p.record_diagnostic(err.msg().replace(os.real_path(os.getwd()) + os.path_separator, ''), call_start)
		return p.add_val_id(5, '')
	}
	source_file := p.a.source_files[p.cur_file_id] or { return p.add_val_id(5, '') }
	mut compiler := VmlCompiler{
		uses_app:     vml_node_uses_path(root, 'app')
		guard_prefix: 'vml_check_${source_file.name.hash()}_${call_start}'
	}
	generated := compiler.compile(root)
	first_node := p.a.nodes.len
	first_diagnostic := p.diagnostics.len
	template := flat.Node{
		value: path
		pos:   p.span_to(call_start)
	}
	mut source_lines := []TemplateSourceLine{}
	mut source_paths := map[string]bool{}
	for location in compiler.locations {
		if location.path !in source_paths {
			source_paths[location.path] = true
			source_lines << TemplateSourceLine{ path: location.path, line: 1 }
		}
	}
	saved_fn := p.cur_fn
	p.cur_fn = ''
	stmts := p.parse_stmts_from_source('_ = ${generated}', path, template.pos, source_lines)
	p.cur_fn = saved_fn
	mut result := flat.empty_node
	if stmts.len > 0 {
		statement := p.a.node(stmts[0])
		if statement.kind == .assign && statement.children_count == 2 {
			result = p.a.child(statement, 1)
		}
		for declaration_id in stmts[1..] {
			// The guard belongs to the calling V module; its body retains VML locations.
			declaration := p.a.node(declaration_id)
			p.a.nodes[int(declaration_id)] = flat.Node{ ...declaration, pos: template.pos }
			p.vml_declarations << declaration_id
		}
	}
	if int(result) < 0 {
		p.record_diagnostic('could not lower VML file `${path}`', call_start)
		result = p.add_val_id(5, '')
	}
	p.remap_vml_source(first_node, first_diagnostic, compiler.locations)
	return result
}

fn vml_node_uses_path(node &VmlNode, base string) bool {
	for property in node.properties {
		if vml_expr_uses_path(property.expr, base) {
			return true
		}
	}
	for child in node.children {
		if vml_node_uses_path(child, base) {
			return true
		}
	}
	return false
}

fn vml_expr_uses_path(expr &VmlExpr, base string) bool {
	if expr.kind in [.path, .call] && (expr.value == base || expr.value.starts_with(base + '.')) {
		return true
	}
	if !isnil(expr.left) && vml_expr_uses_path(expr.left, base) {
		return true
	}
	if !isnil(expr.right) && vml_expr_uses_path(expr.right, base) {
		return true
	}
	if !isnil(expr.third) && vml_expr_uses_path(expr.third, base) {
		return true
	}
	for arg in expr.args {
		if vml_expr_uses_path(arg, base) {
			return true
		}
	}
	for part in expr.parts {
		if !isnil(part.expr) && vml_expr_uses_path(part.expr, base) {
			return true
		}
	}
	return false
}

struct VmlNamedValue {
	frame string
	props map[string]string
}

struct VmlScope {
mut:
	ids     map[string]VmlNamedValue
	special map[string]string
}

struct VmlGuard {
	field_name string
	model_path string
	name       string
	array      bool
	location   VmlLocation
}

struct VmlCompiler {
	guard_prefix string
	uses_app     bool
mut:
	guards    []VmlGuard
	out       strings.Builder
	location  VmlLocation
	locations []VmlLocation
}

fn (mut c VmlCompiler) compile(root &VmlNode) string {
	c.out = strings.new_builder(4096)
	c.location = VmlLocation{ path: root.source, line: root.line, column: root.column }
	c.writeln('')
	if root.tag in ['Menu', 'MenuBar'] { return c.compile_menus(root) }
	c.location = VmlLocation{ path: root.source, line: root.line, column: root.column }
	capture := if c.uses_app { '[mut app] ' } else { '' }
	c.writeln('(fn ${capture}() ui2.Element {')
	c.writeln('\tvml_input_0 := ui2.bounds()')
	scope := VmlScope{
		ids:     map[string]VmlNamedValue{}
		special: map[string]string{}
	}
	c.compile_node(root, '0', 'vml_input_0', scope, '')
	c.writeln('\tui2.validate_element_tree(vml_element_0) or { panic(' + vml_quote(root.source + ':' + root.line.str() + ': ') + ' + err.msg()) }')
	c.writeln('\treturn vml_element_0')
	c.writeln('}())')
	c.write_list_guards()
	return c.out.str()
}

fn vml_clone_scope(scope VmlScope) VmlScope {
	return VmlScope{
		ids:     scope.ids.clone()
		special: scope.special.clone()
	}
}

fn vml_var(path string) string {
	return path.replace('.', '_').replace('-', '_')
}

fn vml_quote(value string) string {
	return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(r'$', r'\$') + "'"
}

fn vml_interpolation_text(value string) string {
	return value.replace('\\', '\\\\').replace("'", "\\'").replace('\n', '\\n').replace('\r', '\\r').replace('\t', '\\t').replace(r'$', r'\$')
}

fn vml_stringify(expression string) string {
	return "'" + r'$' + '{' + expression + "}'"
}

fn vml_color_call(expression string) string {
	value := vml_stringify(expression)
	return "(if typeof(${expression}).name == 'string' { ui2.parse_hex_color(${value}) } else { u32(${value}.u64()) })"
}

fn vml_numeric_cast(type_name string, expression string) string {
	if expression.starts_with('(') && expression.ends_with(')') {
		return type_name + expression
	}
	return '${type_name}(${expression})'
}

enum VmlExprUse {
	raw
	number
	string_
	bool_
	color
}

fn vml_property_use(property VmlProperty) VmlExprUse {
	if property.declared_type.len > 0 {
		return match property.declared_type {
			'f64', 'f32', 'int' { .number }
			'bool' { .bool_ }
			'string' { .string_ }
			'color' { .color }
			else { .raw }
		}
	}
	if property.name in ['x', 'y', 'width', 'height', 'padding', 'spacing', 'corner_radius', 'radius',
		'rotation', 'font_size', 'size', 'head_indent', 'first_line_indent', 'hyphenation_factor',
		'lines', 'pad_left', 'dialog_width', 'dialog_height', 'border_width', 'border_left',
		'border_top', 'border_right', 'border_bottom', 'value', 'min', 'max', 'step', 'track_width',
		'thumb_size'] {
		return .number
	}
	if property.name in ['background', 'color', 'background_color', 'border_color', 'value_track_color',
		'thumb_color', 'inactive_color', 'active_color', 'disabled_track_color', 'disabled_thumb_color'] {
		return .color
	}
	if property.name in ['checked', 'hidden', 'enabled', 'native', 'multiline', 'password', 'readonly',
		'disable_scroll', 'secure', 'clickable', 'draggable', 'long_press', 'swipe_left', 'persistent',
		'autocorrect', 'bold', 'italic', 'underline', 'strikethrough', 'shadow', 'outline',
		'value_track', 'active', 'text_autoupdate']
		|| property.name in ['bind.checked', 'bind.active'] {
		return .bool_
	}
	if property.name == 'bind.value' {
		return .number
	}
	if property.name == 'model' {
		return .raw
	}
	return .string_
}

fn vml_expr_is_string(expr &VmlExpr) bool {
	if expr.kind == .interpolation || (expr.kind == .literal && expr.quoted) {
		return true
	}
	if expr.kind == .conditional {
		return vml_expr_is_string(expr.right) || vml_expr_is_string(expr.third)
	}
	return false
}

fn (c &VmlCompiler) resolve_path(path string, scope VmlScope) (string, bool) {
	parts := path.split('.')
	if parts.len == 0 {
		return path, false
	}
	if replacement := scope.special[parts[0]] {
		return replacement + if parts.len > 1 { '.' + parts[1..].join('.') } else { '' }, true
	}
	if named := scope.ids[parts[0]] {
		if parts.len >= 2 {
			if prop := named.props[parts[1]] {
				return prop + if parts.len > 2 { '.' + parts[2..].join('.') } else { '' }, true
			}
		}
		if parts.len == 2 {
			if parts[1] in ['x', 'y', 'width', 'height'] {
				return '${named.frame}.${parts[1]}', true
			}
		}
	}
	return path, path.contains('.')
}

fn (c &VmlCompiler) expr(expr &VmlExpr, scope VmlScope, use VmlExprUse) string {
	match expr.kind {
		.literal {
			if expr.quoted {
				if use == .color {
					if expr.value.starts_with('#') && expr.value.len == 7 {
						return 'u32(0x${expr.value[1..]})'
					}
					return 'ui2.parse_hex_color(${vml_quote(expr.value)})'
				}
				return vml_quote(expr.value)
			}
			return match use {
				.string_ { vml_quote(expr.value) }
				.number { 'f64(${expr.value})' }
				else { expr.value }
			}
		}
		.path {
			resolved, _ := c.resolve_path(expr.value, scope)
			if use == .color {
				if expr.value.starts_with('#') && expr.value.len == 7 {
					return 'u32(0x${expr.value[1..]})'
				}
				return vml_color_call(resolved)
			}
			if use == .string_ {
				return vml_stringify(resolved)
			}
			if use == .number {
				return 'f64(${resolved})'
			}
			return resolved
		}
		.call {
			args := expr.args.map(c.expr(it, scope, .raw)).join(', ')
			resolved, _ := c.resolve_path(expr.value, scope)
			call := '${resolved}(${args})'
			return match use {
				.string_ { vml_stringify(call) }
				.number { 'f64(${call})' }
				.color { vml_color_call(call) }
				else { call }
			}
		}
		.unary {
			operand_use := if use in [.raw, .string_] {
				VmlExprUse.raw
			} else if expr.value == '!' {
				VmlExprUse.bool_
			} else {
				VmlExprUse.number
			}
			result := '(${expr.value}${c.expr(expr.left, scope, operand_use)})'
			return if use == .string_ { vml_stringify(result) } else { result }
		}
		.binary {
			if use == .raw {
				return '(${c.expr(expr.left, scope, .raw)} ${expr.value} ${c.expr(expr.right, scope, .raw)})'
			}
			if expr.value in ['&&', '||'] {
				result := '(${c.expr(expr.left, scope, .bool_)} ${expr.value} ${c.expr(expr.right, scope, .bool_)})'
				return if use == .string_ { vml_stringify(result) } else { result }
			}
			if expr.value in ['==', '!=', '<', '<=', '>', '>='] {
				operand_use := if vml_expr_is_string(expr.left) || vml_expr_is_string(expr.right) {
					VmlExprUse.string_
				} else {
					VmlExprUse.raw
				}
				result := '(${c.expr(expr.left, scope, operand_use)} ${expr.value} ${c.expr(expr.right, scope, operand_use)})'
				return if use == .string_ { vml_stringify(result) } else { result }
			}
			if expr.value == '+' && use == .string_ {
				if vml_expr_is_string(expr.left) || vml_expr_is_string(expr.right) {
					return '(${c.expr(expr.left, scope, .string_)} + ${c.expr(expr.right, scope, .string_)})'
				}
				return vml_stringify('(${c.expr(expr.left, scope, .raw)} + ${c.expr(expr.right, scope, .raw)})')
			}
			if use == .string_ && expr.value in ['-', '*', '/', '%'] {
				return vml_stringify('(${c.expr(expr.left, scope, .raw)} ${expr.value} ${c.expr(expr.right, scope, .raw)})')
			}
			if expr.value == '%' {
				return 'f64(int(${c.expr(expr.left, scope, .number)}) % int(${c.expr(expr.right, scope, .number)}))'
			}
			return '(${c.expr(expr.left, scope, .number)} ${expr.value} ${c.expr(expr.right, scope, .number)})'
		}
		.conditional {
			condition_use := if use == .raw { VmlExprUse.raw } else { VmlExprUse.bool_ }
			return '(if ${c.expr(expr.left, scope, condition_use)} { ${c.expr(expr.right, scope, use)} } else { ${c.expr(expr.third, scope, use)} })'
		}
		.assignment { return c.expr(expr.right, scope, .raw) }
		.interpolation {
			mut value := "'"
			for part in expr.parts {
				if isnil(part.expr) {
					value += vml_interpolation_text(part.text)
				} else {
					value += r'$' + '{' + c.expr(part.expr, scope, .raw) + '}'
				}
			}
			return value + "'"
		}
	}
}

fn vml_find_property(node &VmlNode, name string) ?VmlProperty {
	for property in node.properties {
		if property.name == name {
			return property
		}
	}
	return none
}

fn vml_prop(properties map[string]string, name string, default_ string) string {
	return properties[name] or { default_ }
}

fn vml_property_is_geometry(property VmlProperty) bool {
	return property.name in ['x', 'y', 'width', 'height']
}

fn vml_order_properties_by_dependencies(properties []VmlProperty, node_id string) []VmlProperty {
	mut remaining := properties.clone()
	if node_id.len == 0 || remaining.len < 2 {
		return remaining
	}
	mut ordered := []VmlProperty{cap: remaining.len}
	for remaining.len > 0 {
		mut deferred := []VmlProperty{cap: remaining.len}
		for property in remaining {
			mut has_pending_dependency := false
			for candidate in remaining {
				if candidate.name != property.name
					&& vml_expr_uses_path(property.expr, '${node_id}.${candidate.name}') {
					has_pending_dependency = true
					break
				}
			}
			if has_pending_dependency {
				deferred << property
			} else {
				ordered << property
			}
		}
		if deferred.len == remaining.len {
			// Preserve source order for a dependency cycle; generated V will report
			// the invalid forward reference without making this pass loop forever.
			ordered << deferred
			break
		}
		remaining = deferred.clone()
	}
	return ordered
}

fn (mut c VmlCompiler) compile_node(node &VmlNode, path string, input string, incoming VmlScope, default_key string) VmlScope {
	suffix := vml_var(path)
	c.location = VmlLocation{ path: node.source, line: node.line, column: node.column }
	c.writeln('\t_ = ${input}')
	mut scope := vml_clone_scope(incoming)
	if node.imported {
		scope.special['__import_parent'] = scope.special['__import'] or { '' }
		scope.special['__import'] = suffix
	}
	mut named_props := map[string]string{}
	// Declared properties are visible before expressions are resolved. Geometry
	// bindings are added after they are emitted below, so self-geometry can use an
	// earlier computed binding while declared properties can still read the input.
	for property in node.properties {
		if property.declared_type.len > 0 {
			named_props[property.name] = 'vml_property_${suffix}_${vml_var(property.name)}'
		}
	}
	if node.id.len > 0 {
		scope.ids[node.id] = VmlNamedValue{ frame: input, props: named_props.clone() }
	}
	mut properties := map[string]string{}
	mut ordered_properties := vml_order_properties_by_dependencies(node.properties.filter(it.declared_type.len > 0), node.id)
	ordered_properties << vml_order_properties_by_dependencies(node.properties.filter(it.declared_type.len == 0
		&& vml_property_is_geometry(it)), node.id)
	ordered_properties << node.properties.filter(it.declared_type.len == 0
		&& !vml_property_is_geometry(it))
	for property in ordered_properties {
		c.location = VmlLocation{ path: property.expr.source, line: property.expr.line, column: property.expr.column }
		if property.name == 'id'
			|| property.name in vml_event_names {
			continue
		}
		name := 'vml_property_${suffix}_${vml_var(property.name)}'
		property_use := vml_property_use(property)
		value := if property.declared_type == 'int' {
			numeric_value := c.expr(property.expr, scope, .raw)
			vml_numeric_cast(property.declared_type, numeric_value)
		} else if property.declared_type == 'f32' {
			numeric_value := c.expr(property.expr, scope, .number)
			vml_numeric_cast(property.declared_type, numeric_value)
		} else {
			c.expr(property.expr, scope, property_use)
		}
		if property.declared_type.len == 0 && property_use == .color
			&& property.expr.kind in [.literal, .path]
			&& property.expr.value.starts_with('#') && property.expr.value.len == 7 {
			// Static colors can be used directly without a generated local.
			properties[property.name] = value
			continue
		}
		c.writeln('\t${name} := ${value}')
		properties[property.name] = name
		if property.declared_type.len == 0 && vml_property_is_geometry(property) {
			named_props[property.name] = name
			if node.id.len > 0 {
				scope.ids[node.id] = VmlNamedValue{ frame: input, props: named_props.clone() }
			}
		}
	}
	frame := 'vml_frame_${suffix}'
	c.writeln('\t${frame} := ui2.rect(${vml_prop(properties, 'x', input + '.x')}, ${vml_prop(properties, 'y', input + '.y')}, ${vml_prop(properties, 'width', input + '.width')}, ${vml_prop(properties, 'height', input + '.height')})')
	if node.id.len > 0 {
		scope.ids[node.id] = VmlNamedValue{ frame: frame, props: named_props.clone() }
	}
	c.write_action_type_checks(node, suffix, scope)
	children := 'vml_children_${suffix}'
	container := node.tag in ['Screen', 'View', 'Rectangle', 'Column', 'Row', 'Scroll']
		|| node.tag !in ['Label', 'Image', 'Button', 'MessageBox', 'Checkbox', 'Dropdown', 'TextInput',
			'ProgressBar', 'Slider', 'Switch', 'Spinner']
	visible_children := if container {
		node.children.filter(it.tag !in ['MenuItem', 'Option'])
	} else {
		[]&VmlNode{}
	}
	if container {
		c.writeln('\tmut ${children} := []ui2.Element{cap: ${visible_children.len}}')
	}
	mut cursor := ''
	if container && node.tag in ['Column', 'Row'] {
		cursor = 'vml_cursor_${suffix}'
		c.writeln('\tmut ${cursor} := ${vml_prop(properties, 'padding', 'f64(0)')}')
	}
	for child_index, child in node.children {
		child_path := '${path}.${child_index}'
		if child.tag == 'MenuItem' {
			c.write_action_type_checks(child, '${vml_var(child_path)}_menu_action', scope)
			continue
		}
		if !container || child.tag == 'Option' {
			continue
		}
		if child.tag == 'Repeater' {
			c.compile_repeater(child, child_path, frame, node.tag, properties, cursor, scope, children, scope.special['__repeat_identity'] or { '' }, false)
			continue
		}
		child_input := 'vml_input_${vml_var(child_path)}'
		c.writeln('\t${child_input} := ${vml_child_input(node.tag, frame, properties, cursor)}')
		child_scope := c.compile_node(child, child_path, child_input, scope, '')
		for id, named in child_scope.ids {
			scope.ids[id] = named
		}
		c.writeln('\t${children} << vml_element_${vml_var(child_path)}')
		vml_advance_cursor(mut c, node.tag, cursor, child_path, properties)
	}
	c.location = VmlLocation{ path: node.source, line: node.line, column: node.column }
	c.compile_element(node, suffix, frame, children, properties, scope, default_key)
	if node.imported {
		mut exported := vml_clone_scope(incoming)
		if node.id.len > 0 { exported.ids[node.id] = scope.ids[node.id] }
		return exported
	}
	return scope
}

fn vml_child_input(tag string, frame string, properties map[string]string, cursor string) string {
	padding := vml_prop(properties, 'padding', 'f64(0)')
	return match tag {
		'Column' {
			'ui2.rect(${padding}, ${cursor}, ${frame}.width - ${padding} * f64(2), f64(32))'
		}
		'Row' {
			'ui2.rect(${cursor}, ${padding}, f64(80), ${frame}.height - ${padding} * f64(2))'
		}
		else { 'ui2.rect(f64(0), f64(0), ${frame}.width, ${frame}.height)' }
	}
}

fn vml_advance_cursor(mut c VmlCompiler, tag string, cursor string, child_path string, properties map[string]string) {
	spacing := vml_prop(properties, 'spacing', 'f64(0)')
	if tag == 'Column' {
		c.writeln('\t${cursor} += vml_frame_${vml_var(child_path)}.height + ${spacing}')
	} else if tag == 'Row' {
		c.writeln('\t${cursor} += vml_frame_${vml_var(child_path)}.width + ${spacing}')
	}
}

fn (mut c VmlCompiler) compile_repeater(node &VmlNode, path string, parent_frame string, parent_tag string, parent_properties map[string]string, cursor string, incoming VmlScope, output string, outer_key string, flattened bool) {
	model := vml_find_property(node, 'model') or { return }
	key := vml_find_property(node, 'key') or { return }
	suffix := vml_var(path)
	index_name := 'vml_index_${suffix}'
	item_name := 'vml_item_${suffix}'
	key_name := 'vml_key_${suffix}'
	c.location = VmlLocation{ path: model.expr.source, line: model.expr.line, column: model.expr.column }
	c.write_model_path_checks(model.expr, incoming)
	collection := 'vml_collection_${suffix}'
	c.writeln('\t${collection} := ${c.expr(model.expr, incoming, .raw)}')
	c.write_list_guard(collection, suffix, true)
	c.writeln('\tmut vml_keys_${suffix} := map[string]bool{}')
	c.writeln('\tfor ${index_name}, ${item_name} in ${collection} {')
	c.writeln('\t_ = ${index_name}')
	mut scope := vml_clone_scope(incoming)
	scope.special['item'] = item_name
	scope.special['index'] = index_name
	c.location = VmlLocation{ path: key.expr.source, line: key.expr.line, column: key.expr.column }
	c.write_model_path_checks(key.expr, scope)
	key_raw := '${key_name}_value'
	c.writeln('\t${key_raw} := ${c.expr(key.expr, scope, .raw)}')
	c.write_list_guard(key_raw, suffix, false)
	c.writeln('\t${key_name} := ${vml_stringify(key_raw)}')
	message := '${key.expr.source}:${key.expr.line}:${key.expr.column}: '
	c.writeln('\tif ${key_name}.len == 0 { panic(' + vml_quote(message + 'Repeater key cannot be empty') + ') }')
	c.writeln('\tif ${key_name} in vml_keys_${suffix} { panic(' + vml_quote(message + 'duplicate Repeater key: ') + ' + ${key_name}) }')
	c.writeln('\tvml_keys_${suffix}[${key_name}] = true')
	identity := 'vml_identity_${suffix}'
	segment := '${key_name}.bytes().hex()'
	c.writeln('\t${identity} := ' + if outer_key.len > 0 {
		"${outer_key} + '/' + ${segment}"
	} else {
		segment
	})
	c.writeln('\t_ = ${identity}')
	scope.special['__repeat_identity'] = identity
	visible_count := node.children.filter(it.tag !in ['MenuItem', 'Option']).len
	mut visible_index := 0
	for child_index, child in node.children {
		if child.tag in ['MenuItem', 'Option'] {
			continue
		}
		child_path := '${path}.${child_index}'
		if child.tag == 'Repeater' {
			c.compile_repeater(child, child_path, parent_frame, parent_tag, parent_properties, cursor, scope, output, identity, true)
			continue
		}
		child_input := 'vml_input_${vml_var(child_path)}'
		c.writeln('\t\t${child_input} := ${vml_child_input(parent_tag, parent_frame, parent_properties, cursor)}')
		default_key := if flattened {
			identity + " + ':${visible_index}'"
		} else if visible_count == 1 {
			key_name
		} else {
			"'" + r'$' + '{' + key_name + '}' + ':${visible_index}' + "'"
		}
		child_scope := c.compile_node(child, child_path, child_input, scope, default_key)
		for id, named in child_scope.ids {
			scope.ids[id] = named
		}
		c.writeln('\t\t${output} << vml_element_${vml_var(child_path)}')
		vml_advance_cursor(mut c, parent_tag, cursor, child_path, parent_properties)
		visible_index++
	}
	c.writeln('\t}')
}

fn vml_value(properties map[string]string, name string, alternative string, default_ string) string {
	if value := properties[name] {
		return value
	}
	if alternative.len > 0 {
		if value := properties[alternative] {
			return value
		}
	}
	return default_
}

fn vml_binding_for_event(node &VmlNode, event_name string) ?VmlProperty {
	for property in node.properties {
		if !property.name.starts_with('bind.') { continue }
		aliases := match property.name {
			'bind.checked' { ['on_change', 'on_tap'] }
			'bind.active' { ['on_active', 'on_change', 'on_tap'] }
			else { ['on_change'] }
		}
		mut selected := match property.name {
			'bind.checked' { 'on_tap' }
			'bind.active' { 'on_active' }
			else { 'on_change' }
		}
		for alias in aliases {
			if vml_find_property(node, alias) != none {
				selected = alias
				break
			}
		}
		if event_name == selected { return property }
	}
	return none
}

fn (c &VmlCompiler) box_style(properties map[string]string) string {
	border_width := vml_prop(properties, 'border_width', 'f64(0)')
	return 'ui2.BoxStyle{bg: ${vml_prop(properties, 'background', 'u32(0xffffff)')}, radius: ${vml_value(properties, 'corner_radius', 'radius', 'f64(0)')}, border_color: ${vml_prop(properties, 'border_color', 'u32(0)')}, border_left: ${vml_prop(properties, 'border_left', border_width)}, border_top: ${vml_prop(properties, 'border_top', border_width)}, border_right: ${vml_prop(properties, 'border_right', border_width)}, border_bottom: ${vml_prop(properties, 'border_bottom', border_width)}}'
}

fn (c &VmlCompiler) text_style(properties map[string]string) string {
	align := vml_prop(properties, 'align', "''")
	fields := [
		'color: ${vml_prop(properties, 'color', 'u32(0x111111)')}',
		'background_color: ${vml_prop(properties, 'background_color', 'u32(0)')}',
		'size: ${vml_value(properties, 'font_size', 'size', 'f64(15)')}',
		'font_family: ${vml_prop(properties, 'font_family', "''")}',
		'bold: ${vml_prop(properties, 'bold', 'false')}',
		'italic: ${vml_prop(properties, 'italic', 'false')}',
		'underline: ${vml_prop(properties, 'underline', 'false')}',
		'strikethrough: ${vml_prop(properties, 'strikethrough', 'false')}',
		'shadow: ${vml_prop(properties, 'shadow', 'false')}',
		'outline: ${vml_prop(properties, 'outline', 'false')}',
		'vertical_align: ${vml_prop(properties, 'vertical_align', "''")}',
		'link: ${vml_prop(properties, 'link', "''")}',
		"align: match ${align} { 'center' { .center } 'right' { .right } else { .left } }",
		'head_indent: ${vml_prop(properties, 'head_indent', 'f64(0)')}',
		'first_line_indent: ${vml_prop(properties, 'first_line_indent', 'f64(0)')}',
		'hyphenation_factor: ${vml_prop(properties, 'hyphenation_factor', 'f64(0)')}',
		'lines: int(${vml_prop(properties, 'lines', 'f64(1)')})',
	]
	return 'ui2.TextStyle{${fields.join(', ')}}'
}

fn (c &VmlCompiler) menu_value(node &VmlNode, suffix string, scope VmlScope) string {
	menu_items := node.children.filter(it.tag == 'MenuItem')
	if menu_items.len > 0 {
		mut entries := []string{cap: menu_items.len}
		for index, item in menu_items {
			id := c.event_callback(item, 'on_tap', scope)
			text := if property := vml_find_property(item, 'text') {
				c.expr(property.expr, scope, .raw)
			} else {
				"''"
			}
			entries << 'ui2.MenuEntry{id: ${c.control_id(item, '${suffix}_menu_${index}', scope)}, on_select: ${id}, title: ${text}}'
		}
		return vml_array_literal('ui2.MenuEntry', entries)
	}
	if node.tag in ['Dropdown', 'Spinner'] {
		mut entries := []string{}
		for option in node.children {
			if option.tag != 'Option' {
				continue
			}
			text := if property := vml_find_property(option, 'text') {
				c.expr(property.expr, scope, .raw)
			} else {
				"''"
			}
			entries << 'ui2.MenuEntry{id: ${text}, title: ${text}}'
		}
		return vml_array_literal('ui2.MenuEntry', entries)
	}
	return '[]ui2.MenuEntry{}'
}

fn (c &VmlCompiler) option_values(node &VmlNode, scope VmlScope) string {
	mut values := []string{}
	for option in node.children {
		if option.tag != 'Option' {
			continue
		}
		value := if property := vml_find_property(option, 'text') {
			c.expr(property.expr, scope, .string_)
		} else {
			"''"
		}
		values << value
	}
	return vml_array_literal('string', values)
}

fn vml_array_literal(elem_type string, values []string) string {
	return if values.len == 0 { '[]${elem_type}{}' } else { '[${values.join(', ')}]' }
}

fn (mut c VmlCompiler) compile_element(node &VmlNode, suffix string, frame string, children string, properties map[string]string, scope VmlScope, default_key string) {
	id := c.control_id(node, suffix, scope)
	key := vml_prop(properties, 'key', if default_key.len > 0 { default_key } else { "''" })
	action := c.write_element_callback(node, suffix, scope)
	if node.tag == 'TextInput' {
		c.compile_text_input(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'MessageBox' {
		c.compile_message_box(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'ProgressBar' {
		c.compile_progress_bar(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'Slider' {
		c.compile_slider(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'Switch' {
		c.compile_switch(node, suffix, frame, properties, scope, key, action)
		return
	}
	if node.tag == 'Spinner' {
		c.compile_spinner(node, suffix, frame, properties, scope, key, action)
		return
	}
	kind := match node.tag {
		'Screen' { 'screen' }
		'Label' { 'label' }
		'Image' { 'image' }
		'Button' { 'button' }
		'Checkbox' { 'checkbox' }
		'Dropdown' { 'dropdown' }
		'Scroll' { 'scroll' }
		else { 'view' }
	}
	c.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.writeln('\t\tkind: .${kind}')
	if node.tag != 'Screen' {
		c.writeln('\t\tid: ${id}')
		c.writeln('\t\tframe: ${frame}')
	}
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tkey: ${key}')
	if node.tag in ['Label', 'Button', 'Checkbox', 'Dropdown', 'TextInput'] {
		c.writeln('\t\ttext: ${vml_value(properties, 'text', 'bind.text', "''")}')
	}
	if node.tag == 'Checkbox' {
		c.writeln('\t\tchecked: ${vml_value(properties, 'checked', 'bind.checked', 'false')}')
	}
	if node.tag == 'Image' {
		c.writeln('\t\timage_path: ${vml_value(properties, 'source', 'path', "''")}')
	}
	if node.tag == 'Screen' {
		c.writeln('\t\tbox: ui2.BoxStyle{bg: ${vml_prop(properties, 'background', 'u32(0xffffff)')}}')
	} else if node.tag == 'Scroll' {
		c.writeln('\t\tbox: ${c.box_style(properties)}')
		c.writeln('\t\tpersistent_scrollbars: ${vml_prop(properties, 'persistent', 'false')}')
	} else if node.tag == 'Checkbox' {
		c.writeln('\t\tbox: ui2.BoxStyle{transparent: true}')
	} else if node.tag in ['View', 'Rectangle', 'Column', 'Row', 'Button', 'Dropdown', 'TextInput'] || kind == 'view' {
		c.writeln('\t\tbox: ${c.box_style(properties)}')
	}
	if node.tag in ['Label', 'Button', 'Checkbox', 'Dropdown', 'TextInput'] {
		c.writeln('\t\ttext_style: ${c.text_style(properties)}')
	}
	if node.tag in ['Screen', 'View', 'Rectangle', 'Column', 'Row', 'Scroll'] || kind == 'view' {
		c.writeln('\t\tchildren: ${children}')
	}
	role_default := if node.tag == 'Checkbox' { "'checkbox'" } else { "''" }
	label_default := if node.tag == 'Checkbox' {
		vml_value(properties, 'text', 'bind.text', "''")
	} else {
		"''"
	}
	value_default := if node.tag == 'Checkbox' {
		"if ${vml_value(properties, 'checked', 'bind.checked', 'false')} { 'checked' } else { 'unchecked' }"
	} else {
		"''"
	}
	c.write_common_fields(node, suffix, properties, scope, role_default, label_default, value_default)
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_text_input(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_text_input_${suffix}'
	keyboard := vml_prop(properties, 'keyboard', "''")
	c.writeln('\t${base} := ui2.text_input(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\ttext: ${vml_value(properties, 'text', 'bind.text', "''")}')
	c.writeln('\t\tplaceholder: ${vml_prop(properties, 'placeholder', "''")}')
	c.writeln('\t\tmultiline: ${vml_prop(properties, 'multiline', 'true')}')
	c.writeln('\t\tpassword: ${vml_prop(properties, 'password', 'false')} || ${vml_prop(properties, 'secure', 'false')}')
	c.writeln('\t\treadonly: ${vml_prop(properties, 'readonly', 'false')}')
	c.writeln('\t\tdisable_scroll: ${vml_prop(properties, 'disable_scroll', 'false')}')
	c.writeln('\t\tbox: ${c.box_style(properties)}')
	c.writeln('\t\ttext_style: ${c.text_style(properties)}')
	c.writeln("\t\tkeyboard: if ${keyboard} in ['decimal', 'numeric', 'number'] { ui2.keyboard_decimal } else { ui2.keyboard_default }")
	c.writeln('\t) or { panic(' + vml_quote('${node.source}:${node.line}:${node.column}: ') + ' + err.msg()) }')
	c.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, "''", "''", "''")
	c.writeln('\t}')
}

fn (mut c VmlCompiler) write_common_fields(node &VmlNode, suffix string, properties map[string]string, scope VmlScope, role_default string, label_default string, value_default string) {
	c.writeln('\t\tmenu: ${c.menu_value(node, suffix, scope)}')
	c.writeln('\t\tsecure: ${vml_prop(properties, 'secure', 'false')}' + if node.tag == 'TextInput' {
		' || ${vml_prop(properties, 'password', 'false')}'
	} else {
		''
	})
	c.writeln('\t\tclickable: ${vml_prop(properties, 'clickable', 'false')}')
	c.writeln('\t\tdraggable: ${vml_prop(properties, 'draggable', 'false')}')
	c.writeln('\t\tlong_press: ${vml_prop(properties, 'long_press', 'false')}')
	c.writeln('\t\tswipe_left: ${vml_prop(properties, 'swipe_left', 'false')}')
	c.writeln('\t\trotation: ${vml_prop(properties, 'rotation', 'f64(0)')}')
	c.writeln('\t\tcursor: ${vml_prop(properties, 'cursor', "''")}')
	c.writeln('\t\ttooltip: ${vml_prop(properties, 'tooltip', "''")}')
	c.writeln('\t\thidden: ${vml_prop(properties, 'hidden', 'false')}')
	c.writeln('\t\tenabled: ${vml_prop(properties, 'enabled', 'true')}')
	c.writeln('\t\taccessibility_role: ${vml_prop(properties, 'accessibility_role', role_default)}')
	c.writeln('\t\taccessibility_label: ${vml_prop(properties, 'accessibility_label', label_default)}')
	c.writeln('\t\taccessibility_value: ${vml_prop(properties, 'accessibility_value', value_default)}')
	c.writeln('\t\tnative_style: ${vml_prop(properties, 'native', 'false')}')
	c.writeln('\t\tautocorrect: ${vml_prop(properties, 'autocorrect', 'true')}')
	c.writeln('\t\tpadding_left: ${vml_prop(properties, 'pad_left', vml_prop(properties, 'padding', 'f64(12)'))}')
}

fn (mut c VmlCompiler) compile_progress_bar(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_progress_${suffix}'
	c.writeln('\t${base} := ui2.progress_bar(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\tvalue: ${vml_prop(properties, 'value', 'f64(0)')}')
	c.writeln('\t\tmax: ${vml_prop(properties, 'max', 'f64(100)')}')
	c.writeln('\t\tbackground: ${vml_prop(properties, 'background', 'u32(0xe2e8f0)')}')
	c.writeln('\t\tcolor: ${vml_prop(properties, 'color', 'u32(0x3b82f6)')}')
	c.writeln('\t\tradius: ${vml_value(properties, 'corner_radius', 'radius', 'f64(4)')}')
	c.writeln('\t)')
	c.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_slider(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_slider_${suffix}'
	style := '${base}_style'
	orientation_value := '${base}_orientation'
	orientation := vml_prop(properties, 'orientation', "''")
	c.writeln('\t${style} := ui2.SliderStyle{')
	c.writeln('\t\ttrack_color: ${vml_prop(properties, 'background', 'u32(0xcbd5e1)')}')
	c.writeln('\t\tvalue_track_color: ${vml_value(properties, 'value_track_color', 'color', 'u32(0x93c5fd)')}')
	c.writeln('\t\tthumb_color: ${vml_prop(properties, 'thumb_color', 'u32(0x2563eb)')}')
	c.writeln('\t\ttrack_width: ${vml_prop(properties, 'track_width', 'f64(4)')}')
	c.writeln('\t\tthumb_size: ${vml_prop(properties, 'thumb_size', 'f64(20)')}')
	c.writeln('\t}')
	c.writeln("\t${orientation_value} := if ${orientation} == 'vertical' { ui2.Orientation.vertical } else { ui2.Orientation.horizontal }")
	c.writeln('\t${base} := ui2.slider(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\tmin: ${vml_prop(properties, 'min', 'f64(0)')}')
	c.writeln('\t\tmax: ${vml_prop(properties, 'max', 'f64(100)')}')
	c.writeln('\t\tvalue: ${vml_value(properties, 'value', 'bind.value', 'f64(0)')}')
	c.writeln('\t\tstep: ${vml_prop(properties, 'step', 'f64(0)')}')
	c.writeln('\t\torientation: ${orientation_value}')
	c.writeln('\t\tpadding: ${vml_prop(properties, 'padding', 'f64(16)')}')
	c.writeln('\t\tvalue_track: ${vml_prop(properties, 'value_track', 'false')}')
	c.writeln('\t\tstyle: ${style}')
	c.writeln('\t)')
	c.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_switch(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_switch_${suffix}'
	style := '${base}_style'
	c.writeln('\t${style} := ui2.SwitchStyle{')
	c.writeln('\t\tinactive_track_color: ${vml_prop(properties, 'inactive_color', 'u32(0xcbd5e1)')}')
	c.writeln('\t\tactive_track_color: ${vml_value(properties, 'active_color', 'color', 'u32(0x22c55e)')}')
	c.writeln('\t\tthumb_color: ${vml_prop(properties, 'thumb_color', 'u32(0xffffff)')}')
	c.writeln('\t\tdisabled_track_color: ${vml_prop(properties, 'disabled_track_color', 'u32(0xe2e8f0)')}')
	c.writeln('\t\tdisabled_thumb_color: ${vml_prop(properties, 'disabled_thumb_color', 'u32(0xf8fafc)')}')
	c.writeln('\t}')
	c.writeln('\t${base} := ui2.switch_control(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\tactive: ${vml_value(properties, 'active', 'bind.active', 'false')}')
	c.writeln('\t\tstyle: ${style}')
	c.writeln('\t)')
	c.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_spinner(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_spinner_${suffix}'
	box := '${base}_box'
	text_style := '${base}_text_style'
	c.writeln('\t${box} := ${c.box_style(properties)}')
	c.writeln('\t${text_style} := ${c.text_style(properties)}')
	c.writeln('\t${base} := ui2.spinner(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\ttext: ${vml_value(properties, 'text', 'bind.text', "''")}')
	c.writeln('\t\tvalues: ${c.option_values(node, scope)}')
	c.writeln('\t\ttext_autoupdate: ${vml_prop(properties, 'text_autoupdate', 'false')}')
	c.writeln('\t\tbox: ${box}')
	c.writeln('\t\ttext_style: ${text_style}')
	c.writeln('\t)')
	c.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.writeln('\t\t...${base}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) compile_message_box(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	mut actions := []string{}
	for child_index, child in node.children {
		if child.tag != 'Button' {
			continue
		}
		c.write_action_type_checks(child, '${suffix}_message_action_${child_index}', scope)
		child_action := c.event_callback(child, 'on_tap', scope)
		text := if property := vml_find_property(child, 'text') {
			c.expr(property.expr, scope, .string_)
		} else {
			"''"
		}
		actions << 'ui2.MessageBoxAction{id: ${c.control_id(child, suffix + '_' + child_index.str(), scope)}, on_event: ${child_action}, title: ${text}}'
	}
	c.writeln('\tvml_message_box_${suffix} := ui2.custom_message_box(')
	c.writeln('\t\tid: ${c.control_id(node, suffix, scope)}')
	c.writeln('\t\tframe: ${frame}')
	c.writeln('\t\ttitle: ${vml_prop(properties, 'title', "''")}')
	c.writeln('\t\ttext: ${vml_prop(properties, 'text', "''")}')
	c.writeln('\t\thidden: ${vml_prop(properties, 'hidden', 'false')}')
	c.writeln('\t\twidth: ${vml_prop(properties, 'dialog_width', 'f64(300)')}')
	c.writeln('\t\theight: ${vml_prop(properties, 'dialog_height', 'f64(150)')}')
	c.writeln('\t\tactions: ${vml_array_literal('ui2.MessageBoxAction', actions)}')
	c.writeln('\t)')
	c.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.writeln('\t\t...vml_message_box_${suffix}')
	c.writeln('\t\ton_event: ${action}')
	c.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, suffix, properties, scope, "''", "''", "''")
	c.writeln('\t}')
}
