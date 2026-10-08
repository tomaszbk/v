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
	kind   VmlTokenKind
	text   string
	line   int
	column int
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
	for l.pos < l.source.len && vml_is_name_char(l.source[l.pos]) {
		l.pos++
	}
	return VmlToken{ kind: .name, text: l.source[start..l.pos], line: line, column: start - l.line_start + 1 }
}

fn (mut l VmlLexer) read_number() VmlToken {
	start := l.pos
	line := l.line
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
	return VmlToken{ kind: .number, text: l.source[start..l.pos], line: line, column: start - l.line_start + 1 }
}

fn (mut l VmlLexer) read_string() !VmlToken {
	line := l.line
	column := l.pos - l.line_start + 1
	quote := l.advance()
	mut value := []u8{}
	for l.pos < l.source.len {
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
			return VmlToken{ kind: .string_, text: value.bytestr(), line: line, column: column }
		} else {
			value << c
		}
	}
	return error('unterminated string at line ${line}')
}

fn tokenize_vml(source string) ![]VmlToken {
	mut lexer := VmlLexer{ source: source }
	mut tokens := []VmlToken{}
	for {
		lexer.skip_space()
		if lexer.pos >= source.len {
			tokens << VmlToken{ kind: .eof, line: lexer.line, column: lexer.pos - lexer.line_start + 1 }
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
					return error('expected `==` at line ${line}')
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
	line          int
	column        int
	expr          &VmlExpr
}

struct VmlNode {
	tag    string
	line   int
	column int
mut:
	id         string
	properties []VmlProperty
	children   []&VmlNode
}

struct VmlSourceParser {
	tokens []VmlToken
mut:
	pos int
}

fn (p &VmlSourceParser) at() VmlToken {
	return if p.pos < p.tokens.len { p.tokens[p.pos] } else { VmlToken{ kind: .eof } }
}

fn (mut p VmlSourceParser) take(kind VmlTokenKind) !VmlToken {
	token := p.at()
	if token.kind != kind {
		return error('expected ${kind}, got ${token.kind} (`${token.text}`) at line ${token.line}')
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
			return error('property has been removed; use computed at line ${p.at().line}, column ${p.at().column}')
		} else if p.at().text == 'computed' {
			p.pos++
			typ := p.take(.name)!
			name := p.take(.name)!
			p.take(.colon)!
			node.properties << VmlProperty{ name: name.text, line: name.line, column: name.column, declared_type: typ.text, expr: p.parse_expression()! }
		} else if p.pos + 1 < p.tokens.len && p.tokens[p.pos + 1].kind == .lbrace {
			node.children << p.parse_node()!
		} else if p.pos + 1 < p.tokens.len && p.tokens[p.pos + 1].kind == .colon {
			name := p.take(.name)!
			p.take(.colon)!
			expr := p.parse_expression()!
			if name.text == 'id' {
				if expr.kind !in [.literal, .path] {
					return error('id must be a literal identifier at line ${name.line}')
				}
				node.id = expr.value
			}
			node.properties << VmlProperty{ name: name.text, line: name.line, column: name.column, expr: expr }
		} else {
			return error('unexpected token `${p.at().text}` at line ${p.at().line}')
		}
	}
	p.take(.rbrace)!
	return node
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
			kind:  .binary
			value: op.text
			line:  op.line
			left:  left
			right: p.parse_and()!
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
			kind:  .binary
			value: op.text
			line:  op.line
			left:  left
			right: p.parse_equality()!
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
			kind:  .binary
			value: op.text
			line:  op.line
			left:  left
			right: p.parse_comparison()!
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
			kind:  .binary
			value: op.text
			line:  op.line
			left:  left
			right: p.parse_term()!
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
			kind:  .binary
			value: op.text
			line:  op.line
			left:  left
			right: p.parse_factor()!
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
			kind:  .binary
			value: op.text
			line:  op.line
			left:  left
			right: p.parse_unary()!
		}
	}
	return left
}

fn (mut p VmlSourceParser) parse_unary() !&VmlExpr {
	if p.at().kind in [.not, .minus] {
		op := p.at()
		p.pos++
		return &VmlExpr{ kind: .unary, value: op.text, line: op.line, left: p.parse_unary()! }
	}
	return p.parse_primary()
}

