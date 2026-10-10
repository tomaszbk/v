module parser

struct VmlParameter {
	name string
	typ  string
}

struct VmlInput {
	name          string
	typ           string
	line          int
	column        int
	bindable      bool
	parameters    []VmlParameter
	default_value &VmlExpr = unsafe { nil }
}

struct VmlData {
	name     string
	computed bool
	expr     &VmlExpr
}

struct VmlFunction {
	name       string
	parameters []VmlParameter
mut:
	body []&VmlExpr
}

fn (mut p VmlSourceParser) parse_vml_type() !string {
	mut prefix := ''
	for p.at().kind == .lsbr {
		p.pos++
		p.take(.rsbr)!
		prefix += '[]'
	}
	return prefix + p.take(.name)!.text
}

fn (mut p VmlSourceParser) parse_vml_parameters() ![]VmlParameter {
	p.take(.lpar)!
	mut parameters := []VmlParameter{}
	for p.at().kind != .rpar {
		name := p.take(.name)!
		if parameters.any(it.name == name.text) {
			return error('duplicate callback parameter `${name.text}`')
		}
		parameters << VmlParameter{ name: name.text, typ: p.parse_vml_type()! }
		if p.at().kind != .comma { break }
		p.pos++
	}
	p.take(.rpar)!
	return parameters
}

fn (mut p VmlSourceParser) parse_vml_document() !&VmlNode {
	if p.at().text != 'component' { return p.parse_node() }
	token := p.take(.name)!
	name := p.take(.name)!
	mut component := &VmlNode{ tag: '__Component', component_name: name.text, line: token.line, column: token.column }
	p.take(.lpar)!
	for p.at().kind != .rpar {
		mut bindable := false
		if p.at().text == 'bind' {
			p.pos++
			bindable = true
		}
		input_name := p.take(.name)!
		typ := p.parse_vml_type()!
		mut parameters := []VmlParameter{}
		if typ == 'event' { parameters = p.parse_vml_parameters()! }
		mut value := unsafe { nil }
		if p.at().kind == .assign {
			p.pos++
			value = p.parse_expression()!
		}
		if typ == 'slot' && (bindable || !isnil(value)) {
			return error('slots cannot be bindable or have default values')
		}
		if typ == 'event' && (bindable || !isnil(value)) {
			return error('events cannot be bindable or have default values')
		}
		component.inputs << VmlInput{ name: input_name.text, typ: typ, line: input_name.line, column: input_name.column, bindable: bindable, parameters: parameters, default_value: value }
		if p.at().kind != .comma { break }
		p.pos++
	}
	p.take(.rpar)!
	p.take(.lbrace)!
	for p.at().kind !in [.rbrace, .eof] {
		if p.at().text in ['state', 'computed'] {
			kind := p.take(.name)!
			data_name := p.take(.name)!
			p.take(.declare)!
			component.data << VmlData{ name: data_name.text, computed: kind.text == 'computed', expr: p.parse_expression()! }
		} else if p.at().text == 'ref' {
			p.pos++
			ref_name := p.take(.name)!
			component.refs << VmlParameter{ name: ref_name.text, typ: p.take(.name)!.text }
		} else if p.at().text == 'fn' {
			p.pos++
			fn_name := p.take(.name)!
			parameters := p.parse_vml_parameters()!
			body := p.parse_handler()!
			if body.kind != .block { return error('local functions require a body') }
			component.functions << VmlFunction{ name: fn_name.text, parameters: parameters, body: body.args }
		} else if p.at().text in ['mount', 'unmount', 'cleanup'] {
			kind := p.take(.name)!
			body := p.parse_handler()!
			if body.kind != .block { return error('lifecycle declarations require a body') }
			match kind.text {
				'mount' { component.mount << body.args }
				'unmount' { component.unmount << body.args }
				else { component.cleanup << body.args }
			}
		} else {
			component.children << p.parse_node()!
		}
		if p.at().kind == .semicolon { p.pos++ }
	}
	p.take(.rbrace)!
	if component.children.len != 1 {
		return error('component `${name.text}` requires exactly one root element')
	}
	validate_vml_component_names(component)!
	return component
}

