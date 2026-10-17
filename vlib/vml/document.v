module vml

// A document is `import` directives (see `parse_file`), then any number of
// `style name = [...]` and `component Name(...) { ... }` declarations, then one
// root element. Local components can invoke each other in any order; named
// styles are lexical values resolved before lowering.

fn (mut p Parser) parse_style() !Style {
	p.take(.name)!
	name := p.take(.name)!
	if name.text.contains('.') || name.text in ['app', 'color', 'spacing', 'radius', 'typography'] {
		return error('${p.file}:${name.line}:${name.column}: style requires a nonreserved local name')
	}
	p.take(.assign)!
	expr := p.parse_expression()!
	if expr.kind != .array {
		return error('${p.file}:${name.line}:${name.column}: style declaration requires a list')
	}
	if p.at().kind == .semicolon { p.pos++ }
	return Style{ name: name.text, line: name.line, column: name.column, expr: expr }
}

// parse_document parses leading `style`/`component` declarations and the root
// element, validates component members, resolves named styles and expands local
// component invocations. The caller checks for `.eof` afterwards.
pub fn (mut p Parser) parse_document() !&Node {
	mut styles := []Style{}
	mut definitions := map[string]&Node{}
	mut last := &Node(unsafe { nil })
	for p.at().text in ['style', 'component'] {
		if p.at().text == 'style' {
			styles << p.parse_style()!
		} else {
			mut component := p.parse_component()!
			if component.component_name in definitions {
				return node_error(component, 'duplicate component `${component.component_name}`')
			}
			definitions[component.component_name] = component
			last = component
		}
	}
	mut root := if p.at().kind == .eof && !isnil(last) {
		last
	} else {
		p.parse_node()!
	}
	if root.tag != component_tag { root.styles = styles.clone() }
	for name, _ in definitions {
		mut component := definitions[name] or { continue }
		locals := component.styles.clone()
		component.styles = styles.clone()
		component.styles << locals
		validate_component_names(component)!
		resolve_style_declarations(mut component, p.config)!
	}
	if root.tag != component_tag { resolve_style_declarations(mut root, p.config)! }
	mut resolved := map[string]&Node{}
	for name, _ in definitions { resolve_local_component(name, definitions, mut resolved, [])! }
	if root.tag == component_tag && root.component_name in resolved {
		root = resolved[root.component_name] or { root }
	} else {
		root = expand_imports(root, resolved)!
	}
	return root
}

fn resolve_local_component(name string, definitions map[string]&Node, mut resolved map[string]&Node, stack []string) ! {
	if name in resolved { return }
	if name in stack { return error('cyclic VML component: ${stack.join(' -> ')} -> ${name}') }
	mut next := stack.clone()
	next << name
	definition := definitions[name] or { return }
	for dependency, _ in definitions {
		if node_has_tag(definition, dependency) {
			resolve_local_component(dependency, definitions, mut resolved, next)!
		}
	}
	resolved[name] = expand_imports(definition, resolved)!
}

fn resolve_style_declarations(mut node Node, config ParseConfig) ! {
	mut styles := map[string]Style{}
	for style in node.styles {
		if style.name in styles {
			return error('duplicate style `${style.name}` at line ${style.line}, column ${style.column}')
		}
		styles[style.name] = style
	}
	if node.tag != component_tag {
		mut names := map[string]bool{}
		for name in ['app', 'color', 'spacing', 'radius', 'typography'] { names[name] = true }
		for name, _ in styles { names[name] = true }
		validate_component_ids(node, mut names)!
	}
	for _, style in styles {
		resolved := resolve_style_expr(style.expr, styles, [style.name])!
		if validate := config.validate_style { validate(node, resolved)! }
	}
	resolve_node_styles(mut node, styles)!
}

fn resolve_node_styles(mut node Node, styles map[string]Style) ! {
	for index, property in node.properties {
		node.properties[index] = Property{ ...property, expr: resolve_style_expr(property.expr, styles, [])! }
	}
	for index, input in node.inputs {
		if !isnil(input.default_value) {
			node.inputs[index] = Input{ ...input, default_value: resolve_style_expr(input.default_value, styles, [])! }
		}
	}
	for mut child in node.children { resolve_node_styles(mut child, styles)! }
}

fn resolve_style_expr(expr &Expr, styles map[string]Style, stack []string) !&Expr {
	if expr.kind == .path {
		if style := styles[expr.value] {
			if expr.value in stack {
				mut cycle := stack.clone()
				cycle << expr.value
				return expr_error(expr, 'cyclic style: ${cycle.join(' -> ')}')
			}
			mut next := stack.clone()
			next << expr.value
			return resolve_style_expr(style.expr, styles, next)
		}
		return expr
	}
	if expr.kind == .array {
		mut args := []&Expr{}
		for arg in expr.args { args << resolve_style_expr(arg, styles, stack)! }
		return &Expr{ ...expr, args: args }
	}
	// A helper's list argument (`hover([card])`) holds values of its namespace.
	if expr.kind == .call && !expr.value.contains('.') {
		mut args := []&Expr{}
		for arg in expr.args {
			args << if arg.kind == .array { resolve_style_expr(arg, styles, stack)! } else { arg }
		}
		return &Expr{ ...expr, args: args }
	}
	if expr.kind == .conditional {
		return &Expr{ ...expr, right: resolve_style_expr(expr.right, styles, stack)!, third: resolve_style_expr(expr.third, styles, stack)! }
	}
	return expr
}