fn (mut p VmlSourceParser) parse_primary() !&VmlExpr {
	token := p.at()
	match token.kind {
		.string_ {
			p.pos++
			return parse_vml_interpolation(token.text, token.line)!
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
				return &VmlExpr{ kind: .call, value: token.text, line: token.line, args: args }
			}
			return &VmlExpr{
				kind:  if token.kind == .number || token.text in ['true', 'false'] {
					VmlExprKind.literal
				} else {
					VmlExprKind.path
				}
				value: token.text
				line:  token.line
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

fn parse_vml_interpolation(value string, line int) !&VmlExpr {
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
		tokens := tokenize_vml(value[start + 2..end])!
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
	validate_compiled_vml_visual(root, '')!
	validate_compiled_vml_node(root)!
	return root
}

fn validate_compiled_vml_node(node &VmlNode) ! {
	mut bindings := 0
	for property in node.properties {
		if property.name.starts_with('bind.') {
			bindings++
			bound_property := property.name.all_after('bind.')
			if bound_property !in ['text', 'checked', 'active', 'value'] {
				return error('two-way binding is not supported for `${bound_property}` at line ${property.expr.line}')
			}
			if property.expr.kind != .path || !property.expr.value.starts_with('app.')
				|| property.expr.value.count('.') != 1 {
				return error('`${property.name}` must target a mutable top-level app field at line ${property.expr.line}')
			}
		}
		if property.name in ['on_tap', 'on_change', 'on_active', 'on_text', 'on_submit']
			&& property.expr.kind == .call {
			if !property.expr.value.starts_with('app.') || property.expr.value.count('.') != 1 {
				return error('event handlers must call an app action at line ${property.expr.line}')
			}
			if property.expr.args.len > 1 {
				return error('app actions support at most one argument at line ${property.expr.line}')
			}
		}
	}
	if bindings > 1 {
		return error('an element can only have one two-way binding at line ${node.line}')
	}
	if node.tag == 'Repeater' {
		if vml_find_property(node, 'model') == none {
			return error('Repeater requires `model` at line ${node.line}')
		}
		if vml_find_property(node, 'key') == none {
			return error('Repeater requires a stable `key` at line ${node.line}')
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
	source := os.read_file(path) or {
		p.record_diagnostic('cannot read VML file `${path}`: ${err.msg()}', call_start)
		return p.add_val_id(5, '')
	}
	root := parse_vml_source(source) or {
		p.record_vml_diagnostic(path, source, err.msg(), call_start)
		return p.add_val_id(5, '')
	}
	target_os := p.prefs.normalized_target_os()
	custom := target_os in ['linux', 'android']
		|| (target_os in ['macos', 'windows'] && 'ui2_custom_rendering' in p.prefs.user_defines)
		|| 'ui2_headless' in p.prefs.user_defines
	if !custom {
		validate_vml_native_visual(root) or {
			p.record_vml_diagnostic(path, source, err.msg(), call_start)
			return p.add_val_id(5, '')
		}
	}
	mut compiler := VmlCompiler{
		uses_app: vml_node_uses_path(root, 'app')
	}
	generated := compiler.compile(root)
	template := flat.Node{
		value: path
		pos:   p.span_to(call_start)
	}
	first_node := p.a.nodes.len
	result := p.parse_veb_template_replacement_expr(generated, template, [TemplateSourceLine{ path: path, line: 1 }]) or {
		p.record_diagnostic('could not lower VML file `${path}`', call_start)
		p.add_val_id(5, '')
	}
	p.remap_vml_visual_positions(first_node, path, source, generated, compiler.property_positions, template.pos)
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
	frame      string
	props      map[string]string
	prop_types map[string]string
}

struct VmlScope {
mut:
	ids     map[string]VmlNamedValue
	special map[string]string
}

struct VmlCompiler {
	uses_app bool
mut:
	out                  strings.Builder
	property_positions   map[string]VmlProperty
	builders             map[string]VmlBuilder
	builder_declarations []string
	builder_dependencies map[string][]string
	active_builder       string
	share_nodes          bool
	reference_readers    map[string][]string
}

fn (mut c VmlCompiler) compile(root &VmlNode) string {
	c.out = strings.new_builder(4096)
	c.share_nodes = vml_has_visual_layout(root)
	c.builders = map[string]VmlBuilder{}
	c.builder_declarations = []string{}
	c.builder_dependencies = map[string][]string{}
	c.reference_readers = map[string][]string{}
	c.collect_builder_references(root, '0')
	capture := if c.uses_app { '[mut app] ' } else { '' }
	c.out.writeln('\tvml_input_0 := ui2.bounds()')
	scope := VmlScope{
		ids:     map[string]VmlNamedValue{}
		special: map[string]string{}
	}
	c.compile_node(root, '0', 'vml_input_0', scope, '', .normal)
	c.out.writeln('\treturn vml_element_0')
	c.out.write_string('}())')
	return '(fn ${capture}() ui2.Element {\n' + c.builder_declarations.join('\n') + '\n' + c.out.str()
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
	if use := vml_visual_property_use(property.name) { return use }
	if property.name in ['x', 'y', 'width', 'height', 'padding', 'spacing', 'corner_radius', 'radius',
		'rotation', 'font_size', 'size', 'head_indent', 'first_line_indent', 'hyphenation_factor',
		'lines', 'pad_left', 'dialog_width', 'dialog_height', 'border_width', 'border_left',
		'border_top', 'border_right', 'border_bottom', 'value', 'min', 'max', 'step', 'track_width',
		'thumb_size', 'keyboard'] {
		return .number
	}
	if property.name in ['background', 'color', 'background_color', 'border_color', 'value_track_color',
		'thumb_color', 'inactive_color', 'active_color', 'disabled_track_color', 'disabled_thumb_color'] {
		return .color
	}
	if property.name in ['checked', 'hidden', 'enabled', 'native', 'editable', 'emit_change', 'secure',
		'clickable', 'draggable', 'long_press', 'swipe_left', 'persistent', 'autocorrect', 'bold',
		'italic', 'underline', 'strikethrough', 'shadow', 'outline', 'value_track', 'active',
		'text_autoupdate']
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
				.string_ { expr.value }
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
				return 'ui2.TextStyle{color: ${resolved}}.color'
			}
			if use == .string_ {
				return resolved
			}
			if use == .number {
				return 'ui2.LayoutSize{width: ${resolved}}.width'
			}
			return resolved
		}
		.call {
			args := expr.args.map(c.expr(it, scope, .raw)).join(', ')
			resolved, _ := c.resolve_path(expr.value, scope)
			call := '${resolved}(${args})'
			return match use {
				.string_ { call }
				.number { 'ui2.LayoutSize{width: ${call}}.width' }
				.color { 'ui2.TextStyle{color: ${call}}.color' }
				else { call }
			}
		}
		.unary {
			operand_use := if use in [.raw, .string_, .color] {
				VmlExprUse.raw
			} else if expr.value == '!' {
				VmlExprUse.bool_
			} else {
				VmlExprUse.number
			}
			result := '(${expr.value}${c.expr(expr.left, scope, operand_use)})'
			return result
		}
		.binary {
			if expr.value in ['&&', '||'] {
				result := '(${c.expr(expr.left, scope, .bool_)} ${expr.value} ${c.expr(expr.right, scope, .bool_)})'
				return result
			}
			if expr.value in ['==', '!=', '<', '<=', '>', '>='] {
				operand_use := if vml_expr_is_string(expr.left) || vml_expr_is_string(expr.right) {
					VmlExprUse.string_
				} else {
					VmlExprUse.raw
				}
				result := '(${c.expr(expr.left, scope, operand_use)} ${expr.value} ${c.expr(expr.right, scope, operand_use)})'
				return result
			}
			if use in [.raw, .string_, .color] {
				return '(${c.expr(expr.left, scope, .raw)} ${expr.value} ${c.expr(expr.right, scope, .raw)})'
			}
			if expr.value == '%' {
				return 'f64(int(${c.expr(expr.left, scope, .number)}) % int(${c.expr(expr.right, scope, .number)}))'
			}
			return '(${c.expr(expr.left, scope, .number)} ${expr.value} ${c.expr(expr.right, scope, .number)})'
		}
		.conditional {
			return '(if ${c.expr(expr.left, scope, .bool_)} { ${c.expr(expr.right, scope, use)} } else { ${c.expr(expr.third, scope, use)} })'
		}
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

fn (mut c VmlCompiler) compile_node(node &VmlNode, path string, input string, incoming VmlScope, default_key string, placement VmlPlacement) VmlScope {
	// Repeater locals have types supplied by structural lowering. Keep its one
	// existing emitter until integration; static visual trees share typed builders.
	if c.share_nodes && incoming.special.len == 0 && default_key.len == 0 {
		return c.compile_shared_node(node, path, input, incoming, placement)
	}
	return c.compile_node_body(node, path, input, incoming, default_key, placement)
}

fn (mut c VmlCompiler) compile_node_body(node &VmlNode, path string, input string, incoming VmlScope, default_key string, placement VmlPlacement) VmlScope {
	suffix := vml_var(path)
	measure_mode := placement in [.preferred, .width_preferred, .inherited_preferred]
	c.out.writeln('\t_ = ${input}')
	mut scope := vml_clone_scope(incoming)
	mut named_props := map[string]string{}
	mut named_types := map[string]string{}
	// Declared properties are visible before expressions are resolved. Geometry
	// bindings are added after they are emitted below, so self-geometry can use an
	// earlier computed binding while declared properties can still read the input.
	for property in node.properties {
		if property.declared_type.len > 0 {
			named_props[property.name] = 'vml_property_${suffix}_${vml_var(property.name)}'
			named_types[property.name] = vml_builder_property_type(node, property)
		}
	}
	if node.id.len > 0 {
		scope.ids[node.id] = VmlNamedValue{ frame: input, props: named_props.clone(), prop_types: named_types.clone() }
	}
	mut properties := map[string]string{}
	mut ordered_properties := vml_order_properties_by_dependencies(node.properties.filter(it.declared_type.len > 0), node.id)
	ordered_properties << vml_order_properties_by_dependencies(node.properties.filter(it.declared_type.len == 0
		&& vml_property_is_geometry(it)), node.id)
	ordered_properties << node.properties.filter(it.declared_type.len == 0
		&& !vml_property_is_geometry(it))
	for property in ordered_properties {
		if property.name == 'id'
			|| property.name in ['on_tap', 'on_change', 'on_active', 'on_text', 'on_submit'] {
			continue
		}
		name := 'vml_property_${suffix}_${vml_var(property.name)}'
		property_use := vml_property_use(property)
		value := c.visual_property_value(node, property, property.expr, scope)
		if property.declared_type.len == 0 && property_use == .color
			&& property.expr.kind in [.literal, .path]
			&& property.expr.value.starts_with('#') && property.expr.value.len == 7 {
			// Static colors can be used directly without a generated local.
			properties[property.name] = value
			continue
		}
		c.out.writeln('\t${name} := ${value}')
		c.property_positions[name] = property
		c.out.writeln('\t_ = ${name}')
		properties[property.name] = name
		if property.declared_type.len == 0 && vml_property_is_geometry(property) {
			named_props[property.name] = name
			named_types[property.name] = vml_builder_property_type(node, property)
			if node.id.len > 0 {
				scope.ids[node.id] = VmlNamedValue{ frame: input, props: named_props.clone(), prop_types: named_types.clone() }
			}
		}
	}
	frame := 'vml_frame_${suffix}'
	if placement == .allocated {
		c.out.writeln('\t${frame} := ${input}')
	} else {
		preferred_mode := placement in [.preferred, .width_preferred]
		width := if placement == .width_preferred {
			input + '.width'
		} else {
			vml_prop(properties, 'width', if preferred_mode { 'f64(0)' } else { input + '.width' })
		}
		height := vml_prop(properties, 'height', if preferred_mode {
			'f64(0)'
		} else {
			input + '.height'
		})
		c.out.writeln('\t${frame} := ui2.rect(${vml_prop(properties, 'x', input + '.x')}, ${vml_prop(properties, 'y', input + '.y')}, ${width}, ${height})')
	}
	c.out.writeln('\t_ = ${frame}')
	if node.id.len > 0 {
		scope.ids[node.id] = VmlNamedValue{ frame: frame, props: named_props.clone(), prop_types: named_types.clone() }
	}
	c.write_action_type_checks(node, suffix, scope)
	if node.tag in ['Flex', 'Row', 'Column', 'Grid'] {
		return c.compile_visual_layout(node, path, input, frame, properties, scope, placement, default_key)
	}
	children := 'vml_children_${suffix}'
	container := node.tag in ['Screen', 'View', 'ScaledContent', 'Scroll']
		|| node.tag !in ['Label', 'Image', 'Button', 'MessageBox', 'Checkbox', 'Dropdown', 'TextInput',
			'ProgressBar', 'Slider', 'Switch', 'Spinner']
	visible_children := if container {
		node.children.filter(it.tag !in ['MenuItem', 'Option'])
	} else {
		[]&VmlNode{}
	}
	if container {
		c.out.writeln('\tmut ${children} := []ui2.Element{cap: ${visible_children.len}}')
	}
	cursor := ''
	for child_index, child in node.children {
		child_path := '${path}.${child_index}'
		if child.tag == 'MenuItem' {
			c.write_action_type_checks(child, '${vml_var(child_path)}_menu_action', scope)
			continue
		}
		if child.tag == 'Run' { continue }
		if !container || child.tag == 'Option' {
			continue
		}
		if child.tag == 'Repeater' {
			c.compile_repeater(child, child_path, frame, node.tag, properties, cursor, scope, children, '')
			continue
		}
		child_input := 'vml_input_${vml_var(child_path)}'
		c.out.writeln('\t${child_input} := ${if node.tag == 'ScaledContent' {
			'ui2.rect(0, 0, ' + vml_prop(properties, 'content_width', 'f64(0)') + ', ' + vml_prop(properties, 'content_height', 'f64(0)') + ')'
		} else {
			vml_child_input(node.tag, frame, properties, cursor)
		}}')
		child_scope := c.compile_node(child, child_path, child_input, scope, '', if node.tag == 'Absolute' {
			.preferred
		} else if measure_mode {
			// Generic containers offer their fixed axes; only zero auto axes need measurement.
			.inherited_preferred
		} else {
			.normal
		})
		for id, named in child_scope.ids {
			scope.ids[id] = named
		}
		c.out.writeln('\t${children} << vml_element_${vml_var(child_path)}')
	}
	if node.tag == 'Label' && node.children.any(it.tag == 'Run') {
		c.prepare_visual_runs(node, suffix, mut properties, scope)
	}
	base_suffix := if measure_mode {
		suffix + '_base'
	} else {
		suffix
	}
	c.compile_element(node, base_suffix, frame, children, properties, scope, default_key)
	if measure_mode {
		c.out.writeln('\tvml_measured_${suffix} := ui2.measure_layout_element(vml_element_${base_suffix}, ui2.LayoutConstraints{}, ui2.measure_layout_text) or { panic(err) }')
		c.out.writeln('\t_ = vml_measured_${suffix}')
		c.out.writeln('\tvml_element_${suffix} := ui2.Element{...vml_element_${base_suffix}, frame: ui2.rect(${frame}.x, ${frame}.y, ${if placement == .width_preferred {
			input + '.width'
		} else {
			vml_prop(properties, 'width', vml_measured_axis(placement, frame + '.width', 'vml_measured_' + suffix + '.width'))
		}}, ${vml_prop(properties, 'height', vml_measured_axis(placement, frame + '.height', 'vml_measured_' + suffix + '.height'))})}')
		if node.id.len > 0 {
			// Later siblings use this pass's measured frame; declared props keep precedence.
			scope.ids[node.id] = VmlNamedValue{
				frame:      'vml_element_${suffix}.frame'
				props:      named_props.clone()
				prop_types: named_types.clone()
			}
		}
	}
	return scope
}

