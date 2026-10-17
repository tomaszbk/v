// Grammar tests for the shared VML parser: tokens, expressions, elements,
// components, named styles and local component expansion.
import vml

// tree renders an expression fully parenthesized, so tests can check precedence.
fn tree(e &vml.Expr) string {
	return match e.kind {
		.literal {
			if e.quoted { '"${e.value}"' } else { e.value }
		}
		.path {
			e.value
		}
		.call {
			e.value + '(' + e.args.map(tree(it)).join(', ') + ')' + if e.fallible {
				'!'
			} else {
				''
			}
		}
		.unary {
			'(${e.value}${tree(e.left)})'
		}
		.binary {
			'(${tree(e.left)} ${e.value} ${tree(e.right)})'
		}
		.assignment {
			'${tree(e.left)} = ${tree(e.right)}'
		}
		.block {
			'{' + e.args.map(tree(it)).join('; ') + '}'
		}
		.array {
			'[' + e.args.map(tree(it)).join(', ') + ']'
		}
		.conditional {
			'(${tree(e.left)} ? ${tree(e.right)} : ${tree(e.third)})'
		}
		.interpolation {
			mut parts := []string{}
			for part in e.parts {
				parts << if isnil(part.expr) { '"${part.text}"' } else { '\${${tree(part.expr)}}' }
			}
			parts.join(' ')
		}
	}
}

fn expr(source string) !&vml.Expr {
	mut p := vml.new_parser(vml.tokenize(source)!, '')
	e := p.parse_expression()!
	p.take(.eof)!
	return e
}

fn handler(source string) !&vml.Expr {
	mut p := vml.new_parser(vml.tokenize(source)!, '')
	e := p.parse_handler()!
	p.take(.eof)!
	return e
}

fn parse_error(source string) string {
	vml.parse_source(source) or { return err.msg() }
	return ''
}

fn test_tokens_carry_kinds_text_and_positions() {
	tokens := vml.tokenize('Row {\n  Label(text: "hi", size: 12.5)\n}')!
	assert tokens.map(it.kind) == [vml.TokenKind.name, .lbrace, .name, .lpar, .name, .colon, .string_,
		.comma, .name, .colon, .number, .rpar, .rbrace, .eof]
	assert tokens.map(it.text) == ['Row', '{', 'Label', '(', 'text', ':', 'hi', ',', 'size', ':',
		'12.5', ')', '}', '']
	assert tokens.map('${it.line}:${it.column}') == ['1:1', '1:5', '2:3', '2:8', '2:9', '2:13',
		'2:15', '2:19', '2:21', '2:25', '2:27', '2:31', '3:1', '3:2']
	// One location per decoded byte, then the closing quote.
	assert tokens[6].string_locations.map(it.column) == [16, 17, 18]
}

fn test_operator_tokens_comments_and_escapes() {
	tokens := vml.tokenize('a := b++ != c-- == d <= e >= f && g || !h < i > j = k; [x] ? 1 % 2 * 3 / 4 // gone\nnext')!
	assert tokens.map(it.text) == ['a', ':=', 'b', '++', '!=', 'c', '--', '==', 'd', '<=', 'e',
		'>=', 'f', '&&', 'g', '||', '!', 'h', '<', 'i', '>', 'j', '=', 'k', ';', '[', 'x', ']',
		'?', '1', '%', '2', '*', '3', '/', '4', 'next', '']
	assert tokens[1].kind == .declare
	assert tokens[16].kind == .not
	assert tokens[22].kind == .assign
	assert tokens[36].line == 2
	strings := vml.tokenize(r'"a\nb\"c" ' + "'#x'")!
	assert strings[0].text == 'a\nb"c'
	assert strings[0].string_locations.map(it.column) == [2, 3, 5, 6, 8, 9]
	assert strings[1].kind == .string_
	assert strings[1].text == '#x'
	names := vml.tokenize('#FF00AA app.items.len _private 10.5.3')!
	assert names.map(it.text) == ['#FF00AA', 'app.items.len', '_private', '10.5', '.3', '']
	assert names[4].kind == .name
}

fn test_lexer_errors() {
	for source, message in {
		'a & b':   'expected `&&` at line 1'
		'a\n| b':  'expected `||` at line 2'
		'"abc':    'unterminated string at line 1'
		'a\n\n@b': 'unexpected character `@` at line 3'
	} {
		vml.tokenize(source) or {
			assert err.msg() == message
			continue
		}
		assert false, source
	}
}

