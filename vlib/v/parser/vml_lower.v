module parser

import strings
import vml

// Generic VML lowering (`-d vml_generic`). The compiler knows the VML language
// (elements, properties, components, repeaters, styles, tokens) but no widget:
// tag `Slider` lowers to the props type `ui2.SliderProps`, every property to a
// field of it, and ui2's generic node runtime (`vml_document`, `vml_root`,
// `vml_child`, `prop`, `bind`, `vml_repeat`) builds, retains and updates the
// tree. V type-checks tags, property names and values against the props types.

const vml_runtime_module = 'ui2'

// VmlLowerParent is the parent handle a node is declared under: a node
// variable or a repeater segment, and the props type of the widget that lays
// the children out. An empty handle declares the document root.
struct VmlLowerParent {
	handle string
	props  string
}

// VmlForwarded is a component invocation property that the component does not
// declare: it applies to the component's root, evaluated in the caller's scope.
struct VmlForwarded {
	property vml.Property
	scope    VmlScope
}

// vml_props_type names the props type of a tag: `Slider` is `ui2.SliderProps`
// and a dotted tag `pkg.Gauge` names `pkg.GaugeProps` in the caller's imports.
fn vml_props_type(tag string) string {
	if tag.contains('.') {
		return tag.all_before_last('.') + '.' + tag.all_after_last('.') + 'Props'
	}
	return '${vml_runtime_module}.${tag}Props'
}

fn vml_source_location(source string, line int, column int) string {
	return 'ui2.VmlSourceLocation{source: ${vml_quote(source)}, line: ${line}, column: ${column}}'
}

// lower lowers a parsed document to an immediately invoked builder returning
// the resolved root element.
fn (mut c VmlCompiler) lower(root &vml.Node) string {
	c.out = strings.new_builder(4096)
	c.location = vml.Location{ path: root.source, line: root.line, column: root.column }
	mut capture_names := c.callback_captures.clone()
	if c.uses_app { capture_names.insert(0, 'mut app') }
	capture := if capture_names.len > 0 { '[' + capture_names.join(', ') + '] ' } else { '' }
	c.writeln('\tmut vml_doc := ui2.vml_document(vml_template_frame, follow_viewport: ${!c.explicit_frame}) or { panic(err) }')
	c.writeln('\tmut vml_root_component := vml_doc.owner')
	mut scope := VmlScope{
		ids:       map[string]VmlNamedValue{}
		special:   map[string]string{}
		component: 'vml_root_component'
	}
	if root.tag != vml.component_tag { c.prepare_style_tokens(root, scope.component) }
	c.lower_node(root, '0', VmlLowerParent{}, scope, '', []VmlForwarded{})
	c.location = vml.Location{ path: root.source, line: root.line, column: root.column }
	c.writeln('\treturn vml_doc.finish() or { panic(err) }')
	c.writeln('})(ui2.vml_bounds())')
	c.write_list_guards()
	body := c.out.str()
	body_locations := c.locations.clone()
	c.out = strings.new_builder(body.len + 256)
	c.locations = []vml.Location{}
	c.writeln('')
	c.writeln('(fn ${capture}(vml_template_frame ui2.Rect) ui2.Element {')
	c.out.write_string(body)
	c.locations << body_locations
	return c.out.str()
}

// lower_node declares one node (an element, a component invocation or slot
// content) and its subtree. It returns the scope following siblings see and
// leaves the declared root variable in `c.lowered_node`.
fn (mut c VmlCompiler) lower_node(node &vml.Node, path string, parent VmlLowerParent, incoming VmlScope, default_key string, forwarded []VmlForwarded) VmlScope {
	if node.caller_content {
		mut lexical := vml_clone_scope(c.slot_scopes[incoming.component] or { incoming })
		owner := 'vml_slot_component_' + vml_var(path)
		c.location = vml.Location{ path: node.source, line: node.line, column: node.column }
		c.writeln('\tmut ${owner} := ${lexical.component}.slot_child(mut ${incoming.component}, ' + vml_quote(path) + ') or { panic(err) }')
		lexical.component = owner
		value := &vml.Node{ ...node, caller_content: false }
		c.lower_node(value, path, parent, lexical, default_key, forwarded)
		return incoming
	}
	if node.tag == vml.component_tag {
		return c.lower_component(node, path, parent, incoming, default_key, forwarded)
	}
	return c.lower_element(node, path, parent, incoming, default_key, forwarded)
}