fn (mut c VmlCompiler) write_action_type_checks(node &VmlNode, suffix string, scope VmlScope) {
	for property in node.properties {
		if property.name !in ['on_tap', 'on_change', 'on_active', 'on_text', 'on_submit'] || property.expr.kind != .call {
			continue
		}
		method_name := property.expr.value.all_after('app.')
		check_name := 'vml_action_check_${suffix}_${vml_var(property.name)}'
		action_arguments := property.expr.args.map(c.expr(it, scope, .raw)).join(', ')
		// The branch is never taken, but V still checks that the method exists and
		// that its argument has the declared type.
		c.out.writeln('\tif false {')
		c.out.writeln('\t\tmut ${check_name} := *app')
		// The runtime dispatcher exposes public methods only. Reflection makes a
		// same-module private method a compile error before its action is serialized.
		c.out.writeln('\t\t\$for method in ${check_name}.methods {')
		c.out.writeln('\t\t\t\$if method.name == ${vml_quote(method_name)} {')
		c.out.writeln('\t\t\t\t\$if !method.is_pub {')
		c.out.writeln('\t\t\t\t\t\$compile_error(${vml_quote('VML action method `${method_name}` must be public')})')
		c.out.writeln('\t\t\t\t}')
		c.out.writeln('\t\t\t}')
		c.out.writeln('\t\t}')
		c.out.writeln('\t\t${check_name}.${method_name}(${action_arguments})')
		c.out.writeln('\t}')
	}
}

