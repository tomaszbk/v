module parser

import strings

// These are compiler records for sharing generated V, not runtime layout data.
struct VmlBuilderValue {
	id       string
	property string
	typ      string
	value    string
}

struct VmlBuilder {
	name       string
	parameters []VmlBuilderValue
	exports    []VmlBuilderValue
	properties []VmlBuilderValue
}

fn vml_has_visual_layout(node &VmlNode) bool {
	if node.tag in ['Flex', 'Row', 'Column', 'Grid'] { return true }
	return node.children.any(vml_has_visual_layout(it))
}

fn (mut c VmlCompiler) collect_builder_references(node &VmlNode, path string) {
	for property in node.properties { c.collect_builder_expr_references(property.expr, path) }
	mut visible_index := 0
	for index, child in node.children {
		// These declarations are consumed by their parent's builder, not by
		// an element builder. Flex/Grid number only the remaining children.
		if child.tag in ['MenuItem', 'Option', 'Run'] {
			c.collect_builder_references(child, path)
			continue
		}
		child_index := if node.tag in ['Flex', 'Row', 'Column', 'Grid'] {
			visible_index
		} else {
			index
		}
		c.collect_builder_references(child, '${path}.${child_index}')
		visible_index++
	}
}

fn (mut c VmlCompiler) collect_builder_expr_references(expr &VmlExpr, path string) {
	if expr.kind in [.path, .call] && expr.value.contains('.') {
		id := expr.value.all_before('.')
		mut readers := c.reference_readers[id] or { []string{} }
		if path !in readers { readers << path }
		c.reference_readers[id] = readers
	}
	if !isnil(expr.left) { c.collect_builder_expr_references(expr.left, path) }
	if !isnil(expr.right) { c.collect_builder_expr_references(expr.right, path) }
	if !isnil(expr.third) { c.collect_builder_expr_references(expr.third, path) }
	for arg in expr.args { c.collect_builder_expr_references(arg, path) }
	for part in expr.parts {
		if !isnil(part.expr) { c.collect_builder_expr_references(part.expr, path) }
	}
}

fn (c &VmlCompiler) builder_exports_id(path string, id string) bool {
	for reader in c.reference_readers[id] or { []string{} } {
		if reader != path && !reader.starts_with(path + '.') { return true }
	}
	return false
}

fn vml_builder_property_type(node &VmlNode, property VmlProperty) string {
	if property.declared_type.len > 0 {
		return if property.declared_type == 'color' { 'u32' } else { property.declared_type }
	}
	if vml_visual_integer_property(property) { return 'int' }
	return match vml_property_use(property) {
		.number { 'f64' }
		.bool_ { 'bool' }
		.color { 'u32' }
		.raw {
			match vml_visual_base_property(property.name) {
				'align' { 'ui2.Align' }
				'valign' { 'ui2.VAlign' }
				'align_items', 'align_self' { 'ui2.LayoutAlignment' }
				'justify' { 'ui2.FlexJustify' }
				'border_pattern' { 'ui2.BorderPattern' }
				'orientation' {
					if node.tag == 'Grid' {
						'ui2.GridOrientation'
					} else if node.tag == 'Slider' {
						'ui2.Orientation'
					} else {
						'ui2.LayoutOrientation'
					}
				}
				else { 'string' }
			}
		}
		else { 'string' }
	}
}

fn vml_builder_path(path string) string {
	return path.replace('_measure', '').replace('_width', '')
}

fn vml_builder_scope_value(scope VmlScope, value VmlBuilderValue) string {
	named := scope.ids[value.id] or { return value.value }
	return if value.property.len == 0 { named.frame } else { named.props[value.property] }
}

