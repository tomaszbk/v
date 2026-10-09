module parser

// Structural declarations register ordered child groups after their parent is
// retained. ui2 owns reconciliation and per-key component lifetimes.
fn (mut c VmlCompiler) compile_child_segments(node &VmlNode, suffix string, scope VmlScope) {
	canonical := suffix.trim_string_right('_base')
	if !node.children.any(it.tag == 'Repeater') { return }
	parent := 'vml_node_' + suffix
	for index, child in node.children {
		if child.tag in ['MenuItem', 'Option', 'Run'] { continue }
		path := '${canonical}.${index}'
		if child.tag == 'Repeater' {
			c.compile_keyed_repeater(child, path, parent, parent, node.tag, scope)
		} else {
			variable := 'vml_node_' + vml_var(path)
			c.write_child_layout(child, variable, vml_var(path), node.tag, scope)
			c.writeln('${parent}.set_segment(' + vml_quote('static:' + index.str()) + ', [${variable}]) or { panic(err) }')
		}
	}
}

fn (mut c VmlCompiler) write_child_layout(node &VmlNode, variable string, suffix string, parent string, scope VmlScope) {
	mut properties := map[string]string{}
	for property in node.properties {
		if property.name in vml_flex_child_properties || property.name in [
			'column_span',
			'row_span',
			'align_self_x',
			'align_self_y',
		] {
			properties[property.name] = c.visual_property_value(node, property, property.expr, scope)
		}
	}
	rule := if parent in ['Flex', 'Row', 'Column'] {
		'ui2.VmlChildLayout{flex: ' + vml_flex_item('ui2.Element{}', properties) + '}'
	} else if parent == 'Grid' {
		'ui2.VmlChildLayout{grid: ui2.GridSpan{column_span: ${vml_prop(properties, 'column_span', '1')}, row_span: ${vml_prop(properties, 'row_span', '1')}}}'
	} else if parent == 'Stack' {
		'ui2.VmlChildLayout{stack: ui2.StackChild{align_x: ${vml_prop(properties, 'align_self_x', '.auto')}, align_y: ${vml_prop(properties, 'align_self_y', '.auto')}}}'
	} else {
		return
	}
	c.writeln('${variable}.set_child_layout(${rule}) or { panic(err) }')
	c.write_child_layout_effects(node, variable, parent, scope)
	_ = suffix
}

fn (mut c VmlCompiler) compile_keyed_repeater(node &VmlNode, path string, parent string, geometry_parent string, parent_tag string, incoming VmlScope) {
	model := vml_find_property(node, 'model') or { return }
	key := vml_find_property(node, 'key') or { return }
	suffix := vml_var(path)
	collection := 'vml_collection_' + suffix
	source := c.expr(model.expr, incoming, .raw)
	c.write_model_path_checks(model.expr, incoming)
	c.writeln('${collection} := ${source}')
	c.write_list_guard(collection, suffix, true)
	item_type := 'typeof(${collection}[0])'
	item := 'vml_item_' + suffix
	signal := 'vml_item_signal_' + suffix
	owner := 'vml_item_component_' + suffix
	index := 'vml_index_signal_' + suffix
	mut key_scope := vml_clone_scope(incoming)
	key_scope.special['item'] = item
	mut key_captures := vml_callback_captures(key.expr, incoming)
	key_captures << collection
	key_value := c.expr(key.expr, key_scope, .raw)
	mut build_captures := c.scope_captures(incoming)
	build_captures << 'mut ' + parent
	if geometry_parent != parent { build_captures << 'mut ' + geometry_parent }
	build_captures << collection
	c.writeln('mut vml_list_${suffix} := ui2.new_vml_keyed_list[${item_type}](mut ${parent}, ' + vml_quote(suffix) + ', fn [${key_captures.join(', ')}] (${item} ${item_type}) string { _ = ${collection}; return ${vml_stringify(key_value)} }, fn [${build_captures.join(', ')}] (mut ${owner} ui2.CompiledVmlComponent, ${signal} &ui2.Signal[${item_type}]) ![]&ui2.CompiledVmlNode {')
	c.writeln('_ = ${collection}')
	c.writeln('mut ${index} := ${owner}.state(' + vml_quote('@index') + ', 0)!')
	c.writeln('_ = ${index}')
	mut scope := vml_clone_scope(incoming)
	scope.component = owner
	scope.special['item'] = '${signal}.get() or { panic(err) }'
	scope.special['__signal_item'] = signal
	scope.special['index'] = '${index}.get() or { panic(err) }'
	scope.special['__signal_index'] = index
	visible := node.children.filter(it.tag !in ['MenuItem', 'Option', 'Run'])
	mut results := []string{}
	nested := visible.any(it.tag == 'Repeater')
	fragment := 'vml_fragment_' + suffix
	if nested {
		c.writeln('mut ${fragment} := ${owner}.fragment(' + vml_quote('body:' + suffix) + ')!')
	}
	for child_index, child in visible {
		child_path := path + '.' + child_index.str()
		child_suffix := vml_var(child_path)
		if child.tag == 'Repeater' {
			c.compile_keyed_repeater(child, child_path, fragment, geometry_parent, parent_tag, scope)
			continue
		}
		input := 'vml_input_' + child_suffix
		c.writeln('${input} := ui2.rect(0, 0, ${geometry_parent}.frame()!.width, ${geometry_parent}.frame()!.height)')
		scope = c.compile_node(child, child_path, input, scope, '', if parent_tag in [
			'Flex',
			'Row',
			'Column',
			'Grid',
			'Stack',
			'Absolute',
		] {
			.preferred
		} else {
			.normal
		})
		c.write_child_layout(child, 'vml_node_' + child_suffix, child_suffix, parent_tag, scope)
		if nested {
			c.writeln('${fragment}.set_segment(' + vml_quote('static:' + child_index.str()) + ', [vml_node_${child_suffix}])!')
		} else {
			results << 'vml_node_' + child_suffix
		}
	}
	c.writeln('return ' + if nested {
		'[${fragment}]'
	} else {
		vml_array_literal('&ui2.CompiledVmlNode', results)
	})
	c.writeln('}) or { panic(err) }')
	mut captures := vml_callback_captures(model.expr, incoming)
	dependency := if vml_expr_uses_path(model.expr, 'app') {
		if ('mut ' + incoming.component) !in captures { captures << 'mut ' + incoming.component }
		incoming.component + '.watch_app()!; '
	} else {
		''
	}
	c.writeln('vml_list_${suffix}.bind(fn [${captures.join(', ')}] () ![]${item_type} { ${dependency} return ${source} }) or { panic(err) }')
}