fn test_expression_precedence_and_associativity() {
	assert tree(expr('a + b * c > 2 && !d || e ? "x" : f(1, g)!')!) == '(((((a + (b * c)) > 2) && (!d)) || e) ? "x" : f(1, g)!)'
	assert tree(expr('a == b < c')!) == '(a == (b < c))'
	assert tree(expr('a - b - c')!) == '((a - b) - c)'
	assert tree(expr('-a * b % c / d')!) == '((((-a) * b) % c) / d)'
	assert tree(expr('(a + b) * c')!) == '((a + b) * c)'
	assert tree(expr('a ? b : c ? d : e')!) == '(a ? b : (c ? d : e))'
	assert tree(expr('!!x != false')!) == '((!(!x)) != false)'
	assert tree(expr('[1, "s", item.name, []]')!) == '[1, "s", item.name, []]'
	assert tree(expr('app.items.len')!) == 'app.items.len'
	assert tree(expr('name_field.focus()!')!) == 'name_field.focus()!'
	assert tree(expr('.start')!) == '.start'
}

fn test_expression_kinds_and_positions() {
	literal := expr('12')!
	assert literal.kind == .literal && !literal.quoted
	assert expr('true')!.kind == .literal
	assert expr('"text"')!.quoted
	assert expr('app.value')!.kind == .path
	binary := expr('a +\n  b')!
	assert binary.kind == .binary
	assert binary.line == 1 && binary.column == 3
	assert binary.right.line == 2 && binary.right.column == 3
	call := expr('  f(x)')!
	assert call.kind == .call && call.column == 3 && call.args.len == 1
	array := expr('[a]')!
	assert array.kind == .array && array.column == 1
	if _ := expr('a +') {
		assert false
	} else {
		assert err.msg() == 'expected expression, got eof (``) at line 1'
	}
	if _ := expr('f(a') {
		assert false
	} else {
		assert err.msg() == ':1:4: expected rpar, got eof (``)'
	}
}

fn test_interpolation_parts_map_back_to_the_source() {
	root := vml.parse_source('Label(text: "n: \${app.count + 1}!")')!
	value := root.properties[0].expr
	assert value.kind == .interpolation
	assert tree(value) == '"n: " \${(app.count + 1)} "!"'
	sum := value.parts[1].expr
	assert sum.line == 1 && sum.column == 29
	assert sum.left.column == 19
	// A decoded `\n` escape does not shift the positions of later fragments.
	escaped := vml.parse_source(r'Label(text: "a\n${x}")')!
	part := escaped.properties[0].expr.parts[1].expr
	assert part.value == 'x'
	assert part.line == 1 && part.column == 19
	multiline := vml.parse_source('View {\n    Label(text: "prefix\${app.first}\n\${app.second}")\n}')!
	parts := multiline.children[0].properties[0].expr.parts
	assert parts[1].expr.line == 2 && parts[1].expr.column == 26
	assert parts[3].expr.line == 3 && parts[3].expr.column == 3
	plain := vml.parse_source('Label(text: "no interpolation")')!
	assert plain.properties[0].expr.kind == .literal
	assert parse_error('Label(text: "\${a b}")') == 'invalid interpolation at line 1: :1:18: expected eof, got name (`b`)'
	assert parse_error('Label(text: "\${a")') == 'unterminated interpolation at line 1'
}

fn test_elements_properties_children_and_ids() {
	root := vml.parse_source('Column(id: "col", spacing: 4, bind.value: app.level) {\n  Label(text: "a")\n  Row { Button }\n  MenuSeparator()\n}')!
	assert root.tag == 'Column'
	assert root.id == 'col'
	assert root.line == 1 && root.column == 1
	assert root.properties.map(it.name) == ['id', 'spacing', 'bind.value']
	assert root.properties[1].line == 1 && root.properties[1].column == 19
	assert root.properties[1].expr.column == 28
	spacing := vml.find_property(root, 'spacing') or { panic('missing spacing') }
	assert spacing.expr.value == '4'
	assert vml.find_property(root, 'width') == none
	assert root.children.map(it.tag) == ['Label', 'Row', 'MenuSeparator']
	assert root.children[1].line == 3 && root.children[1].column == 3
	assert root.children[1].children[0].tag == 'Button'
	assert root.children[2].properties.len == 0
	trailing := vml.parse_source('Menu(\n    title: "File",\n) {}')!
	assert trailing.properties.len == 1
}