fn (mut c VmlCompiler) compile_shared_node(node &VmlNode, path string, input string, incoming VmlScope, placement VmlPlacement) VmlScope {
	canonical := vml_builder_path(path)
	key := '${canonical}_${placement}'
	name := 'vml_builder_${vml_var(key)}'
	if c.active_builder.len > 0 {
		mut dependencies := c.builder_dependencies[c.active_builder] or { []string{} }
		if name !in dependencies { dependencies << name }
		c.builder_dependencies[c.active_builder] = dependencies
	}
	if key !in c.builders {
		mut parameters := []VmlBuilderValue{}
		mut local_scope := VmlScope{}
		mut ids := incoming.ids.keys()
		ids.sort()
		for id in ids {
			if !vml_node_uses_path(node, id) { continue }
			named := incoming.ids[id]
			frame := 'vml_argument_${parameters.len}'
			parameters << VmlBuilderValue{ id: id, typ: 'ui2.Rect', value: frame }
			mut props := map[string]string{}
			mut names := named.props.keys()
			names.sort()
			for property in names {
				argument := 'vml_argument_${parameters.len}'
				parameters << VmlBuilderValue{ id: id, property: property, typ: named.prop_types[property], value: argument }
				props[property] = argument
			}
			local_scope.ids[id] = VmlNamedValue{ frame: frame, props: props, prop_types: named.prop_types }
		}
		previous := c.out
		previous_locations := c.locations.clone()
		previous_location := c.location
		parent := c.active_builder
		c.out = strings.new_builder(4096)
		c.locations = []VmlLocation{}
		c.active_builder = name
		body_path := canonical
		result := c.compile_node_body(node, body_path, 'vml_builder_input', local_scope, '', placement)
		mut exports := []VmlBuilderValue{}
		mut result_ids := result.ids.keys()
		result_ids.sort()
		for id in result_ids {
			// Only references crossing this builder's boundary need tuple outputs.
			// Self reads and internal descendants stay local, avoiding accumulated
			// exports in an ordinary chain of named containers.
			if !c.builder_exports_id(canonical, id) { continue }
			named := result.ids[id]
			if old := local_scope.ids[id] {
				if old.frame == named.frame { continue }
			}
			exports << VmlBuilderValue{ id: id, typ: 'ui2.Rect', value: named.frame }
			mut props := named.props.keys()
			props.sort()
			for property in props {
				exports << VmlBuilderValue{ id: id, property: property, typ: named.prop_types[property], value: named.props[property] }
			}
		}
		mut properties := []VmlBuilderValue{}
		for property in node.properties {
			if property.name !in vml_flex_child_properties
				&& property.name !in ['column_span', 'row_span'] {
				continue
			}
			variable := 'vml_property_${vml_var(body_path)}_${vml_var(property.name)}'
			if variable !in c.property_positions { continue }
			properties << VmlBuilderValue{ property: property.name, typ: vml_builder_property_type(node, property), value: variable }
		}
		body := c.out.str()
		body_locations := c.locations.clone()
		c.out = previous
		c.locations = previous_locations
		c.location = previous_location
		c.active_builder = parent
		builder := VmlBuilder{ name: name, parameters: parameters, exports: exports, properties: properties }
		c.builders[key] = builder
		c.emit_shared_builder(builder, body, body_locations, 'vml_element_${vml_var(body_path)}')
	}
	builder := c.builders[key]
	mut call_arguments := [input]
	for parameter in builder.parameters {
		call_arguments << vml_builder_scope_value(incoming, parameter)
	}
	suffix := vml_var(path)
	mut outputs := ['vml_element_${suffix}']
	mut scope := vml_clone_scope(incoming)
	mut named := map[string]VmlNamedValue{}
	for index, export in builder.exports {
		variable := 'vml_export_${suffix}_${index}'
		outputs << variable
		mut value := named[export.id] or { VmlNamedValue{} }
		if export.property.len == 0 {
			value = VmlNamedValue{ ...value, frame: variable }
		} else {
			mut props := value.props.clone()
			mut types := value.prop_types.clone()
			props[export.property] = variable
			types[export.property] = export.typ
			value = VmlNamedValue{ ...value, props: props, prop_types: types }
		}
		named[export.id] = value
	}
	for property in builder.properties {
		outputs << 'vml_property_${suffix}_${vml_var(property.property)}'
	}
	c.writeln('\t${outputs.join(', ')} := ${name}(${call_arguments.join(', ')})')
	for output in outputs { c.writeln('\t_ = ${output}') }
	for id, value in named { scope.ids[id] = value }
	return scope
}

// A builder's results are shared only inside this $vml construction. Exact typed
// arguments include offered geometry and visible references, so an allocated
// sibling cannot reuse a result measured with a different scope. ui2 still owns
// every measure/allocation call; there is no persistent text or layout cache.
fn (mut c VmlCompiler) emit_shared_builder(builder VmlBuilder, body string, body_locations []VmlLocation, element string) {
	mut out := strings.new_builder(body.len + 2048)
	inputs := [VmlBuilderValue{ typ: 'ui2.Rect', value: 'vml_builder_input' }]
	mut all_inputs := inputs.clone()
	all_inputs << builder.parameters
	mut results := [VmlBuilderValue{ typ: 'ui2.Element', value: element }]
	results << builder.exports
	results << builder.properties
	mut captures := if c.uses_app { ['mut app'] } else { []string{} }
	captures << c.builder_dependencies[builder.name] or { []string{} }
	mut signature := []string{}
	mut comparisons := []string{}
	for index, argument in all_inputs {
		cache := '${builder.name}_input_${index}'
		out.writeln('\tmut ${cache} := []${argument.typ}{}')
		captures << 'mut ${cache}'
		signature << '${argument.value} ${argument.typ}'
		comparisons << '${cache}[vml_cached_index] == ${argument.value}'
	}
	mut types := []string{}
	mut cached := []string{}
	for index, result in results {
		cache := '${builder.name}_result_${index}'
		out.writeln('\tmut ${cache} := []${result.typ}{}')
		captures << 'mut ${cache}'
		types << result.typ
		cached << '${cache}[vml_cached_index]'
	}
	return_type := if types.len == 1 { types[0] } else { '(' + types.join(', ') + ')' }
	out.writeln('\t${builder.name} := fn [${captures.join(', ')}] (${signature.join(', ')}) ${return_type} {')
	out.writeln('\tfor vml_cached_index in 0 .. ${builder.name}_input_0.len {')
	out.writeln('\t\tif ${comparisons.join(' && ')} { return ${cached.join(', ')} }')
	out.writeln('\t}')
	body_start := out.spart(0, out.len).count('\n')
	out.write_string(body)
	for index, argument in all_inputs {
		out.writeln('\t${builder.name}_input_${index} << ${argument.value}')
	}
	for index, result in results {
		out.writeln('\t${builder.name}_result_${index} << ${result.value}')
	}
	out.writeln('\treturn ${results.map(it.value).join(', ')}')
	out.writeln('\t}')
	declaration := out.str()
	mut locations := []VmlLocation{len: declaration.count('\n'), init: c.location}
	for index, location in body_locations { locations[body_start + index] = location }
	c.builder_declarations << declaration
	c.builder_locations << locations
}
