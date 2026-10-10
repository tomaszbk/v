module parser

fn vml_property_is_reactive(property VmlProperty, scope VmlScope) bool {
	if property.expr.kind == .literal { return false }
	if vml_expr_uses_path(property.expr, 'app') { return true }
	for member, _ in scope.special {
		if !member.starts_with('__') && vml_expr_uses_path(property.expr, member) { return true }
	}
	for id, _ in scope.ids {
		if vml_expr_uses_path(property.expr, id) { return true }
	}
	return false
}

// Geometry needed to construct this node precedes its live frame signal.
// Its effect must resolve those own-frame reads after the signal exists.
fn vml_property_uses_initial_geometry(node &VmlNode, property VmlProperty, scope VmlScope) bool {
	if !vml_property_is_geometry(property) || node.id.len == 0 { return false }
	if named := scope.ids[node.id] {
		if named.frame_signal.len > 0 { return false }
	}
	for field in ['x', 'y', 'width', 'height'] {
		if vml_expr_uses_path(property.expr, node.id + '.' + field) { return true }
	}
	return false
}

fn vml_property_name(suffix string, property string) string {
	return 'vml_property_${suffix}_${vml_var(property)}'
}

// The constructor and its immediate property effect consume the same memo.
// Reactive reads remain in its factory, so each invalidation evaluates once.
fn (mut c VmlCompiler) write_property_initializer(node &VmlNode, property VmlProperty, suffix string, scope VmlScope) string {
	c.location = VmlLocation{ path: property.expr.source, line: property.line, column: property.column }
	name := vml_property_name(suffix, property.name)
	mut value := c.visual_property_value(node, property, property.expr, scope)
	if vml_property_use(property) == .color && property.expr.kind in [.literal, .path] && property.expr.value.starts_with('#') && property.expr.value.len == 7 {
		return value
	}
	if property.name !in ['key', 'model'] && vml_property_is_reactive(property, scope)
		&& !vml_property_uses_initial_geometry(node, property, scope) {
		memo := name + '_memo'
		app_dependency := vml_expr_uses_path(property.expr, 'app')
		dependency := if app_dependency { scope.component + '.watch_app()!; ' } else { '' }
		mut captures := vml_callback_captures(property.expr, scope)
		if app_dependency { captures << 'mut ' + scope.component }
		captures = vml_used_captures(dependency + value, captures)
		key := '@property:' + vml_builder_path(suffix) + ':' + property.name
		c.writeln('mut ${memo} := ${scope.component}.computed[typeof(${value})](' + vml_quote(key) + ', fn [${captures.join(', ')}] () !typeof(${value}) { ${dependency} return ${value} }) or { panic(err) }')
		c.property_memos[name] = memo
		value = '${memo}.get() or { panic(err) }'
	}
	c.writeln('${name} := ${value}')
	c.writeln('_ = ${name}')
	c.property_positions[name] = property
	return name
}

fn (c &VmlCompiler) property_effect_value(node &VmlNode, property VmlProperty, suffix string, scope VmlScope) string {
	if memo := c.property_memos[vml_property_name(suffix, property.name)] {
		return '${memo}.get() or { panic(err) }'
	}
	return c.visual_property_value(node, property, property.expr, scope)
}

fn (c &VmlCompiler) property_memo_capture(suffix string, property string) []string {
	if memo := c.property_memos[vml_property_name(suffix, property)] { return ['mut ' + memo] }
	return []string{}
}

fn vml_content_suffix(suffix string, child &VmlNode) string {
	return suffix.trim_string_right('_effect').trim_string_right('_plain') + '_content_${child.line}_${child.column}'
}

fn (mut c VmlCompiler) prepare_menu_initializers(node &VmlNode, suffix string, scope VmlScope) {
	for child in node.children {
		if child.tag !in ['Option', 'MenuItem'] { continue }
		if property := vml_find_property(child, 'text') {
			c.write_property_initializer(child, property, vml_content_suffix(suffix, child), scope)
		}
	}
}