fn vml_child_input(tag string, frame string, properties map[string]string, cursor string) string {
	_ = tag
	_ = properties
	_ = cursor
	return 'ui2.rect(f64(0), f64(0), ${frame}.width, ${frame}.height)'
}

fn (mut c VmlCompiler) compile_repeater(node &VmlNode, path string, parent_frame string, parent_tag string, parent_properties map[string]string, cursor string, incoming VmlScope, output string, outer_key string) {
	model := vml_find_property(node, 'model') or { return }
	key := vml_find_property(node, 'key') or { return }
	suffix := vml_var(path)
	index_name := 'vml_index_${suffix}'
	item_name := 'vml_item_${suffix}'
	key_name := 'vml_key_${suffix}'
	c.out.writeln('\tfor ${index_name}, ${item_name} in ${c.expr(model.expr, incoming, .raw)} {')
	mut scope := vml_clone_scope(incoming)
	scope.special['item'] = item_name
	scope.special['index'] = index_name
	key_value := c.expr(key.expr, scope, .string_)
	if outer_key.len > 0 {
		local_key_name := '${key_name}_local'
		c.out.writeln('\t\t${local_key_name} := ${key_value}')
		c.out.writeln("\t\t${key_name} := ${outer_key} + ':' + ${local_key_name}")
	} else {
		c.out.writeln('\t\t${key_name} := ${key_value}')
	}
	visible_count := node.children.filter(it.tag !in ['MenuItem', 'Option']).len
	mut visible_index := 0
	for child_index, child in node.children {
		if child.tag in ['MenuItem', 'Option'] {
			continue
		}
		child_path := '${path}.${child_index}'
		if child.tag == 'Repeater' {
			c.compile_repeater(child, child_path, parent_frame, parent_tag, parent_properties, cursor, scope, output, key_name)
			continue
		}
		child_input := 'vml_input_${vml_var(child_path)}'
		c.out.writeln('\t\t${child_input} := ${vml_child_input(parent_tag, parent_frame, parent_properties, cursor)}')
		default_key := if visible_count == 1 {
			key_name
		} else {
			"'" + r'$' + '{' + key_name + '}' + ':${visible_index}' + "'"
		}
		child_scope := c.compile_node(child, child_path, child_input, scope, default_key, .normal)
		for id, named in child_scope.ids {
			scope.ids[id] = named
		}
		c.out.writeln('\t\t${output} << vml_element_${vml_var(child_path)}')
		visible_index++
	}
	c.out.writeln('\t}')
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
	if event_name == 'on_change' {
		if binding := vml_find_property(node, 'bind.value') {
			return binding
		}
		if binding := vml_find_property(node, 'bind.active') {
			return binding
		}
		return vml_find_property(node, 'bind.text')
	}
	if event_name == 'on_tap' {
		return vml_find_property(node, 'bind.checked')
	}
	if event_name == 'on_active' {
		return vml_find_property(node, 'bind.active')
	}
	if event_name == 'on_text' {
		return vml_find_property(node, 'bind.text')
	}
	return none
}

