module parser

// Named styles are lexical values. The compiler resolves references; ui2 owns
// typed patches, ordered composition, theme signals and retained application.
struct VmlStyle {
	name   string
	line   int
	column int
	expr   &VmlExpr
}

const vml_style_text_names = ['foreground', 'text_background', 'font_size', 'font_family', 'weight',
	'letter_spacing', 'line_height', 'line_height_factor', 'baseline_offset', 'tabular_figures',
	'italic', 'underline', 'strikethrough', 'shadow', 'text_outline', 'vertical_align', 'link',
	'text_align', 'text_valign', 'head_indent', 'first_line_indent', 'hyphenation_factor', 'lines']

const vml_style_box_names = ['background', 'radius', 'transparent', 'border_color', 'border_width',
	'border_left', 'border_top', 'border_right', 'border_bottom', 'border_left_color',
	'border_top_color', 'border_right_color', 'border_bottom_color', 'border_pattern', 'dash_length',
	'dash_gap', 'outline_color', 'outline_width', 'outline_offset']

const vml_style_padding_names = ['padding', 'padding_left', 'padding_top', 'padding_right',
	'padding_bottom']

fn (mut p VmlSourceParser) parse_vml_style() !VmlStyle {
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
	return VmlStyle{ name: name.text, line: name.line, column: name.column, expr: expr }
}