fn (mut c VmlCompiler) lower_element(node &vml.Node, path string, parent VmlLowerParent, incoming VmlScope, default_key string, forwarded []VmlForwarded) VmlScope {
	suffix := vml_var(path)
	variable := 'vml_node_' + suffix
	props := vml_props_type(node.tag)
	owner := incoming.component
	node_location := vml.Location{ path: node.source, line: node.line, column: node.column }
	mut scope := vml_clone_scope(incoming)
	if node.id.len > 0 {
		scope.ids[node.id] = VmlNamedValue{ geometry: variable }
	}
	mut properties := []VmlForwarded{cap: node.properties.len + forwarded.len}
	for property in node.properties {
		properties << VmlForwarded{ property: property, scope: scope }
	}
	for item in forwarded {
		if item.property.name in ['id', 'key', 'ref'] { continue }
		properties << VmlForwarded{ property: item.property, scope: item.scope }
	}
	// Static checks run where the node's sources are in scope.
	for item in properties {
		property := item.property
		c.location = vml.Location{ path: property.expr.source, line: property.line, column: property.column }
		if property.name.starts_with('bind.') {
			if property.expr.value.starts_with('app.') {
				c.write_mutable_check(property.expr.value)
			}
		}
		if property.name.starts_with('on_') {
			c.write_app_action_checks(property.expr)
		}
		c.write_model_path_checks(property.expr, item.scope)
	}
	mut statics := []VmlForwarded{}
	mut reactive := []VmlForwarded{}
	mut bindings := []VmlForwarded{}
	mut key := if default_key.len > 0 { default_key } else { '' }
	for item in properties {
		property := item.property
		if property.name in ['id', 'ref'] { continue }
		if property.name == 'key' {
			key = c.lower_key(property.expr, item.scope)
			continue
		}
		if property.name.starts_with('bind.') {
			bindings << item
		} else if property.name.starts_with('on_') {
			statics << item
		} else if vml_property_is_reactive(property, item.scope) {
			reactive << item
		} else {
			statics << item
		}
	}
	if parent.handle.len > 0 {
		c.location = node_location
		c.uses_unreachable = true
		c.writeln('\tif ${c.guard_prefix}_unreachable() { ui2.vml_guard_child[${parent.props}, ${props}]() }')
	}
	// The document is the parent of the root: it positions no child.
	positioner := if parent.handle.len > 0 { parent.props } else { 'ui2.VmlDocument' }
	for position in node.properties {
		if position.name !in ['x', 'y'] { continue }
		c.location = vml.Location{ path: position.expr.source, line: position.line, column: position.column }
		c.uses_unreachable = true
		c.writeln('\tif ${c.guard_prefix}_unreachable() { ui2.vml_guard_positioned[${positioner}]() }')
		break
	}
	c.location = node_location
	declare := if parent.handle.len > 0 {
		'ui2.vml_child(mut ${parent.handle}, mut ${owner}, '
	} else {
		'ui2.vml_root(mut ${owner}, '
	}
	mut options := []string{}
	if node.id.len > 0 { options << 'id: ' + vml_quote(node.id) }
	options << 'path: ' + vml_quote(path)
	if key.len > 0 { options << 'key: ' + key }
	options << 'src: ' + vml_source_location(node.source, node.line, node.column)
	if statics.len == 0 {
		c.writeln('\tmut ${variable} := ${declare}${props}{}, ${options.join(', ')}) or { panic(err) }')
	} else {
		c.writeln('\tmut ${variable} := ${declare}${props}{')
		for item in statics {
			property := item.property
			c.location = vml.Location{ path: property.expr.source, line: property.line, column: property.column }
			value := if property.name.starts_with('on_') {
				c.lower_event(property, item.scope)
			} else {
				c.lower_value(property, item.scope)
			}
			c.writeln('\t\t${property.name}: ${value}')
		}
		c.location = node_location
		c.writeln('\t}, ${options.join(', ')}) or { panic(err) }')
	}
	c.writeln('\t_ = ${variable}')
	for item in reactive {
		c.lower_prop(variable, props, item.property.name, item.property, item.property.expr,
			item.scope)
	}
	for item in bindings {
		c.lower_binding(variable, props, item.property, item.scope)
	}
	if reference := vml.find_property(node, 'ref') {
		c.location = vml.Location{ path: reference.expr.source, line: reference.line, column: reference.column }
		c.writeln(c.expr(reference.expr, scope, .raw) + '.bind_widget(mut ${variable}) or { panic(err) }')
	}
	child_parent := VmlLowerParent{
		handle: variable
		props:  props
	}
	for index, child in node.children {
		if child.tag == 'Repeater' {
			c.lower_repeater(child, vml_var(path) + '.' + index.str(), child_parent, scope)
			continue
		}
		child_scope := c.lower_node(child, '${path}.${index}', child_parent, scope, '', []VmlForwarded{})
		for id, named in child_scope.ids { scope.ids[id] = named }
	}
	c.lowered_node = variable
	c.lowered_props = props
	return vml_node_output_scope(node, incoming, scope)
}