fn validate_vml_component_names(node &VmlNode) ! {
	mut names := map[string]bool{}
	names['app'] = true
	for input in node.inputs {
		if input.name in names {
			return error('duplicate/reserved component member `${input.name}`')
		}
		names[input.name] = true
	}
	for data in node.data {
		if data.name in names { return error('duplicate/reserved component member `${data.name}`') }
		names[data.name] = true
	}
	for function in node.functions {
		if function.name in names {
			return error('duplicate/reserved component member `${function.name}`')
		}
		names[function.name] = true
	}
	for reference in node.refs {
		if reference.name in names {
			return error('ref name collides with component member `${reference.name}`')
		}
		names[reference.name] = true
	}
	for data in node.data {
		if data.computed {
			for input in node.inputs {
				if input.typ == 'event' && vml_expr_uses_path(data.expr, input.name) {
					return error('computed `${data.name}` cannot emit events')
				}
			}
			for function in node.functions {
				if vml_expr_uses_path(data.expr, function.name) {
					return error('computed `${data.name}` cannot call a handler')
				}
			}
		}
	}
	validate_vml_component_ids(node.children[0], mut names)!
	validate_vml_component_calls(node, node)!
	for function in node.functions {
		mut parameters := map[string]bool{}
		for parameter in function.parameters {
			if parameter.name in names || parameter.name in parameters {
				return error('local function parameter `${parameter.name}` collides with a component member or id')
			}
			parameters[parameter.name] = true
		}
	}
}

fn validate_vml_component_calls(node &VmlNode, owner &VmlNode) ! {
	for data in node.data { validate_vml_local_call_arity(data.expr, owner)! }
	for function in node.functions {
		for statement in function.body { validate_vml_local_call_arity(statement, owner)! }
	}
	for statement in node.mount { validate_vml_local_call_arity(statement, owner)! }
	for statement in node.unmount { validate_vml_local_call_arity(statement, owner)! }
	for statement in node.cleanup { validate_vml_local_call_arity(statement, owner)! }
	for property in node.properties { validate_vml_local_call_arity(property.expr, owner)! }
	for child in node.children {
		if child.tag != '__Component' { validate_vml_component_calls(child, owner)! }
	}
}

fn validate_vml_local_call_arity(expr &VmlExpr, owner &VmlNode) ! {
	if expr.kind == .call {
		for function in owner.functions {
			if expr.value == function.name && expr.args.len != function.parameters.len {
				return error('${expr.source}:${expr.line}:${expr.column}: local function `${expr.value}` requires ${function.parameters.len} arguments, received ${expr.args.len}')
			}
		}
		for input in owner.inputs {
			if input.typ == 'event' && expr.value == input.name && expr.args.len != input.parameters.len {
				return error('${expr.source}:${expr.line}:${expr.column}: event `${expr.value}` requires ${input.parameters.len} payload arguments, received ${expr.args.len}')
			}
		}
	}
	if !isnil(expr.left) { validate_vml_local_call_arity(expr.left, owner)! }
	if !isnil(expr.right) { validate_vml_local_call_arity(expr.right, owner)! }
	if !isnil(expr.third) { validate_vml_local_call_arity(expr.third, owner)! }
	for argument in expr.args { validate_vml_local_call_arity(argument, owner)! }
	for part in expr.parts {
		if !isnil(part.expr) { validate_vml_local_call_arity(part.expr, owner)! }
	}
}

fn validate_vml_component_ids(node &VmlNode, mut names map[string]bool) ! {
	if node.id.len > 0 {
		if node.id in names {
			return error('element id `${node.id}` collides with a component member or id')
		}
		names[node.id] = true
	}
	for child in node.children {
		if child.tag == '__Component' { continue }
		validate_vml_component_ids(child, mut names)!
	}
}

fn vml_external_callbacks(node &VmlNode) []string {
	mut result := []string{}
	for property in node.properties {
		if property.name.starts_with('on_') && property.expr.kind == .path && !property.expr.value.contains('.') && property.expr.value !in result {
			result << property.expr.value
		}
	}
	// Component function names are lexical locals, not enclosing V bindings.
	if node.tag == '__Component' { return result }
	for child in node.children {
		for name in vml_external_callbacks(child) { if name !in result { result << name } }
	}
	return result
}