fn test_handlers_and_actions() {
	root := vml.parse_source('Row {\n  Button(on_click: { count = 0; changed(count) })\n  Button(on_click: count++)\n  Button(on_click: app.save)\n  Button(on_click: app.total = app.total - 1)\n}')!
	block := root.children[0].properties[0].expr
	assert block.kind == .block
	assert block.line == 2 && block.column == 20
	assert tree(block) == '{count = 0; changed(count)}'
	increment := root.children[1].properties[0].expr
	assert increment.kind == .assignment
	assert tree(increment) == 'count = (count + 1)'
	assert increment.column == 25
	assert root.children[2].properties[0].expr.kind == .path
	assert tree(root.children[3].properties[0].expr) == 'app.total = (app.total - 1)'
	assert tree(handler('{ a--; b() }')!) == '{a = (a - 1); b()}'
	assert parse_error('Button(on_click: "x")') == 'callback `on_click` requires a typed function reference or an action at line 1:8'
	assert parse_error('Button(on_click: item.count = 1)') == 'assignment target `item.count` is read-only at line 1, column 18'
	assert parse_error('Button(on_click: app.a.b++)') == 'assignment target `app.a.b` is read-only at line 1, column 18'
}

fn test_element_errors() {
	assert parse_error('Label(text: "a", text: "b")') == 'duplicate VML argument `text` at line 1:18'
	assert parse_error('Label(id: name)') == 'id must be a quoted local name at line 1:7'
	assert parse_error('Column { spacing: 4 }') == ':1:10: element arguments use `Name(name: value)`; state/computed belong to the component body'
	assert parse_error('Column { state x := 1 }') == ':1:10: element arguments use `Name(name: value)`; state/computed belong to the component body'
	assert parse_error('Label(text "a")') == ':1:12: expected colon, got string_ (`a`)'
	assert parse_error('Label Label') == ':1:7: expected eof, got name (`Label`)'
}

fn test_component_declarations() {
	root := vml.parse_source('component Counter(title string = "Count", bind value int = 0, items []string,
    changed event(value int, label string), content slot) {
    state count := 0
    computed doubled := count * 2
    ref field TextInput
    style surface = [padding(4)]
    fn bump(step int) { count = count + step; changed(count, "x") }
    mount { app.mounted() }
    unmount { app.unmounted() }
    cleanup { app.cleaned() }
    Column(id: "panel", style: [surface]) { Slot {} }
}')!
	assert root.tag == vml.component_tag
	assert root.component_name == 'Counter'
	assert root.line == 1 && root.column == 1
	assert root.inputs.map('${it.name} ${it.typ}') == ['title string', 'value int', 'items []string',
		'changed event', 'content slot']
	assert root.inputs.map(it.bindable) == [false, true, false, false, false]
	assert root.inputs[0].default_value.value == 'Count'
	assert root.inputs[1].default_value.value == '0'
	assert isnil(root.inputs[2].default_value)
	assert root.inputs[0].line == 1 && root.inputs[0].column == 19
	assert root.inputs[3].line == 2 && root.inputs[3].column == 5
	assert root.inputs[3].parameters.map('${it.name} ${it.typ}') == ['value int', 'label string']
	assert root.data.map(it.name) == ['count', 'doubled']
	assert root.data.map(it.computed) == [false, true]
	assert root.refs.map('${it.name} ${it.typ}') == ['field TextInput']
	assert root.styles.map(it.name) == ['surface']
	assert root.functions.len == 1
	assert root.functions[0].name == 'bump'
	assert root.functions[0].parameters.map('${it.name} ${it.typ}') == ['step int']
	assert root.functions[0].body.map(tree(it)) == ['count = (count + step)', 'changed(count, "x")']
	assert root.mount.map(tree(it)) == ['app.mounted()']
	assert root.unmount.len == 1 && root.cleanup.len == 1
	assert root.children.len == 1
	panel := root.children[0]
	assert panel.id == 'panel'
	assert panel.children[0].tag == 'Slot'
	// Named styles are inlined into every property expression.
	assert tree(panel.properties[1].expr) == '[[padding(4)]]'
}