// lower_key stringifies a reconciliation key once, when the node is declared.
fn (c &VmlCompiler) lower_key(expr &vml.Expr, scope VmlScope) string {
	if expr.kind == .literal && expr.quoted { return vml_quote(expr.value) }
	return vml_stringify(c.lower_expr(expr, scope))
}

// lower_value is a property value in the typed context of its props field.
fn (c &VmlCompiler) lower_value(property vml.Property, scope VmlScope) string {
	if property.name == 'style' { return c.lower_style(property.expr, scope) }
	return c.lower_expr(property.expr, scope)
}

// lower_prop registers a reactive property: the setter reads its tracked
// sources and assigns the field.
fn (mut c VmlCompiler) lower_prop(variable string, props string, field string, property vml.Property, expr &vml.Expr, scope VmlScope) {
	c.location = vml.Location{ path: expr.source, line: property.line, column: property.column }
	value := if property.name == 'style' {
		c.lower_style(expr, scope)
	} else {
		c.lower_expr(expr, scope)
	}
	app_dependency := vml.expr_uses_path(expr, 'app')
	dependency := if app_dependency { scope.component + '.watch_app()!; ' } else { '' }
	mut captures := vml_callback_captures(expr, scope)
	if app_dependency || vml_style_uses_theme(expr) { captures << 'mut ' + scope.component }
	body := '${dependency}vml_p.${field} = ${value}'
	captures = vml_used_captures(body, captures)
	c.writeln('\t${variable}.prop(' + vml_quote(field) + ', fn [${captures.join(', ')}] (mut vml_p ${props}) ! { ${body} }) or { panic(err) }')
}

// lower_binding keeps `bind.name: target` two-way: the field follows the
// target, and a widget change writes the field back through the target.
fn (mut c VmlCompiler) lower_binding(variable string, props string, property vml.Property, scope VmlScope) {
	field := property.name.all_after('bind.')
	target := property.expr
	c.lower_prop(variable, props, field, property, target, scope)
	current := if signal := scope.special['__signal_' + target.value] {
		'${signal}.peek() or { panic(err) }'
	} else {
		c.expr(target, scope, .raw)
	}
	write := c.compile_write(target.value, 'ui2.vml_assign(${current}, vml_p.${field})', scope)
	mut captures := vml_callback_captures(target, scope)
	captures = vml_used_captures(write, captures)
	c.writeln('\t${variable}.bind(' + vml_quote(field) + ', fn [${captures.join(', ')}] (vml_p ${props}) ! { ${write} }) or { panic(err) }')
}

// lower_event is the value of an `on_*` field: an action or a callback
// reference run in the owner's batch.
fn (c &VmlCompiler) lower_event(property vml.Property, scope VmlScope) string {
	mut captures := vml_callback_captures(property.expr, scope)
	mut body := '_ = event\n'
	if property.expr.kind == .path {
		callback := c.expr(property.expr, scope, .raw)
		body += 'ui2.vml_callback(${callback}, refresh: false)(event)\n'
		if !callback.contains('.') && callback !in captures
			&& (callback in c.callback_captures || callback.starts_with('vml_')) {
			captures << callback
		}
	} else {
		body += c.compile_action(property.expr, scope) + '\n'
	}
	captures = vml_used_captures(body, captures)
	return '${scope.component}.callback(fn [${captures.join(', ')}] (event ui2.ElementEvent) ! { ${body} })'
}