fn (mut c VmlCompiler) compile_component(node &VmlNode, path string, input string, incoming VmlScope, default_key string, placement VmlPlacement) VmlScope {
	suffix := vml_var(path)
	for property in node.properties {
		if property.name in ['id', 'key', 'ref'] || property.name in vml_flex_child_properties || property.name in [
			'column_span',
			'row_span',
			'align_self_x',
			'align_self_y',
		] {
			continue
		}
		name := if property.name.starts_with('bind.') {
			property.name.all_after('bind.')
		} else {
			property.name
		}
		if property.name.starts_with('on_') {
			if !node.inputs.any(it.typ == 'event' && it.name == property.name.all_after('on_')) {
				c.writeln('$compile_error(' + vml_quote('unknown component event `${property.name}` on ${node.component_name}') + ')')
			}
		} else if !node.inputs.any(it.typ !in ['event', 'slot'] && it.name == name) {
			c.writeln('$compile_error(' + vml_quote('unknown component input `${property.name}` on ${node.component_name}') + ')')
		}
	}
	owner := 'vml_component_${suffix}'
	parent := incoming.component
	c.slot_scopes[owner] = incoming
	c.writeln('\tmut ${owner} := ${parent}.child(' + vml_quote(vml_builder_path(path)) + ') or { panic(err) }')
	mut scope := VmlScope{ component: owner, special: map[string]string{}, writable: map[string]string{}, ids: map[string]VmlNamedValue{} }
	for parameter in node.inputs {
		c.location = VmlLocation{ path: node.source, line: parameter.line, column: parameter.column }
		if parameter.typ == 'slot' { continue }
		if parameter.typ == 'event' {
			variable := 'vml_event_${suffix}_${parameter.name}'
			signature := parameter.parameters.map('${it.name} ${it.typ}').join(', ')
			payload_args := parameter.parameters.map(it.name).join(', ')
			action := vml_find_property(node, 'on_' + parameter.name)
			if handler := action {
				value := c.expr(handler.expr, incoming, .raw)
				mut captures := vml_callback_captures(handler.expr, incoming)
				listener := 'vml_listener_' + suffix + '_' + parameter.name
				if handler.expr.kind == .path {
					c.writeln('${listener} := ${value}')
					captures = [listener]
				}
				prefix := '\t${variable} := fn '
				capture_start := c.out.len + prefix.len
				c.writeln(prefix + '[] (${signature}) {')
				body_start := c.out.len
				for parameter_ in parameter.parameters { c.writeln('\t_ = ${parameter_.name}') }
				if handler.expr.kind == .path {
					types := parameter.parameters.map(it.typ).join(', ')
					c.writeln('\t$if ${listener} is fn () { ${listener}() } $else $if ${listener} is fn (${types}) { ${listener}(${payload_args}) } $else { $compile_error(' + vml_quote('event callback `${parameter.name}` requires fn() or the exact declared payload and a void return') + ') }')
				} else {
					c.writeln(c.compile_action(handler.expr, incoming))
				}
				c.finish_scope_captures(capture_start, body_start, captures)
				c.writeln('\t}')
			} else {
				c.writeln('\t${variable} := fn (${signature}) {')
				for parameter_ in parameter.parameters { c.writeln('\t_ = ${parameter_.name}') }
				c.writeln('\t}')
			}
			scope.special[parameter.name] = variable
			scope.event_parameters[parameter.name] = parameter.parameters
			continue
		}
		argument := vml_find_property(node, parameter.name)
		binding := vml_find_property(node, 'bind.' + parameter.name)
		if argument != none && binding != none {
			c.writeln("$compile_error('component input cannot have both value and bind connection')")
		}
		chosen := if property := binding {
			property.expr
		} else if property := argument {
			property.expr
		} else {
			parameter.default_value
		}
		if isnil(chosen) {
			c.writeln('$compile_error(' + vml_quote('required component input `${parameter.name}` is missing') + ')')
			continue
		}
		if property := binding {
			c.location = VmlLocation{ path: chosen.source, line: property.line, column: property.column }
		} else if property := argument {
			c.location = VmlLocation{ path: chosen.source, line: property.line, column: property.column }
		}
		value := c.expr(chosen, if argument != none || binding != none { incoming } else { scope }, .raw)
		variable := 'vml_input_${suffix}_${parameter.name}'
		input_scope := if argument != none || binding != none { incoming } else { scope }
		mut input_captures := vml_used_captures(value, vml_callback_captures(chosen, input_scope))
		if argument != none || binding != none {
			app_dependency := vml_expr_uses_path(chosen, 'app')
			if app_dependency { input_captures << 'mut ' + incoming.component }
			dependency := if app_dependency { incoming.component + '.watch_app()!; ' } else { '' }
			memo := variable + '_memo'
			input_captures = vml_used_captures(dependency + value, input_captures)
			c.writeln('mut ${memo} := ${owner}.computed[' + parameter.typ + '](' + vml_quote('@input:' + parameter.name) + ', fn [${input_captures.join(', ')}] () !${parameter.typ} { ${dependency} return ${value} }) or { panic(err) }')
			c.writeln('mut ${variable} := ${owner}.state_factory(' + vml_quote(parameter.name) + ', fn [mut ${memo}] () !${parameter.typ} { return ${memo}.get()! }) or { panic(err) }')
			c.writeln('${owner}.scope.effect(' + vml_quote('@input:' + parameter.name) + ', fn [mut ${memo}, mut ${variable}] () ! { ${variable}.set(${memo}.get()!)! }) or { panic(err) }')
		} else {
			c.writeln('mut ${variable} := ${owner}.state_factory(' + vml_quote(parameter.name) + ', fn [${input_captures.join(', ')}] () !${parameter.typ} { return ${value} }) or { panic(err) }')
		}
		scope.special[parameter.name] = '${variable}.get() or { panic(err) }'
		scope.special['__signal_' + parameter.name] = variable
		if binding != none {
			if !parameter.bindable {
				c.writeln('$compile_error(' + vml_quote('input `${parameter.name}` is not declared bindable') + ')')
			}
			setter := 'vml_set_input_${suffix}_${parameter.name}'
			captures := vml_callback_captures(chosen, incoming)
			mut all_captures := captures.clone()
			all_captures << 'mut ' + variable
			prefix := '\t${setter} := fn '
			capture_start := c.out.len + prefix.len
			c.writeln(prefix + '[] (value ${parameter.typ}) ! {')
			body_start := c.out.len
			c.writeln(c.compile_write(chosen.value, 'value', incoming))
			c.writeln('\t${variable}.set(value) or { panic(err) }')
			c.finish_scope_captures(capture_start, body_start, all_captures)
			c.writeln('}')
			scope.writable[parameter.name] = setter
		}
	}
	c.location = VmlLocation{ path: node.source, line: node.line, column: node.column }
	for reference in node.refs {
		variable := 'vml_ref_${suffix}_${reference.name}'
		c.writeln('\tmut ${variable} := ${owner}.ref[ui2.Vml${reference.typ}](' + vml_quote(reference.name) + ') or { panic(err) }')
		scope.special[reference.name] = variable
		scope.special['__ref_' + reference.name] = reference.typ
	}
	for data in node.data {
		variable := 'vml_state_${suffix}_${data.name}'
		value := c.expr(data.expr, scope, .raw)
		if data.computed {
			captures := vml_used_captures(value, vml_callback_captures(data.expr, scope))
			c.writeln('\tmut ${variable} := ${owner}.computed[typeof(${value})](' + vml_quote(data.name) + ', fn [${captures.join(', ')}] () !typeof(${value}) { return ${value} }) or { panic(err) }')
		} else {
			captures := vml_used_captures(value, vml_callback_captures(data.expr, scope))
			c.writeln('\tmut ${variable} := ${owner}.state_factory[typeof(${value})](' + vml_quote(data.name) + ', fn [${captures.join(', ')}] () !typeof(${value}) { return ${value} }) or { panic(err) }')
			scope.writable[data.name] = variable + '.set'
		}
		scope.special[data.name] = '${variable}.get() or { panic(err) }'
		scope.special['__signal_' + data.name] = variable
	}
	for function in node.functions {
		variable := 'vml_fn_${suffix}_${function.name}'
		mut function_scope := vml_clone_scope(scope)
		for parameter in function.parameters {
			function_scope.special[parameter.name] = parameter.name
		}
		body := &VmlExpr{ kind: .block, args: function.body }
		c.write_app_action_checks(body)
		action := c.compile_action(body, function_scope)
		captures := vml_used_captures(action, vml_callback_captures(body, scope))
		signature := function.parameters.map('${it.name} ${it.typ}').join(', ')
		c.writeln('\t${variable} := fn [${captures.join(', ')}] (${signature}) { ${action} }')
		scope.special[function.name] = variable
	}
	for kind in ['mount', 'unmount', 'cleanup'] {
		statements := match kind {
			'mount' { node.mount }
			'unmount' { node.unmount }
			else { node.cleanup }
		}
		if statements.len == 0 { continue }
		body := &VmlExpr{ kind: .block, args: statements }
		c.write_app_action_checks(body)
		action := c.compile_action(body, scope)
		captures := vml_used_captures(action, vml_callback_captures(body, scope))
		c.writeln('\t${owner}.on_${kind}(' + vml_quote(kind) + ', fn [${captures.join(', ')}] ()' + if kind == 'mount' {
			' !'
		} else {
			''
		} + ' { ' + action + ' }) or { panic(err) }')
	}
	key := if property := vml_find_property(node, 'key') {
		c.visual_property_value(node, property, property.expr, incoming)
	} else {
		default_key
	}
	// Invocation keys belong to the actual root, before it is retained. A nested
	// component forwards this same key instead of exposing its private root key.
	root := if key.len > 0 {
		&VmlNode{ ...node.children[0], properties: node.children[0].properties.filter(it.name != 'key') }
	} else {
		node.children[0]
	}
	c.compile_node(root, path + '.root', input, scope, key, placement)
	c.writeln('\tmut vml_node_${suffix} := vml_node_${suffix}_root')
	c.writeln('\t_ = vml_node_${suffix}')
	c.writeln('\tvml_element_${suffix} := vml_element_${suffix}_root')
	if reference := vml_find_property(node, 'ref') {
		c.location = VmlLocation{ path: reference.expr.source, line: reference.line, column: reference.column }
		mut control := root
		for control.tag == '__Component' { control = control.children[0] }
		ref_type := incoming.special['__ref_' + reference.expr.value] or { '' }
		if ref_type != control.tag {
			c.writeln('$compile_error(' + vml_quote('ref `${reference.expr.value}` requires ${ref_type}; received ${control.tag}') + ')')
		}
		c.writeln(c.expr(reference.expr, incoming, .raw) + '.bind(vml_node_${suffix}) or { panic(err) }')
	}
	mut exported := vml_clone_scope(incoming)
	if node.id.len > 0 {
		exported.ids[node.id] = VmlNamedValue{ frame_node: 'vml_node_${suffix}' }
	}
	return exported
}

