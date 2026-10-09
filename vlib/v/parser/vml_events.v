module parser

fn (c &VmlCompiler) control_id(node &VmlNode, suffix string, scope VmlScope) string {
	mut id := node.id
	if id.len == 0 {
		if node.properties.any(it.name.starts_with('bind.')) {
			id = '__vml_control_${suffix}'
		} else {
			return "''"
		}
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
	for property in node.properties {
		if !property.name.starts_with('bind.') { c.write_model_path_checks(property.expr, scope) }
		if property.name.starts_with('bind.') {
			c.location = VmlLocation{ path: property.expr.source, line: property.expr.line, column: property.expr.column }
			c.write_mutable_check(property.expr.value)
			// A dead write checks existence, mutability and payload type without effects.
			payload := match property.name {
				'bind.text' { "''" }
				'bind.value' { property.expr.value }
				else { 'false' }
			}
			if property.name == 'bind.value' {
				c.writeln('\t$for field in app.fields {')
				c.writeln('\t\t$if field.name == ${vml_quote(property.expr.value.all_after('app.'))} {')
				c.writeln("\t\t\t$if field.typ !is $int && field.typ !is $float { $compile_error('VML value binding must target a numeric field') }")
				c.writeln('\t\t}')
				c.writeln('\t}')
			}
			c.writeln('\tif false { ${property.expr.value} = ${payload} }')
		}
		if !vml_is_event(property.name) { continue }
		expr := property.expr
		c.location = VmlLocation{ path: expr.source, line: expr.line, column: expr.column }
		if expr.kind == .assignment {
			c.write_mutable_check(expr.left.value)
			continue
		}
		if expr.kind != .call { continue }
		method_name := expr.value.all_after('app.')
		check_name := 'vml_action_check_${suffix}_${vml_var(property.name)}'
		call_args := expr.args.map(c.expr(it, scope, .raw)).join(', ')
		c.writeln('\tif false {')
		c.writeln('\t\tmut ${check_name} := *app')
		c.writeln('\t\t$for method in ${check_name}.methods {')
		c.writeln('\t\t\t$if method.name == ${vml_quote(method_name)} {')
		c.writeln('\t\t\t\t$if !method.is_pub { $compile_error(' + vml_quote('VML action method `${method_name}` must be public') + ') }')
		c.writeln('\t\t\t\t$if method.typ !is fn () && method.typ !is fn (int) && method.typ !is fn (string) { $compile_error(' + vml_quote('VML action method `${method_name}` has an unsupported signature') + ') }')
		c.writeln('\t\t\t}')
		c.writeln('\t\t}')
		c.writeln('\t\t${check_name}.${method_name}(${call_args})')
		c.writeln('\t}')
	}
}

fn vml_callback_captures(expr &VmlExpr, scope VmlScope) []string {
	mut captures := ['mut app']
	for base, variable in scope.special {
		if !base.starts_with('__') && vml_expr_uses_path(expr, base) && variable !in captures {
			captures << variable
		}
	}
	for id, named in scope.ids {
		for field, variable in named.props {
			if vml_expr_uses_path(expr, '${id}.${field}') && variable !in captures {
				captures << variable
			}
		}
		for field in ['x', 'y', 'width', 'height'] {
			if field !in named.props && vml_expr_uses_path(expr, '${id}.${field}')
				&& named.frame !in captures {
				captures << named.frame
			}
		}
	}
	return captures
}

fn (c &VmlCompiler) event_callback(node &VmlNode, name string, scope VmlScope) string {
	action := vml_find_property(node, name)
	binding := vml_binding_for_event(node, name)
	if action == none && binding == none { return 'unsafe { nil }' }
	mut fields := []string{}
	if property := binding {
		fields << 'binding_property: ' + vml_quote(property.name.all_after('bind.'))
		fields << 'binding_target: ' + vml_quote(property.expr.value)
	}
	if property := action {
		if property.expr.kind in [.assignment, .call] {
			captures := vml_callback_captures(property.expr, scope)
			mut body := '_ = event\n'
			if fields.len > 0 {
				body += 'ui2.compiled_vml_callback(mut app, ui2.CompiledVmlCallbackConfig{${fields.join(', ')}})(event)\n'
			}
			// Ordinary typed V executes against the borrowed model after the payload
			// write. Only row/local values are captured when building the callback.
			body += if property.expr.kind == .assignment {
				'${property.expr.left.value} = ${c.expr(property.expr.right, scope, .raw)}'
			} else {
				c.expr(property.expr, scope, .raw)
			}
			body += '\nui2.request_refresh()'
			return 'fn [${captures.join(', ')}] (event ui2.ElementEvent) { ${body} }'
		}
		// Explicit V callbacks are resolved by the checker, never by a global id.
		callback := c.expr(property.expr, scope, .raw)
		if fields.len == 0 {
			return '(fn (callback ui2.ElementCallback) ui2.ElementCallback { return fn [callback] (event ui2.ElementEvent) { if callback != unsafe { nil } { callback(event) } } })(${callback})'
		}
		return '(fn [mut app] (callback ui2.ElementCallback) ui2.ElementCallback { bound := ui2.compiled_vml_callback(mut app, ui2.CompiledVmlCallbackConfig{${fields.join(', ')}}) return fn [bound, callback] (event ui2.ElementEvent) { bound(event) if callback != unsafe { nil } { callback(event) } } })(${callback})'
	}
	return 'ui2.compiled_vml_callback(mut app, ui2.CompiledVmlCallbackConfig{${fields.join(', ')}})'
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
	}
	if callbacks.len == 0 { return 'unsafe { nil }' }
	mut captures := []string{}
	for _, variable in callbacks { captures << variable }
	mut body := ''
	if callback := callbacks['on_tap'] { body += '.tap { ${callback}(event) }\n' }
	change := if node.tag == 'Switch' {
		callbacks['on_active'] or { callbacks['on_change'] or { '' } }
	} else {
		callbacks['on_change'] or { '' }
	}
	if change.len > 0 { body += '.change { ${change}(event) }\n' }
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