// lower_expr lowers a value expression. Unbound bare names are enum values in
// the typed context of the field (`align_items: stretch`), `#RRGGBB` is a u32
// color and the four theme roots read the owner's tokens.
fn (c &VmlCompiler) lower_expr(expr &vml.Expr, scope VmlScope) string {
	match expr.kind {
		.literal {
			return if expr.quoted { vml_quote(expr.value) } else { expr.value }
		}
		.path {
			if color := vml_hex_color(expr.value) { return color }
			for pair in [['color', 'color_token'], ['spacing', 'spacing_token'],
				['radius', 'radius_token'], ['typography', 'font_size_token']] {
				if expr.value.starts_with(pair[0] + '.') {
					return '${scope.component}.${pair[1]}(' + vml_quote(expr.value.all_after(pair[0] + '.')) + ') or { panic(err) }'
				}
			}
			resolved, bound := c.resolve_path(expr.value, scope)
			if !bound && !expr.value.contains('.') && expr.value != 'app'
				&& expr.value !in c.callback_captures {
				return '.' + expr.value
			}
			return resolved
		}
		.call {
			args := expr.args.map(c.lower_expr(it, scope)).join(', ')
			resolved, _ := c.resolve_path(expr.value, scope)
			return '${resolved}(${args})' + if expr.fallible { ' or { panic(err) }' } else { '' }
		}
		.unary {
			return '(${expr.value}${c.lower_expr(expr.left, scope)})'
		}
		.binary {
			return '(${c.lower_expr(expr.left, scope)} ${expr.value} ${c.lower_expr(expr.right, scope)})'
		}
		.conditional {
			return '(if ${c.lower_expr(expr.left, scope)} { ${c.lower_expr(expr.right, scope)} } else { ${c.lower_expr(expr.third, scope)} })'
		}
		.assignment {
			return c.lower_expr(expr.right, scope)
		}
		.block {
			return expr.args.map(c.lower_expr(it, scope)).join('\n')
		}
		.array {
			return '[' + expr.args.map(c.lower_expr(it, scope)).join(', ') + ']'
		}
		.interpolation {
			mut value := "'"
			for part in expr.parts {
				if isnil(part.expr) {
					value += vml_interpolation_text(part.text)
				} else {
					value += r'$' + '{' + c.lower_expr(part.expr, scope) + '}'
				}
			}
			return value + "'"
		}
	}
}

// vml_hex_color reads `#RRGGBB` (or `#RRGGBBAA`) as a u32 literal.
fn vml_hex_color(value string) ?string {
	if !value.starts_with('#') || value.len !in [7, 9] { return none }
	for ch in value[1..] {
		if !ch.is_hex_digit() { return none }
	}
	return 'u32(0x${value[1..]})'
}

// lower_style lowers a style value: a list composes patches, a call
// `f(a)` is the helper `ui2.style_f(a)`, and a call whose argument is a style
// list (`hover([...])`) builds a fallible state patch. Any other value is cast
// to `ui2.StylePatch`, so V checks its type where it is written: V does not
// check the elements of an array literal passed as an argument.
fn (c &VmlCompiler) lower_style(expr &vml.Expr, scope VmlScope) string {
	match expr.kind {
		.array {
			return 'ui2.compose_styles(' + vml_array_literal('ui2.StylePatch', expr.args.map(c.lower_style(it, scope))) + ')'
		}
		.conditional {
			return '(if ${c.lower_expr(expr.left, scope)} { ${c.lower_style(expr.right, scope)} } else { ${c.lower_style(expr.third, scope)} })'
		}
		.call {
			if expr.value.contains('.') {
				return 'ui2.StylePatch(' + c.lower_expr(expr, scope) + ')'
			}
			if expr.args.len == 1 && expr.args[0].kind == .array {
				return 'ui2.style_${expr.value}(' + vml_array_literal('ui2.StylePatch', expr.args[0].args.map(c.lower_style(it, scope))) + ') or { panic(err) }'
			}
			return 'ui2.style_${expr.value}(' + expr.args.map(c.lower_style_argument(it, scope)).join(', ') + ')'
		}
		else {
			return 'ui2.StylePatch(' + c.lower_expr(expr, scope) + ')'
		}
	}
}

// lower_style_argument lowers an argument of a style helper. A quoted
// `"#RRGGBB"` is a color there too, as `#RRGGBB` is.
fn (c &VmlCompiler) lower_style_argument(expr &vml.Expr, scope VmlScope) string {
	if expr.kind == .literal && expr.quoted {
		if color := vml_hex_color(expr.value) { return color }
	}
	return c.lower_expr(expr, scope)
}