fn test_component_errors() {
	for source, message in {
		'component A() { Label Label }':                                    'component `A` requires exactly one root element'
		'component A(x int, x string) { Label }':                           'duplicate/reserved component member `x`'
		'component A(app int) { Label }':                                   'duplicate/reserved component member `app`'
		'component A() { state color := 1 Label }':                         'duplicate/reserved component member `color`'
		'component A() { state a := 1 ref a TextInput Label }':             'ref name collides with component member `a`'
		'component A(e event(v int)) { computed c := e(1) Label }':         'computed `c` cannot emit events'
		'component A() { fn f() { app.x = 1 } computed c := f() Label }':   'computed `c` cannot call a handler'
		'component A() { fn f(a int) { app.x = a } Label(on_click: f()) }': ':1:59: local function `f` requires 1 arguments, received 0'
		'component A(e event(v int)) { Label(on_click: e()) }':             ':1:47: event `e` requires 1 payload arguments, received 0'
		'component A(content slot = 1) { Label }':                          'slots cannot be bindable or have default values'
		'component A(bind e event()) { Label }':                            'events cannot be bindable or have default values'
		'component A() { Label(id: "a") { Label(id: "a") } }':              'element id `a` collides with a component member or id'
		'component A(a int) { Label(id: "a") }':                            'element id `a` collides with a component member or id'
		'component A() { fn f(a int, a int) { app.x = a } Label }':         'duplicate callback parameter `a`'
		'component A(x int) { fn f(x int) { app.y = x } Label }':           'local function parameter `x` collides with a component member or id'
		'component A() { fn f() app.x Label }':                             'local functions require a body'
		'component A() { mount app.x() Label }':                            'lifecycle declarations require a body'
		'component A() { Label } component A() { Label } Row':              'duplicate component `A` at line 1, column 25'
		'component A() { B } component B() { A } Row { A }':                'cyclic VML component: A -> B -> A'
		'component A() { style app = [] Label }':                           ':1:23: style requires a nonreserved local name'
	} {
		assert parse_error(source) == message, source
	}
}

fn test_local_components_expand_with_slots() {
	root := vml.parse_source('component Card(title string, header slot, content slot) {
    Column { Label(text: title) Slot(name: "header") Slot {} }
}
Row {
    Card(title: "A", id: "card") {
        Slot(name: "header") { Label(text: "H") }
        Slot(name: "content") { Button }
    }
    Card(title: "B") { Label(text: "implicit") }
}')!
	assert root.tag == 'Row'
	first := root.children[0]
	assert first.tag == vml.component_tag
	assert first.component_name == 'Card'
	assert first.imported
	assert first.id == 'card'
	assert first.line == 1 && first.column == 1
	assert first.properties.map(it.name) == ['title', 'id']
	assert first.properties[0].line == 5
	column := first.children[0]
	assert column.children.map(it.tag) == ['Label', 'Label', 'Button']
	assert column.children.map(it.caller_content) == [false, true, true]
	assert column.children[1].line == 6
	second := root.children[1].children[0]
	assert second.children.map(it.tag) == ['Label', 'Label']
	assert second.children[1].properties[0].expr.value == 'implicit'
	// Definitions can be used before they are declared.
	nested := vml.parse_source('component Outer() { Inner {} }\ncomponent Inner() { Label }\nOuter')!
	assert nested.component_name == 'Outer'
	assert nested.children[0].component_name == 'Inner'
	assert nested.children[0].children[0].tag == 'Label'
	// A document made only of declarations exposes its last component.
	last := vml.parse_source('component Inner() { Label }\ncomponent Outer() { Inner }')!
	assert last.component_name == 'Outer'
	assert last.children[0].component_name == 'Inner'
	for source, message in {
		'component C() { Label } Row { C { Label } }':                                                              'component `C` does not declare a content slot'
		'component C(header slot) { Column { Slot(name: "header") } } Row { C { Label } }':                         'implicit content requires a slot named `content`'
		'component C(header slot) { Column { Slot(name: "header") } } Row { C { Slot(name: "nope") { Label } } }':  'unknown component slot `nope`'
		'component C(header slot) { Column { Slot(name: "header") } } Row { C { Slot(name: "header") {} Label } }': 'named slot content requires Slot(name: "name") blocks'
		'component C(header slot) { Column { Slot(name: "other") } } Row { C { Slot(name: "header") { Label } } }': 'unknown slot `other`'
	} {
		assert parse_error(source) == message, source
	}
}