fn (c &VmlCompiler) compiled_event_value(node &VmlNode, event_name string, scope VmlScope, control string) string {
	_ = control
	action := vml_find_property(node, event_name)
	binding := vml_binding_for_event(node, event_name)
	if action == none && binding == none { return 'unsafe { nil }' }
	mut fields := []string{}
	if property := binding {
		fields << 'binding_property: ${vml_quote(property.name.all_after('bind.'))}'
		fields << 'binding_target: ${vml_quote(vml_expr_text(property.expr))}'
	}
	if property := action {
		fields << 'action_name: ${vml_quote(property.expr.value.all_after('app.'))}'
		if property.expr.args.len > 0 {
			argument := property.expr.args[0]
			if argument.kind == .path && argument.value.starts_with('app.') {
				fields << 'argument_path: ${vml_quote(argument.value)}'
			} else {
				fields << 'arguments: [ui2.CompiledVmlArgument(${c.expr(argument, scope, .raw)})]'
			}
		}
	}
	return 'ui2.compiled_vml_callback(mut app, ui2.CompiledVmlCallbackConfig{${fields.join(', ')}})'
}

fn (c &VmlCompiler) box_style(properties map[string]string) string {
	return c.visual_box_style(properties, '', false)
}

fn (c &VmlCompiler) text_style(properties map[string]string) string {
	mut fields := []string{}
	for name in vml_text_properties {
		if value := properties[name] {
			field := match name {
				'font_size', 'size' { 'size' }
				else { name }
			}
			if name == 'size' && 'font_size' in properties { continue }
			fields << '${field}: ${if name in ['weight', 'lines'] {
				'int(' + value + ')'
			} else {
				value
			}}'
		}
	}
	return 'ui2.TextStyle{${fields.join(', ')}}'
}