// lower_repeater declares a keyed repeater among the children of `parent`.
// Items are declared under their own owner and segment, in declaration order.
fn (mut c VmlCompiler) lower_repeater(node &vml.Node, path string, parent VmlLowerParent, incoming VmlScope) {
	model := vml.find_property(node, 'model') or { return }
	key := vml.find_property(node, 'key') or { return }
	suffix := vml_var(path)
	c.location = vml.Location{ path: node.source, line: node.line, column: node.column }
	collection := 'vml_collection_' + suffix
	source := c.lower_expr(model.expr, incoming)
	c.location = vml.Location{ path: model.expr.source, line: model.line, column: model.column }
	c.write_model_path_checks(model.expr, incoming)
	c.writeln('\t${collection} := ${source}')
	c.write_list_guard(collection, suffix, true)
	item_type := 'typeof(${collection}[0])'
	item := 'vml_item_' + suffix
	signal := 'vml_item_signal_' + suffix
	owner := 'vml_item_component_' + suffix
	segment := 'vml_segment_' + suffix
	index := 'vml_index_signal_' + suffix
	// Key paths read item fields: they follow the same public-field rule.
	mut check_scope := vml_clone_scope(incoming)
	check_scope.special['item'] = '${collection}[0]'
	c.location = vml.Location{ path: key.expr.source, line: key.line, column: key.column }
	c.write_model_path_checks(key.expr, check_scope)
	mut key_scope := vml_clone_scope(incoming)
	key_scope.special['item'] = item
	mut key_captures := vml_callback_captures(key.expr, incoming)
	key_captures << collection
	key_body := '_ = ${collection}; return ${vml_stringify(c.lower_expr(key.expr, key_scope))}'
	key_captures = vml_used_captures(key_body, key_captures)
	mut model_captures := vml_callback_captures(model.expr, incoming)
	dependency := if vml.expr_uses_path(model.expr, 'app') {
		model_captures << 'mut ' + incoming.component
		incoming.component + '.watch_app()!; '
	} else {
		''
	}
	model_body := '${dependency}return ${source}'
	model_captures = vml_used_captures(model_body, model_captures)
	mut build_captures := c.scope_captures(incoming)
	build_captures << 'mut ' + parent.handle
	build_captures << collection
	build_captures = build_captures.filter(it.starts_with('mut ') || ('mut ' + it) !in build_captures)
	c.location = vml.Location{ path: node.source, line: node.line, column: node.column }
	prefix := '\tui2.vml_repeat(mut ${parent.handle}, ' + vml_quote(suffix) + ', fn [${model_captures.join(', ')}] () ![]${item_type} { ${model_body} }, fn [${key_captures.join(', ')}] (${item} ${item_type}) string { ${key_body} }, fn '
	capture_start := c.out.len + prefix.len
	c.writeln(prefix + '[] (mut ${owner} ui2.CompiledVmlComponent, mut ${segment} ui2.VmlSegment, ${signal}_input &ui2.Signal[${item_type}]) ! {')
	body_start := c.out.len
	// Item closures read the list-owned signal through a mutable handle.
	c.writeln('\tmut ${signal} := unsafe { ${signal}_input }')
	c.writeln('\t_ = ${signal}')
	c.writeln('\t_ = ${collection}')
	c.writeln('\tmut ${index} := ${owner}.state(' + vml_quote('@index') + ', 0)!')
	c.writeln('\t_ = ${index}')
	mut scope := vml_clone_scope(incoming)
	scope.component = owner
	scope.special['item'] = '${signal}.get() or { panic(err) }'
	scope.special['__signal_item'] = signal
	scope.special['index'] = '${index}.get() or { panic(err) }'
	scope.special['__signal_index'] = index
	item_parent := VmlLowerParent{
		handle: segment
		props:  parent.props
	}
	for child_index, child in node.children {
		child_path := path + '.' + child_index.str()
		if child.tag == 'Repeater' {
			c.lower_repeater(child, child_path, item_parent, scope)
			continue
		}
		scope = c.lower_node(child, child_path, item_parent, scope, '', []VmlForwarded{})
	}
	c.finish_scope_captures(capture_start, body_start, build_captures)
	c.location = vml.Location{ path: node.source, line: node.line, column: node.column }
	c.writeln('\t}, source: ' + vml_quote(node.source) + ', line: ${node.line}, column: ${node.column}) or { panic(err) }')
}

