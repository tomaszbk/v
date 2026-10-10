module parser

fn (c &VmlCompiler) control_id(node &VmlNode, suffix string, scope VmlScope) string {
	if node.id.len == 0 && (node.properties.any(it.name.starts_with('bind.')) || node.properties.any(it.name == 'ref')) {
		return c.node_identity(node, suffix, scope)
	}
	return vml_quote(node.id)
}

fn (c &VmlCompiler) node_identity(node &VmlNode, suffix string, scope VmlScope) string {
	mut id := node.id
	if id.len == 0 {
		id = '__vml_control_${vml_builder_path(suffix).replace('_base', '')}'
	}
	namespace := scope.special[if node.import_id { '__import_parent' } else { '__import' }] or { '' }
	if namespace.len > 0 {
		id = '__vml_import_${namespace}_${id.bytes().hex()}'
	}
	if repeated := scope.special['__repeat_identity'] {
		return vml_quote(id + '__vml_${suffix}_') + ' + ${repeated}'
	}
	return vml_quote(id)
}

fn (mut c VmlCompiler) write_mutable_check(target string) {
	field_name := target.all_after('app.')
	c.writeln('\t$for field in app.fields {')
	c.writeln('\t\t$if field.name == ' + vml_quote(field_name) + ' {')
	c.writeln('\t\t\t$if !field.is_pub || !field.is_mut { $compile_error(' + vml_quote('VML target `${target}` must be public and mutable') + ') }')
	c.writeln('\t\t}')
	c.writeln('\t}')
}

fn (mut c VmlCompiler) write_action_type_checks(node &VmlNode, suffix string, scope VmlScope) {
	_ = suffix
	for property in node.properties {
		if property.name.starts_with('bind.') {
			value := 'vml_binding_target_' + suffix + '_' + vml_var(property.name)
			c.writeln('${value} := ' + c.expr(property.expr, scope, .raw))
			c.writeln('_ = ${value}')
			if property.name == 'bind.text' {
				c.writeln("$if ${value} !is string { $compile_error('VML text binding must target a string') }")
			} else if property.name in ['bind.checked', 'bind.active', 'bind.pressed'] {
				c.writeln("$if ${value} !is bool { $compile_error('VML checked binding must target bool') }")
			} else if property.name == 'bind.value' {
				c.writeln("$if ${value} !is $int && ${value} !is $float { $compile_error('VML value binding must target a number') }")
			}
			if property.expr.value.starts_with('app.') {
				c.write_mutable_check(property.expr.value)
			} else if property.expr.value !in scope.writable {
				c.writeln('$compile_error(' + vml_quote('binding source `${property.expr.value}` is read-only or unknown') + ')')
			}
		} else {
			c.write_model_path_checks(property.expr, scope)
		}
		if vml_is_event(property.name) { c.write_app_action_checks(property.expr) }
	}
}

fn vml_callback_captures(expr &VmlExpr, scope VmlScope) []string {
	mut captures := []string{}
	if vml_expr_uses_path(expr, 'app') { captures << 'mut app' }
	for base, variable in scope.special {
		if base.starts_with('__') || !vml_expr_uses_path(expr, base) { continue }
		captured := if signal := scope.special['__signal_' + base] {
			'mut ' + signal
		} else {
			variable
		}
		if setter := scope.writable[base] {
			if !setter.contains('.') && setter.starts_with('vml_') && setter !in captures {
				captures << setter
			}
		}
		if (!captured.contains('.') && !captured.contains(' ')) || captured.starts_with('mut ') {
			if captured !in captures { captures << captured }
		}
	}
	for id, named in scope.ids {
		for field, variable in named.props {
			if vml_expr_uses_path(expr, '${id}.${field}') && variable !in captures {
				captures << variable
			}
		}
		for field in ['x', 'y', 'width', 'height'] {
			if vml_expr_uses_path(expr, '${id}.${field}') {
				captured := if named.frame_node.len > 0 {
					named.frame_node
				} else if named.frame_signal.len > 0 {
					'mut ' + named.frame_signal
				} else {
					named.frame
				}
				if captured !in captures { captures << captured }
			}
		}
	}
	return captures
}