fn (c &VmlCompiler) compile_write(target string, value string, scope VmlScope) string {
	if setter := scope.writable[target] { return '${setter}(${value}) or { panic(err) }' }
	if target.starts_with('app.') && target.count('.') == 1 { return '${target} = ${value}' }
	return '$compile_error(' + vml_quote('VML target `${target}` is read-only or unknown; use state or an explicit bind connection') + ')'
}

fn (c &VmlCompiler) compile_action(expr &VmlExpr, scope VmlScope) string {
	if expr.kind == .block { return expr.args.map(c.compile_action(it, scope)).join('\n') }
	if expr.kind == .assignment {
		return c.compile_write(expr.left.value, c.expr(expr.right, scope, .raw), scope)
	}
	if expr.kind == .call {
		if parameters := scope.event_parameters[expr.value] {
			mut statements := []string{}
			mut payload_values := []string{}
			for index, parameter in parameters {
				if index >= expr.args.len { break }
				argument := 'vml_payload_' + index.str()
				statements << argument + ' := ' + c.event_payload_value(expr.args[index], parameter.typ, scope)
				statements << '$if ' + argument + ' !is ' + parameter.typ + ' { $compile_error(' + vml_quote('event `' + expr.value + '` payload `' + parameter.name + '` requires exact type ' + parameter.typ) + ') }'
				payload_values << argument
			}
			statements << (scope.special[expr.value] or { expr.value }) + '(' + payload_values.join(', ') + ')'
			return 'if true {\n' + statements.join('\n') + '\n}'
		}
	}
	return c.expr(expr, scope, .raw)
}

