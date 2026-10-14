module parser

const vml_overlay_properties = ['open', 'owner', 'anchor', 'point', 'placement', 'gap', 'margin',
	'initial_focus', 'dismiss_on_escape', 'dismiss_on_outside', 'backdrop', 'backdrop_opacity',
	'tooltip_delay']

fn vml_overlay_tag(tag string) bool {
	return tag in ['Dialog', 'Popover', 'MenuOverlay', 'ContextMenu', 'Tooltip']
}

fn vml_has_overlay(node &VmlNode) bool {
	return vml_overlay_tag(node.tag) || (node.tag == 'View' && vml_find_property(node, 'overlay') != none)
}

fn vml_overlay_ref_tag(tag string) string {
	return if vml_overlay_tag(tag) { 'View' } else { tag }
}

// Literal references name controls in the current component's lexical scope.
// Values from V state or an opaque config already contain resolved public ids.
fn vml_overlay_local_reference(property VmlProperty) bool {
	return vml_overlay_local_reference_expr(property.name, property.expr)
}

fn vml_overlay_local_reference_expr(name string, expr &VmlExpr) bool {
	return name in ['anchor', 'owner', 'initial_focus']
		&& expr.kind == .literal && expr.quoted && expr.value.len > 0
}

// A component invocation aliases its actual private root, whose public id is
// available only after lowering the invocation. Ordinary local ids are known
// from their author and may still be referenced before their declaration.
fn vml_overlay_component_aliases(nodes []&VmlNode) []string {
	mut aliases := []string{}
	for node in nodes {
		if node.caller_content || node.tag == 'Repeater' { continue }
		if node.tag == '__Component' {
			if node.id.len > 0 { aliases << node.id }
			continue
		}
		aliases << vml_overlay_component_aliases(node.children)
	}
	return aliases
}

fn validate_vml_overlay_component_alias(property VmlProperty, expr &VmlExpr, scope VmlScope) ! {
	if vml_overlay_local_reference_expr(property.name, expr)
		&& expr.value in scope.component_aliases && expr.value !in scope.ids {
		return vml_visual_error(property, 'overlay `${property.name}` references component alias `${expr.value}` before its declaration; declare the component first or pass a resolved control id')
	}
	if expr.kind == .conditional {
		validate_vml_overlay_component_alias(property, expr.right, scope)!
		validate_vml_overlay_component_alias(property, expr.third, scope)!
	}
}

fn vml_overlay_reference_captures(name string, expr &VmlExpr, scope VmlScope) []string {
	if vml_overlay_local_reference_expr(name, expr) {
		if named := scope.ids[expr.value] {
			if named.frame_node.len > 0 { return [named.frame_node] }
			if named.control_id.len > 0 {
				return ['mut ' + named.control_id.all_before('.control_id(')]
			}
		}
		return ['mut ' + scope.component]
	}
	if expr.kind == .conditional {
		mut captures := vml_overlay_reference_captures(name, expr.right, scope)
		captures << vml_overlay_reference_captures(name, expr.third, scope)
		return captures
	}
	return []string{}
}

fn vml_overlay_property_use(name string) ?VmlExprUse {
	return match name {
		'open', 'dismiss_on_escape', 'dismiss_on_outside' { .bool_ }
		'owner', 'anchor', 'initial_focus' { .string_ }
		'gap', 'margin', 'backdrop_opacity', 'tooltip_delay' { .number }
		'overlay', 'point', 'placement', 'backdrop', 'scroll_mode' { .raw }
		else { return none }
	}
}

fn vml_overlay_typed_value(name string, value string) ?string {
	return match name {
		'overlay' { 'ui2.OverlayConfig{...${value}}' }
		'point' { 'ui2.OverlayConfig{point: ${value}}.point' }
		'placement' { 'ui2.OverlayConfig{placement: ${value}}.placement' }
		'backdrop' { 'ui2.BoxStyle{...${value}}' }
		'scroll_mode' { 'ui2.Element{scroll_mode: ${value}}.scroll_mode' }
		else { return none }
	}
}

fn vml_overlay_effect_property(node &VmlNode, name string) bool {
	if !vml_has_overlay(node) { return false }
	return name in ['hidden', 'accessibility_role', 'overlay']
		|| (vml_overlay_tag(node.tag) && name in vml_overlay_properties)
}

fn (c &VmlCompiler) overlay_config(node &VmlNode, suffix string, properties map[string]string) string {
	mut callbacks := []string{}
	for name in ['on_open', 'on_dismiss'] {
		if callback := c.event_references[suffix + ':' + name] {
			callbacks << '${name}: ${callback}'
		}
	}
	if config := properties['overlay'] {
		return if callbacks.len > 0 {
			'ui2.OverlayConfig{...${config}, ${callbacks.join(', ')}}'
		} else {
			config
		}
	}
	kind := match node.tag {
		'Dialog' { 'dialog' }
		'Popover' { 'popover' }
		'MenuOverlay' { 'menu' }
		'ContextMenu' { 'context_menu' }
		else { 'tooltip' }
	}
	mut fields := ['kind: .${kind}']
	for name in vml_overlay_properties {
		if value := properties[name] { fields << '${name}: ${value}' }
	}
	fields << callbacks
	return 'ui2.OverlayConfig{${fields.join(', ')}}'
}

// Overlay updates patch the retained surface and keep its children mounted.
// Reapply authored visibility instead of carrying a previous closed state into
// with_overlay, so reopening restores the same focus/edit/lifecycle identity.
fn (mut c VmlCompiler) compile_overlay_effect(node &VmlNode, suffix string, scope VmlScope) {
	if !vml_has_overlay(node) { return }
	properties := node.properties.filter(vml_overlay_effect_property(node, it.name))
	if !properties.any(vml_property_is_reactive(it, scope)) { return }
	base := 'vml_overlay_base_' + suffix
	mut captures := [base]
	mut values := map[string]string{}
	mut app_dependency := false
	for property in properties {
		values[property.name] = c.property_effect_value(node, property, suffix, scope)
		captures << vml_callback_captures(property.expr, scope)
		captures << c.property_memo_capture(suffix, property.name)
		app_dependency = app_dependency || vml_expr_uses_path(property.expr, 'app')
	}
	for name in ['on_open', 'on_dismiss'] {
		if callback := c.event_references[suffix + ':' + name] { captures << callback }
	}
	if app_dependency { captures << 'mut ' + scope.component }
	dependency := if app_dependency { scope.component + '.watch_app()!; ' } else { '' }
	config := c.overlay_config(node, suffix, values)
	hidden := vml_prop(values, 'hidden', 'false')
	role := vml_prop(values, 'accessibility_role', base + '.accessibility_role')
	updated := 'ui2.with_overlay(ui2.Element{...element, hidden: ${hidden}, focus_scope: ${base}.focus_scope, focus_policy: ${base}.focus_policy, tab_index: ${base}.tab_index, accessibility_role: ${role}}, ${config})!'
	captures = vml_used_captures(dependency + updated, captures)
	c.writeln('vml_node_${suffix}.effect(' + vml_quote('@overlay') + ', fn [${captures.join(', ')}] (element ui2.Element) !ui2.Element { ${dependency} return ${updated} }) or { panic(err) }')
}