fn (c &VmlCompiler) event_callback(node &VmlNode, name string, scope VmlScope) string {
	if c.effect_mode {
		if value := c.event_references[(scope.special['__node_suffix'] or { '' }) + ':' + name] {
			return value
		}
	}
	action := vml_find_property(node, name)
	binding := vml_binding_for_event(node, name)
	if action == none && binding == none { return 'unsafe { nil }' }
	mut body := '_ = event\n'
	mut captures := []string{}
	if property := binding {
		captures << vml_callback_captures(property.expr, scope)
		payload := match property.name {
			'bind.text' { 'event.text' }
			'bind.value' {
				'ui2.vml_binding_number(' + c.expr(property.expr, scope, .raw) + ', event.value)'
			}
			else { 'event.checked' }
		}
		body += c.compile_write(property.expr.value, payload, scope) + '\n'
	}
	if property := action {
		captures << vml_callback_captures(property.expr, scope).filter(it !in captures)
		if property.expr.kind == .path {
			callback := c.expr(property.expr, scope, .raw)
			body += 'ui2.vml_callback(${callback}' + if scope.component.len > 0 {
				', refresh: false'
			} else {
				''
			} + ')(event)\n'
			if !callback.contains('.') && callback !in captures && (callback in c.callback_captures || callback.starts_with('vml_')) {
				captures << callback
			}
		} else {
			body += c.compile_action(property.expr, scope) + '\n'
		}
	}
	captures = vml_used_captures(body, captures)
	if scope.component.len > 0 {
		return '${scope.component}.callback(fn [${captures.join(', ')}] (event ui2.ElementEvent) ! { ${body} })'
	}
	body += 'ui2.request_refresh()'
	return 'fn [${captures.join(', ')}] (event ui2.ElementEvent) { ${body} }'
}

fn (mut c VmlCompiler) write_element_callback(node &VmlNode, suffix string, scope VmlScope) string {
	mut callbacks := map[string]string{}
	for name in vml_event_names {
		if vml_find_property(node, name) == none && vml_binding_for_event(node, name) == none {
			continue
		}
		if property := vml_find_property(node, name) {
			c.location = VmlLocation{ path: property.expr.source, line: property.expr.line, column: property.expr.column }
		}
		variable := 'vml_callback_${suffix}_${name}'
		c.writeln('\t${variable} := ${c.event_callback(node, name, scope)}')
		callbacks[name] = variable
		c.event_references[suffix + ':' + name] = variable
	}
	if callbacks.len == 0 { return 'unsafe { nil }' }
	mut captures := []string{}
	for _, variable in callbacks { captures << variable }
	mut body := ''
	if callback := callbacks['on_tap'] { body += '.tap { ${callback}(event) }\n' }
	mut change := ''
	if node.tag == 'Switch' {
		if callback := callbacks['on_active'] { change += '${callback}(event)\n' }
	}
	if callback := callbacks['on_change'] { change += '${callback}(event)\n' }
	if change.len > 0 { body += '.change { ${change} }\n' }
	if callback := callbacks['on_submit'] { body += '.submit { ${callback}(event) }\n' }
	if callback := callbacks['on_scroll'] { body += '.scroll { ${callback}(event) }\n' }
	for kind in ['pointer_down', 'pointer_drag', 'pointer_up', 'long_press', 'swipe_left', 'link'] {
		callback := callbacks['on_${kind}'] or { '' }
		if callback.len > 0 { body += '.${kind} { ${callback}(event) }\n' }
	}
	return 'fn [${captures.join(', ')}] (event ui2.ElementEvent) { match event.kind { ${body} else {} } }'
}

fn (mut c VmlCompiler) write_model_path_checks(expr &VmlExpr, scope VmlScope) {
	if expr.kind == .path {
		parts := expr.value.split('.')
		if parts.len < 2 || parts[0] !in ['app', 'item'] { return }
		mut base := if parts[0] == 'app' { 'app' } else { scope.special['item'] or { return } }
		c.location = VmlLocation{ path: expr.source, line: expr.line, column: expr.column }
		for field_name in parts[1..] {
			if field_name == 'len' { break }
			c.write_field_guard(base, field_name, expr.value)
			base += '.' + field_name
		}
	}
	if !isnil(expr.left) && expr.kind != .assignment { c.write_model_path_checks(expr.left, scope) }
	if !isnil(expr.right) { c.write_model_path_checks(expr.right, scope) }
	if !isnil(expr.third) { c.write_model_path_checks(expr.third, scope) }
	for argument in expr.args { c.write_model_path_checks(argument, scope) }
	for part in expr.parts {
		if !isnil(part.expr) { c.write_model_path_checks(part.expr, scope) }
	}
}

fn (mut c VmlCompiler) write_app_action_checks(expr &VmlExpr) {
	if expr.kind == .assignment && expr.left.value.starts_with('app.') {
		c.write_mutable_check(expr.left.value)
	}
	if expr.kind in [.call, .path] && expr.value.starts_with('app.') && expr.value.count('.') == 1 {
		method := expr.value.all_after('app.')
		c.writeln('\t$for method in app.methods {')
		c.writeln('\t$if method.name == ' + vml_quote(method) + ' {')
		c.writeln('\t$if !method.is_pub { $compile_error(' + vml_quote('VML action method `${method}` must be public') + ') }')
		if expr.kind == .call {
			c.writeln('\t$if method.args.len != ${expr.args.len} { $compile_error(' + vml_quote('VML action `${method}` argument count does not match its declared signature') + ') }')
		}
		c.writeln('\t}\n}')
	}
	if !isnil(expr.left) { c.write_app_action_checks(expr.left) }
	if !isnil(expr.right) { c.write_app_action_checks(expr.right) }
	for argument in expr.args { c.write_app_action_checks(argument) }
}