// Payload temporaries validate exact types without losing V's contextual enum
// literals or empty arrays. Expressions still execute once, inside the action.
fn (c &VmlCompiler) event_payload_value(expr &VmlExpr, expected string, scope VmlScope) string {
	if expr.kind == .path && expr.value.starts_with('.') { return expected + expr.value }
	if expr.kind == .conditional {
		return '(if ' + c.expr(expr.left, scope, .bool_) + ' { ' + c.event_payload_value(expr.right, expected, scope) + ' } else { ' + c.event_payload_value(expr.third, expected, scope) + ' })'
	}
	if expr.kind == .array && expected.starts_with('[]') {
		return vml_array_literal(expected[2..], expr.args.map(c.event_payload_value(it, expected[2..], scope)))
	}
	return c.expr(expr, scope, .raw)
}

fn (mut c VmlCompiler) retain_element(node &VmlNode, suffix string, scope VmlScope, placement VmlPlacement) {
	owner := scope.component
	variable := 'vml_node_${suffix}'
	declaration := 'vml_declaration_${suffix}'
	authored_width := vml_find_property(node, 'width') != none
	authored_height := vml_find_property(node, 'height') != none
	inherited := placement in [.normal, .inherited_preferred]
	c.writeln('\tmut ${variable} := ${owner}.element(${declaration}, identity: ${c.node_identity(node, suffix, scope)}, authored_width: ${authored_width}, authored_height: ${authored_height}, inherit_width: ${inherited && !authored_width}, inherit_height: ${inherited && !authored_height}) or { panic(' + vml_quote('${node.source}:${node.line}:${node.column}: ') + ' + err.msg()) }')
	c.writeln('\t${variable}.set_element_children(${declaration}.children) or { panic(' + vml_quote('${node.source}:${node.line}:${node.column}: ') + ' + err.msg()) }')
	c.compile_structural_effect(node, suffix, scope)
	if reference := vml_find_property(node, 'ref') {
		ref_type := scope.special['__ref_' + reference.expr.value] or { '' }
		if ref_type != node.tag {
			c.writeln('$compile_error(' + vml_quote('ref `${reference.expr.value}` requires ${ref_type}; received ${node.tag}') + ')')
		}
		c.writeln(c.expr(reference.expr, scope, .raw) + '.bind(${variable}) or { panic(err) }')
	}
	for property in node.properties {
		if property.name in ['id', 'ref'] || vml_is_event(property.name) || property.expr.kind == .literal {
			continue
		}
		if !vml_property_is_reactive(property, scope) { continue }
		app_dependency := vml_expr_uses_path(property.expr, 'app')
		value := c.property_effect_value(node, property, suffix, scope)
		patch := vml_property_patch(node, property.name, value) or { continue }
		mut captures := vml_callback_captures(property.expr, scope)
		captures << c.property_memo_capture(suffix, property.name)
		if app_dependency && ('mut ' + owner) !in captures { captures << 'mut ' + owner }
		dependency := if app_dependency { owner + '.watch_app() or { panic(err) }; ' } else { '' }
		updated := if property.name in ['x', 'y', 'width', 'height'] {
			'element.with_layout_frame(ui2.Rect{...(element.layout_input or { element.frame }), ${property.name}: ${value}})'
		} else {
			'ui2.Element{...element, ${patch}}'
		}
		captures = vml_used_captures(dependency + updated, captures)
		c.writeln('\t${variable}.effect(' + vml_quote(property.name) + ', fn [${captures.join(', ')}] (element ui2.Element) !ui2.Element { ${dependency} return ${updated} }) or { panic(err) }')
	}
	c.compile_content_effect(node, suffix, scope)
	c.compile_child_segments(node, suffix, scope)
	c.writeln('\tvml_element_${suffix} := ${variable}.element()')
	c.writeln('\t_ = vml_element_${suffix}')
}