fn test_named_styles_resolve_lexically() {
	root := vml.parse_source('style base = [padding(4)]
style card = [base, background(#fff)]
Column(style: [card, app.extra]) {
    Label(style: app.on ? card : [])
    Button(style: [hover([card]), focus([base])])
}')!
	assert root.styles.map(it.name) == ['base', 'card']
	assert tree(root.properties[0].expr) == '[[[padding(4)], background(#fff)], app.extra]'
	assert tree(root.children[0].properties[0].expr) == '(app.on ? [[padding(4)], background(#fff)] : [])'
	assert tree(root.children[1].properties[0].expr) == '[hover([[[padding(4)], background(#fff)]]), focus([[padding(4)]])]'
	// Resolution keeps the reference's position on unchanged expressions.
	assert root.properties[0].expr.args[1].column == 22
	// Document styles are visible inside local components, before their own styles.
	local := vml.parse_source('style base = [padding(4)]
component Card() { style own = [base] View(style: [own]) }
Card')!
	assert local.styles.map(it.name) == ['base', 'own']
	assert tree(local.children[0].properties[0].expr) == '[[[padding(4)]]]'
	for source, message in {
		'style a = [b] style b = [a] Label':        'cyclic style: a -> b -> a at line 1, column 26'
		'style a = [] style a = [] Label':          'duplicate style `a` at line 1, column 20'
		'style color = [] Label':                   ':1:7: style requires a nonreserved local name'
		'style a.b = [] Label':                     ':1:7: style requires a nonreserved local name'
		'style a = 1 Label':                        ':1:7: style declaration requires a list'
		'style a = [] Label(id: "a")':              'element id `a` collides with a component member or id'
		'Column { Label(id: "x") Label(id: "x") }': 'element id `x` collides with a component member or id'
	} {
		assert parse_error(source) == message, source
	}
}

struct Recorder {
mut:
	items []string
}

fn test_validate_style_hook_sees_each_resolved_style() {
	mut recorder := &Recorder{}
	config := vml.ParseConfig{
		validate_style: fn [mut recorder] (owner &vml.Node, style &vml.Expr) ! {
			owner_name := if owner.tag == vml.component_tag {
				owner.component_name
			} else {
				owner.tag
			}
			recorder.items << '${owner_name}: ${vml.expr_text(style)}'
		}
	}
	vml.parse_source('style base = [padding(4)]
component Card() { style own = [base, radius(2)] View }
Column { Card }', config)!
	assert recorder.items == ['Card: [padding(4)]', 'Card: [[padding(4)], radius(2)]',
		'Column: [padding(4)]']
	rejecting := vml.ParseConfig{
		validate_style: fn (owner &vml.Node, style &vml.Expr) ! {
			return vml.expr_error(style.args[0], 'unknown style helper `${style.args[0].value}`')
		}
	}
	vml.parse_source('style s = [shine(1)]\nLabel', rejecting) or {
		assert err.msg() == 'unknown style helper `shine` at line 1, column 12'
		return
	}
	assert false
}

fn test_ast_helpers() {
	root := vml.parse_source('component C(x int = app.width) { state s := item.count fn f() { app.go() } Column { Label(text: "\${index}") } }')!
	assert vml.node_uses_path(root, 'app')
	assert vml.node_uses_path(root, 'item')
	assert vml.node_uses_path(root, 'index')
	assert !vml.node_uses_path(root, 'model')
	assert vml.expr_uses_path(root.data[0].expr, 'item')
	assert !vml.expr_uses_path(root.data[0].expr, 'ite')
	assert vml.expr_text(vml.parse_source('Label(on_click: { a = b ? 1 : f(2, [x]); c++ })')!.properties[0].expr) == '{a = b ? 1 : f(2, [x]); c = c + 1}'
	mut copy := vml.clone_node(root)
	copy.children = []
	assert root.children.len == 1
	mut sourced := vml.parse_source('Column { Label(text: a + b) }')!
	vml.set_source(mut sourced, 'screen.vml')
	label := sourced.children[0]
	assert label.source == 'screen.vml'
	assert label.properties[0].expr.right.source == 'screen.vml'
	assert vml.node_error(label, 'bad').msg() == 'screen.vml:1:10: bad'
	assert vml.expr_error(label.properties[0].expr, 'worse').msg() == 'screen.vml:1:24: worse'
	assert vml.node_error(root, 'bad').msg() == 'bad at line 1, column 1'
}