// lower_component inlines a component invocation: its owner, inputs, events,
// refs, state, computed values, functions and lifecycle hooks, then its root
// under the invocation's parent. Undeclared invocation properties configure
// the root.
fn (mut c VmlCompiler) lower_component(node &vml.Node, path string, parent VmlLowerParent, incoming VmlScope, default_key string, forwarded []VmlForwarded) VmlScope {
	suffix := vml_var(path)
	mut root_properties := []VmlForwarded{}
	for property in node.properties {
		if property.name in ['id', 'key', 'ref'] { continue }
		name := if property.name.starts_with('bind.') {
			property.name.all_after('bind.')
		} else {
			property.name
		}
		declared := if property.name.starts_with('on_') {
			node.inputs.any(it.typ == 'event' && it.name == property.name.all_after('on_'))
		} else {
			node.inputs.any(it.typ !in ['event', 'slot'] && it.name == name)
		}
		if !declared { root_properties << VmlForwarded{ property: property, scope: incoming } }
	}
	// An enclosing invocation's undeclared properties apply to this root too.
	root_properties << forwarded
	owner := 'vml_component_${suffix}'
	c.slot_scopes[owner] = incoming
	c.location = vml.Location{ path: node.source, line: node.line, column: node.column }
	c.writeln('\tmut ${owner} := ${incoming.component}.child(' + vml_quote(vml_builder_path(path)) + ') or { panic(err) }')
	c.prepare_style_tokens(node, owner)
	mut scope := VmlScope{
		component: owner
		special:   map[string]string{}
		writable:  map[string]string{}
		ids:       map[string]VmlNamedValue{}
	}
	c.write_component_inputs(node, suffix, owner, incoming, mut scope)
	c.location = vml.Location{ path: node.source, line: node.line, column: node.column }
	for reference in node.refs {
		variable := 'vml_ref_${suffix}_${reference.name}'
		c.writeln('\tmut ${variable} := ${owner}.ref[${vml_props_type(reference.typ)}](' + vml_quote(reference.name) + ') or { panic(err) }')
		scope.special[reference.name] = variable
	}
	c.write_component_members(node, suffix, owner, mut scope)
	key := if property := vml.find_property(node, 'key') {
		c.lower_key(property.expr, incoming)
	} else {
		default_key
	}
	// Invocation keys belong to the actual root: the root's own key gives way.
	root := if key.len > 0 {
		&vml.Node{ ...node.children[0], properties: node.children[0].properties.filter(it.name != 'key') }
	} else {
		node.children[0]
	}
	c.lower_node(root, path + '.root', parent, scope, key, root_properties)
	variable := c.lowered_node
	if reference := vml.find_property(node, 'ref') {
		c.location = vml.Location{ path: reference.expr.source, line: reference.line, column: reference.column }
		c.writeln(c.expr(reference.expr, incoming, .raw) + '.bind_widget(mut ${variable}) or { panic(err) }')
	}
	mut exported := vml_clone_scope(incoming)
	if node.id.len > 0 {
		exported.ids[node.id] = VmlNamedValue{ geometry: variable }
	}
	return exported
}

