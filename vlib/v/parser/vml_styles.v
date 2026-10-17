module parser

import vml

// vml_style_uses_theme reports whether an expression reads a theme token.
fn vml_style_uses_theme(expr &vml.Expr) bool {
	for namespace in ['color', 'spacing', 'radius', 'typography'] {
		if vml.expr_uses_path(expr, namespace) { return true }
	}
	return false
}

fn vml_theme_expr_tokens(expr &vml.Expr, mut names []string) {
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

fn vml_theme_slot_tokens(node &vml.Node, mut names []string) {
	if node.caller_content {
		vml_theme_node_tokens(node, mut names)
		return
	}
	for child in node.children { vml_theme_slot_tokens(child, mut names) }
}

fn vml_theme_node_tokens(node &vml.Node, mut names []string) {
	if node.tag != vml.component_tag {
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
		if child.tag == vml.component_tag {
			for property in child.properties { vml_theme_expr_tokens(property.expr, mut names) }
			vml_theme_slot_tokens(child, mut names)
		} else if !child.caller_content {
			vml_theme_node_tokens(child, mut names)
		}
	}
}

// prepare_style_tokens resolves the theme tokens a document or component
// reads before its nodes are declared.
fn (mut c VmlCompiler) prepare_style_tokens(node &vml.Node, component string) {
	mut names := []string{}
	vml_theme_node_tokens(node, mut names)
	if names.len > 0 {
		c.writeln('${component}.prepare_theme_tokens(' + vml_array_literal('string', names.map(vml_quote(it))) + ') or { panic(err) }')
	}
}