fn (mut p VmlSourceParser) parse_vml_document() !&VmlNode {
	mut styles := []VmlStyle{}
	mut definitions := map[string]&VmlNode{}
	mut last := &VmlNode(unsafe { nil })
	for p.at().text in ['style', 'component'] {
		if p.at().text == 'style' {
			styles << p.parse_vml_style()!
		} else {
			mut component := p.parse_vml_component_document()!
			if component.component_name in definitions {
				return vml_visual_node_error(component, 'duplicate component `${component.component_name}`')
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
	if root.tag != '__Component' { root.styles = styles.clone() }
	for name, _ in definitions {
		mut component := definitions[name] or { continue }
		locals := component.styles.clone()
		component.styles = styles.clone()
		component.styles << locals
		validate_vml_component_names(component)!
		resolve_vml_style_declarations(mut component)!
	}
	if root.tag != '__Component' { resolve_vml_style_declarations(mut root)! }
	mut resolved := map[string]&VmlNode{}
	for name, _ in definitions { resolve_vml_local_component(name, definitions, mut resolved, [])! }
	if root.tag == '__Component' && root.component_name in resolved {
		root = resolved[root.component_name] or { root }
	} else {
		root = expand_compiled_vml_import(root, resolved)!
	}
	return root
}

fn resolve_vml_local_component(name string, definitions map[string]&VmlNode, mut resolved map[string]&VmlNode, stack []string) ! {
	if name in resolved { return }
	if name in stack { return error('cyclic VML component: ${stack.join(' -> ')} -> ${name}') }
	mut next := stack.clone()
	next << name
	definition := definitions[name] or { return }
	for dependency, _ in definitions {
		if vml_node_has_tag(definition, dependency) {
			resolve_vml_local_component(dependency, definitions, mut resolved, next)!
		}
	}
	resolved[name] = expand_compiled_vml_import(definition, resolved)!
}

fn vml_node_has_tag(node &VmlNode, tag string) bool {
	if node.tag == tag { return true }
	for child in node.children { if vml_node_has_tag(child, tag) { return true } }
	return false
}

fn resolve_vml_style_declarations(mut node VmlNode) ! {
	mut styles := map[string]VmlStyle{}
	for style in node.styles {
		if style.name in styles {
			return error('duplicate style `${style.name}` at line ${style.line}, column ${style.column}')
		}
		styles[style.name] = style
	}
	if node.tag != '__Component' {
		mut names := map[string]bool{}
		for name in ['app', 'color', 'spacing', 'radius', 'typography'] { names[name] = true }
		for name, _ in styles { names[name] = true }
		validate_vml_component_ids(node, mut names)!
	}
	for _, style in styles {
		resolved := resolve_vml_style_expr(style.expr, styles, [style.name])!
		validate_vml_style_expr(node, resolved, false, false)!
	}
	resolve_vml_node_styles(mut node, styles)!
}

fn resolve_vml_node_styles(mut node VmlNode, styles map[string]VmlStyle) ! {
	for index, property in node.properties {
		node.properties[index] = VmlProperty{ ...property, expr: resolve_vml_style_expr(property.expr, styles, [])! }
	}
	for index, input in node.inputs {
		if input.typ == 'ui2.StylePatch' && !isnil(input.default_value) {
			node.inputs[index] = VmlInput{ ...input, default_value: resolve_vml_style_expr(input.default_value, styles, [])! }
		}
	}
	for mut child in node.children { resolve_vml_node_styles(mut child, styles)! }
}

fn resolve_vml_style_expr(expr &VmlExpr, styles map[string]VmlStyle, stack []string) !&VmlExpr {
	if expr.kind == .path {
		if style := styles[expr.value] {
			if expr.value in stack {
				mut cycle := stack.clone()
				cycle << expr.value
				return vml_style_error(expr, 'cyclic style: ${cycle.join(' -> ')}')
			}
			mut next := stack.clone()
			next << expr.value
			return resolve_vml_style_expr(style.expr, styles, next)
		}
		return expr
	}
	if expr.kind == .array || (expr.kind == .call && expr.value in ['hover', 'focus', 'pressed',
		'disabled']) {
		mut args := []&VmlExpr{}
		for arg in expr.args { args << resolve_vml_style_expr(arg, styles, stack)! }
		return &VmlExpr{ ...expr, args: args }
	}
	if expr.kind == .conditional {
		return &VmlExpr{ ...expr, right: resolve_vml_style_expr(expr.right, styles, stack)!, third: resolve_vml_style_expr(expr.third, styles, stack)! }
	}
	return expr
}

fn vml_style_error(expr &VmlExpr, message string) IError {
	return if expr.source.len > 0 {
		error('${expr.source}:${expr.line}:${expr.column}: ${message}')
	} else {
		error('${message} at line ${expr.line}, column ${expr.column}')
	}
}

fn vml_style_property_name(name string) string {
	return match name {
		'foreground' { 'color' }
		'text_background' { 'background_color' }
		'text_outline' { 'outline' }
		'text_align' { 'align' }
		'text_valign' { 'valign' }
		else { name }
	}
}

fn vml_direct_appearance(name string) bool {
	base := vml_visual_base_property(name)
	if base in vml_box_properties { return true }
	if base in vml_text_properties { return true }
	return name in vml_style_padding_names || name == 'pad_left'
}

fn validate_vml_style_expr(node &VmlNode, expr &VmlExpr, native bool, state bool) ! {
	match expr.kind {
		.array {
			for argument in expr.args { validate_vml_style_expr(node, argument, native, state)! }
		}
		.conditional {
			property := VmlProperty{ name: 'style', line: expr.line, column: expr.column, expr: &VmlExpr{ ...expr } }
			validate_vml_visual_bool(property, expr.left)!
			validate_vml_style_expr(node, expr.right, native, state)!
			validate_vml_style_expr(node, expr.third, native, state)!
		}
		.path {}
		.call {
			if expr.value.contains('.') { return }
			if expr.value in ['hover', 'focus', 'pressed', 'disabled'] {
				if node.tag == 'Run' {
					return vml_style_error(expr, 'Run styles support text properties')
				}
				if state {
					return vml_style_error(expr, 'interaction styles cannot nest interaction states')
				}
				if native {
					return vml_style_error(expr, '`${expr.value}` requires the custom renderer')
				}
				if expr.args.len != 1 || expr.args[0].kind != .array {
					return vml_style_error(expr, '`${expr.value}` requires one style list')
				}
				validate_vml_style_expr(node, expr.args[0], native, true)!
				return
			}
			if expr.value !in vml_style_box_names && expr.value !in vml_style_text_names && expr.value !in vml_style_padding_names {
				return vml_style_error(expr, 'unknown style helper `${expr.value}`')
			}
			if expr.args.len != 1 {
				return vml_style_error(expr, '`${expr.value}` requires exactly one argument')
			}
			if state && expr.value !in vml_style_box_names && expr.value != 'foreground' {
				return vml_style_error(expr, 'interaction styles support box properties and foreground')
			}
			name := vml_style_property_name(expr.value)
			property := VmlProperty{ name: name, line: expr.line, column: expr.column, expr: expr.args[0] }
			if node.tag == 'Run' && expr.value !in vml_style_text_names {
				return vml_style_error(expr, 'Run styles support text properties')
			}
			validate_vml_visual_value(node, property, expr.args[0], true, false)!
			if native { validate_vml_native_property(property)! }
		}
		else {
			return vml_style_error(expr, 'style requires a list, typed style value or conditional style')
		}
	}
}

fn vml_style_uses_theme(expr &VmlExpr) bool {
	for namespace in ['color', 'spacing', 'radius', 'typography'] {
		if vml_expr_uses_path(expr, namespace) { return true }
	}
	return false
}

fn (c &VmlCompiler) style_expr(expr &VmlExpr, node &VmlNode, scope VmlScope) string {
	match expr.kind {
		.array {
			return 'ui2.compose_styles(' + vml_array_literal('ui2.StylePatch', expr.args.map(c.style_expr(it, node, scope))) + ')'
		}
		.conditional {
			return '(if ${c.expr(expr.left, scope, .bool_)} { ${c.style_expr(expr.right, node, scope)} } else { ${c.style_expr(expr.third, node, scope)} })'
		}
		.call {
			if expr.value.contains('.') { return c.expr(expr, scope, .raw) }
			if expr.value in ['hover', 'focus', 'pressed', 'disabled'] {
				return 'ui2.style_${expr.value}(' + vml_array_literal('ui2.StylePatch', expr.args[0].args.map(c.style_expr(it, node, scope))) + ') or { panic(err) }'
			}
			name := vml_style_property_name(expr.value)
			property := VmlProperty{ name: name, line: expr.line, column: expr.column, expr: expr.args[0] }
			return 'ui2.style_${expr.value}(${c.visual_property_value(node, property, expr.args[0], scope)})'
		}
		else { return c.expr(expr, scope, .raw) }
	}
}

fn vml_theme_expr_tokens(expr &VmlExpr, mut names []string) {
	if expr.kind == .path {
		for pair in [['color', 'color'], ['spacing', 'spacing'], ['radius', 'radius'],
			['typography', 'font_size']] {
			if expr.value.starts_with(pair[0] + '.') {
				name := pair[1] + ':' + expr.value.all_after(pair[0] + '.')
				if name !in names { names << name }
			}
		}
	}
	if !isnil(expr.left) { vml_theme_expr_tokens(expr.left, mut names) }
	if !isnil(expr.right) { vml_theme_expr_tokens(expr.right, mut names) }
	if !isnil(expr.third) { vml_theme_expr_tokens(expr.third, mut names) }
	for argument in expr.args { vml_theme_expr_tokens(argument, mut names) }
	for part in expr.parts { if !isnil(part.expr) { vml_theme_expr_tokens(part.expr, mut names) } }
}

fn vml_theme_slot_tokens(node &VmlNode, mut names []string) {
	if node.caller_content {
		vml_theme_node_tokens(node, mut names)
		return
	}
	for child in node.children { vml_theme_slot_tokens(child, mut names) }
}

fn vml_theme_node_tokens(node &VmlNode, mut names []string) {
	if node.tag != '__Component' {
		for property in node.properties { vml_theme_expr_tokens(property.expr, mut names) }
	}
	for input in node.inputs {
		if !isnil(input.default_value) { vml_theme_expr_tokens(input.default_value, mut names) }
	}
	for data in node.data { vml_theme_expr_tokens(data.expr, mut names) }
	for function in node.functions {
		for statement in function.body { vml_theme_expr_tokens(statement, mut names) }
	}
	for child in node.children {
		if child.tag == '__Component' {
			for property in child.properties { vml_theme_expr_tokens(property.expr, mut names) }
			vml_theme_slot_tokens(child, mut names)
		} else if !child.caller_content {
			vml_theme_node_tokens(child, mut names)
		}
	}
}

fn (mut c VmlCompiler) prepare_style_tokens(node &VmlNode, component string) {
	mut names := []string{}
	vml_theme_node_tokens(node, mut names)
	if names.len > 0 {
		c.writeln('${component}.prepare_theme_tokens(' + vml_array_literal('string', names.map(vml_quote(it))) + ') or { panic(err) }')
	}
}

fn vml_style_uses_layout_geometry(expr &VmlExpr, scope VmlScope) bool {
	if expr.kind == .call && expr.value in vml_style_padding_names {
		for argument in expr.args {
			if vml_expr_uses_element_geometry(argument, scope) { return true }
		}
	}
	if !isnil(expr.right) && vml_style_uses_layout_geometry(expr.right, scope) { return true }
	if !isnil(expr.third) && vml_style_uses_layout_geometry(expr.third, scope) { return true }
	for argument in expr.args { if vml_style_uses_layout_geometry(argument, scope) { return true } }
	return false
}