fn (c &VmlCompiler) menu_value(node &VmlNode, scope VmlScope) string {
	menu_items := node.children.filter(it.tag == 'MenuItem')
	if menu_items.len > 0 {
		mut entries := []string{cap: menu_items.len}
		for item in menu_items {
			fallback_id := vml_quote(item.id)
			id := c.compiled_event_value(item, 'on_tap', scope, fallback_id)
			text := if property := vml_find_property(item, 'text') {
				c.expr(property.expr, scope, .string_)
			} else {
				"''"
			}
			entries << 'ui2.MenuEntry{id: ${fallback_id}, on_select: ${id}, title: ${text}}'
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
				c.expr(property.expr, scope, .string_)
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
	has_binding := vml_find_property(node, 'bind.text') != none
		|| vml_find_property(node, 'bind.checked') != none
		|| vml_find_property(node, 'bind.active') != none || vml_find_property(node, 'bind.value') != none
	id := if node.id.len > 0 {
		vml_quote(node.id)
	} else if has_binding && default_key.len > 0 {
		"'__vml_control_${suffix}_" + r'$' + '{' + default_key + "}'"
	} else if has_binding {
		vml_quote('__vml_control_${suffix}')
	} else {
		"''"
	}
	key := vml_prop(properties, 'key', if default_key.len > 0 { default_key } else { "''" })
	action := c.compiled_node_callback(node, scope)
	if node.tag == 'TextInput' {
		c.compile_text_input(node, suffix, frame, properties, scope, id, key, action)
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
		'TextInput' { 'text_area' }
		'Scroll' { 'scroll' }
		else { 'view' }
	}
	c.out.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.out.writeln('\t\tkind: .${kind}')
	c.out.writeln('\t\tid: ${id}')
	if node.tag != 'Screen' { c.out.writeln('\t\tframe: ${frame}') }
	c.out.writeln('\t\ton_event: ${action}')
	c.out.writeln('\t\tkey: ${key}')
	if node.tag in ['Label', 'Button', 'Checkbox', 'Dropdown', 'TextInput'] {
		c.out.writeln('\t\ttext: ${if node.tag == 'Label' && node.children.any(it.tag == 'Run') {
			vml_prop(properties, '@run_text', "''")
		} else {
			vml_value(properties, 'text', 'bind.text', "''")
		}}')
	}
	if node.tag == 'Checkbox' {
		c.out.writeln('\t\tchecked: ${vml_value(properties, 'checked', 'bind.checked', 'false')}')
	}
	if node.tag == 'Image' {
		c.out.writeln('\t\timage_path: ${vml_value(properties, 'source', 'path', "''")}')
	}
	if node.tag == 'Screen' {
		c.out.writeln('\t\tbox: ${c.box_style(properties)}')
	} else if node.tag == 'Scroll' {
		c.out.writeln('\t\tbox: ${c.box_style(properties)}')
		c.out.writeln('\t\tpersistent_scrollbars: ${vml_prop(properties, 'persistent', 'false')}')
	} else if node.tag == 'Checkbox' {
		c.out.writeln('\t\tbox: ui2.BoxStyle{transparent: true}')
	} else if node.tag in ['View', 'ScaledContent', 'Button', 'Dropdown', 'Label'] || kind == 'view' {
		c.out.writeln('\t\tbox: ${c.box_style(properties)}')
	}
	if node.tag in ['Label', 'Button', 'Checkbox', 'Dropdown', 'TextInput'] {
		c.out.writeln('\t\ttext_style: ${c.text_style(properties)}')
	}
	if node.tag == 'Label' && node.children.any(it.tag == 'Run') {
		c.out.writeln('\t\ttext_runs: ${vml_prop(properties, '@runs', '[]ui2.TextRun{}')}')
	}
	if node.tag == 'ScaledContent' {
		c.out.writeln('\t\tcontent_size: ui2.LayoutSize{width: ${vml_prop(properties, 'content_width', 'f64(0)')}, height: ${vml_prop(properties, 'content_height', 'f64(0)')}}')
	}
	if node.tag in ['Screen', 'View', 'ScaledContent', 'Scroll'] || kind == 'view' {
		c.out.writeln('\t\tchildren: ${children}')
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
	c.write_common_fields(node, properties, scope, role_default, label_default, value_default)
	c.out.writeln('\t}')
}

fn (mut c VmlCompiler) write_common_fields(node &VmlNode, properties map[string]string, scope VmlScope, role_default string, label_default string, value_default string) {
	c.out.writeln('\t\tinteraction_style: ${c.interaction_style(properties)}')
	c.out.writeln('\t\tbutton_behavior: ${vml_prop(properties, 'button_behavior', 'false')}')
	c.out.writeln('\t\tmenu: ${c.menu_value(node, scope)}')
	c.out.writeln('\t\tsecure: ${vml_prop(properties, 'secure', 'false')}')
	c.out.writeln('\t\tclickable: ${vml_prop(properties, 'clickable', 'false')}')
	c.out.writeln('\t\tdraggable: ${vml_prop(properties, 'draggable', 'false')}')
	c.out.writeln('\t\tlong_press: ${vml_prop(properties, 'long_press', 'false')}')
	c.out.writeln('\t\tswipe_left: ${vml_prop(properties, 'swipe_left', 'false')}')
	c.out.writeln('\t\trotation: ${vml_prop(properties, 'rotation', 'f64(0)')}')
	c.out.writeln('\t\tcursor: ${vml_prop(properties, 'cursor', "''")}')
	c.out.writeln('\t\ttooltip: ${vml_prop(properties, 'tooltip', "''")}')
	c.out.writeln('\t\thidden: ${vml_prop(properties, 'hidden', 'false')}')
	c.out.writeln('\t\tenabled: ${vml_prop(properties, 'enabled', 'true')}')
	c.out.writeln('\t\taccessibility_role: ${vml_prop(properties, 'accessibility_role', role_default)}')
	c.out.writeln('\t\taccessibility_label: ${vml_prop(properties, 'accessibility_label', label_default)}')
	c.out.writeln('\t\taccessibility_value: ${vml_prop(properties, 'accessibility_value', value_default)}')
	c.out.writeln('\t\tnative_style: ${vml_prop(properties, 'native', 'false')}')
	c.out.writeln('\t\tautocorrect: ${vml_prop(properties, 'autocorrect', 'true')}')
	c.out.writeln('\t\tpadding_left: ${vml_value(properties, 'padding_left', 'pad_left', 'f64(12)')}')
}

fn (mut c VmlCompiler) compile_progress_bar(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_progress_${suffix}'
	c.out.writeln('\t${base} := ui2.progress_bar(')
	c.out.writeln('\t\tid: ${vml_quote(node.id)}')
	c.out.writeln('\t\tframe: ${frame}')
	c.out.writeln('\t\tvalue: ${vml_prop(properties, 'value', 'f64(0)')}')
	c.out.writeln('\t\tmax: ${vml_prop(properties, 'max', 'f64(100)')}')
	c.out.writeln('\t\tbackground: ${vml_prop(properties, 'background', 'u32(0xe2e8f0)')}')
	c.out.writeln('\t\tcolor: ${vml_prop(properties, 'color', 'u32(0x3b82f6)')}')
	c.out.writeln('\t\tradius: ${vml_value(properties, 'corner_radius', 'radius', 'f64(4)')}')
	c.out.writeln('\t)')
	c.out.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.out.writeln('\t\t...${base}')
	c.out.writeln('\t\ton_event: ${action}')
	c.out.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.out.writeln('\t}')
}

fn (mut c VmlCompiler) compile_slider(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_slider_${suffix}'
	style := '${base}_style'
	orientation_value := '${base}_orientation'
	orientation := vml_prop(properties, 'orientation', 'ui2.Orientation.horizontal')
	c.out.writeln('\t${style} := ui2.SliderStyle{')
	c.out.writeln('\t\ttrack_color: ${vml_prop(properties, 'background', 'u32(0xcbd5e1)')}')
	c.out.writeln('\t\tvalue_track_color: ${vml_value(properties, 'value_track_color', 'color', 'u32(0x93c5fd)')}')
	c.out.writeln('\t\tthumb_color: ${vml_prop(properties, 'thumb_color', 'u32(0x2563eb)')}')
	c.out.writeln('\t\ttrack_width: ${vml_prop(properties, 'track_width', 'f64(4)')}')
	c.out.writeln('\t\tthumb_size: ${vml_prop(properties, 'thumb_size', 'f64(20)')}')
	c.out.writeln('\t}')
	c.out.writeln('\t${orientation_value} := ${orientation}')
	c.out.writeln('\t${base} := ui2.slider(')
	c.out.writeln('\t\tid: ${vml_quote(node.id)}')
	c.out.writeln('\t\ton_event: ${action}')
	c.out.writeln('\t\tframe: ${frame}')
	c.out.writeln('\t\tmin: ${vml_prop(properties, 'min', 'f64(0)')}')
	c.out.writeln('\t\tmax: ${vml_prop(properties, 'max', 'f64(100)')}')
	c.out.writeln('\t\tvalue: ${vml_value(properties, 'value', 'bind.value', 'f64(0)')}')
	c.out.writeln('\t\tstep: ${vml_prop(properties, 'step', 'f64(0)')}')
	c.out.writeln('\t\torientation: ${orientation_value}')
	c.out.writeln('\t\tpadding: ${vml_prop(properties, 'padding', 'f64(16)')}')
	c.out.writeln('\t\tvalue_track: ${vml_prop(properties, 'value_track', 'false')}')
	c.out.writeln('\t\tstyle: ${style}')
	c.out.writeln('\t)')
	c.out.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.out.writeln('\t\t...${base}')
	c.out.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.out.writeln('\t}')
}

fn (mut c VmlCompiler) compile_switch(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_switch_${suffix}'
	style := '${base}_style'
	c.out.writeln('\t${style} := ui2.SwitchStyle{')
	c.out.writeln('\t\tinactive_track_color: ${vml_prop(properties, 'inactive_color', 'u32(0xcbd5e1)')}')
	c.out.writeln('\t\tactive_track_color: ${vml_value(properties, 'active_color', 'color', 'u32(0x22c55e)')}')
	c.out.writeln('\t\tthumb_color: ${vml_prop(properties, 'thumb_color', 'u32(0xffffff)')}')
	c.out.writeln('\t\tdisabled_track_color: ${vml_prop(properties, 'disabled_track_color', 'u32(0xe2e8f0)')}')
	c.out.writeln('\t\tdisabled_thumb_color: ${vml_prop(properties, 'disabled_thumb_color', 'u32(0xf8fafc)')}')
	c.out.writeln('\t}')
	c.out.writeln('\t${base} := ui2.switch_control(')
	c.out.writeln('\t\tid: ${vml_quote(node.id)}')
	c.out.writeln('\t\ton_event: ${action}')
	c.out.writeln('\t\tframe: ${frame}')
	c.out.writeln('\t\tactive: ${vml_value(properties, 'active', 'bind.active', 'false')}')
	c.out.writeln('\t\tstyle: ${style}')
	c.out.writeln('\t)')
	c.out.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.out.writeln('\t\t...${base}')
	c.out.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.out.writeln('\t}')
}

fn (mut c VmlCompiler) compile_spinner(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	base := 'vml_spinner_${suffix}'
	box := '${base}_box'
	text_style := '${base}_text_style'
	c.out.writeln('\t${box} := ${c.box_style(properties)}')
	c.out.writeln('\t${text_style} := ${c.text_style(properties)}')
	c.out.writeln('\t${base} := ui2.spinner(')
	c.out.writeln('\t\tid: ${vml_quote(node.id)}')
	c.out.writeln('\t\ton_event: ${action}')
	c.out.writeln('\t\tframe: ${frame}')
	c.out.writeln('\t\ttext: ${vml_value(properties, 'text', 'bind.text', "''")}')
	c.out.writeln('\t\tvalues: ${c.option_values(node, scope)}')
	c.out.writeln('\t\ttext_autoupdate: ${vml_prop(properties, 'text_autoupdate', 'false')}')
	c.out.writeln('\t\tbox: ${box}')
	c.out.writeln('\t\ttext_style: ${text_style}')
	c.out.writeln('\t)')
	c.out.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.out.writeln('\t\t...${base}')
	c.out.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, properties, scope, '${base}.accessibility_role', '${base}.accessibility_label', '${base}.accessibility_value')
	c.out.writeln('\t}')
}

fn (mut c VmlCompiler) compile_message_box(node &VmlNode, suffix string, frame string, properties map[string]string, scope VmlScope, key string, action string) {
	mut actions := []string{}
	for child_index, child in node.children {
		if child.tag != 'Button' {
			continue
		}
		c.write_action_type_checks(child, '${suffix}_message_action_${child_index}', scope)
		child_id := vml_quote(child.id)
		child_action := c.compiled_event_value(child, 'on_tap', scope, child_id)
		text := if property := vml_find_property(child, 'text') {
			c.expr(property.expr, scope, .string_)
		} else {
			"''"
		}
		actions << 'ui2.MessageBoxAction{id: ${vml_quote(child.id)}, on_event: ${child_action}, title: ${text}}'
	}
	c.out.writeln('\tvml_message_box_${suffix} := ui2.custom_message_box(')
	c.out.writeln('\t\tid: ${vml_quote(node.id)}')
	c.out.writeln('\t\tframe: ${frame}')
	c.out.writeln('\t\ttitle: ${vml_prop(properties, 'title', "''")}')
	c.out.writeln('\t\ttext: ${vml_prop(properties, 'text', "''")}')
	c.out.writeln('\t\thidden: ${vml_prop(properties, 'hidden', 'false')}')
	c.out.writeln('\t\twidth: ${vml_prop(properties, 'dialog_width', 'f64(300)')}')
	c.out.writeln('\t\theight: ${vml_prop(properties, 'dialog_height', 'f64(150)')}')
	c.out.writeln('\t\tactions: ${vml_array_literal('ui2.MessageBoxAction', actions)}')
	c.out.writeln('\t)')
	c.out.writeln('\tvml_element_${suffix} := ui2.Element{')
	c.out.writeln('\t\t...vml_message_box_${suffix}')
	c.out.writeln('\t\ton_event: ${action}')
	c.out.writeln('\t\tkey: ${key}')
	c.write_common_fields(node, properties, scope, "''", "''", "''")
	c.out.writeln('\t}')
}
