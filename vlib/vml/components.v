module vml

fn (mut p Parser) parse_type() !string {
	mut prefix := ''
	for p.at().kind == .lsbr {
		p.pos++
		p.take(.rsbr)!
		prefix += '[]'
	}
	return prefix + p.take(.name)!.text
}

fn (mut p Parser) parse_parameters() ![]Parameter {
	p.take(.lpar)!
	mut parameters := []Parameter{}
	for p.at().kind != .rpar {
		name := p.take(.name)!
		if parameters.any(it.name == name.text) {
			return error('duplicate callback parameter `${name.text}`')
		}
		parameters << Parameter{ name: name.text, typ: p.parse_type()! }
		if p.at().kind != .comma { break }
		p.pos++
	}
	p.take(.rpar)!
	return parameters
}

fn (mut p Parser) parse_component() !&Node {
	if p.at().text != 'component' { return p.parse_node() }
	token := p.take(.name)!
	name := p.take(.name)!
	mut component := &Node{ tag: component_tag, component_name: name.text, line: token.line, column: token.column }
	p.take(.lpar)!
	for p.at().kind != .rpar {
		mut bindable := false
		if p.at().text == 'bind' {
			p.pos++
			bindable = true
		}
		input_name := p.take(.name)!
		typ := p.parse_type()!
		mut parameters := []Parameter{}
		if typ == 'event' { parameters = p.parse_parameters()! }
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
		component.inputs << Input{ name: input_name.text, typ: typ, line: input_name.line, column: input_name.column, bindable: bindable, parameters: parameters, default_value: value }
		if p.at().kind != .comma { break }
		p.pos++
	}
	p.take(.rpar)!
	p.take(.lbrace)!
	for p.at().kind !in [.rbrace, .eof] {
		if p.at().text == 'style' {
			component.styles << p.parse_style()!
		} else if p.at().text in ['state', 'computed'] {
			kind := p.take(.name)!
			data_name := p.take(.name)!
			p.take(.declare)!
			component.data << Data{ name: data_name.text, computed: kind.text == 'computed', expr: p.parse_expression()! }
		} else if p.at().text == 'ref' {
			p.pos++
			ref_name := p.take(.name)!
			component.refs << Parameter{ name: ref_name.text, typ: p.take(.name)!.text }
		} else if p.at().text == 'fn' {
			p.pos++
			fn_name := p.take(.name)!
			parameters := p.parse_parameters()!
			body := p.parse_handler()!
			if body.kind != .block { return error('local functions require a body') }
			component.functions << Function{ name: fn_name.text, parameters: parameters, body: body.args }
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
	validate_component_names(component)!
	return component
}

fn validate_component_names(node &Node) ! {
	mut names := map[string]bool{}
	for name in ['app', 'color', 'spacing', 'radius', 'typography'] { names[name] = true }
	for input in node.inputs {
		if input.name in names {
			return error('duplicate/reserved component member `${input.name}`')
		}
		names[input.name] = true
	}
	for style in node.styles {
		if style.name in names {
			return error('duplicate/reserved component member `${style.name}`')
		}
		names[style.name] = true
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
				if input.typ == 'event' && expr_uses_path(data.expr, input.name) {
					return error('computed `${data.name}` cannot emit events')
				}
			}
			for function in node.functions {
				if expr_uses_path(data.expr, function.name) {
					return error('computed `${data.name}` cannot call a handler')
				}
			}
		}
	}
	validate_component_ids(node.children[0], mut names)!
	validate_component_calls(node, node)!
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

fn validate_component_calls(node &Node, owner &Node) ! {
	for data in node.data { validate_local_call_arity(data.expr, owner)! }
	for function in node.functions {
		for statement in function.body { validate_local_call_arity(statement, owner)! }
	}
	for statement in node.mount { validate_local_call_arity(statement, owner)! }
	for statement in node.unmount { validate_local_call_arity(statement, owner)! }
	for statement in node.cleanup { validate_local_call_arity(statement, owner)! }
	for property in node.properties { validate_local_call_arity(property.expr, owner)! }
	for child in node.children {
		if child.tag != component_tag { validate_component_calls(child, owner)! }
	}
}

fn validate_local_call_arity(expr &Expr, owner &Node) ! {
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
	if !isnil(expr.left) { validate_local_call_arity(expr.left, owner)! }
	if !isnil(expr.right) { validate_local_call_arity(expr.right, owner)! }
	if !isnil(expr.third) { validate_local_call_arity(expr.third, owner)! }
	for argument in expr.args { validate_local_call_arity(argument, owner)! }
	for part in expr.parts {
		if !isnil(part.expr) { validate_local_call_arity(part.expr, owner)! }
	}
}

fn validate_component_ids(node &Node, mut names map[string]bool) ! {
	if node.id.len > 0 {
		if node.id in names {
			return error('element id `${node.id}` collides with a component member or id')
		}
		names[node.id] = true
	}
	for child in node.children {
		if child.tag == component_tag { continue }
		validate_component_ids(child, mut names)!
	}
}