fn (c &VmlCompiler) scope_captures(scope VmlScope) []string {
	mut captures := []string{}
	if c.uses_app { captures << 'mut app' }
	for name, value in scope.special {
		if name.starts_with('__signal_') {
			if ('mut ' + value) !in captures { captures << 'mut ' + value }
		} else if !name.starts_with('__') && value.starts_with('vml_') && !value.contains('.') && value !in captures {
			captures << value
		}
	}
	for _, named in scope.ids {
		for _, property in named.props { if property !in captures { captures << property } }
		value := if named.frame_signal.len > 0 { 'mut ' + named.frame_signal } else { named.frame }
		if value !in captures { captures << value }
	}
	captures << c.callback_captures.filter(it !in captures)
	return captures
}

fn (mut c VmlCompiler) write_child_layout_effects(node &VmlNode, variable string, parent string, scope VmlScope) {
	for property in node.properties {
		name := property.name
		if name !in vml_flex_child_properties && name !in ['column_span', 'row_span', 'align_self_x',
			'align_self_y'] {
			continue
		}
		if property.expr.kind == .literal { continue }
		effect_key := variable + ':' + name
		if effect_key in c.emitted_child_effects { continue }
		c.emitted_child_effects[effect_key] = true
		kind := if parent == 'Grid' {
			'grid'
		} else if parent == 'Stack' {
			'stack'
		} else {
			'flex'
		}
		typ := if kind == 'grid' {
			'GridSpan'
		} else if kind == 'stack' {
			'StackChild'
		} else {
			'FlexChild'
		}
		field := match name {
			'flex_basis' { 'basis' }
			'flex_grow' { 'grow' }
			'flex_shrink' { 'shrink' }
			'min_width' { 'minimum_width' }
			'min_height' { 'minimum_height' }
			'max_width' { 'maximum_width' }
			'max_height' { 'maximum_height' }
			'align_self_x' { 'align_x' }
			'align_self_y' { 'align_y' }
			else { name }
		}
		value := c.visual_property_value(node, property, property.expr, scope)
		mut captures := vml_callback_captures(property.expr, scope)
		captures << 'mut ' + variable
		app_dependency := vml_expr_uses_path(property.expr, 'app')
		if app_dependency { captures << 'mut ' + scope.component }
		dependency := if app_dependency { scope.component + '.watch_app()!; ' } else { '' }
		c.writeln('${scope.component}.scope.effect(' + vml_quote('@child:' + variable + ':' + name) + ', fn [${captures.join(', ')}] () ! { ${dependency} current := ${variable}.child_rule(); ${variable}.set_child_layout(ui2.VmlChildLayout{...current, ${kind}: ui2.${typ}{...current.${kind}, ${field}: ${value}}})! }) or { panic(err) }')
	}
}