// write_component_inputs declares a component's events and inputs. Inputs
// read the caller's value through a memo into component state; bindable
// inputs also write back through the caller's target.
fn (mut c VmlCompiler) write_component_inputs(node &vml.Node, suffix string, owner string, incoming VmlScope, mut scope VmlScope) {
	for parameter in node.inputs {
		c.location = vml.Location{ path: node.source, line: parameter.line, column: parameter.column }
		if parameter.typ == 'slot' { continue }
		if parameter.typ == 'event' {
			variable := 'vml_event_${suffix}_${parameter.name}'
			signature := parameter.parameters.map('${it.name} ${it.typ}').join(', ')
			payload_args := parameter.parameters.map(it.name).join(', ')
			if handler := vml.find_property(node, 'on_' + parameter.name) {
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
					c.write_app_action_checks(handler.expr)
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
		argument := vml.find_property(node, parameter.name)
		binding := vml.find_property(node, 'bind.' + parameter.name)
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
			c.location = vml.Location{ path: chosen.source, line: property.line, column: property.column }
		} else if property := argument {
			c.location = vml.Location{ path: chosen.source, line: property.line, column: property.column }
		}
		supplied := argument != none || binding != none
		input_scope := if supplied { incoming } else { scope }
		c.write_model_path_checks(chosen, input_scope)
		value := if parameter.typ == 'ui2.StylePatch' {
			c.lower_style(chosen, input_scope)
		} else {
			c.lower_expr(chosen, input_scope)
		}
		variable := 'vml_input_${suffix}_${parameter.name}'
		mut input_candidates := vml_callback_captures(chosen, input_scope)
		if vml_style_uses_theme(chosen) { input_candidates << 'mut ' + input_scope.component }
		mut input_captures := vml_used_captures(value, input_candidates)
		if supplied {
			app_dependency := vml.expr_uses_path(chosen, 'app')
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
		if property := binding {
			if !parameter.bindable {
				c.writeln('$compile_error(' + vml_quote('input `${parameter.name}` is not declared bindable') + ')')
			}
			if chosen.value.starts_with('app.') { c.write_mutable_check(chosen.value) }
			setter := 'vml_set_input_${suffix}_${parameter.name}'
			mut all_captures := vml_callback_captures(chosen, incoming)
			all_captures << 'mut ' + variable
			prefix := '\t${setter} := fn '
			capture_start := c.out.len + prefix.len
			c.writeln(prefix + '[] (value ${parameter.typ}) ! {')
			body_start := c.out.len
			c.location = vml.Location{ path: chosen.source, line: property.line, column: property.column }
			c.writeln(c.compile_write(chosen.value, 'value', incoming))
			c.writeln('\t${variable}.set(value) or { panic(err) }')
			c.finish_scope_captures(capture_start, body_start, all_captures)
			c.writeln('}')
			scope.writable[parameter.name] = setter
		}
	}
}

// write_component_members declares state, computed values, local functions
// and lifecycle hooks in declaration order.
fn (mut c VmlCompiler) write_component_members(node &vml.Node, suffix string, owner string, mut scope VmlScope) {
	for data in node.data {
		c.location = vml.Location{ path: data.expr.source, line: data.expr.line, column: data.expr.column }
		variable := 'vml_state_${suffix}_${data.name}'
		c.write_model_path_checks(data.expr, scope)
		value := c.lower_expr(data.expr, scope)
		if data.computed {
			mut captures := vml_callback_captures(data.expr, scope)
			app_dependency := vml.expr_uses_path(data.expr, 'app')
			if (app_dependency || vml_style_uses_theme(data.expr)) && ('mut ' + owner) !in captures {
				captures << 'mut ' + owner
			}
			dependency := if app_dependency { owner + '.watch_app()!; ' } else { '' }
			body := '${dependency} return ${value}'
			captures = vml_used_captures(body, captures)
			c.writeln('\tmut ${variable} := ${owner}.computed[typeof(${value})](' + vml_quote(data.name) + ', fn [${captures.join(', ')}] () !typeof(${value}) { ${body} }) or { panic(err) }')
		} else {
			mut captures := vml_callback_captures(data.expr, scope)
			if vml_style_uses_theme(data.expr) && ('mut ' + owner) !in captures {
				captures << 'mut ' + owner
			}
			captures = vml_used_captures(value, captures)
			c.writeln('\tmut ${variable} := ${owner}.state_factory[typeof(${value})](' + vml_quote(data.name) + ', fn [${captures.join(', ')}] () !typeof(${value}) { return ${value} }) or { panic(err) }')
			scope.writable[data.name] = variable + '.set'
		}
		scope.special[data.name] = '${variable}.get() or { panic(err) }'
		scope.special['__signal_' + data.name] = variable
	}
	c.location = vml.Location{ path: node.source, line: node.line, column: node.column }
	for function in node.functions {
		variable := 'vml_fn_${suffix}_${function.name}'
		mut function_scope := vml_clone_scope(scope)
		for parameter in function.parameters {
			function_scope.special[parameter.name] = parameter.name
		}
		body := &vml.Expr{
			kind: .block
			args: function.body
		}
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
		body := &vml.Expr{
			kind: .block
			args: statements
		}
		c.write_app_action_checks(body)
		action := c.compile_action(body, scope)
		captures := vml_used_captures(action, vml_callback_captures(body, scope))
		c.writeln('\t${owner}.on_${kind}(' + vml_quote(kind) + ', fn [${captures.join(', ')}] ()' + if kind == 'mount' {
			' !'
		} else {
			''
		} + ' { ' + action + ' }) or { panic(err) }')
	}
}