fn expand_vml_slots(node &VmlNode, content map[string][]&VmlNode) !&VmlNode {
	mut result := vml_clone_node(node)
	mut children := []&VmlNode{}
	for child in result.children {
		if child.tag == 'Slot' {
			name := if property := vml_find_property(child, 'name') {
				property.expr.value
			} else {
				'content'
			}
			supplied := content[name] or { return error('unknown slot `${name}`') }
			for value in supplied {
				children << &VmlNode{ ...vml_clone_node(value), caller_content: true }
			}
		} else if child.tag == '__Component' {
			children << child
		} else {
			children << expand_vml_slots(child, content)!
		}
	}
	result.children = children
	return result
}

// Parser workers merge local ASTs with shifted node ids. Inferred closure
// annotations hold expression links and relocate with the ordinary child links.
fn shift_vml_inferred_type(typ string, shift int) string {
	mut result := typ
	mut offset := 0
	marker := 'typeof(__vml_expr_'
	for offset < result.len {
		start := result[offset..].index(marker) or { break } + offset
		end := result[start..].index(')') or { break } + start
		value := result[start + marker.len..end].int()
		replacement := marker + (value + shift).str() + ')'
		result = result[..start] + replacement + result[end + 1..]
		offset = start + replacement.len
	}
	return result
}
